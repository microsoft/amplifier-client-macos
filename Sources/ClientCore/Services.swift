import Foundation

public struct RegisteredService: Codable, Equatable, Identifiable {
    public let id: String
    public let address: String
    public var name: String
    public var paused: Bool
    public var hostIdentity: String?
    public var endpoint: Endpoint { try! Endpoint(address) } // Validated on registry load/add.
    public var displayName: String {
        if !name.isEmpty { return name }
        let url = endpoint.url
        return (url.host ?? address) + (url.port.map { ":\($0)" } ?? "")
    }
    public init(address: String, name: String = "", paused: Bool = false) throws {
        self.id = UUID().uuidString.lowercased()
        self.address = try Endpoint(address).url.absoluteString
        self.name = NoticeText.plain(name, limit: 60); self.paused = paused
    }
}

/// Nonsecret registration catalog. Credentials remain in the endpoint's Keychain account.
public struct ServiceRegistry: Codable, Equatable {
    public var version = 1
    public private(set) var services: [RegisteredService] = []
    public var preferredID: String?
    public init() {}
    public static let defaultsKey = "registeredServices.v1"
    public static func load(data: Data?, legacyAddress: String?, legacyPaused: Bool) throws -> ServiceRegistry {
        if let data {
            let result = try JSONDecoder().decode(Self.self, from: data)
            guard result.version == 1, Set(result.services.map(\.id)).count == result.services.count,
                  Set(try result.services.map { try origin($0.address) }).count == result.services.count,
                  result.services.allSatisfy({ UUID(uuidString: $0.id) != nil }),
                  result.preferredID == nil || result.services.contains(where: { $0.id == result.preferredID }) else {
                throw CompanionError.incompatibleHost
            }
            return result
        }
        var result = Self()
        if let legacyAddress {
            let service = try RegisteredService(address: legacyAddress, paused: legacyPaused)
            result.services = [service]; result.preferredID = service.id
        }
        return result
    }
    private static func origin(_ address: String) throws -> String {
        let endpoint = try Endpoint(address)
        var parts = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)!
        if parts.scheme == "https" && parts.port == 443 || parts.scheme == "http" && parts.port == 80 { parts.port = nil }
        return parts.string!
    }
    public func service(address: String) -> RegisteredService? {
        guard let key = try? Self.origin(address) else { return nil }
        return services.first { (try? Self.origin($0.address)) == key }
    }
    @discardableResult public mutating func register(address: String, name: String, reapproved: Bool) throws -> RegisteredService {
        var service = try self.service(address: address) ?? RegisteredService(address: address)
        service.name = NoticeText.plain(name, limit: 60); service.paused = false
        if reapproved { service.hostIdentity = nil }
        replace(service); preferredID = service.id
        return service
    }
    public mutating func replace(_ service: RegisteredService) {
        if let index = services.firstIndex(where: { $0.id == service.id }) { services[index] = service }
        else { services.append(service) }
    }
    public mutating func remove(_ id: String) {
        services.removeAll { $0.id == id }
        if preferredID == id { preferredID = services.first?.id }
    }
}

/// Every action captures its original service and durable host, including new-chat sends.
public struct ServiceTarget: Equatable, Hashable {
    public let serviceID: String
    public let address: String
    public let hostIdentity: String
    public let sessionID: String?
    public init(service: RegisteredService, hostIdentity: String, sessionID: String?) {
        self.serviceID = service.id; self.address = service.address
        self.hostIdentity = hostIdentity; self.sessionID = sessionID
    }
    public var key: String {
        // Length-safe even when host/session identifiers contain separators.
        let data = try! JSONEncoder().encode([serviceID, address, hostIdentity, sessionID] as [String?])
        return data.base64EncodedString()
    }
    public var url: URL { sessionID.map { try! Endpoint(address).chatURL($0) } ?? (try! Endpoint(address).url) }
    public func matches(service: RegisteredService, hostIdentity: String?) -> Bool {
        serviceID == service.id && address == service.address && self.hostIdentity == hostIdentity && !service.paused
    }
}

extension AttentionItem {
    public func scoped(to scope: String) -> AttentionItem {
        AttentionItem(id: scope + ":" + id, fingerprint: fingerprint, sessionId: sessionId,
                      title: title, kind: kind, summary: summary, pinned: pinned, agentCreated: agentCreated)
    }
}
