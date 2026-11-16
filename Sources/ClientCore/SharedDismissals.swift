import Foundation

public struct DismissalIntent: Codable, Equatable {
    public let requestID: String
    public let serviceID: String
    public let endpoint: String
    public let hostIdentity: String
    public let id: String
    public let fingerprint: String
    public var accepted: Bool
    public func matches(_ service: RegisteredService) -> Bool {
        serviceID == service.id && endpoint == service.address && hostIdentity == service.hostIdentity
    }
}
/// Own only durable pending presentation intent. The host remains authoritative
/// across devices. Local display settings and chat-reply recovery stay separate.
public struct SharedDismissals: Codable {
    public private(set) var entries: [DismissalIntent] = []
    public init() {}
    public mutating func enqueue(_ state: DismissalDescriptor, service: RegisteredService) throws -> DismissalIntent {
        guard let host = service.hostIdentity, !state.id.isEmpty, !state.fingerprint.isEmpty else { throw CompanionError.incompatibleHost }
        if let existing = entries.first(where: { $0.matches(service) && $0.id == state.id && $0.fingerprint == state.fingerprint }) { return existing }
        guard entries.count < 512 else { throw CompanionError.observationPending }
        let entry = DismissalIntent(requestID: UUID().uuidString.lowercased(), serviceID: service.id,
            endpoint: service.address, hostIdentity: host, id: state.id, fingerprint: state.fingerprint, accepted: false)
        entries.append(entry); return entry
    }
    public func hidden(_ state: DismissalDescriptor, service: RegisteredService) -> Bool {
        state.dismissed || entries.contains { $0.matches(service) && $0.id == state.id && $0.fingerprint == state.fingerprint }
    }
    public mutating func accepted(_ requestID: String) {
        if let index = entries.firstIndex(where: { $0.requestID == requestID }) { entries[index].accepted = true }
    }
    /// Call only with a complete fresh observation, never an offline/partial one.
    public mutating func reconcile(_ current: [DismissalDescriptor], service: RegisteredService) {
        entries.removeAll { entry in
            guard entry.matches(service) else { return false }
            return !current.contains { $0.id == entry.id && $0.fingerprint == entry.fingerprint && !$0.dismissed }
        }
    }
    public func save(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    public static func load(from file: URL) throws -> SharedDismissals {
        guard FileManager.default.fileExists(atPath: file.path) else { return SharedDismissals() }
        return try JSONDecoder().decode(SharedDismissals.self, from: Data(contentsOf: file))
    }
}
