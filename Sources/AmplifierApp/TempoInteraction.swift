#if os(macOS)
import AppKit

/// Native glass controls share one policy; older macOS keeps native bezels.
@MainActor enum TempoControls {
    static func style(_ button: NSButton) {
        button.isBordered = true
        if #available(macOS 26.0, *) { button.bezelStyle = .glass }
        else { button.bezelStyle = .rounded }
    }
    static func statusSymbol(attention: Bool, working: Bool) -> String? {
        attention ? (working ? "exclamationmark.arrow.triangle.2.circlepath" : "circle.fill") : (working ? "arrow.triangle.2.circlepath" : nil)
    }
    static func statusImage(attention: Bool, working: Bool) -> NSImage? {
        guard let symbol = statusSymbol(attention: attention, working: working) else { return nil }
        // Widely available symbols keep the macOS 13 fallback readable too.
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: attention ? (working ? "Update available; working" : "Update available") : "Working")
            ?? NSImage(systemSymbolName: attention ? "circle.fill" : "arrow.clockwise", accessibilityDescription: attention ? "Update available" : "Working")
        return image?.withSymbolConfiguration(.init(paletteColors: [attention ? .controlAccentColor : .secondaryLabelColor]))
    }
}

/// A presence badge, never a work counter. The template logo remains OS-tinted.
@MainActor final class AttentionDot: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds)
        NSColor.systemBlue.setFill(); circle.fill()
    }
}

/// One level above ordinary floating windows; system menus stay above Tempo.
@MainActor enum TempoWindows {
    static let avatar = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    static let input = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
}

/// Share screen constraints between drag handling and the composer, including
/// displays whose origin is negative. Input stays below the visible artwork.
enum TempoPlacement {
    static let margin: CGFloat = 12
    static func inset(_ visible: NSRect) -> NSRect { visible.insetBy(dx: margin, dy: margin) }
    static func bubbles(anchor: NSRect, size: NSSize, visible: NSRect) -> NSRect {
        let safe = inset(visible)
        let above = anchor.maxY + 8
        let y = above + size.height <= safe.maxY ? above : anchor.minY - size.height - 8
        return NSRect(x: min(max(anchor.midX - size.width / 2, safe.minX), max(safe.minX, safe.maxX - size.width)),
                      y: min(max(y, safe.minY), max(safe.minY, safe.maxY - size.height)), width: size.width, height: size.height)
    }
    static func avatar(_ frame: NSRect, visible: NSRect, composerHeight: CGFloat = 0) -> NSRect {
        let visible = inset(visible)
        let bottom = visible.minY + max(0, composerHeight - 40)
        var result = frame
        result.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
        result.origin.y = min(max(frame.minY, bottom), max(bottom, visible.maxY - frame.height))
        return result
    }
    static func composer(anchor: NSRect, size: NSSize, visible: NSRect) -> NSRect {
        let anchor = avatar(anchor, visible: visible, composerHeight: size.height)
        let visible = inset(visible)
        return NSRect(x: min(max(anchor.midX - size.width / 2, visible.minX), max(visible.minX, visible.maxX - size.width)),
                      y: anchor.minY + 40 - size.height, width: size.width, height: size.height)
    }
}

/// System Liquid Glass on modern macOS; native vibrancy on older releases.
/// Content belongs inside the glass contentView so AppKit controls its layering.
@MainActor class TempoMaterial: NSView {
    let content = NSView()
    let usesLiquidGlass: Bool
    init(radius: CGFloat = 18) {
        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius; glass.style = .regular
            glass.contentView = content
            background = glass; usesLiquidGlass = true
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow; effect.blendingMode = .behindWindow; effect.state = .active
            effect.wantsLayer = true; effect.layer?.cornerRadius = radius; effect.layer?.masksToBounds = true
            effect.addSubview(content)
            background = effect; usesLiquidGlass = false
        }
        super.init(frame: .zero)
        addSubview(background)
        background.autoresizingMask = [.width, .height]
        content.autoresizingMask = [.width, .height]
    }
    func setTint(_ color: NSColor) {
        if #available(macOS 26.0, *), let glass = subviews.first as? NSGlassEffectView {
            glass.tintColor = color
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        subviews.first?.frame = bounds
        content.frame = bounds
    }
}

@MainActor class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class DraggableMaterial: TempoMaterial {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is NSControl { return hit }
            view = current.superview
        }
        // Material and separator subviews are decoration, not separate targets.
        return self
    }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

@MainActor class DragHandle: FirstClickButton {
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { performClick(nil); return }
            let delta = hypot(next.locationInWindow.x - event.locationInWindow.x, next.locationInWindow.y - event.locationInWindow.y)
            if delta >= 3 { window.performDrag(with: next); return }
        }
    }
}

@MainActor final class ComposerPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if TempoEditing.route(event, in: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
#endif
