#if os(macOS)
import AppKit
import ClientCore

@MainActor final class SpriteView: NSView {
    var motion = Motion.waiting
    var open: (() -> Void)?
    private var frames: [[NSImage]] = []
    private var timer: Timer?
    private var tick = 0
    private var shape = ""
    private var palette = ""
    private var ink = NSRect(x: 0, y: 0, width: 1, height: 1)
    private var sculpted: NSImage?
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func load(_ name: String, palette: String = "blue", finish: String = "clear") {
        let name = AvatarAppearance.resourceName(name, finish: finish)
        guard shape != name || self.palette != palette else { return }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources"),
              let original = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let source = AvatarAppearance.colored(original, palette: palette)
        let reference = source.width == 1536 && source.height == 2288
            ? source.cropping(to: CGRect(x: 0, y: 0, width: 192, height: 208))! : source
        ink = AvatarAppearance.inkBounds(reference)
        shape = name; self.palette = palette
        if source.width != 1536 || source.height != 2288 {
            sculpted = NSImage(cgImage: source, size: NSSize(width: source.width, height: source.height))
            frames = []; needsDisplay = true; return
        }
        sculpted = nil
        frames = (0..<11).map { row in
            (0..<8).compactMap { column in
                source.cropping(to: CGRect(x: column * 192, y: row * 208, width: 192, height: 208))
                    .map { NSImage(cgImage: $0, size: NSSize(width: 192, height: 208)) }
            }
        }
        shape = name; needsDisplay = true
    }
    var visibleArtworkBounds: NSRect {
        var rect = bounds
        if let sculpted {
            let ratio = min(bounds.width / sculpted.size.width, bounds.height / sculpted.size.height)
            let size = NSSize(width: sculpted.size.width * ratio, height: sculpted.size.height * ratio)
            rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        }
        return NSRect(x: rect.minX + ink.minX * rect.width, y: rect.minY + ink.minY * rect.height,
            width: ink.width * rect.width, height: ink.height * rect.height).insetBy(dx: 0, dy: -3)
    }
    func animate(_ enabled: Bool) {
        timer?.invalidate(); timer = nil
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick += 1; self?.needsDisplay = true }
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if let sculpted {
            let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let phase = Double(tick) * (motion == .idle ? 0.16 : 0.32)
            let rise = reduced ? 0 : CGFloat(sin(phase)) * (motion == .idle ? 1.0 : 2.5)
            let ratio = min(bounds.width / sculpted.size.width, bounds.height / sculpted.size.height)
            let size = NSSize(width: sculpted.size.width * ratio, height: sculpted.size.height * ratio)
            sculpted.draw(in: NSRect(x: bounds.midX - size.width/2, y: bounds.midY - size.height/2 + rise, width: size.width, height: size.height))
            return
        }
        guard frames.count == 11 else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var row = motion.rawValue, column = reduced ? 0 : tick % motion.count
        if !reduced, motion == .idle, let window {
            let cursor = NSEvent.mouseLocation
            let dx = cursor.x - window.frame.midX, dy = cursor.y - window.frame.midY
            let distance = hypot(dx, dy)
            if distance > 100 && distance < 500 {
                let angle = atan2(dx, dy) + 2 * Double.pi
                let direction = Int((angle / (2 * Double.pi) * 16).rounded()) % 16
                row = 9 + direction / 8; column = direction % 8
            }
        }
        frames[row][column].draw(in: bounds)
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { open?() }
        else { window?.performDrag(with: event) }
    }
}
#endif
