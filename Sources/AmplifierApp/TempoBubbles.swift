#if os(macOS)
import AppKit
#if !NATIVE_CHECK
import ClientCore
#endif

/// Activity follows the avatar in an independent panel. Drag cards to move the avatar,
/// drag the expanded header to resize, and click to expand/collapse or open a chat.
@MainActor final class TempoBubbles {
    struct Row: Equatable {
        let key: String
        let title: String
        var detail: String
        let sessionID: String
        var status: NoticeStatus = .unread
        var dismissalState: String = ""
    }
    let window: NoticePanel
    private var rows: [Row] = []
    private var attentionCount = 0
    private var summary: String { attentionCount > 0 ? "\(attentionCount) update\(attentionCount == 1 ? "" : "s")" : "Ongoing work" }
    private(set) var listExpanded = false
    var artworkFrame: (() -> NSRect?)?
    var openChat: ((String) -> Void)?
    var dismiss: ((Row) -> Void)?
    private let defaults: UserDefaults
    private var sizing: NoticeListSize
    private var scrollView: NSScrollView?
    private var renderedKeys: [String] = []
    var listHeight: CGFloat { scrollView?.frame.height ?? 0 }
    var fitsContents: Bool { sizing.fitsContents }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sizing = NoticeListSize(maximum: defaults.object(forKey: "noticeListMaximum") as? Double ?? 178,
                                fitsContents: defaults.bool(forKey: "noticeListFitsContents"))
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
        window.anchor = anchor
        if rows != previous || previousCount != self.attentionCount || !window.isVisible { render() }
        window.anchor = anchor
        position(anchor); window.orderFrontRegardless()
    }
    private func card(_ row: Row, index: Int, compact: Bool) -> TempoMaterial {
        let material = NoticeMaterial(radius: 24)
        material.frame = NSRect(x: 0, y: 0, width: 320, height: compact ? 38 : 54)
        let button = NoticeButton(frame: NSRect(x: compact ? 16 : 36, y: 9, width: compact ? 288 : 248, height: compact ? 20 : 36))
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
        if !compact {
            let icon = NoticeStatusView(status: row.status)
            icon.frame = NSRect(x: 13, y: 28, width: 15, height: 15)
            material.content.addSubview(icon)
            let remove = FirstClickButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")!, target: self, action: #selector(dismissRow(_:)))
            remove.frame = NSRect(x: 290, y: 16, width: 24, height: 24); remove.isBordered = false
            remove.contentTintColor = .secondaryLabelColor; remove.tag = index
            remove.toolTip = row.status == .working ? "Hide until activity changes" : "Hide from Tempo; keep unread"; remove.setAccessibilityLabel("Dismiss " + row.title + " from Tempo")
            material.content.addSubview(remove)
        }
        material.onClick = { [weak button] in button?.performClick(nil) }
        return material
    }
    private func render() {
        guard let first = rows.first else { return }
        // Preserve a logical row and its offset, including removal above it.
        let oldScroll = scrollView
        let oldStack = oldScroll?.documentView as? NSStackView
        let oldTop = oldScroll?.documentVisibleRect.maxY ?? 0
        let bookmarks: [(String, CGFloat)] = zip(renderedKeys, oldStack?.arrangedSubviews ?? []).compactMap { key, view in
            guard let visible = oldScroll?.documentVisibleRect, view.frame.intersects(visible) else { return nil }
            return (key, oldTop - view.frame.maxY)
        }
        let oldDistance = (oldStack?.frame.height ?? 0) - oldTop
        scrollView = nil
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
            let height = CGFloat(sizing.height(content: Double(listHeight), available: Double(availableListHeight)))
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
            scroll.documentView = stack; root.addSubview(scroll); scrollView = scroll
            if listExpanded {
                let collapse = NoticeResizeButton(title: summary + "    ⌃ Collapse", target: self, action: #selector(toggleList))
                let header = NoticeMaterial(radius: 14)
                header.frame = NSRect(x: 0, y: height + 2, width: 320, height: 28)
                collapse.frame = header.bounds
                collapse.isBordered = false
                collapse.contentTintColor = .labelColor
                collapse.setAccessibilityLabel("Collapse updates")
                collapse.toolTip = "Drag to resize; click to collapse"
                let resize: (CGFloat) -> Void = { [weak self] delta in
                    guard let self else { return }; self.resizeList(to: self.listHeight + delta)
                }
                collapse.resizeBy = resize; header.resizeBy = resize
                collapse.setAccessibilityCustomActions([
                    NSAccessibilityCustomAction(name: "Show all updates") { [weak self] in self?.resizeList(to: .greatestFiniteMagnitude); return true },
                    NSAccessibilityCustomAction(name: "Make list taller") { resize(62); return true },
                    NSAccessibilityCustomAction(name: "Make list shorter") { resize(-62); return true }
                ])
                header.onClick = { [weak self] in self?.toggleList() }
                header.content.addSubview(collapse); root.addSubview(header)
            }
        }
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        if let scroll = scrollView, let stack = scroll.documentView as? NSStackView {
            stack.layoutSubtreeIfNeeded()
            let match = bookmarks.first { mark in rows.contains { $0.key == mark.0 } }
            var top = stack.frame.height - max(0, oldDistance)
            if let match, let index = rows.firstIndex(where: { $0.key == match.0 }) {
                top = stack.arrangedSubviews[index].frame.maxY + match.1
            }
            let y = min(max(0, top - scroll.contentSize.height), max(0, stack.frame.height - scroll.contentSize.height))
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
        }
        renderedKeys = rows.map(\.key)
        if let anchor = window.anchor { position(anchor) }
    }
    @objc private func toggleList() { listExpanded.toggle(); render() }
    #if NATIVE_CHECK
    var availableHeightOverride: CGFloat?
    #endif
    private var contentHeight: CGFloat { CGFloat(max(0, rows.count * 62 - 8)) }
    private var availableListHeight: CGFloat {
        #if NATIVE_CHECK
        if let availableHeightOverride { return availableHeightOverride }
        #endif
        guard let anchor = window.anchor, let screen = anchor.screen else { return 178 }
        let safe = TempoPlacement.inset(screen.visibleFrame)
        let top = artworkFrame?()?.maxY ?? anchor.frame.maxY
        let header: CGFloat = listExpanded ? 32 : 0
        // Prefer above the artwork, with the existing below-avatar fallback near the screen top.
        let above = safe.maxY - top - 8 - header
        let room = above >= 54 ? above : anchor.frame.minY - safe.minY - 8 - header
        return max(0, min(safe.height - header, room))
    }
    func resizeList(to height: CGFloat) {
        guard listExpanded else { return }
        sizing.resize(to: Double(height), content: Double(contentHeight), available: Double(availableListHeight))
        defaults.set(sizing.maximum, forKey: "noticeListMaximum")
        defaults.set(sizing.fitsContents, forKey: "noticeListFitsContents")
        render()
    }
    func position(_ anchor: NSWindow) {
        if scrollView != nil {
            let expected = CGFloat(sizing.height(content: Double(contentHeight), available: Double(availableListHeight)))
            if abs(expected - listHeight) > 0.5 { render(); return }
        }
        guard let visible = anchor.screen?.visibleFrame else { return }
        var reference = anchor.frame
        if let art = artworkFrame?() { reference.size.height = max(0, art.maxY - reference.minY) }
        window.setFrameOrigin(TempoPlacement.bubbles(anchor: reference, size: window.frame.size, visible: visible).origin)
    }
    func close() { window.anchor = nil; window.orderOut(nil); rows = []; renderedKeys = []; scrollView = nil; listExpanded = false }

    @objc private func select(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }; openChat?(rows[sender.tag].sessionID)
    }
    @objc private func dismissRow(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }; dismiss?(rows[sender.tag])
    }
}

@MainActor private final class NoticeStatusView: NSView {
    let status: NoticeStatus
    init(status: NoticeStatus) { self.status = status; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = status == .error ? .systemRed :
            ([.blocked, .question].contains(status) ? .systemOrange : .controlAccentColor)
        if status == .working {
            color.setStroke(); let path = NSBezierPath()
            path.appendArc(withCenter: NSPoint(x: bounds.midX, y: bounds.midY), radius: 5.5, startAngle: 25, endAngle: 320)
            path.lineWidth = 1.6; path.lineCapStyle = .round; path.stroke()
        } else {
            let image = NSImage(systemSymbolName: status.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [color]))
            let rect = status == .unread ? bounds.insetBy(dx: 4, dy: 4) : bounds
            image?.draw(in: rect)
        }
    }
}
@MainActor private enum NoticeResize {
    static func track(in view: NSView, event initial: NSEvent, resize: (CGFloat) -> Void, click: () -> Void) {
        guard let window = view.window else { return }
        let start = window.convertPoint(toScreen: initial.locationInWindow); var previous = start; var dragging = false
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = window.convertPoint(toScreen: event.locationInWindow)
            if abs(point.y - start.y) >= 3 { dragging = true }
            if event.type == .leftMouseUp { if !dragging { click() }; return }
            if dragging { resize(point.y - previous.y); previous = point }
        }
    }
}
@MainActor final class NoticeResizeButton: NoticeButton {
    var resizeBy: ((CGFloat) -> Void)?
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
    override func mouseDown(with event: NSEvent) {
        NoticeResize.track(in: self, event: event, resize: { self.resizeBy?($0) }) { self.performClick(nil) }
    }
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
@MainActor class NoticeButton: FirstClickButton {
    override func mouseDown(with event: NSEvent) { NoticeDrag.track(in: self) { self.performClick(nil) } }
}
@MainActor private final class NoticeMaterial: TempoMaterial {
    var onClick: (() -> Void)?
    var resizeBy: ((CGFloat) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSControl ? hit : self
    }
    override func mouseDown(with event: NSEvent) {
        if let resizeBy { NoticeResize.track(in: self, event: event, resize: resizeBy) { self.onClick?() } }
        else { NoticeDrag.track(in: self) { onClick?() } }
    }
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
