import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PairingError: LocalizedError {
    case unsupported, invalidResponse, denied, expired, unavailable
    public var errorDescription: String? {
        switch self {
        case .unsupported: return "This Amplifier does not support browser connection yet. Update the host, or use an access token."
        case .invalidResponse: return "Amplifier returned an invalid connection response."
        case .denied: return "The connection was denied or removed. Start again when you’re ready."
        case .expired: return "The connection request expired. Choose Connect in browser to try again."
        case .unavailable: return "Could not connect. Check the Amplifier address and try again."
        }
    }
}

public struct PairingRequest: Decodable {
    public let id: String
    public let code: String
    public let verificationPath: String
    public let expiresIn: Int
    public let interval: Int
    public func browserURL(endpoint: Endpoint) throws -> URL {
        guard id.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              code.range(of: "^[A-Z2-9]{4}-[A-Z2-9]{4}$", options: .regularExpression) != nil,
              verificationPath == "/devices/pair?id=" + id,
              (1...600).contains(expiresIn), (5...30).contains(interval),
              let url = URL(string: endpoint.url.absoluteString + verificationPath) else { throw PairingError.invalidResponse }
        return url
    }
}

private final class PairingNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public final class PairingClient {
    private let endpoint: Endpoint
    private let session: URLSession
    public init(endpoint: Endpoint, configuration: URLSessionConfiguration = .ephemeral) {
        self.endpoint = endpoint
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: PairingNoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    private func post(_ path: [String], body: [String: String]) async throws -> Data {
        var request = URLRequest(url: path.reduce(endpoint.url) { $0.appendingPathComponent($1) })
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PairingError.invalidResponse }
        switch http.statusCode {
        case 200: return data
        case 401, 404: throw PairingError.unsupported
        case 410: throw PairingError.expired
        case 403: throw PairingError.denied
        default: throw PairingError.unavailable
        }
    }
    public func begin(name: String, challenge: String) async throws -> PairingRequest {
        let data = try await post(["api", "devices", "pair"], body: ["name": name, "challenge": challenge])
        let request = try JSONDecoder().decode(PairingRequest.self, from: data)
        _ = try request.browserURL(endpoint: endpoint)
        return request
    }
    /// A pending result never saves a credential. Only the proof-bound approved result does.
    public func poll(id: String, verifier: String) async throws -> String? {
        let data = try await post(["api", "devices", "pair", "token"], body: ["id": id, "verifier": verifier])
        let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        switch value?["status"] as? String {
        case "pending": return nil
        case "approved":
            guard value?["scope"] as? String == "companion-v1", let token = value?["token"] as? String,
                  token.range(of: "^amc_[a-f0-9]{32}\\.[A-Za-z0-9_-]{64}$", options: .regularExpression) != nil else { throw PairingError.invalidResponse }
            return token
        case "denied", "revoked": throw PairingError.denied
        default: throw PairingError.invalidResponse
        }
    }
}
