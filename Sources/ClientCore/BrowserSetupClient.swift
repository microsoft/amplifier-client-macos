import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum BrowserSetupError: LocalizedError {
    case unsupported, invalidResponse, unavailable
    public var errorDescription: String? {
        switch self {
        case .unsupported: return "This Amplifier does not offer browser setup yet. Your chat connection is unchanged."
        case .invalidResponse: return "Amplifier returned an unsupported browser setup response. Your chat connection is unchanged."
        case .unavailable: return "Could not open browser setup. Check the host address and try again. Your chat connection is unchanged."
        }
    }
}

private final class BrowserSetupNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Read-only discovery. The external browser and extension own execution enrollment;
/// this client neither receives a device credential nor creates a setup/operation.
public final class BrowserSetupClient {
    private let endpoint: Endpoint
    private let session: URLSession
    public init(endpoint: Endpoint, configuration: URLSessionConfiguration = .ephemeral) {
        self.endpoint = endpoint
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.httpAdditionalHeaders = nil
        configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8; configuration.timeoutIntervalForResource = 12
        session = URLSession(configuration: configuration, delegate: BrowserSetupNoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    public func setupURL() async throws -> URL {
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint.route("api", "connections", "v1"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw BrowserSetupError.invalidResponse }
        if [404, 501].contains(http.statusCode) { throw BrowserSetupError.unsupported }
        guard http.statusCode == 200 else { throw BrowserSetupError.unavailable }
        guard http.mimeType == "application/json", data.count <= 65_536,
              let value = try? JSONDecoder().decode(Discovery.self, from: data),
              value.protocolVersion == 1, value.transport == "outbound-poll",
              value.enrollment == "/api/connections/v1/enroll", value.token == "/api/connections/v1/token",
              value.selfPath == "/api/connections/v1/self",
              value.grants["browser.observe"] != nil else { throw BrowserSetupError.invalidResponse }
        // Never open an arbitrary server-supplied URL or pass credentials in a URL.
        return endpoint.route("connect")
    }

    private struct Discovery: Decodable {
        let protocolVersion: Int
        let transport: String
        let enrollment: String
        let token: String
        let selfPath: String
        let grants: [String: String]
        enum CodingKeys: String, CodingKey {
            case protocolVersion, transport, enrollment, token, grants
            case selfPath = "self"
        }
    }
}
