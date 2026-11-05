#if os(macOS)
import AppKit
import ImageIO
#if !NATIVE_CHECK
import ClientCore
#endif

@MainActor final class SpriteView: NSView {
    var open: (() -> Void)?
    #if NATIVE_CHECK
    var previewElapsed: Double?
    var animationTimerIsRunning: Bool { timer != nil }
    var previewReducedMotion: Bool? { didSet { refreshTimer(); needsDisplay = true } }
    #endif
    private(set) var playback = AvatarPlayback()
    private var frames: [CGImage] = []
    private var working: CGImageSource?
    private var workingEnds: [Double] = []
    private var cache = NSCache<NSNumber, CGImage>()
    private var timer: Timer?
    private var enabled = false
    private var shape = "relay"
    private var resource = ""
    private var palette = "blue"
    private var ink = NSRect(x: 0, y: 0, width: 1, height: 1)
    private var accessibilityObserver: NSObjectProtocol?
    private var reducedMotion: Bool {
        #if NATIVE_CHECK
        if let previewReducedMotion { return previewReducedMotion }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cache.countLimit = 12; cache.totalCostLimit = 5 * 1024 * 1024
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshTimer(); self?.needsDisplay = true } }
        setAccessibilityElement(true); setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        timer?.invalidate()
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }
    func update(connected: Bool, connecting: Bool, working: Int, items: [AttentionItem], scope: String) {
        playback.update(connected: connected, connecting: connecting, working: working,
                        items: items, scope: scope, now: ProcessInfo.processInfo.systemUptime)
        setAccessibilityLabel("\(shape == "d20" ? "d20" : shape.capitalized), \(playback.state.label)")
        refreshTimer(); needsDisplay = true
    }
    func load(_ name: String, palette: String = "blue", finish: String = "clear", directory: URL? = nil) {
        let canonical = AvatarCatalog.canonical(name)
        let resource = AvatarAppearance.resourceName(canonical, finish: finish)
        guard self.resource != resource || self.palette != palette else { return }
        let base: URL?
        #if NATIVE_CHECK
        base = directory
        #else
        base = directory ?? Bundle.module.url(forResource: resource, withExtension: "png", subdirectory: "Resources")?.deletingLastPathComponent()
        #endif
        guard let base, let original = NSImage(contentsOf: base.appendingPathComponent(resource + ".png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let count = AvatarCatalog.frameCount(canonical)
        guard original.width == 1280, original.height == 320*((count+3)/4) else { return }
        let colored = AvatarAppearance.colored(original, palette: palette)
        frames = (0..<count).compactMap { colored.cropping(to: CGRect(x: ($0%4)*320, y: ($0/4)*320, width: 320, height: 320)) }
        ink = AvatarAppearance.inkBounds(frames[AvatarCatalog.quietFrame(canonical)])
        working = nil
        if !["relay", "meter"].contains(canonical) {
            working = CGImageSourceCreateWithURL(base.appendingPathComponent(resource + "-working.png") as CFURL,
                                            [kCGImageSourceShouldCache: false] as CFDictionary)
        }
        workingEnds = []; var duration = 0.0
        if let working {
            for i in 0..<CGImageSourceGetCount(working) {
                let properties = CGImageSourceCopyPropertiesAtIndex(working, i, nil) as? [CFString: Any]
                let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
                duration += max(0.01, (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double) ??
                    (png?[kCGImagePropertyAPNGDelayTime] as? Double) ?? 1.0/48)
                workingEnds.append(duration)
            }
        }
        cache.removeAllObjects(); shape = canonical; self.resource = resource; self.palette = palette
        setAccessibilityLabel("\(shape == "d20" ? "d20" : shape.capitalized), \(playback.state.label)")
        needsDisplay = true
    }
    var visibleArtworkBounds: NSRect {
        let side = min(bounds.width, bounds.height)
        let rect = NSRect(x: bounds.midX-side/2, y: bounds.midY-side/2, width: side, height: side)
        return NSRect(x: rect.minX+ink.minX*side, y: rect.minY+ink.minY*side,
                      width: ink.width*side, height: ink.height*side).insetBy(dx: 0, dy: -3)
    }
    func animate(_ enabled: Bool) { self.enabled = enabled; refreshTimer(); needsDisplay = true }
    private func refreshTimer() {
        let shouldRun = playback.animates(at: ProcessInfo.processInfo.systemUptime, visible: enabled,
            reducedMotion: reducedMotion)
        if !shouldRun { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0/50, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true; self?.refreshTimer() }
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    private func workingFrame(at elapsed: Double) -> CGImage? {
        guard let working, let duration = workingEnds.last, duration > 0 else { return nil }
        let phase = elapsed.truncatingRemainder(dividingBy: duration)
        let index = workingEnds.firstIndex { $0 > phase } ?? 0, key = NSNumber(value: index)
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateImageAtIndex(working, index, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let image = AvatarAppearance.colored(source, palette: palette)
        cache.setObject(image, forKey: key, cost: image.bytesPerRow*image.height)
        return image
    }
    override func draw(_ dirtyRect: NSRect) {
        guard !frames.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let reduced = reducedMotion
        var now = ProcessInfo.processInfo.systemUptime
        #if NATIVE_CHECK
        if let previewElapsed { now += previewElapsed - playback.elapsed(at: now) }
        #endif
        let presentation = playback.presentation(at: now)
        let state = reduced ? playback.state : presentation.state
        let elapsed = reduced ? playback.elapsed(at: now) : presentation.elapsed
        context.saveGState(); defer { context.restoreGState() }
        let side = min(bounds.width, bounds.height)
        context.translateBy(x: bounds.midX-side/2, y: bounds.midY-side/2)
        context.scaleBy(x: side/320, y: side/320); context.interpolationQuality = .high
        let rect = CGRect(x: 0, y: 0, width: 320, height: 320)
        if state == .working, !reduced, let frame = workingFrame(at: elapsed) { context.draw(frame, in: rect); return }
        let pose = AvatarPose.sample(shape: shape, state: state, elapsed: elapsed, reduced: reduced)
        let pivotY: CGFloat = shape == "d20" ? 160 : (shape == "meter" && state == .working ? 28 : 60)
        context.translateBy(x: 160, y: pivotY + pose.rise)
        // Choreography uses image coordinates (downward Y); AppKit uses upward Y.
        context.rotate(by: -pose.tilt * .pi/180)
        context.scaleBy(x: pose.scaleX, y: pose.scaleY)
        context.translateBy(x: -160, y: -pivotY)
        // Add weighted premultiplied layers in an isolated transparent group.
        // Source-over crossfades would thin the silhouette halfway through.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setBlendMode(.plusLighter)
        for (index, weight) in pose.weights.enumerated() where weight > 0 {
            context.setAlpha(weight); context.draw(frames[index], in: rect)
        }
        context.endTransparencyLayer()
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { open?() } else { window?.performDrag(with: event) }
    }
}
#endif
