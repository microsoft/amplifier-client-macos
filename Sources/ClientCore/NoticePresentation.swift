import Foundation

public struct NoticeListSize {
    public var maximum: Double
    public var fitsContents: Bool
    public init(maximum: Double = 178, fitsContents: Bool = false) {
        self.maximum = maximum.isFinite ? max(54, maximum) : 178
        self.fitsContents = fitsContents
    }
    public func height(content: Double, available: Double) -> Double {
        max(0, min(content, available, fitsContents ? content : maximum))
    }
    public mutating func resize(to requested: Double, content: Double, available: Double) {
        let limit = max(0, min(content, available))
        fitsContents = requested >= limit - 2
        if !fitsContents { maximum = max(54, min(requested, limit)) }
    }
}

public enum NoticeStatus: String {
    case working, unread, blocked, question, error, idle
    public var symbol: String {
        switch self {
        case .working: return "arrow.clockwise" // Native view draws the sidebar's open progress ring.
        case .unread: return "circle.fill"
        case .blocked: return "pause.circle"
        case .question: return "questionmark.circle"
        case .error: return "exclamationmark.circle"
        case .idle: return "bubble.left"
        }
    }
    public static func attention(kind: String, working: Bool = false) -> NoticeStatus {
        if ["session", "session-error"].contains(kind) { return .error }
        if ["completion", "unread", "manual-unread"].contains(kind) { return working ? .working : .unread }
        if kind.contains("block") { return .blocked }
        return .question
    }
}

/// Bounded public activity text; never infer model reasoning or dump tool inputs.
public struct WorkPreview: Equatable {
    public let text: String
    public let stateID: String
    public init(text: String, stateID: String) { self.text = text; self.stateID = stateID }
    public static func fallback(status: String) -> String {
        switch status {
        case "starting", "preparing": return "Preparing…"
        case "stopping": return "Stopping…"
        case "retrying": return "Retrying…"
        default: return "Thinking…"
        }
    }
    public static func from(nodes: [[String: Any]]) -> WorkPreview? {
        let live = ["running", "working", "streaming", "pending", "started", "queued", "waiting"]
        guard let row = nodes.last(where: {
            ($0["endedAt"] == nil || $0["endedAt"] is NSNull) && live.contains(($0["phase"] ?? $0["status"]) as? String ?? "")
        }) else { return nil }
        func line(_ key: String) -> String? {
            guard let raw = row[key] as? String else { return nil }
            let text = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return text.isEmpty ? nil : String(text.prefix(240))
        }
        let kind = line("kind") ?? "", label = line("label") ?? ""
        let model = ["llm", "model", "model_call", "provider"].contains(kind.lowercased()) ||
            ["model call", "llm request", "llm response", "thinking", "working"].contains(label.lowercased())
        let text: String
        if model { text = "Thinking…" }
        else {
            let summary = line("summary")
            let action = label.isEmpty ? (kind == "tool" ? "Running tool…" : "Working…") : label
            text = summary.map { $0 == action ? action : action + " · " + $0 } ?? action
        }
        // Detail/progress changes do not resurrect a dismissed action. A new node
        // or lifecycle phase does, including another model call with the same label.
        let state = [line("id") ?? label, kind, line("phase") ?? line("status") ?? ""].joined(separator: "|")
        return WorkPreview(text: String(text.prefix(360)), stateID: state)
    }
}

public enum NoticeDismissal {
    public static func reconcile(_ saved: [String: String], current: [String: String]) -> [String: String] {
        var kept: [String: String] = [:]
        for (key, old) in saved {
            guard let new = current[key] else { continue }
            if old == new { kept[key] = old; continue }
            let before = old.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            let after = new.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            // Missing detail is not a new action: preserve dismissal across startup,
            // a successful empty detail read, or the first detail arriving after dismissal.
            if before.count == 3, after.count == 3, before[0] == "work", after[0] == "work",
               before[1] == after[1], before[2].isEmpty || after[2].isEmpty {
                kept[key] = after[2].isEmpty ? old : new
            }
        }
        return kept
    }
}
