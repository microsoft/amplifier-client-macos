#if os(macOS)
import AppKit
import QuartzCore
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
        var serviceID: String = ""
        var serviceName: String = ""
        var priority: NoticePriority = .unread
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
    private var renderedCards: [String: NSView] = [:]
    private var showServiceHeadings = false
    private var suppressedForSpace = false
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
    func update(_ incoming: [Row], anchor: NSWindow, keepExisting: Bool, attentionCount: Int? = nil, showServiceHeadings: Bool = false) {
        guard !incoming.isEmpty else { close(); return }
        let previous = rows
        let previousCount = self.attentionCount
        let headingsChanged = self.showServiceHeadings != showServiceHeadings
        self.showServiceHeadings = showServiceHeadings
        self.attentionCount = max(0, attentionCount ?? incoming.count)
        // Retain ordering while reading, but remove notices that were reviewed.
        if keepExisting {
            let updates = Dictionary(uniqueKeysWithValues: incoming.map { ($0.key, $0) })
            rows = rows.compactMap { updates[$0.key] }
            let keys = Set(rows.map(\.key)); rows += incoming.filter { !keys.contains($0.key) }
        } else { rows = incoming }
        window.anchor = anchor
        if rows != previous || previousCount != self.attentionCount || headingsChanged || !window.isVisible { render() }
        window.anchor = anchor
        position(anchor)
        if !suppressedForSpace { window.orderFrontRegardless() }
    }
    private func card(_ row: Row, index: Int, compact: Bool) -> TempoMaterial {
        let material = NoticeMaterial(radius: 24)
        material.frame = NSRect(x: 0, y: 0, width: 320, height: compact ? 38 : 54)
        let button = NoticeButton(frame: NSRect(x: compact ? 16 : 36, y: compact ? 9 : 28, width: compact ? 288 : 248, height: 20))
        button.isBordered = false; button.alignment = .left; button.cell?.wraps = false
        button.cell?.lineBreakMode = .byTruncatingTail
        let cleanTitle = NoticeText.plain(row.title, limit: 240)
        let cleanDetail = NoticeText.plain(row.detail)
        let heading = compact ? summary + " · " + cleanTitle : cleanTitle
        button.attributedTitle = NSAttributedString(string: heading, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])
        button.toolTip = compact ? "Show " + summary.lowercased() : cleanTitle + "\n" + cleanDetail
        button.setAccessibilityLabel(compact ? "Show " + summary.lowercased() : cleanTitle + ", " + cleanDetail + ". Open chat")
        button.tag = index; button.target = self; button.action = compact ? #selector(toggleList) : #selector(select(_:))
        material.content.addSubview(button)
        if !compact {
            // The detail uses the whole lower line, including the space below the
            // icon and dismiss control. Its hit region belongs to the draggable card.
            let detail = NoticeDetailLabel(labelWithString: cleanDetail)
            detail.frame = NSRect(x: 16, y: 9, width: 288, height: 18)
            detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
            detail.lineBreakMode = .byTruncatingTail; detail.maximumNumberOfLines = 1
            detail.setAccessibilityElement(false); detail.toolTip = cleanDetail
            material.content.addSubview(detail)
            let icon = NoticeStatusView(status: row.status)
            icon.frame = NSRect(x: 13, y: 28, width: 15, height: 15)
            material.content.addSubview(icon)
            let remove = FirstClickButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")!, target: self, action: #selector(dismissRow(_:)))
            remove.frame = NSRect(x: 290, y: 28, width: 24, height: 24); remove.isBordered = false
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
        let bookmarks: [(String, CGFloat)] = renderedKeys.compactMap { key in
            guard let view = renderedCards[key], let visible = oldScroll?.documentVisibleRect, view.frame.intersects(visible) else { return nil }
            return (key, oldTop - view.frame.maxY)
        }
        let oldDistance = (oldStack?.frame.height ?? 0) - oldTop
        scrollView = nil
        renderedCards = [:]
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
            let listHeight = contentHeight
            let height = CGFloat(sizing.height(content: Double(listHeight), available: Double(availableListHeight)))
            window.setContentSize(NSSize(width: 320, height: height + header)); root.frame = NSRect(x: 0, y: 0, width: 320, height: height + header)
            let scroll = NoticeScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: height))
            scroll.contentView = TransparentNoticeClipView()
            scroll.drawsBackground = false
            // Floating cards scroll directly; keep indicator chrome off the desktop.
            scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
            let stack = NoticeStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
            for (index, row) in rows.enumerated() {
                if startsGroup(at: index) {
                    let heading = NoticeGroupHeader(name: row.serviceName)
                    heading.translatesAutoresizingMaskIntoConstraints = false
                    heading.widthAnchor.constraint(equalToConstant: 320).isActive = true
                    heading.heightAnchor.constraint(equalToConstant: 24).isActive = true
                    stack.addArrangedSubview(heading)
                }
                let material = card(row, index: index, compact: false)
                material.translatesAutoresizingMaskIntoConstraints = false
                material.widthAnchor.constraint(equalToConstant: 320).isActive = true
                material.heightAnchor.constraint(equalToConstant: 54).isActive = true
                stack.addArrangedSubview(material)
                renderedCards[row.key] = material
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
            if oldDistance > 0.5, let match, let card = renderedCards[match.0] {
                top = card.frame.maxY + match.1
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
    private func startsGroup(at index: Int) -> Bool {
        showServiceHeadings && !rows[index].serviceID.isEmpty &&
            (index == 0 || rows[index - 1].serviceID != rows[index].serviceID)
    }
    private var contentHeight: CGFloat {
        CGFloat(max(0, rows.count * 62 - 8) + rows.indices.filter { startsGroup(at: $0) }.count * 32)
    }
    private func referenceFrame(_ anchor: NSWindow) -> NSRect {
        var reference = anchor.frame
        if let art = artworkFrame?() { reference.size.height = max(0, art.maxY - reference.minY) }
        return reference
    }
    private var availableListHeight: CGFloat {
        #if NATIVE_CHECK
        if let availableHeightOverride { return availableHeightOverride }
        #endif
        guard let anchor = window.anchor, let screen = anchor.screen else { return 178 }
        let header: CGFloat = listExpanded ? 32 : 0
        return max(0, TempoPlacement.noticeHeight(anchor: referenceFrame(anchor), visible: screen.visibleFrame) - header)
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
        let reference = referenceFrame(anchor)
        let room = TempoPlacement.noticeHeight(anchor: reference, visible: visible)
        // With no room even for the header/compact card, temporarily hide rather
        // than detach the list or cover the avatar. Keep expansion and saved size.
        let minimum = listExpanded ? CGFloat(32) : (scrollView == nil ? window.frame.height : CGFloat(1))
        guard room >= minimum else {
            suppressedForSpace = true; window.orderOut(nil); return
        }
        window.setFrameOrigin(TempoPlacement.bubbles(anchor: reference, size: window.frame.size, visible: visible).origin)
        if suppressedForSpace { window.orderFrontRegardless() }
        suppressedForSpace = false
    }
    func close() { window.anchor = nil; window.orderOut(nil); rows = []; renderedKeys = []; renderedCards = [:]; scrollView = nil; listExpanded = false; suppressedForSpace = false }

    @objc private func select(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }; openChat?(rows[sender.tag].sessionID)
    }
    @objc private func dismissRow(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }; dismiss?(rows[sender.tag])
    }
}

@MainActor private final class NoticeGroupHeader: NSView {
    init(name: String) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: NoticeText.plain(name, limit: 120))
        label.frame = NSRect(x: 16, y: 5, width: 288, height: 17)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor; label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill(); NSRect(x: 16, y: 0, width: 288, height: 1).fill()
    }
    override func mouseDown(with event: NSEvent) { NoticeDrag.track(in: self) {} }
}

@MainActor private final class NoticeDetailLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
    private let edgeMask = CAGradientLayer()
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateEdgeFade()
    }
    override func layout() {
        super.layout()
        updateEdgeFade()
    }
    private func updateEdgeFade() {
        guard let document = documentView else { return }
        let visible = documentVisibleRect
        let lower = max(0, visible.minY - document.bounds.minY)
        let upper = max(0, document.bounds.maxY - visible.maxY)
        document.wantsLayer = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard visible.height > 0, lower > 0.5 || upper > 0.5 else {
            document.layer?.mask = nil
            return
        }
        // Mask only the cards/headings, leaving the clip view's transparent
        // wheel-event coverage intact. Never paint a background over the desktop.
        let depth = min(CGFloat(18), visible.height / 3)
        let bottom = lower > 0.5 ? min(depth, lower) : 0
        let top = upper > 0.5 ? min(depth, upper) : 0
        edgeMask.frame = visible
        edgeMask.startPoint = CGPoint(x: 0.5, y: 0)
        edgeMask.endPoint = CGPoint(x: 0.5, y: 1)
        edgeMask.colors = [NSColor.black.withAlphaComponent(bottom > 0 ? 0 : 1).cgColor,
                           NSColor.black.cgColor, NSColor.black.cgColor,
                           NSColor.black.withAlphaComponent(top > 0 ? 0 : 1).cgColor]
        edgeMask.locations = [0, NSNumber(value: Double(bottom / visible.height)),
                              NSNumber(value: Double(1 - top / visible.height)), 1]
        document.layer?.mask = edgeMask
    }
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
