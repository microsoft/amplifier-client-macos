#if os(macOS)
import AppKit
import QuartzCore
import CoreText

/// The artwork keeps its own drag handling. Controls are sibling native buttons,
/// so pressing one can never turn into a window drag.
@MainActor final class TempoSurface: NSView {
    static let size = NSSize(width: 160, height: 154)
    let artwork: NSView
    let strip = DraggableMaterial()
    let handle = RestingHandle()
    let chatButton = FirstClickButton()
    let activityButton = FirstClickButton()
    private let divider = NSBox()
    private let badge = BadgeLabel()
    private var tracking: NSTrackingArea?
    private var collapse: Timer?
    private var pointerInside = false
    private var composing = false
    private var presenting = false
    private(set) var expanded = false
    var onChat: (() -> Void)?
    var onActivity: ((NSView) -> Void)?
    func installContextMenu(_ menu: NSMenu) {
        for view in [self, artwork, strip, strip.content, handle, chatButton, activityButton] { view.menu = menu }
    }

    init(artwork: NSView) {
        self.artwork = artwork
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        setAccessibilityElement(false)
        artwork.frame = NSRect(x: 32, y: 46, width: 96, height: 104)
        addSubview(artwork)
        strip.frame = NSRect(x: 4, y: 4, width: 152, height: 36)
        addSubview(strip)
        for (button, symbol, label, action, x) in [
            (chatButton, "bubble.left", "Write a message", #selector(chat), 7.0),
            (activityButton, "bell", "Activity", #selector(activity), 57.0)
        ] {
            button.frame = NSRect(x: x, y: 2, width: 38, height: 32)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.imageScaling = .scaleProportionallyDown
            button.isBordered = false; button.bezelStyle = .recessed
            button.target = self; button.action = action
            button.toolTip = label; button.setAccessibilityLabel(label)
            strip.content.addSubview(button)
        }
        divider.frame = NSRect(x: 51, y: 10, width: 1, height: 16)
        divider.boxType = .separator; strip.content.addSubview(divider)
        badge.frame = NSRect(x: 79, y: 17, width: 18, height: 18)
        badge.isHidden = true
        badge.setAccessibilityElement(false)
        // Decoration: badge clicks reach the bell underneath.
        strip.content.addSubview(badge)
        handle.frame = NSRect(x: 58, y: 27, width: 44, height: 24)
        handle.isBordered = false; handle.target = self; handle.action = #selector(toggle)
        handle.setAccessibilityLabel("Show Tempo controls")
        addSubview(handle)
        updateStatus(connected: true, working: 0, unread: 0, detail: "Ready")
        setExpanded(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    func setActivityAvailable(_ available: Bool) {
        activityButton.isHidden = !available; divider.isHidden = !available
        let width: CGFloat = available ? 102 : 52
        strip.frame = NSRect(x: (bounds.width - width) / 2, y: 4, width: width, height: 36)
        strip.layoutSubtreeIfNeeded()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { pointerInside = true; collapse?.invalidate(); setExpanded(true) }
    override func mouseExited(with event: NSEvent) { pointerInside = false; scheduleCollapse() }
    func setPresenting(_ value: Bool) {
        presenting = value
        if !value, let window {
            let location = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            pointerInside = bounds.contains(location)
        }
        if value { collapse?.invalidate(); setExpanded(true) } else { scheduleCollapse() }
    }
    func dismissControls() { setExpanded(false) }
    func setComposing(_ value: Bool) {
        composing = value
        if value { collapse?.invalidate() }
        setExpanded(false)
    }
    private func scheduleCollapse() {
        collapse?.invalidate()
        guard !pointerInside, !presenting else { return }
        collapse = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.pointerInside, !self.presenting else { return }
                self.setExpanded(false)
            }
        }
    }
    private func setExpanded(_ value: Bool) {
        expanded = value && !composing; strip.isHidden = !expanded; handle.isHidden = expanded || composing
        handle.refreshAnimation()
    }
    @objc private func toggle() { setExpanded(true); scheduleCollapse() }
    @objc private func chat() { onChat?() }
    @objc private func activity() { onActivity?(activityButton) }

    func setBubblesVisible(_ visible: Bool) {
        activityButton.image = NSImage(systemSymbolName: visible ? "chevron.down" : "bell", accessibilityDescription: nil)
        activityButton.toolTip = visible ? "Collapse updates" : "Show updates"
        activityButton.setAccessibilityLabel(visible ? "Collapse updates" : "Show updates")
    }

    func updateStatus(connected: Bool, working: Int, unread: Int, error: Bool = false, detail: String) {
        let count = max(0, unread)
        setActivityAvailable(connected && (count > 0 || working > 0))
        badge.stringValue = String(count)
        let diameter = max(18, ceil(badge.glyphBounds.width) + 8)
        badge.frame = NSRect(x: 97 - diameter, y: 35 - diameter, width: diameter, height: diameter)
        badge.isHidden = count == 0 || !connected
        activityButton.setAccessibilityLabel(connected ? "Activity, \(count) updates" : "Activity, disconnected")
        activityButton.toolTip = connected ? (count > 0 ? "\(count) updates" : "View activity") : "Connection details"
        artwork.toolTip = detail
        // Only a small handle remains at rest; status text lives in tooltips,
        // accessibility, the activity card, and the menu bar.
        handle.title = "━"
        handle.update(connected: connected, working: working > 0, attention: unread > 0, error: error)
        handle.needsDisplay = true
        handle.font = .systemFont(ofSize: 12, weight: .medium)
        handle.contentTintColor = !connected ? .systemOrange : (working > 0 ? .controlAccentColor : .secondaryLabelColor)
        let meaning = !connected ? detail : (error ? "Error needs review" : (count > 0 ? "\(count) updates to review" : (working > 0 ? "Working" : "Idle")))
        handle.toolTip = "\(meaning) · Show Tempo controls"
        handle.setAccessibilityLabel("\(meaning). Show Tempo controls")
    }
}

/// Core Animation runs the color flow and attention pulse together without a
/// redraw timer. Stop both when hidden or when Reduce Motion is enabled.
@MainActor final class RestingHandle: DragHandle {
    let material = TempoMaterial(radius: 6)
    private var pill: CALayer { material.layer! }
    private let fill = CALayer()
    private let gradient = CAGradientLayer()
    private(set) var shape = "relay"
    private(set) var working = false
    private(set) var attention = false
    private var connected = true
    private(set) var hasError = false
    var animationsEnabled = true { didSet { refreshAnimation() } }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var activeAnimations: Set<String> { Set((pill.animationKeys() ?? []) + (gradient.animationKeys() ?? [])) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        material.wantsLayer = true; material.content.wantsLayer = true
        material.setAccessibilityElement(false)
        addSubview(material)
        material.content.layer?.addSublayer(fill); fill.addSublayer(gradient)
        fill.masksToBounds = true
        gradient.startPoint = NSPoint(x: 0, y: 0.5); gradient.endPoint = NSPoint(x: 1, y: 0.5)
        gradient.locations = [0, 0.25, 0.5, 0.75, 1]
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setTheme(_ shape: String, palette: String = "blue") { self.shape = shape; refreshAnimation() }
    func update(connected: Bool, working: Bool, attention: Bool, error: Bool = false) {
        self.connected = connected; self.working = connected && working; self.attention = connected && attention
        self.hasError = connected && error
        refreshAnimation()
    }
    // Glass is decoration inside the button: the entire hit area keeps click/drag behavior.
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func layout() { super.layout(); updateLayers() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshAnimation() }
    @objc private func accessibilityChanged() { refreshAnimation() }
    // Status belongs to the work, never to the selected artwork palette.
    var statusColor: NSColor {
        if !connected { return .systemOrange }
        if hasError { return .systemRed }
        if attention { return .systemBlue }
        return working ? .systemTeal : .systemGray
    }
    private func colors() -> [NSColor] {
        [statusColor, statusColor.blended(withFraction: 0.25, of: .white) ?? statusColor]
    }
    private func updateLayers() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // One native glass surface, with a restrained status wash inside its contentView.
        material.frame = NSRect(x: bounds.midX - 18, y: bounds.midY - 6, width: 36, height: 12)
        material.setTint(statusColor.withAlphaComponent(0.8))
        material.layoutSubtreeIfNeeded()
        pill.cornerRadius = 6; pill.shadowOffset = .zero
        pill.shadowPath = CGPath(roundedRect: pill.bounds, cornerWidth: 6, cornerHeight: 6, transform: nil)
        fill.frame = material.bounds; fill.cornerRadius = 6
        gradient.frame = NSRect(x: 0, y: 0, width: 72, height: 12)
        let palette = colors()
        let alpha: CGFloat = material.usesLiquidGlass ? 0.16 : (working || attention ? 0.8 : 0.45)
        gradient.colors = [palette[0], palette[1], palette[0], palette[1], palette[0]].map { $0.withAlphaComponent(alpha).cgColor }
        pill.shadowColor = palette[0].cgColor
        pill.shadowRadius = attention ? 5 : 2
        pill.shadowOpacity = attention ? 0.8 : (working ? 0.35 : 0)
        fill.borderWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0.5
        fill.borderColor = NSColor.labelColor.withAlphaComponent(0.3).cgColor
        CATransaction.commit()
    }
    func refreshAnimation(reduceMotion override: Bool? = nil) {
        updateLayers()
        let animate = animationsEnabled && !isHidden && !(override ?? reduceMotion)
        if animate && working {
            if gradient.animation(forKey: "flow") == nil {
                let flow = CABasicAnimation(keyPath: "transform.translation.x")
                flow.fromValue = 0; flow.toValue = -36; flow.duration = 2.4; flow.repeatCount = .infinity
                gradient.add(flow, forKey: "flow")
            }
        } else { gradient.removeAnimation(forKey: "flow") }
        if animate && attention {
            if pill.animation(forKey: "attention") == nil {
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = 1; scale.toValue = 1.12
                let glow = CABasicAnimation(keyPath: "shadowOpacity")
                glow.fromValue = 0.35; glow.toValue = 0.95
                let pulse = CAAnimationGroup(); pulse.animations = [scale, glow]
                pulse.duration = 1.2; pulse.autoreverses = true; pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                pill.add(pulse, forKey: "attention")
            }
        } else { pill.removeAnimation(forKey: "attention") }
    }
    override func draw(_ dirtyRect: NSRect) { /* Native glass and its status wash draw the pill; no title glyph. */ }
}

@MainActor final class BadgeLabel: NSView {
    var stringValue = "" { didSet { needsDisplay = true } }
    private var line: CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: stringValue,
            attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: NSColor.white]))
    }
    var glyphBounds: NSRect { CTLineGetBoundsWithOptions(line, .useGlyphPathBounds) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemBlue.setFill(); NSBezierPath(ovalIn: bounds).fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let text = line, ink = CTLineGetBoundsWithOptions(text, .useGlyphPathBounds)
        context.saveGState(); context.textMatrix = .identity
        context.textPosition = NSPoint(x: bounds.midX - ink.midX, y: bounds.midY - ink.midY)
        CTLineDraw(text, context); context.restoreGState()
    }
}

@MainActor final class TempoPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

#endif
