#if os(macOS)
import AppKit

/// Activity follows the avatar in an independent panel. A drag anywhere on a notice moves the
/// avatar; a click expands the stack or opens that notice's chat.
@MainActor final class TempoBubbles {
    struct Row: Equatable {
        let key: String
        let title: String
        var detail: String
        let sessionID: String
    }
    let window: NoticePanel
    private var rows: [Row] = []
    private var attentionCount = 0
    private var summary: String { attentionCount > 0 ? "\(attentionCount) update\(attentionCount == 1 ? "" : "s")" : "Ongoing work" }
    private(set) var listExpanded = false
    var artworkFrame: (() -> NSRect?)?
    var openChat: ((String) -> Void)?
    init() {
        window = NoticePanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.level = TempoWindows.input; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    func update(_ incoming: [Row], anchor: NSWindow, keepExisting: Bool, attentionCount: Int? = nil) {
        guard !incoming.isEmpty else { close(); return }
        let previous = rows
        let previousCount = self.attentionCount
        self.attentionCount = max(0, attentionCount ?? incoming.count)
        // Retain ordering while reading, but remove notices that were reviewed.
        if keepExisting {
            let updates = Dictionary(uniqueKeysWithValues: incoming.map { ($0.key, $0) })
            rows = rows.compactMap { updates[$0.key] }
            let keys = Set(rows.map(\.key)); rows += incoming.filter { !keys.contains($0.key) }
        } else { rows = incoming }
        if rows.count == 1 { listExpanded = false }
        if rows != previous || previousCount != self.attentionCount || !window.isVisible { render() }
        window.anchor = anchor
        position(anchor); window.orderFrontRegardless()
    }
    private func card(_ row: Row, index: Int, compact: Bool) -> TempoMaterial {
        let material = NoticeMaterial(radius: 24)
        material.frame = NSRect(x: 0, y: 0, width: 320, height: compact ? 38 : 54)
        let button = NoticeButton(frame: NSRect(x: 16, y: 9, width: 288, height: compact ? 20 : 36))
        button.isBordered = false; button.alignment = .left; button.cell?.wraps = true
        button.cell?.lineBreakMode = .byTruncatingTail
        let heading = compact ? summary + " · " + row.title : row.title
        let title = NSMutableAttributedString(string: heading + (compact ? "" : "\n"), attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])
        if !compact {
            title.append(NSAttributedString(string: row.detail, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        button.attributedTitle = title; button.toolTip = compact ? "Show " + summary.lowercased() : row.title + "\n" + row.detail
        button.setAccessibilityLabel(compact ? "Show " + summary.lowercased() : row.title + ", " + row.detail + ". Open chat")
        button.tag = index; button.target = self; button.action = compact ? #selector(toggleList) : #selector(select(_:))
        material.content.addSubview(button)
        material.onClick = { [weak button] in button?.performClick(nil) }
        return material
    }
    private func render() {
        guard let first = rows.first else { return }
        let root = NoticeBackground()
        if rows.count > 1 && !listExpanded {
            let depth = min(2, rows.count - 1)
            let height = CGFloat(38 + depth * 8)
            window.setContentSize(NSSize(width: 320, height: height)); root.frame = NSRect(x: 0, y: 0, width: 320, height: height)
            root.onClick = { [weak self] in self?.toggleList() }
            for level in (1...depth).reversed() {
                let back = NoticeReveal()
                back.frame = NSRect(x: CGFloat(level * 6), y: CGFloat((depth-level)*8), width: CGFloat(320-level*12), height: 38)
                root.addSubview(back)
            }
            let front = card(first, index: 0, compact: true)
            front.frame.origin.y = CGFloat(depth * 8); root.addSubview(front)
        } else {
            let header: CGFloat = listExpanded ? 32 : 0
            let listHeight = CGFloat(rows.count * 62 - 8)
            let height = min(178, listHeight)
            window.setContentSize(NSSize(width: 320, height: height + header)); root.frame = NSRect(x: 0, y: 0, width: 320, height: height + header)
            let scroll = NoticeScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: height))
            scroll.contentView = TransparentNoticeClipView()
            scroll.drawsBackground = false
            // Floating cards scroll directly; keep indicator chrome off the desktop.
            scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
            let stack = NoticeStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
            for (index, row) in rows.enumerated() {
                let material = card(row, index: index, compact: false)
                material.translatesAutoresizingMaskIntoConstraints = false
                material.widthAnchor.constraint(equalToConstant: 320).isActive = true
                material.heightAnchor.constraint(equalToConstant: 54).isActive = true
                stack.addArrangedSubview(material)
            }
            stack.frame = NSRect(x: 0, y: 0, width: 320, height: listHeight)
            scroll.documentView = stack; root.addSubview(scroll)
            if listExpanded {
                let collapse = NoticeButton(title: summary + "    ⌃ Collapse", target: self, action: #selector(toggleList))
                let header = NoticeMaterial(radius: 14)
                header.frame = NSRect(x: 0, y: height + 2, width: 320, height: 28)
                collapse.frame = header.bounds
                collapse.isBordered = false
                collapse.contentTintColor = .labelColor
                collapse.setAccessibilityLabel("Collapse updates")
                header.content.addSubview(collapse); root.addSubview(header)
            }
        }
        window.contentView = root
        if let anchor = window.anchor { position(anchor) }
    }
    @objc private func toggleList() { listExpanded.toggle(); render() }
    func position(_ anchor: NSWindow) {
        guard let visible = anchor.screen?.visibleFrame else { return }
        var reference = anchor.frame
        if let art = artworkFrame?() { reference.size.height = max(0, art.maxY - reference.minY) }
        window.setFrameOrigin(TempoPlacement.bubbles(anchor: reference, size: window.frame.size, visible: visible).origin)
    }
    func close() { window.anchor = nil; window.orderOut(nil); rows = []; listExpanded = false }

    @objc private func select(_ sender: NSButton) { openChat?(rows[sender.tag].sessionID) }
}

// Independent panels have a single geometry owner. AppKit child-window translation
// otherwise competes with edge clamping during each parent move and causes jitter.
@MainActor final class NoticePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    weak var anchor: NSWindow?
}

/// Borderless transparent windows otherwise have holes between their cards.
/// WindowServer excludes zero-alpha pixels from event targeting. One alpha step
/// supplies hit coverage. Draw it ourselves: NSScrollView’s background rendering
/// flattens alpha into an opaque rectangle. No blur/material backs the gaps.
@MainActor final class TransparentNoticeClipView: NSClipView {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(1.0 / 255.0).setFill()
        dirtyRect.fill()
    }
}
@MainActor final class NoticeScrollView: NSScrollView {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
@MainActor private final class NoticeStackView: NSStackView {
    override func scrollWheel(with event: NSEvent) { enclosingScrollView?.scrollWheel(with: event) }
    override func mouseDown(with event: NSEvent) { NoticeDrag.track(in: self) {} }
}

@MainActor private enum NoticeDrag {
    static func track(in view: NSView, click: () -> Void) {
        guard let eventWindow = view.window, let avatar = (eventWindow as? NoticePanel)?.anchor else { click(); return }
        let start = NSEvent.mouseLocation, origin = avatar.frame.origin
        var dragging = false
        while let event = eventWindow.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let cursor = NSEvent.mouseLocation
            if hypot(cursor.x-start.x, cursor.y-start.y) >= 3 { dragging = true }
            if event.type == .leftMouseUp { if !dragging { click() }; return }
            if dragging { avatar.setFrameOrigin(NSPoint(x: origin.x+cursor.x-start.x, y: origin.y+cursor.y-start.y)) }
        }
    }
}
@MainActor final class NoticeButton: FirstClickButton {
    override func mouseDown(with event: NSEvent) { NoticeDrag.track(in: self) { self.performClick(nil) } }
}
@MainActor private final class NoticeMaterial: TempoMaterial {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NoticeButton ? hit : self
    }
    override func mouseDown(with event: NSEvent) { NoticeDrag.track(in: self) { onClick?() } }
}
/// Stack reveals are ordinary content, not nested glass surfaces.
@MainActor private final class NoticeReveal: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.8).setFill()
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 24, yRadius: 24)
        shape.fill()
        NSColor.separatorColor.setStroke(); shape.lineWidth = 0.5; shape.stroke()
    }
}
@MainActor private final class NoticeBackground: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { NoticeDrag.track(in: self) { self.onClick?() } }
}
#endif
