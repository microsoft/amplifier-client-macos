import XCTest
@testable import ClientCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ServicesTests: XCTestCase {
    func testLegacyMigrationPreservesCredentialAccountAndPausedState() throws {
        let registry = try ServiceRegistry.load(data: nil, legacyAddress: "https://example.com:443", legacyPaused: true)
        let original = try XCTUnwrap(registry.services.first)
        XCTAssertEqual(original.address, "https://example.com:443")
        XCTAssertTrue(original.paused)
        XCTAssertEqual(registry.preferredID, original.id)
        let restored = try ServiceRegistry.load(data: JSONEncoder().encode(registry), legacyAddress: "https://ignored.example", legacyPaused: false)
        XCTAssertEqual(restored, registry)
        var removed = restored; removed.remove(original.id)
        XCTAssertTrue(try ServiceRegistry.load(data: JSONEncoder().encode(removed), legacyAddress: original.address, legacyPaused: false).services.isEmpty,
                      "An intentionally empty catalog must not resurrect the legacy registration")
    }
    func testRegistrationsDeduplicateOriginButKeepIndependentPortsAndIdentities() throws {
        var registry = ServiceRegistry()
        var first = try registry.register(address: "https://example.com:443", name: "Office", reapproved: false)
        first.hostIdentity = "host-a"; registry.replace(first)
        let alias = try registry.register(address: "https://EXAMPLE.com/", name: "Renamed", reapproved: false)
        XCTAssertEqual(alias.id, first.id); XCTAssertEqual(alias.address, first.address)
        XCTAssertEqual(alias.hostIdentity, "host-a")
        let other = try registry.register(address: "https://example.com:8443", name: "Lab", reapproved: true)
        XCTAssertNotEqual(other.id, first.id); XCTAssertEqual(registry.services.count, 2)
        registry.remove(other.id)
        XCTAssertEqual(registry.preferredID, first.id)
        let reapproved = try registry.register(address: first.address, name: "Office", reapproved: true)
        XCTAssertNil(reapproved.hostIdentity)
    }
    func testDamagedRegistryNeverFallsBackToLegacyOrDropsExistingRegistrations() throws {
        XCTAssertThrowsError(try ServiceRegistry.load(data: Data("bad".utf8), legacyAddress: "https://example.com", legacyPaused: false))
        var registry = ServiceRegistry(); registry.version = 2
        XCTAssertThrowsError(try ServiceRegistry.load(data: JSONEncoder().encode(registry), legacyAddress: nil, legacyPaused: false))
        registry.version = 1; registry.preferredID = "missing"
        XCTAssertThrowsError(try ServiceRegistry.load(data: JSONEncoder().encode(registry), legacyAddress: nil, legacyPaused: false))
    }
    func testCapturedDestinationCannotFollowDefaultOrReplacementHost() throws {
        var a = try RegisteredService(address: "https://a.example", name: "Same name")
        let b = try RegisteredService(address: "https://b.example", name: "Same name")
        let target = ServiceTarget(service: a, hostIdentity: "same-host", sessionID: "same-chat")
        let other = ServiceTarget(service: b, hostIdentity: "same-host", sessionID: "same-chat")
        XCTAssertNotEqual(target.key, other.key)
        XCTAssertNotEqual(ServiceTarget(service: a, hostIdentity: "same-host", sessionID: nil).key, ServiceTarget(service: a, hostIdentity: "same-host", sessionID: "").key)
        XCTAssertEqual(target.url.host, "a.example")
        XCTAssertTrue(target.matches(service: a, hostIdentity: "same-host"))
        XCTAssertFalse(target.matches(service: b, hostIdentity: "same-host"))
        XCTAssertFalse(target.matches(service: a, hostIdentity: "replacement"))
        a.paused = true; XCTAssertFalse(target.matches(service: a, hostIdentity: "same-host"))
        let new = try RegisteredService(address: a.address)
        XCTAssertFalse(target.matches(service: new, hostIdentity: "same-host"), "Forget/re-add must not retarget a captured draft")
    }
    func testAttentionAndRepliesWithCollidingIDsRemainIndependent() throws {
        let data = snapshotData(host: "cloned-host", fingerprint: "one")
        var snapshot = try JSONDecoder().decode(CompanionSnapshot.self, from: data)
        var journal = Journal()
        XCTAssertTrue(journal.observe(snapshot, endpoint: "https://a.example", enabled: true, pinnedOnly: false).isEmpty)
        XCTAssertTrue(journal.observe(snapshot, endpoint: "https://b.example", enabled: true, pinnedOnly: false).isEmpty)
        snapshot = try JSONDecoder().decode(CompanionSnapshot.self, from: snapshotData(host: "cloned-host", fingerprint: "two"))
        XCTAssertEqual(journal.observe(snapshot, endpoint: "https://a.example", enabled: true, pinnedOnly: false).count, 1)
        XCTAssertEqual(journal.observe(snapshot, endpoint: "https://b.example", enabled: true, pinnedOnly: false).count, 1)
        for endpoint in ["https://a.example", "https://b.example"] {
            XCTAssertTrue(journal.enqueue(notificationID: "same", endpoint: endpoint, hostIdentity: "cloned-host", sessionID: "chat", text: "Reply").1)
        }
        XCTAssertEqual(journal.replies.count, 2)
        let item = try XCTUnwrap(snapshot.items.first)
        XCTAssertNotEqual(item.scoped(to: "service-a").id, item.scoped(to: "service-b").id)
    }
    func testStoppedTransportCannotStartAnotherReadButOtherServiceStillWorks() async throws {
        ServicesURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "b.example", "Stopped credential must not issue further requests")
            return (200, Data("{\"protocolVersion\":1}".utf8))
        }
        defer { ServicesURLProtocol.handler = nil }
        func client(_ address: String) throws -> HostClient {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ServicesURLProtocol.self]
            return HostClient(endpoint: try Endpoint(address), token: "fixture", clientID: "fixture", configuration: config)
        }
        let stopped = try client("https://a.example"), healthy = try client("https://b.example")
        stopped.cancelRequests()
        do { try await stopped.attach(); XCTFail("Stopped transport was reused") } catch { }
        try await healthy.attach()
    }
    func testInFlightReadsCancelOnTaskCancellationAndServiceStop() async throws {
        let started = expectation(description: "two reads started"); started.expectedFulfillmentCount = 2
        let finished = expectation(description: "both reads canceled"); finished.expectedFulfillmentCount = 2
        HeldServiceURLProtocol.onStart = { started.fulfill() }
        defer { HeldServiceURLProtocol.onStart = nil }
        func client() throws -> HostClient {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HeldServiceURLProtocol.self]
            return HostClient(endpoint: try Endpoint("https://example.com"), token: "fixture", clientID: "fixture", configuration: config)
        }
        let first = try client(), second = try client()
        func read(_ client: HostClient) async {
            do { try await client.attach(); XCTFail("Canceled read completed") }
            catch { XCTAssertEqual((error as NSError).code, NSURLErrorCancelled) }
            finished.fulfill()
        }
        let task = Task { await read(first) }, other = Task { await read(second) }
        defer { task.cancel(); other.cancel(); first.cancelRequests(); second.cancelRequests() }
        await fulfillment(of: [started], timeout: 3)
        task.cancel(); second.cancelRequests()
        await fulfillment(of: [finished], timeout: 3)
    }
    @MainActor func testFailingServiceDoesNotBlockHealthyServiceAndPauseKeepsOtherConnection() async throws {
        let a = ServiceConnection(try RegisteredService(address: "https://a.example"))
        let b = ServiceConnection(try RegisteredService(address: "https://b.example"))
        let healthy = expectation(description: "healthy snapshot"), failed = expectation(description: "offline service")
        let payload = snapshotData(host: "host-b")
        ServicesURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-" + request.url!.host!)
            if request.url?.host == "a.example" { return (503, Data()) }
            return (200, request.url!.path.hasSuffix("attach") ? Data("{\"protocolVersion\":1}".utf8) : payload)
        }
        defer { a.stop(); b.stop(); ServicesURLProtocol.handler = nil }
        a.onChange = { if a.status.contains("503") { failed.fulfill() } }
        b.onSnapshot = { _, _, _ in healthy.fulfill() }
        func make(_ endpoint: Endpoint, _ token: String, _ id: String) -> HostClient {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ServicesURLProtocol.self]
            return HostClient(endpoint: endpoint, token: token, clientID: id, configuration: config)
        }
        a.start(clientID: "fixture", token: { "token-" + URL(string: $0)!.host! }, makeClient: make)
        b.start(clientID: "fixture", token: { "token-" + URL(string: $0)!.host! }, makeClient: make)
        await fulfillment(of: [healthy, failed], timeout: 3)
        XCTAssertFalse(a.connected); XCTAssertTrue(b.connected)
        let client = b.client
        a.registration.paused = true; a.stop()
        XCTAssertTrue(b.connected); XCTAssertTrue(b.client === client)
        b.stop(); XCTAssertFalse(b.connected)
        XCTAssertNotNil(b.latest, "Last observation may be retained, but is unavailable, not current")
    }
    @MainActor func testCanceledCredentialReadCannotReconnectAndHostReplacementIsRejected() async throws {
        let state = ServiceConnection(try RegisteredService(address: "https://example.com"))
        let began = expectation(description: "credential started")
        var release: CheckedContinuation<String?, Never>?
        state.start(clientID: "fixture", token: { _ in
            began.fulfill(); return await withCheckedContinuation { release = $0 }
        }, makeClient: { _, _, _ in fatalError("Canceled generation must not create a client") })
        await fulfillment(of: [began], timeout: 1)
        state.stop(); release?.resume(returning: "token")
        await Task.yield(); XCTAssertNil(state.client); XCTAssertFalse(state.connected)
        state.registration.hostIdentity = "original"
        let rejected = expectation(description: "different durable host refused")
        let payload = snapshotData(host: "replacement")
        ServicesURLProtocol.handler = { request in (200, request.url!.path.hasSuffix("attach") ? Data("{\"protocolVersion\":1}".utf8) : payload) }
        defer { state.stop(); ServicesURLProtocol.handler = nil }
        state.onSnapshot = { _, _, _ in XCTFail("Replacement snapshot published") }
        state.onChange = { if state.status == CompanionError.changedService.localizedDescription { rejected.fulfill() } }
        state.start(clientID: "fixture", token: { _ in "token" }, makeClient: { endpoint, token, id in
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ServicesURLProtocol.self]
            return HostClient(endpoint: endpoint, token: token, clientID: id, configuration: config)
        })
        await fulfillment(of: [rejected], timeout: 3)
        XCTAssertFalse(state.connected); XCTAssertNil(state.latest)
    }
    private func snapshotData(host: String, fingerprint: String = "one") -> Data {
        try! JSONSerialization.data(withJSONObject: ["protocolVersion": 1, "hostIdentity": host, "hostInstanceId": "process",
            "workingCount": 0, "attentionCount": 1, "sessions": [], "sessionsTruncated": false, "itemsTruncated": false,
            "items": [["id": "completion:chat", "fingerprint": fingerprint, "sessionId": "chat", "title": "Synthetic chat", "kind": "completion", "summary": "Ready", "pinned": true]]])
    }
}

private final class ServicesURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class HeldServiceURLProtocol: URLProtocol {
    static var onStart: (() -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.onStart?() }
    override func stopLoading() {}
}
