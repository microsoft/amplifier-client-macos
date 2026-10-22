import XCTest
@testable import ClientCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class BrowserSetupTests: XCTestCase {
    private func discovery() -> [String: Any] {
        ["protocolVersion": 1, "transport": "outbound-poll",
         "enrollment": "/api/connections/v1/enroll", "token": "/api/connections/v1/token",
         "self": "/api/connections/v1/self", "grants": ["browser.observe": "Inspect selected document"]]
    }
    private func client() throws -> BrowserSetupClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserDiscoveryStub.self]
        // The caller cannot accidentally carry its chat authorization into discovery.
        config.httpAdditionalHeaders = ["Authorization": "Bearer synthetic-chat-token", "Cookie": "synthetic-cookie"]
        return BrowserSetupClient(endpoint: try Endpoint("https://example.invalid:8444"), configuration: config)
    }
    override func tearDown() { BrowserDiscoveryStub.handler = nil; super.tearDown() }

    func testDiscoveryIsAnonymousReadOnlyAndOpensOnlyTheCapturedOrigin() async throws {
        var requests = 0
        var value = discovery()
        value["setupURL"] = "https://untrusted.invalid/enable?token=not-a-credential"
        value["futureCapability"] = true
        BrowserDiscoveryStub.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.absoluteString, "https://example.invalid:8444/api/connections/v1")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody); XCTAssertNil(request.httpBodyStream)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (200, "application/json", try JSONSerialization.data(withJSONObject: value))
        }
        let url = try await client().setupURL()
        XCTAssertEqual(url.absoluteString, "https://example.invalid:8444/connect")
        XCTAssertEqual(requests, 1, "Discovery must not enroll, poll, approve or execute")
    }

    func testAbsentFeatureDoesNotFallBackToAuthenticatedEnrollment() async throws {
        for status in [404, 501] {
            var requests = 0
            BrowserDiscoveryStub.handler = { _ in requests += 1; return (status, "text/html", Data()) }
            do { _ = try await client().setupURL(); XCTFail("Opened unsupported host") }
            catch BrowserSetupError.unsupported { }
            XCTAssertEqual(requests, 1)
        }
    }

    func testInvalidProtocolAndForeignEndpointsFailClosed() async throws {
        let changes: [(String, Any)] = [
            ("protocolVersion", 2), ("transport", "arbitrary-shell"),
            ("enrollment", "https://untrusted.invalid/enroll"),
            ("token", "/other/token"), ("self", "//untrusted.invalid/self"),
            ("grants", ["connection.ping": "Ping"])
        ]
        for (key, bad) in changes {
            var value = discovery(); value[key] = bad
            BrowserDiscoveryStub.handler = { _ in (200, "application/json", try JSONSerialization.data(withJSONObject: value)) }
            do { _ = try await client().setupURL(); XCTFail("Accepted invalid \(key)") }
            catch BrowserSetupError.invalidResponse { }
        }
    }

    func testErrorsAndNonDiscoveryBodiesNeverOpenSetup() async throws {
        for status in [301, 302, 401, 403, 500] {
            BrowserDiscoveryStub.handler = { _ in (status, "application/json", try JSONSerialization.data(withJSONObject: self.discovery())) }
            do { _ = try await client().setupURL(); XCTFail("Accepted HTTP \(status)") }
            catch BrowserSetupError.unavailable { }
        }
        for (mime, data) in [("text/html", Data("<html>sign in</html>".utf8)),
                             ("application/json", Data("{}".utf8)),
                             ("application/json", Data(repeating: 32, count: 65_537))] {
            BrowserDiscoveryStub.handler = { _ in (200, mime, data) }
            do { _ = try await client().setupURL(); XCTFail("Accepted invalid discovery body") }
            catch BrowserSetupError.invalidResponse { }
        }
    }
}

private final class BrowserDiscoveryStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, mime, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": mime])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
