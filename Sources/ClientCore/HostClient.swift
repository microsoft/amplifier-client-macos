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

/// Cancellation can arrive before URLSession has created the task.
private final class RequestCancellation {
    private let lock = NSLock()
    private var cancelled = false
    private var task: URLSessionDataTask?
    func attach(_ task: URLSessionDataTask) {
        lock.lock(); self.task = task; let cancel = cancelled; lock.unlock()
        if cancel { task.cancel() }
    }
    func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        task?.cancel()
    }
}

public final class HostClient {
    public let endpoint: Endpoint
    private let token: String
    private let clientID: String
    private let session: URLSession
    private let transportLock = NSLock()
    private var observedHost: String?
    private var observedInstance: String?
    private var resources: [String: String] = [:]
    private var closed = false
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
    /// End this registration's transport, including bounded detail reads whose
    /// callers may still be awaiting a result. A new connection uses a new client.
    public func cancelRequests() {
        transportLock.lock(); closed = true; transportLock.unlock()
        // Keep the session valid until deinit: data(for:) on an invalidated
        // session can raise an NSException rather than a catchable Swift error.
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }
    private func startTask(_ request: URLRequest,
                           completion: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask? {
        transportLock.lock(); defer { transportLock.unlock() }
        guard !closed else { return nil }
        // Creation and resume share the close gate, so cancelRequests' task
        // enumeration includes every admitted read and no later request starts.
        let task = session.dataTask(with: request, completionHandler: completion)
        task.resume(); return task
    }
    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let cancellation = RequestCancellation()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = startTask(request) { data, response, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, let response { continuation.resume(returning: (data, response)) }
                    else { continuation.resume(throwing: CompanionError.uncertain) }
                }
                if let task { cancellation.attach(task) }
                else { continuation.resume(throwing: URLError(.cancelled)) }
            }
        }, onCancel: { cancellation.cancel() })
    }
    private func request(_ url: URL, body: [String: Any]? = nil, deadline: Date? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        if let deadline {
            try checkObservationBudget(deadline)
            request.timeoutInterval = min(20, deadline.timeIntervalSinceNow)
        }
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "X-Amplifier-Client")
        request.setValue("delta-v1", forHTTPHeaderField: "X-Amplifier-State-Transport")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CompanionError.uncertain }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 503,
               let error = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               error["code"] as? String == "observation_pending" { throw CompanionError.observationPending }
            throw CompanionError.rejected(http.statusCode)
        }
        guard data.count <= 2 * 1024 * 1024 else { throw CompanionError.incompatibleHost }
        return data
    }
    public func attach() async throws {
        try await discover(deadline: nil)
    }
    @discardableResult
    private func discover(deadline: Date?, cache: Bool = true) async throws -> (host: String, instance: String) {
        let data = try await request(endpoint.route("api", "clients", "attach"),
            body: ["clientId": clientID, "kind": "native", "protocolVersion": 1, "includeState": false], deadline: deadline)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["protocolVersion"] as? Int == 1,
              let host = value["hostIdentity"] as? String, !host.isEmpty,
              let instance = value["hostInstanceId"] as? String, !instance.isEmpty,
              let capabilities = value["capabilities"] as? [String: Any],
              let observations = capabilities["observations"] as? [String: Any],
              observations["version"] as? Int == 1,
              observations["identity"] as? Bool == true,
              let dismissals = observations["dismissals"] as? [String: Any],
              dismissals["version"] as? Int == 1, dismissals["action"] as? String == "presentation.dismiss" else { throw CompanionError.incompatibleHost }
        if let observedHost, observedHost != host { throw CompanionError.changedHost }
        let expected = ["sessions": "/api/sessions?view=observation", "attention": "/api/attention", "activity": "/api/activity"]
        for (key, path) in expected {
            guard observations[key] as? String == path else { throw CompanionError.incompatibleHost }
        }
        if cache { observedHost = host; observedInstance = instance; resources = expected }
        return (host, instance)
    }
    /// Each collection is coherent independently; never publish partial pages.
    public func snapshot() async throws -> ObservationSnapshot {
        let deadline = Date().addingTimeInterval(45)
        for attempt in 0..<3 {
            do {
                if observedHost == nil || attempt > 0 { try await discover(deadline: deadline) }
                let host = observedHost!, instance = observedInstance!
                let sessions: [ChatSummary] = try await collection("sessions", deadline: deadline)
                let notices: [ObservedNotice] = try await collection("attention", deadline: deadline)
                let counts = try await activity(deadline: deadline)
                let pins = Set(sessions.filter(\.pinned).map(\.id))
                return ObservationSnapshot(protocolVersion: 1, hostIdentity: host, hostInstanceId: instance,
                    workingCount: counts.executionCount, attentionCount: counts.attentionCount,
                    sessions: sessions, items: notices.map { $0.item(pinned: pins.contains($0.target.sessionId)) },
                    sessionsTruncated: false, itemsTruncated: false)
            } catch CompanionError.rejected(404) { throw CompanionError.incompatibleHost }
            catch CompanionError.rejected(let code) where [400, 409].contains(code) && attempt < 2 { continue }
        }
        throw CompanionError.observationPending
    }
    private func checkObservationBudget(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw CompanionError.observationPending }
    }
    private func observationURL(_ resource: String, cursor: String?) throws -> URL {
        guard let path = resources[resource], let base = URL(string: path, relativeTo: endpoint.url)?.absoluteURL,
              var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw CompanionError.incompatibleHost }
        var query = parts.queryItems ?? []
        query.append(URLQueryItem(name: "scope", value: "roots"))
        if resource != "activity" { query.append(URLQueryItem(name: "limit", value: "200")) }
        if resource == "sessions" { query.append(URLQueryItem(name: "activity", value: "active-or-pinned")) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        parts.queryItems = query
        return parts.url!
    }
    private func page(_ resource: String, cursor: String?, deadline: Date) async throws -> [String: Any] {
        let data = try await request(observationURL(resource, cursor: cursor), deadline: deadline)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["nextCursor"] != nil, value["revision"] is String || value["revision"] is NSNumber else {
            throw CompanionError.incompatibleHost
        }
        guard value["hostIdentity"] as? String == observedHost else { throw CompanionError.changedHost }
        guard value["hostInstanceId"] as? String == observedInstance else { throw CompanionError.rejected(400) }
        return value
    }
    private func continuation(_ value: [String: Any], seen: inout Set<String>) throws -> String? {
        if value["nextCursor"] is NSNull { return nil }
        guard let next = value["nextCursor"] as? String, !next.isEmpty, next.utf8.count <= 8192,
              seen.insert(next).inserted else { throw CompanionError.observationPending }
        return next
    }
    private func checkRevision(_ value: [String: Any], previous: inout Data?) throws {
        let current = try JSONSerialization.data(withJSONObject: value["revision"]!, options: [.fragmentsAllowed, .sortedKeys])
        if let previous, previous != current { throw CompanionError.incompatibleHost }
        previous = current
    }
    private func collection<T: Decodable & Identifiable>(_ resource: String, deadline: Date) async throws -> [T] where T.ID == String {
        var result: [T] = [], cursor: String?, revision: Data?
        var seen = Set<String>(), ids = Set<String>()
        for _ in 0..<256 {
            let value = try await page(resource, cursor: cursor, deadline: deadline)
            try checkRevision(value, previous: &revision)
            guard let items = value["items"] as? [[String: Any]], items.count <= 200 else { throw CompanionError.incompatibleHost }
            let decoded = try JSONDecoder().decode([T].self, from: JSONSerialization.data(withJSONObject: items))
            for row in decoded {
                guard !row.id.isEmpty, ids.insert(row.id).inserted else { throw CompanionError.incompatibleHost }
            }
            if resource == "sessions", decoded.contains(where: { ($0 as? ChatSummary).map { $0.activity == nil || $0.isWorking && ($0.dismissal == nil || $0.dismissal!.id.isEmpty || $0.dismissal!.fingerprint.isEmpty) } ?? true }) { throw CompanionError.incompatibleHost }
            if resource == "attention", decoded.contains(where: { ($0 as? ObservedNotice).map { $0.target.type != "session" || $0.target.sessionId.isEmpty || $0.fingerprint.isEmpty || $0.dismissal.id.isEmpty || $0.dismissal.fingerprint.isEmpty } ?? false }) { throw CompanionError.incompatibleHost }
            result += decoded
            cursor = try continuation(value, seen: &seen)
            if cursor == nil { return result }
        }
        throw CompanionError.observationPending
    }
    private func activity(deadline: Date) async throws -> ActivityCounts {
        var cursor: String?, revision: Data?, seen = Set<String>()
        for _ in 0..<256 {
            let value = try await page("activity", cursor: cursor, deadline: deadline)
            try checkRevision(value, previous: &revision)
            cursor = try continuation(value, seen: &seen)
            if value["status"] as? String == "ready", cursor == nil {
                let counts = try JSONDecoder().decode(ActivityCounts.self, from: JSONSerialization.data(withJSONObject: value))
                guard counts.valid else { throw CompanionError.incompatibleHost }
                return counts
            }
            guard value["status"] as? String == "collecting", cursor != nil else { throw CompanionError.incompatibleHost }
        }
        throw CompanionError.observationPending
    }
    public func dismiss(_ intent: DismissalIntent) async throws {
        guard intent.endpoint == endpoint.url.absoluteString else { throw CompanionError.changedHost }
        let deadline = Date().addingTimeInterval(30)
        let identity = try await discover(deadline: deadline, cache: false)
        guard identity.host == intent.hostIdentity else { throw CompanionError.changedHost }
        let data = try await request(endpoint.route("api", "actions"), body: ["id": intent.requestID,
            "action": "presentation.dismiss", "args": ["items": [["id": intent.id, "fingerprint": intent.fingerprint]]]], deadline: deadline)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], value["accepted"] as? Bool == true else {
            throw CompanionError.uncertain
        }
    }
    public func send(_ reply: PendingReply) async throws {
        guard reply.endpoint == endpoint.url.absoluteString else { throw CompanionError.changedHost }
        // Verify durable host identity even if the address was reassigned.
        let identity = try await discover(deadline: Date().addingTimeInterval(20), cache: false)
        guard identity.host == reply.hostIdentity else { throw CompanionError.changedHost }
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
                let preview = NoticeText.plain(text)
                return preview.isEmpty ? nil : preview
            }
        }
        return nil
    }
    public func workPreview(sessionID: String) async throws -> WorkPreview? {
        WorkPreview.from(nodes: try await details(sessionID: sessionID, part: "nodes"))
    }

}

private struct ObservedNotice: Decodable, Identifiable {
    struct Target: Decodable { let type: String; let sessionId: String }
    let id: String; let fingerprint: String; let kind: String; let target: Target
    let requiresAction: Bool; let read: Bool; let title: String; let summary: String
    let agentCreated: Bool?; let pinned: Bool?; let dismissal: DismissalDescriptor
    func item(pinned selected: Bool) -> AttentionItem {
        AttentionItem(id: id, fingerprint: fingerprint, sessionId: target.sessionId,
            title: title, kind: kind, summary: summary, pinned: pinned ?? selected, agentCreated: agentCreated, dismissal: dismissal, requiresAction: requiresAction, read: read)
    }
}
private struct ActivityCounts: Decodable {
    let executionCount: Int; let preparingCount: Int; let loadingCount: Int
    let attentionCount: Int; let requiresActionCount: Int
    var valid: Bool { [executionCount, preparingCount, loadingCount, attentionCount, requiresActionCount].allSatisfy { $0 >= 0 } }
}
