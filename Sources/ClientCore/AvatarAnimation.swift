import Foundation

/// Presentation only. Host-owned attention is never acknowledged by animation.
public enum AvatarState: String, CaseIterable {
    case idle, working, ready, review, error, connecting, offline
    public var loops: Bool { [.idle, .working, .review, .connecting].contains(self) }
    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .ready: return "Response ready"
        case .review: return "Needs input"
        case .error: return "Error"
        case .connecting: return "Connecting"
        case .offline: return "Offline or paused"
        }
    }
}

public enum AvatarCatalog {
    public static let shapes = ["relay", "accord", "d20", "crest", "meter", "clippy"]
    public static func canonical(_ name: String) -> String {
        switch name {
        case "arc", "fold": return "d20"
        case "chord": return "accord"
        default: return shapes.contains(name) ? name : "relay"
        }
    }
    public static func frameCount(_ shape: String) -> Int {
        shape == "relay" ? 6 : (["accord", "clippy"].contains(shape) ? 8 : 16)
    }
    public static func quietFrame(_ shape: String) -> Int {
        ["relay": 1, "accord": 7, "d20": 15, "crest": 15, "meter": 13, "clippy": 4][shape] ?? 1
    }
}

public struct AvatarPlayback {
    public private(set) var state: AvatarState = .offline
    private var started: TimeInterval = 0
    private var workingStarted: TimeInterval?
    // Bound memory while retaining reactions across reconnects and menu rebuilds.
    private var seen: [String] = []
    public init() {}
    public mutating func update(connected: Bool, connecting: Bool, working: Int,
                                items: [AttentionItem], scope: String, now: TimeInterval) {
        if connected && working > 0 {
            if workingStarted == nil { workingStarted = now }
        } else { workingStarted = nil }
        let errors = items.filter(\.isError)
        let input = items.filter { !$0.isError && $0.kind != "completion" }
        let next: AvatarState = !connected ? (connecting ? .connecting : .offline) :
            (!errors.isEmpty ? .error : (!input.isEmpty ? .review :
                (!items.isEmpty ? .ready : (working > 0 ? .working : .idle))))
        let events = (next == .error ? errors : (next == .ready ? items : [])).map { scope + ":" + $0.key }
        let fresh = events.filter { !seen.contains($0) }
        if next != state || !fresh.isEmpty {
            // A previously shown one-shot resumes in its settled pose after a
            // disconnect or a higher-priority state. Polls cannot replay it.
            started = now - ((next == .ready || next == .error) && fresh.isEmpty ? 4 : 0)
        }
        seen.append(contentsOf: fresh)
        if seen.count > 256 { seen.removeFirst(seen.count - 256) }
        state = next
    }
    public func elapsed(at now: TimeInterval) -> TimeInterval { max(0, now - started) }
    /// Attention remains visible in the badge/pill after its one-shot reaction.
    /// It must not suppress the working loop for other ongoing chats.
    public func presentation(at now: TimeInterval) -> (state: AvatarState, elapsed: TimeInterval) {
        if let workingStarted, state == .working ||
            ((state == .ready || state == .error) && elapsed(at: now) >= 4) {
            return (.working, max(0, now - workingStarted))
        }
        return (state, elapsed(at: now))
    }
    public func animates(at now: TimeInterval, visible: Bool, reducedMotion: Bool) -> Bool {
        let shown = presentation(at: now)
        return visible && !reducedMotion && shown.state != .offline && (shown.state.loops || shown.elapsed < 4)
    }
}

/// Choreography shared by every finish/palette. Frame indices refer to the
/// approved, registered crystal poses; body movement uses continuous time.
public struct AvatarPose {
    public var weights: [Double]
    public var tilt: Double = 0
    public var rise: Double = 0
    public var scaleX: Double = 1
    public var scaleY: Double = 1
    public static func sample(shape: String, state: AvatarState, elapsed: Double, reduced: Bool = false) -> AvatarPose {
        let shape = AvatarCatalog.canonical(shape), quiet = AvatarCatalog.quietFrame(shape)
        var pose = AvatarPose(weights: Array(repeating: 0, count: AvatarCatalog.frameCount(shape)))
        let peaks = ["relay": 0, "accord": 3, "d20": 7, "crest": 7, "meter": 3, "clippy": 0]
        let paths = ["relay": [0,2,4], "accord": [1,3,5], "d20": [4,7,9], "crest": [3,7,9], "meter": [0,1,3], "clippy": [0,2,4]]
        func ease(_ x: Double) -> Double { let v = min(1, max(0, x)); return v*v*(3-2*v) }
        func bump(_ t: Double, _ start: Double, _ length: Double) -> Double {
            let u = (t-start)/length; return u > 0 && u < 1 ? pow(sin(.pi*u), 2) : 0
        }
        let period = state == .connecting ? 3.6 : 6.0
        let t = reduced ? (state == .ready || state == .error ? 4.0 : 0.0) :
            (state.loops ? elapsed.truncatingRemainder(dividingBy: period) : min(4, elapsed))
        var selected = [(peaks[shape]!, 1.0)], amp = 0.0
        switch state {
        case .idle:
            let b = (1-cos(2 * .pi*t/6))/2; pose.scaleX += 0.003*b; pose.scaleY += 0.006*b
            if shape == "clippy" { selected = [(5,1)]; amp = bump(t,3.8,0.34) }
        case .ready:
            let progress = min(2, t/1.35*2), i = min(2, Int(progress)), f = ease(progress-Double(i))
            selected = [(paths[shape]![i],1-f),(paths[shape]![min(2,i+1)],f)]
            amp = 0.95*bump(t,0,1.5)+0.22*ease((t-1.2)/0.5)
            let g = bump(t,0.15,1.1)
            pose.tilt = ["relay": -1.4,"accord": 0,"d20": 3,"crest": -1.8,"meter": 0,"clippy": 2][shape]! * g
            pose.rise = 2*g; pose.scaleY += (shape == "meter" ? 0.013 : 0.005)*g
            if shape == "clippy" && t > 0.55 && t < 0.9 { selected = [(5,1)]; amp = bump(t,0.55,0.35) }
        case .review:
            amp = 0.13+0.75*bump(t,0.35,0.7)+0.65*bump(t,1.35,0.7)
            pose.tilt = ["relay": -0.6,"accord": 0,"d20": 1,"crest": -0.8,"meter": 0,"clippy": 1.4][shape]! * bump(t,0.2,2.2)
        case .error:
            amp = 0.45*bump(t,0,0.5); let r = bump(t,0.05,0.7)
            pose.tilt = ["relay": 2,"accord": 1,"d20": -4,"crest": 2,"meter": 0.6,"clippy": -2][shape]! * r
            pose.scaleY -= 0.014*r; pose.rise = -1.5*r
        case .connecting:
            let unit = t/1.2; selected = [(paths[shape]![Int(unit)%3],1)]
            amp = 0.55*pow(sin(.pi*(unit-floor(unit))),2)
            if shape == "clippy" { pose.tilt = sin(2 * .pi*t/3.6)*0.8 }
        case .working:
            if !reduced && (shape == "relay" || shape == "meter") {
                let period = shape == "relay" ? 0.84 : 7.2
                let phase = elapsed.truncatingRemainder(dividingBy: period)/period*Double(pose.weights.count)
                let index = Int(phase), fraction = phase-Double(index)
                let blend = ease(shape == "relay" ? fraction : (fraction-0.8)/0.2)
                selected = [(index,1-blend),((index+1)%pose.weights.count,blend)]; amp = 1
                if shape == "meter" {
                    let b = (1-cos(2 * .pi*elapsed/3.6))/2
                    pose.scaleX += 0.014*b; pose.scaleY += 0.024*b
                }
            }
        case .offline: break
        }
        amp = min(1, max(0, amp)); pose.weights[quiet] += 1-amp
        for (index, weight) in selected { pose.weights[index] += amp*weight }
        return pose
    }
}
