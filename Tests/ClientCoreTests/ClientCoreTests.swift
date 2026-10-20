import XCTest
@testable import ClientCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ClientCoreTests: XCTestCase {
    func testWebAppLaunchPinsProfileWithoutChangingChatURL() throws {
        let id = String(repeating: "a", count: 32)
        let url = try Endpoint("https://host:8443").chatURL("chat A&other=value")
        let args = WebAppLaunch.arguments(appID: id, target: url, profile: "Profile 1")
        XCTAssertEqual(args.count, 3)
        XCTAssertEqual(args.last, "--profile-directory=Profile 1")
        let passedURL = try XCTUnwrap(URL(string: String(args[1].dropFirst("--app-launch-url-for-shortcuts-menu-item=".count))))
        XCTAssertEqual(URLComponents(url: passedURL, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "chat", value: "chat A&other=value")])
        XCTAssertEqual(WebAppLaunch.arguments(appID: id, target: url, profile: nil).count, 2)
        for invalid in ["../Default", "/tmp/profile", "..", "--profile-directory=Other", "Default\nOther", "", String(repeating: "a", count: 101)] {
            XCTAssertNil(WebAppLaunch.profileDirectory(invalid), invalid)
        }
        XCTAssertEqual(WebAppLaunch.profileDirectory(" Default "), "Default")
    }
    func testBrowserProfileBindingRequiresExactAppIdentity() {
        let id = String(repeating: "a", count: 32)
        XCTAssertEqual(WebAppLaunch.browserID(for: "com.microsoft.edgemac.app." + id, appID: id), "com.microsoft.edgemac")
        XCTAssertEqual(WebAppLaunch.browserID(for: "com.google.Chrome.app." + id, appID: id), "com.google.Chrome")
        XCTAssertNil(WebAppLaunch.browserID(for: "com.microsoft.edgemac.app.other", appID: id))
        XCTAssertNil(WebAppLaunch.browserID(for: "com.microsoft.edgemac.app." + id, appID: "--argument"))
    }
    func snapshot(_ fingerprint: String = "one", host: String = "host", pinned: Bool = true) throws -> CompanionSnapshot {
        let value: [String: Any] = ["protocolVersion": 1, "hostIdentity": host, "hostInstanceId": UUID().uuidString,
            "workingCount": 1, "attentionCount": 1, "sessions": [], "sessionsTruncated": false, "itemsTruncated": false,
            "items": [["id": "completion:chat-A", "fingerprint": fingerprint, "sessionId": "chat-A", "title": "A",
                       "kind": "completion", "summary": "Response ready", "pinned": pinned]]]
        return try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testOlderHostKeepsPairingUnsupportedInsteadOfRequestingCredentials() async throws {
        StubURLProtocol.handler = { _ in (401, Data()) }
        defer { StubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let client = PairingClient(endpoint: try Endpoint("https://host"), configuration: config)
        do { _ = try await client.begin(name: "Mac", challenge: String(repeating: "a", count: 43)); XCTFail("Expected unsupported") }
        catch PairingError.unsupported { }
    }
    func testPairingCannotRedirectBrowserToAnotherHost() throws {
        let endpoint = try Endpoint("https://host")
        let id = String(repeating: "a", count: 43)
        for path in ["https://evil.example/devices/pair", "//evil.example", "/devices/pair?id=" + id + "&next=evil", "/login"] {
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "code": "ABCD-EFGH", "verificationPath": path, "expiresIn": 600, "interval": 5])
            let request = try JSONDecoder().decode(PairingRequest.self, from: data)
            XCTAssertThrowsError(try request.browserURL(endpoint: endpoint))
        }
    }
    func testPairingOnlyAcceptsApprovedScopedCredentials() async throws {
        let id = String(repeating: "a", count: 43)
        var result: [String: Any] = ["status": "pending"]
        StubURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.httpMethod, "POST")
            return (200, try JSONSerialization.data(withJSONObject: result))
        }
        defer { StubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let client = PairingClient(endpoint: try Endpoint("https://host"), configuration: config)
        let pending = try await client.poll(id: id, verifier: id)
        XCTAssertNil(pending)
        result = ["status": "approved", "token": "control-token", "scope": "full"]
        do { _ = try await client.poll(id: id, verifier: id); XCTFail("Accepted unscoped credential") }
        catch PairingError.invalidResponse { }
        let token = "amc_" + String(repeating: "a", count: 32) + "." + String(repeating: "b", count: 64)
        result = ["status": "approved", "token": token, "scope": "companion-v1"]
        let approved = try await client.poll(id: id, verifier: id)
        XCTAssertEqual(approved, token)
        result = ["status": "approved", "token": token.replacingOccurrences(of: "amc_", with: "amt_"), "scope": "companion-v1"]
        do { _ = try await client.poll(id: id, verifier: id); XCTFail("Accepted legacy full-authority token family") }
        catch PairingError.invalidResponse { }
        result = ["status": "revoked"]
        do { _ = try await client.poll(id: id, verifier: id); XCTFail("Accepted revoked credential") }
        catch PairingError.denied { }
    }
    func testPairingUsesDistinctStableClientIdentityWithoutChangingJournal() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let endpoint = try Endpoint("https://host")
        var identities = [String]()
        StubURLProtocol.handler = { request in
            let identity = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Amplifier-Client"))
            identities.append(identity)
            XCTAssertLessThanOrEqual(identity.count, 100)
            return (200, Data("{\"protocolVersion\":1}".utf8))
        }
        defer { StubURLProtocol.handler = nil }
        for device in ["a", "a", "b"] {
            let token = "amc_" + String(repeating: device, count: 32) + "." + String(repeating: "s", count: 64)
            try await HostClient(endpoint: endpoint, token: token, clientID: "mac-existing", configuration: config).attach()
        }
        try await HostClient(endpoint: endpoint, token: "manual-token", clientID: "mac-existing", configuration: config).attach()
        XCTAssertEqual(identities[0], identities[1])
        XCTAssertNotEqual(identities[0], identities[2])
        XCTAssertNotEqual(identities[0], identities[3])
        XCTAssertEqual(identities[3], "mac-existing")
    }
    func testEndpointValidationAndEncodedNavigation() throws {
        for address in ["http://example.com", "https://user:pass@host", "https://host/?token=x", "https://host/path", "file:///tmp/a", "https://host/#x"] {
            XCTAssertThrowsError(try Endpoint(address), address)
        }
        let host = try Endpoint("http://127.0.0.1:8941/")
        XCTAssertEqual(host.url.absoluteString, "http://127.0.0.1:8941")
        let url = host.chatURL("chat A&other=value")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.count, 1)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "chat A&other=value")
    }
    func testBaselineAndRestartNeverReplayOldNotifications() throws {
        var ledger = Journal()
        XCTAssertTrue(ledger.observe(try snapshot(), endpoint: "host", enabled: true, pinnedOnly: true).isEmpty)
        XCTAssertTrue(ledger.observe(try snapshot(), endpoint: "host", enabled: true, pinnedOnly: true).isEmpty)
        XCTAssertEqual(ledger.observe(try snapshot("two"), endpoint: "host", enabled: true, pinnedOnly: true).count, 1)
        XCTAssertTrue(ledger.observe(try snapshot("two", host: "replacement"), endpoint: "host", enabled: true, pinnedOnly: true).isEmpty)
    }
    func testDisabledAndUnpinnedActivityDoesNotFloodWhenEnabled() throws {
        var ledger = Journal()
        _ = ledger.observe(try snapshot(), endpoint: "host", enabled: false, pinnedOnly: true)
        XCTAssertTrue(ledger.observe(try snapshot("two", pinned: false), endpoint: "host", enabled: true, pinnedOnly: true).isEmpty)
        XCTAssertTrue(ledger.observe(try snapshot("two", pinned: false), endpoint: "host", enabled: true, pinnedOnly: false).isEmpty)
    }
    func testReplyTargetAndIdentitySurviveRestart() throws {
        var ledger = Journal()
        let (first, fresh) = ledger.enqueue(notificationID: "notice", endpoint: "https://host", hostIdentity: "host-id", sessionID: "chat-A", text: "Continue")
        XCTAssertTrue(fresh)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("journal.json")
        ledger.mark(first.id, "unconfirmed"); try ledger.save(to: file)
        var restored = try Journal.load(from: file)
        let (duplicate, isNew) = restored.enqueue(notificationID: "notice", endpoint: "https://host", hostIdentity: "host-id", sessionID: "chat-A", text: "Continue")
        XCTAssertFalse(isNew); XCTAssertEqual(first.id, duplicate.id)
        XCTAssertEqual(duplicate.sessionID, "chat-A"); XCTAssertEqual(duplicate.status, "unconfirmed")
        XCTAssertEqual(restored.clientID, ledger.clientID)
        try Data("broken".utf8).write(to: file)
        XCTAssertThrowsError(try Journal.load(from: file))
    }
    func testFreshNotificationWaitsForMatchingHostAndKeepsIdentity() {
        var ledger = Journal()
        let (reply, fresh) = ledger.enqueue(notificationID: "cold-launch", endpoint: "https://host", hostIdentity: "original", sessionID: "chat-A", text: "Continue")
        XCTAssertTrue(fresh)
        func decision(_ endpoint: String? = "https://host", _ identity: String? = nil,
                      connected: Bool = false, paused: Bool = false, expired: Bool = false) -> NotificationDelivery.Decision {
            NotificationDelivery.decision(for: reply, endpoint: endpoint, hostIdentity: identity,
                connected: connected, paused: paused, expired: expired)
        }
        XCTAssertEqual(decision(), .wait)
        XCTAssertEqual(decision("https://host", "original", connected: true), .send)
        XCTAssertEqual(decision("https://host", "replacement", connected: true), .keepSaved)
        XCTAssertEqual(decision("https://other"), .keepSaved)
        XCTAssertEqual(decision(paused: true), .keepSaved)
        XCTAssertEqual(decision(expired: true), .keepSaved)
        ledger.mark(reply.id, "unconfirmed")
        let (duplicate, isNew) = ledger.enqueue(notificationID: "cold-launch", endpoint: "https://host", hostIdentity: "original", sessionID: "chat-A", text: "Continue")
        XCTAssertFalse(isNew, "Replayed OS callbacks must not start another automatic delivery")
        XCTAssertEqual(duplicate.id, reply.id)
        XCTAssertEqual(duplicate.status, "unconfirmed")
    }
    func testStateMapping() {
        XCTAssertEqual(Motion.status(connected: false, working: 3, attention: 1), .waiting)
        XCTAssertEqual(Motion.status(connected: true, working: 3, attention: 1), .review)
        XCTAssertEqual(Motion.status(connected: true, working: 3, attention: 0), .working)
        XCTAssertEqual(Motion.status(connected: true, working: 0, attention: 0), .idle)
    }
    func testReassignedAddressCannotReceiveAnOldReply() async throws {
        var ledger = Journal()
        let (reply, _) = ledger.enqueue(notificationID: "notice", endpoint: "https://host", hostIdentity: "original",
                                       sessionID: "chat-A", text: "Continue")
        let data = try JSONSerialization.data(withJSONObject: ["protocolVersion": 1, "hostIdentity": "replacement", "hostInstanceId": "instance",
            "workingCount": 0, "attentionCount": 0, "sessions": [], "items": [], "sessionsTruncated": false, "itemsTruncated": false])
        var requests = 0
        StubURLProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url!.path, "/api/companion")
            return (200, data)
        }
        defer { StubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let client = HostClient(endpoint: try Endpoint("https://host"), token: "token", clientID: ledger.clientID, configuration: config)
        do { try await client.send(reply); XCTFail("Wrong host accepted a reply") }
        catch CompanionError.changedHost { }
        XCTAssertEqual(requests, 1)
    }
    func testReplyUsesCapturedTargetAndExactIDForRetry() async throws {
        var ledger = Journal()
        let (reply, _) = ledger.enqueue(notificationID: "notice", endpoint: "https://host", hostIdentity: "host", sessionID: "chat-A", text: "Continue")
        let data = try JSONSerialization.data(withJSONObject: ["protocolVersion": 1, "hostIdentity": "host", "hostInstanceId": "instance",
            "workingCount": 0, "attentionCount": 0, "sessions": [], "items": [], "sessionsTruncated": false, "itemsTruncated": false])
        var commands: [[String: Any]] = []
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer private-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Amplifier-Client"), ledger.clientID)
            if request.url!.path == "/api/companion" { return (200, data) }
            XCTAssertEqual(request.url!.path, "/api/sessions/chat-A/commands")
            let body: Data
            if let bytes = request.httpBody { body = bytes }
            else {
                let stream = request.httpBodyStream!; stream.open(); defer { stream.close() }
                var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; result.append(buffer, count: count) }
                body = result
            }
            commands.append(try JSONSerialization.jsonObject(with: body) as! [String: Any])
            return (200, Data("{\"accepted\":true}".utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let client = HostClient(endpoint: try Endpoint("https://host"), token: "private-token", clientID: ledger.clientID, configuration: config)
        try await client.send(reply); try await client.send(reply)
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0]["id"] as? String, reply.id)
        XCTAssertEqual(commands[1]["id"] as? String, reply.id)
        XCTAssertEqual((commands[0]["args"] as? [String: Any])?["preserveDraft"] as? Bool, true)
    }
    func testComposerPersistsCreationIdentityAndFollowsOnlyItsHost() throws {
        var ledger = Journal()
        _ = ledger.observe(try snapshot(pinned: false), endpoint: "https://host", enabled: true, pinnedOnly: true)
        let new = ledger.compose(endpoint: "https://host", hostIdentity: "host", sessionID: nil, text: "Hello")
        XCTAssertNotNil(new.createCommandID)
        XCTAssertEqual(UUID(uuidString: new.sessionID)?.uuidString.lowercased(), new.sessionID)
        let restored = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored.replies.first?.createCommandID, new.createCommandID)
        _ = ledger.compose(endpoint: "https://host", hostIdentity: "host", sessionID: "chat-A", text: "Continue")
        XCTAssertEqual(ledger.observe(try snapshot("two", pinned: false), endpoint: "https://host", enabled: true, pinnedOnly: true).count, 1)
        XCTAssertFalse(ledger.follows("chat-A", endpoint: "https://other", hostIdentity: "host"))
        XCTAssertFalse(ledger.follows("chat-A", endpoint: "https://host", hostIdentity: "replacement"))
        XCTAssertTrue(ledger.observe(try snapshot("three", pinned: false), endpoint: "https://host", enabled: false, pinnedOnly: true).isEmpty)
    }
    func testOldJournalWithoutCreationFieldStillLoads() throws {
        var ledger = Journal()
        _ = ledger.enqueue(notificationID: "old", endpoint: "host", hostIdentity: "host", sessionID: "chat-A", text: "Old reply")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
        var replies = json["replies"] as! [[String: Any]]
        replies[0].removeValue(forKey: "createCommandID"); json["replies"] = replies
        let old = try JSONDecoder().decode(Journal.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.replies[0].createCommandID)
        XCTAssertEqual(old.replies[0].text, "Old reply")
    }
    func testWebAppMatchingRequiresExactOriginAndScope() {
        func match(_ launch: String, _ target: String) -> Bool { WebAppMatch.matches(URL(string: launch)!, target: URL(string: target)!) }
        XCTAssertTrue(match("https://amplifier.example:8443/", "https://amplifier.example:8443?chat=abc"))
        XCTAssertTrue(match("https://host/", "https://host:443/?chat=abc"))
        XCTAssertFalse(match("https://amplifier.example:8443/", "http://127.0.0.1:8080?chat=abc"))
        XCTAssertFalse(match("https://host:8443/", "https://host:9543/"))
        XCTAssertFalse(match("https://host/", "http://host/"))
        XCTAssertFalse(match("https://host/nested/index.html", "https://host/"))
        XCTAssertFalse(match("https://user@host/", "https://host/"))
    }
    func testNewChatRetryReusesBothCommandIDsAndNeverSelectsBrowser() async throws {
        var ledger = Journal()
        let reply = ledger.compose(endpoint: "https://host", hostIdentity: "host", sessionID: nil, text: "Hello")
        let data = try JSONSerialization.data(withJSONObject: ["protocolVersion": 1, "hostIdentity": "host", "hostInstanceId": "instance", "workingCount": 0, "attentionCount": 0, "sessions": [], "items": [], "sessionsTruncated": false, "itemsTruncated": false])
        var commands: [[String: Any]] = []
        StubURLProtocol.handler = { request in
            if request.url!.path == "/api/companion" { return (200, data) }
            let body = try self.body(request); commands.append(body)
            if request.url!.path == "/api/actions" {
                let args = body["args"] as! [String: Any]
                XCTAssertEqual(args["select"] as? Bool, false)
                XCTAssertEqual((args["location"] as? [String: String])?["kind"], "managed")
                return (200, try JSONSerialization.data(withJSONObject: ["accepted": true, "sessionId": reply.sessionID]))
            }
            XCTAssertEqual(request.url!.path, "/api/sessions/" + reply.sessionID + "/commands")
            return (200, Data("{\"accepted\":true}".utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let client = HostClient(endpoint: try Endpoint("https://host"), token: "test", clientID: "test", configuration: config)
        try await client.send(reply); try await client.send(reply)
        XCTAssertEqual(commands.count, 4)
        XCTAssertEqual(commands[0]["id"] as? String, reply.createCommandID)
        XCTAssertEqual(commands[2]["id"] as? String, reply.createCommandID)
        XCTAssertEqual(commands[1]["id"] as? String, reply.id)
        XCTAssertEqual(commands[3]["id"] as? String, reply.id)
    }
    func testUnconfirmedCreationDoesNotSendMessage() async throws {
        var ledger = Journal()
        let reply = ledger.compose(endpoint: "https://host", hostIdentity: "host", sessionID: nil, text: "Hello")
        let data = try JSONSerialization.data(withJSONObject: ["protocolVersion": 1, "hostIdentity": "host", "hostInstanceId": "instance", "workingCount": 0, "attentionCount": 0, "sessions": [], "items": [], "sessionsTruncated": false, "itemsTruncated": false])
        var paths: [String] = []
        StubURLProtocol.handler = { request in
            paths.append(request.url!.path)
            return (200, request.url!.path == "/api/companion" ? data : Data("{\"accepted\":true,\"sessionId\":\"wrong\"}".utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let client = HostClient(endpoint: try Endpoint("https://host"), token: "test", clientID: "test", configuration: config)
        do { try await client.send(reply); XCTFail("Creation identity was not verified") } catch CompanionError.uncertain { }
        XCTAssertEqual(paths, ["/api/companion", "/api/actions"])
    }
    func testResponsePreviewDoesNotReuseAnAnswerBeforeLatestUserMessage() async throws {
        var rows: [[String: String]] = [["role": "assistant", "text": "old answer"], ["role": "user", "text": "new question"]]
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/conversation/detail")
            return (200, try JSONSerialization.data(withJSONObject: ["items": rows]))
        }
        defer { StubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let client = HostClient(endpoint: try Endpoint("https://host"), token: "test", clientID: "test", configuration: config)
        let stale = try await client.responsePreview(sessionID: "chat-A"); XCTAssertNil(stale)
        rows.append(["role": "assistant", "text": String(repeating: "x", count: 900)])
        let current = try await client.responsePreview(sessionID: "chat-A"); XCTAssertEqual(current?.count, 600)
    }
    func testOnlyCanonicalWorkAndUserVisibleChatsReachTempo() throws {
        let sessions: [[String: Any]] = [
            ["id":"stopped", "status":"stopped", "pinned":true],
            ["id":"readonly", "status":"read-only", "pinned":true],
            ["id":"agent", "status":"working", "pinned":false, "agentCreated":true],
            ["id":"pinned-agent", "status":"starting", "pinned":true, "agentCreated":true],
            ["id":"followed-agent", "status":"running", "pinned":false, "agentCreated":true],
            ["id":"loading", "status":"idle", "pinned":true, "activity":["execution":false,"preparing":false,"loading":true]],
            ["id":"preparing", "status":"idle", "pinned":true, "activity":["execution":false,"preparing":true,"loading":false]]
        ].map { ["title":"Chat"].merging($0) { _, value in value } }
        let items = sessions.map { row in ["id":row["id"]!, "sessionId":row["id"]!, "fingerprint":"1", "title":"Chat",
            "kind":"completion", "summary":"Ready", "pinned":row["pinned"]!, "agentCreated":row["agentCreated"] ?? false] }
        let data = try JSONSerialization.data(withJSONObject:["protocolVersion":1,"hostIdentity":"host","hostInstanceId":"instance",
            "workingCount":20,"attentionCount":20,"sessions":sessions,"items":items,"sessionsTruncated":false,"itemsTruncated":false])
        let visible = try JSONDecoder().decode(CompanionSnapshot.self, from:data).visibleChats { $0 == "followed-agent" }
        XCTAssertFalse(visible.sessions.contains { $0.id == "agent" })
        XCTAssertFalse(visible.items.contains { $0.sessionId == "agent" })
        XCTAssertEqual(Set(visible.sessions.filter(\.isWorking).map(\.id)), ["pinned-agent","followed-agent","preparing"])
        XCTAssertEqual(visible.workingCount,3)
    }
    private func observationFixture(session: String = "A", item: String = "A", sessionCursor: String? = nil,
                                    itemCursor: String? = nil, host: String = "host") throws -> Data {
        var value: [String: Any] = ["protocolVersion": 1, "hostIdentity": host, "hostInstanceId": "instance",
            "workingCount": 1, "attentionCount": 3,
            "sessions": [["id": session, "title": session, "status": "ready", "pinned": true]],
            "items": [["id": item, "fingerprint": "one", "sessionId": item, "title": item,
                       "kind": "completion", "summary": "Response ready", "pinned": true]],
            "sessionsTruncated": sessionCursor != nil, "itemsTruncated": itemCursor != nil]
        value["sessionsNextCursor"] = sessionCursor; value["itemsNextCursor"] = itemCursor
        return try JSONSerialization.data(withJSONObject: value)
    }
    private func observationClient() throws -> HostClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        return HostClient(endpoint: try Endpoint("https://host"), token: "test", clientID: "test", configuration: config)
    }
    func testPendingActivityFollowsCursorBeforeRetryingRead() async throws {
        var step = 0
        StubURLProtocol.handler = { request in
            defer { step += 1 }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            switch step {
            case 0:
                XCTAssertEqual(request.url!.path, "/api/companion")
                return (503, Data("{\"code\":\"observation_pending\"}".utf8))
            case 1:
                XCTAssertEqual(request.url!.path, "/api/activity"); XCTAssertTrue(query.isEmpty)
                return (200, Data("{\"status\":\"collecting\",\"nextCursor\":\"a+/=\"}".utf8))
            case 2:
                XCTAssertEqual(query.first?.value, "a+/=")
                return (200, Data("{\"status\":\"ready\"}".utf8))
            default:
                XCTAssertEqual(request.url!.path, "/api/companion")
                return (200, try self.observationFixture())
            }
        }
        defer { StubURLProtocol.handler = nil }
        let result = try await observationClient().snapshot()
        XCTAssertEqual(result.items.count, 1); XCTAssertEqual(step, 4)
    }
    func testUnequalPageCountsRetainTerminalCursorAndDoNotDuplicateItems() async throws {
        var step = 0
        StubURLProtocol.handler = { request in
            defer { step += 1 }
            let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value!) })
            switch step {
            case 0: return (200, try self.observationFixture(sessionCursor: "s1", itemCursor: "i1"))
            case 1:
                XCTAssertEqual(query, ["sessionsCursor": "s1", "itemsCursor": "i1"])
                return (200, try self.observationFixture(session: "B", item: "B", sessionCursor: "s2"))
            default:
                XCTAssertEqual(query, ["sessionsCursor": "s2", "itemsCursor": "i1"])
                return (200, try self.observationFixture(session: "C", item: "B"))
            }
        }
        defer { StubURLProtocol.handler = nil }
        let result = try await observationClient().snapshot()
        XCTAssertEqual(result.sessions.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(result.items.map(\.id), ["A", "B"])
        XCTAssertFalse(result.sessionsTruncated); XCTAssertFalse(result.itemsTruncated)
        XCTAssertNil(result.sessionsNextCursor); XCTAssertNil(result.itemsNextCursor)
        XCTAssertEqual(step, 3)
    }
    func testExpiredTraversalDiscardsPartialBaselineAndStartsAgain() async throws {
        var step = 0
        StubURLProtocol.handler = { request in
            defer { step += 1 }
            if step == 0 { return (200, try self.observationFixture(sessionCursor: "expired")) }
            if step == 1 { return (409, Data("{}".utf8)) }
            XCTAssertTrue(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.isEmpty ?? true)
            return (200, try self.observationFixture(session: "fresh", item: "fresh"))
        }
        defer { StubURLProtocol.handler = nil }
        let result = try await observationClient().snapshot()
        XCTAssertEqual(result.sessions.map(\.id), ["fresh"]); XCTAssertEqual(result.items.map(\.id), ["fresh"])
        XCTAssertEqual(step, 3)
    }
    func testUnrelated503IsNotRetriedAsActivityCollection() async throws {
        var requests = 0
        StubURLProtocol.handler = { _ in requests += 1; return (503, Data("{\"code\":\"busy\"}".utf8)) }
        defer { StubURLProtocol.handler = nil }
        do { _ = try await observationClient().snapshot(); XCTFail("Accepted a failed snapshot") }
        catch CompanionError.rejected(503) { }
        XCTAssertEqual(requests, 1)
    }
    func testRepeatedActivityCursorStopsInsteadOfLooping() async throws {
        var requests = 0
        StubURLProtocol.handler = { request in
            requests += 1
            if request.url!.path == "/api/companion" { return (503, Data("{\"code\":\"observation_pending\"}".utf8)) }
            return (200, Data("{\"status\":\"collecting\",\"nextCursor\":\"same\"}".utf8))
        }
        defer { StubURLProtocol.handler = nil }
        do { _ = try await observationClient().snapshot(); XCTFail("Accepted a looping cursor") }
        catch CompanionError.observationPending { }
        XCTAssertEqual(requests, 3)
    }
    func testHostReplacementDuringPaginationIsRejected() async throws {
        var requests = 0
        StubURLProtocol.handler = { _ in
            requests += 1
            return (200, try self.observationFixture(sessionCursor: requests == 1 ? "next" : nil,
                                                    host: requests == 1 ? "host" : "replacement"))
        }
        defer { StubURLProtocol.handler = nil }
        do { _ = try await observationClient().snapshot(); XCTFail("Combined two hosts") }
        catch CompanionError.changedHost { }
        XCTAssertEqual(requests, 2)
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

}

private final class StubURLProtocol: URLProtocol {
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
