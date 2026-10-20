import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public final class HostClient {
    public let endpoint: Endpoint
    private let token: String
    private let clientID: String
    private let session: URLSession
    public init(endpoint: Endpoint, token: String, clientID: String,
                configuration: URLSessionConfiguration = .ephemeral) {
        self.endpoint = endpoint; self.token = token
        // Pairing is a new device identity, not permission to adopt an earlier
        // browser/manual-token client. Preserve the journal and command IDs.
        if token.range(of: "^amc_[a-f0-9]{32}\\.[A-Za-z0-9_-]{64}$", options: .regularExpression) != nil {
            let deviceID = token.dropFirst(4).prefix(32)
            self.clientID = "paired-" + deviceID + "-" + clientID
        } else {
            self.clientID = clientID
        }
        let config = configuration
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    private func request(_ url: URL, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "X-Amplifier-Client")
        request.setValue("delta-v1", forHTTPHeaderField: "X-Amplifier-State-Transport")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CompanionError.uncertain }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 503,
               let error = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               error["code"] as? String == "observation_pending" { throw CompanionError.observationPending }
            throw CompanionError.rejected(http.statusCode)
        }
        return data
    }
    public func attach() async throws {
        let data = try await request(endpoint.route("api", "clients", "attach"),
            body: ["clientId": clientID, "kind": "native", "protocolVersion": 1])
        let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard value?["protocolVersion"] as? Int == 1 else { throw CompanionError.incompatibleHost }
    }
    /// Finish bounded server scans within one poll; never publish a partial notification baseline.
    public func snapshot() async throws -> CompanionSnapshot {
        let deadline = Date().addingTimeInterval(45)
        for attempt in 0..<3 {
            do { return try await completeSnapshot(deadline: deadline) }
            catch CompanionError.rejected(404) { throw CompanionError.incompatibleHost }
            catch CompanionError.rejected(409) where attempt < 2 { continue }
        }
        throw CompanionError.observationPending
    }
    private func checkObservationBudget(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw CompanionError.observationPending }
    }
    private func observationURL(_ path: String, cursors: [String: String]) -> URL {
        var url = URLComponents(url: endpoint.route("api", path), resolvingAgainstBaseURL: false)!
        url.queryItems = cursors.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url!
    }
    private func finishActivity(deadline: Date) async throws {
        var cursor: String?
        var seen = Set<String>()
        for _ in 0..<256 {
            try checkObservationBudget(deadline)
            let data = try await request(observationURL("activity", cursors: cursor.map { ["cursor": $0] } ?? [:]))
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CompanionError.incompatibleHost
            }
            if value["status"] as? String == "ready" { return }
            guard value["status"] as? String == "collecting",
                  let next = value["nextCursor"] as? String, !next.isEmpty,
                  seen.insert(next).inserted else { throw CompanionError.observationPending }
            cursor = next
        }
        throw CompanionError.observationPending
    }
    private func observationPage(_ cursors: [String: String], deadline: Date) async throws -> CompanionSnapshot {
        for _ in 0..<3 {
            try checkObservationBudget(deadline)
            do {
                let data = try await request(observationURL("companion", cursors: cursors))
                let value = try JSONDecoder().decode(CompanionSnapshot.self, from: data)
                guard value.protocolVersion == 1 else { throw CompanionError.incompatibleHost }
                return value
            } catch CompanionError.observationPending {
                // A large/changing catalog cannot finish if every partial scan waits for the next poll.
                // Follow the immutable activity traversal before retrying this read, never a command.
                try await finishActivity(deadline: deadline)
            }
        }
        throw CompanionError.observationPending
    }
    private func completeSnapshot(deadline: Date) async throws -> CompanionSnapshot {
        var result = try await observationPage([:], deadline: deadline)
        var sessionCursor = result.sessionsNextCursor
        var itemCursor = result.itemsNextCursor
        var cursors: [String: String] = [:]
        var seen = Set<String>()
        for _ in 0..<256 {
            if sessionCursor == nil && itemCursor == nil { return result }
            if let sessionCursor { cursors["sessionsCursor"] = sessionCursor }
            if let itemCursor { cursors["itemsCursor"] = itemCursor }
            // Retain a finished side's terminal cursor while the other side continues.
            // The server replays that terminal page instead of allocating another traversal.
            let key = cursors.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: "&")
            guard seen.insert(key).inserted else { throw CompanionError.observationPending }
            let page = try await observationPage(cursors, deadline: deadline)
            guard page.hostIdentity == result.hostIdentity, page.hostInstanceId == result.hostInstanceId else {
                throw CompanionError.changedHost
            }
            if sessionCursor != nil { result.sessions.append(contentsOf: page.sessions); sessionCursor = page.sessionsNextCursor; result.sessionsTruncated = page.sessionsTruncated }
            if itemCursor != nil { result.items.append(contentsOf: page.items); itemCursor = page.itemsNextCursor; result.itemsTruncated = page.itemsTruncated }
            result.sessionsNextCursor = sessionCursor; result.itemsNextCursor = itemCursor
        }
        throw CompanionError.observationPending
    }
    public func send(_ reply: PendingReply) async throws {
        guard reply.endpoint == endpoint.url.absoluteString else { throw CompanionError.changedHost }
        // Verify durable host identity even if the address was reassigned.
        guard try await snapshot().hostIdentity == reply.hostIdentity else { throw CompanionError.changedHost }
        if let command = reply.createCommandID {
            let created = try await request(endpoint.route("api", "actions"), body: [
                "id": command, "action": "session.create", "args": [
                    "id": reply.sessionID, "title": "New chat", "location": ["kind": "managed"], "select": false] as [String: Any]])
            let receipt = try JSONSerialization.jsonObject(with: created) as? [String: Any]
            guard receipt?["accepted"] as? Bool == true,
                  receipt?["sessionId"] as? String == reply.sessionID else { throw CompanionError.uncertain }
        }
        let data = try await request(endpoint.route("api", "sessions", reply.sessionID, "commands"), body: [
            "id": reply.id, "action": "conversation.send", "args": [
                "text": reply.text, "via": "chat", "preserveDraft": true, "attachmentIds": []] as [String: Any]])
        let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard value?["accepted"] as? Bool == true else { throw CompanionError.uncertain }
    }
    /// Fetch bounded details only for visible work or a new response, never on every idle poll.
    public func details(sessionID: String, part: String) async throws -> [[String: Any]] {
        var url = URLComponents(url: endpoint.route("api", "conversation", "detail"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "sessionId", value: sessionID), URLQueryItem(name: "part", value: part)]
        let data = try await request(url.url!)
        let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return value?["items"] as? [[String: Any]] ?? []
    }
    public func responsePreview(sessionID: String) async throws -> String? {
        let rows = try await details(sessionID: sessionID, part: "messages")
        // Never display a prior answer as a response to the latest user input.
        for row in rows.reversed() {
            if row["role"] as? String == "user" { return nil }
            if row["role"] as? String == "assistant", let text = row["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return String(text.prefix(600))
            }
        }
        return nil
    }
    public func workPreview(sessionID: String) async throws -> String? {
        let rows = try await details(sessionID: sessionID, part: "nodes")
        let live = ["running", "working", "streaming", "pending", "started"]
        let row = rows.last { row in
            row["endedAt"] == nil && live.contains((row["status"] ?? row["phase"]) as? String ?? "")
        }
        return (row?["label"] as? String).map { String($0.prefix(140)) }
    }

}
