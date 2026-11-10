import Foundation

public enum NoticePriority: Int {
    case input = 0, unread, working
    public static func attention(_ status: NoticeStatus) -> Self {
        [.error, .blocked, .question].contains(status) ? .input : .unread
    }
}

/// Stable ties preserve each host's order; grouping changes only the outer key.
public enum NoticeOrdering {
    public static func sorted<Row>(_ rows: [Row], grouped: Bool,
                                   service: (Row) -> String, priority: (Row) -> NoticePriority) -> [Row] {
        var groups: [String: Int] = [:]
        for row in rows where groups[service(row)] == nil { groups[service(row)] = groups.count }
        return rows.enumerated().sorted { a, b in
            if grouped, groups[service(a.element)] != groups[service(b.element)] {
                return groups[service(a.element)]! < groups[service(b.element)]!
            }
            if priority(a.element) != priority(b.element) { return priority(a.element).rawValue < priority(b.element).rawValue }
            return a.offset < b.offset
        }.map(\.element)
    }
}

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

/// Plain, bounded presentation text. Never evaluate links or fetch linked content.
public enum NoticeText {
    public static func plain(_ raw: String, limit: Int = 600) -> String {
        var text = String(raw.prefix(8192))
        // Strip block syntax before inline parsing, including incomplete streamed headings.
        text = text.replacingOccurrences(of: #"(?m)^\s{0,3}(?:#{1,6}\s+|>\s*|[-+*]\s+|[0-9]+[.)]\s+)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s*```[^\n]*"#, with: "", options: .regularExpression)
        if let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            text = String(parsed.characters)
        }
        // A bounded/streaming response may end before its emphasis closes.
        text = text.replacingOccurrences(of: #"(^|\s)\*\*(?=\S)"#, with: "$1", options: .regularExpression)
        text = String(text.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            if CharacterSet.controlCharacters.contains(scalar) || (0x200B...0x200F).contains(value) ||
                (0x202A...0x202E).contains(value) || (0x2060...0x206F).contains(value) || value == 0xFEFF { return " " }
            return Character(String(scalar))
        })
        text = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard text.count > limit else { return text }
        return String(text.prefix(max(0, limit - 1))) + "…"
    }
}

/// Public labels and selected host-projected hints, never raw tool inputs/results.
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
    private static func line(_ row: [String: Any], _ key: String) -> String {
        NoticeText.plain(row[key] as? String ?? "", limit: 240)
    }
    private static func identifier(_ value: String) -> String? {
        guard !value.isEmpty, value.count <= 120,
              value.range(of: #"^[A-Za-z][A-Za-z0-9_.:/-]*$"#, options: .regularExpression) != nil else { return nil }
        return value
    }
    private static func words(_ value: String) -> String {
        value.replacingOccurrences(of: #"[_.:/-]+"#, with: " ", options: .regularExpression)
    }
    private static func action(_ row: [String: Any]) -> String {
        let kind = line(row, "kind").lowercased(), label = line(row, "label")
        if ["llm", "model", "model_call", "provider"].contains(kind) { return "Thinking…" }
        let tool = line(row, "tool").isEmpty ? label : line(row, "tool")
        let name = tool.lowercased().components(separatedBy: ":").last ?? tool.lowercased()
        let summary = line(row, "summary")
        // A useful producer title/summary wins. Do not repeat the tool name around it.
        if !summary.isEmpty && summary.caseInsensitiveCompare(label) != .orderedSame &&
            !["Running \(tool)", "Completed \(tool)"].contains(summary) {
            if label.isEmpty || label == tool && identifier(tool) != nil { return summary }
            return summary.lowercased().hasPrefix(label.lowercased()) ? summary : label + " · " + summary
        }
        if !label.isEmpty && label != tool { return label }
        let hints = row["inputSummary"] as? [String: Any] ?? [:]
        let operation = identifier(line(hints, "action")) ?? identifier(line(hints, "operation"))
        if name == "app_control" {
            let path = line(row, "actionPath")
            if path.hasPrefix("dispatch → "), let nested = identifier(String(path.dropFirst("dispatch → ".count))) {
                return "App · " + words(nested)
            }
            return operation.map { "App · " + words($0) } ?? "Using app controls…"
        }
        let file = ["file_path", "path", "filename"].map { line(hints, $0) }.first { !$0.isEmpty }
        let leaf = file.map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        let fileVerbs = ["read_file":"Reading", "read":"Reading", "write_file":"Writing", "write":"Writing", "edit_file":"Editing"]
        if let verb = fileVerbs[name] { return leaf.map { verb + " " + $0 } ?? verb + " a file…" }
        if let operation { return words(tool) + " · " + words(operation) }
        let known = ["bash":"Running a command…", "shell":"Running a command…", "exec_command":"Running a command…",
                     "apply_patch":"Editing files…", "grep":"Searching files…", "glob":"Finding files…",
                     "web_search":"Searching the web…", "web_fetch":"Fetching a page…", "todo":"Updating the task list…",
                     "image_generate":"Generating an image…", "delegate":"Delegating work…"]
        if let text = known[name] { return text }
        if ["model call", "llm request", "llm response", "thinking", "working"].contains(label.lowercased()) { return "Thinking…" }
        if tool.isEmpty { return kind == "tool" ? "Running a tool…" : "Working…" }
        return identifier(tool) == nil ? tool : "Using " + words(tool) + "…"
    }
    public static func from(nodes: [[String: Any]]) -> WorkPreview? {
        let live = ["running", "working", "streaming", "pending", "started", "starting", "queued", "waiting", "retrying"]
        let active = nodes.filter {
            ($0["endedAt"] == nil || $0["endedAt"] is NSNull) && live.contains(($0["phase"] ?? $0["status"]) as? String ?? "")
        }
        let tools = active.filter { line($0, "kind") == "tool" }
        guard let row = tools.last ?? active.last else { return nil }
        let others = max(0, tools.count - 1)
        let suffix = others == 0 ? "" : " · +\(others) tool\(others == 1 ? "" : "s")"
        let text = NoticeText.plain(action(row), limit: 360 - suffix.count) + suffix
        // Progress text and concurrent siblings do not resurrect a dismissed action.
        let state = [line(row, "id").isEmpty ? line(row, "label") : line(row, "id"), line(row, "kind"),
                     line(row, "phase").isEmpty ? line(row, "status") : line(row, "phase")].joined(separator: "|")
        return WorkPreview(text: text, stateID: state)
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
