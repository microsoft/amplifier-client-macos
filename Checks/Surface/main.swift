import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let window = TempoPanel(contentRect: NSRect(x: -10000, y: -10000, width: 720, height: 300),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let root = NSView(frame: window.contentView!.bounds)
    window.contentView = root
    let art = NSView()
    let surface = TempoSurface(artwork: art)
    root.addSubview(surface)
    window.makeKeyAndOrderFront(nil)
    precondition(!surface.expanded, "Controls must rest quietly")
    precondition(art.frame.width == 96 && art.frame.height == 104, "Artwork must retain the reduced size")
    surface.handle.performClick(nil)
    precondition(surface.expanded, "Handle must reveal controls")
    var actions: [String] = []
    surface.onChat = { actions.append("chat") }
    surface.onActivity = { _ in actions.append("activity") }
    let context = NSMenu()
    context.addItem(withTitle: "Settings…", action: nil, keyEquivalent: "")
    context.addItem(withTitle: "Hide Tempo", action: nil, keyEquivalent: "")
    surface.installContextMenu(context)
    precondition(surface.activityButton.isHidden && surface.strip.frame.width == 52)
    precondition(surface.artwork.menu === context && surface.strip.menu === context && surface.chatButton.menu === context)
    precondition(surface.strip.content.subviews.compactMap { $0 as? NSButton }.count == 2, "No ellipsis button")
    surface.updateStatus(connected: true, working: 0, unread: 3, detail: "3 updates")
    precondition(!surface.activityButton.isHidden && surface.strip.frame.width == 102)
    if #available(macOS 26.0, *) { precondition(surface.strip.usesLiquidGlass) }
    else { precondition(!surface.strip.usesLiquidGlass) }
    surface.chatButton.performClick(nil)
    surface.activityButton.performClick(nil)
    precondition(actions == ["chat", "activity"], "All native actions must dispatch")
    surface.updateStatus(connected: true, working: 0, unread: 3, detail: "3 updates")
    // Clicking through the decorative badge must still reach the activity button.
    let target = surface.strip.hitTest(NSPoint(x: surface.strip.frame.minX + 85, y: 27))
    precondition(target === surface.activityButton, "Badge must not intercept the activity button")
    precondition(surface.strip.hitTest(NSPoint(x: surface.strip.frame.minX + 51, y: 27)) === surface.strip, "Capsule decoration must route dragging to the material")
    let badge = surface.strip.content.subviews.compactMap { $0 as? BadgeLabel }.first!
    precondition(badge.frame.width == badge.frame.height, "Notification badge must be circular")
    surface.updateStatus(connected: true, working: 1, unread: 12, detail: "12 updates")
    precondition(badge.stringValue == "12" && badge.frame.width == badge.frame.height)
    precondition(badge.glyphBounds.width <= badge.frame.width - 8)
    precondition(surface.handle.title == "━", "Collapsed handle must never show an unread number")
    precondition(surface.handle.frame.midY == 39, "Collapsed handle must sit close to the artwork")
    if #available(macOS 26.0, *) { precondition(surface.handle.material.usesLiquidGlass, "Resting pill uses native glass") }
    surface.dismissControls()
    let pillHit = surface.handle.hitTest(NSPoint(x: surface.handle.frame.midX, y: surface.handle.frame.midY))
    precondition(pillHit === surface.handle, "Glass must route clicks and dragging to the resting handle")
    precondition(!surface.expanded)
    surface.setPresenting(true)
    precondition(surface.expanded, "Open activity/settings must keep controls visible")
    surface.setPresenting(false)
    surface.updateStatus(connected: false, working: 0, unread: 3, detail: "Not connected")
    precondition(surface.handle.toolTip?.contains("Not connected") == true)
    precondition(surface.handle.title == "━", "Old host badges must disappear while offline")
    window.onEscape = { surface.dismissControls() }
    window.cancelOperation(nil)
    precondition(!surface.expanded, "Escape must dismiss controls")
    print("PASS: quiet/expanded states, button dispatch, badge hit target, offline state, artwork size, Escape")

    let hover = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
    surface.mouseEntered(with: hover)
    precondition(surface.expanded)
    surface.setBubblesVisible(true)
    // AppKit timers can fire late on shared CI runners. Observe the actual state
    // transition with a bounded deadline instead of giving a 0.65s timer only
    // 0.1s of scheduling slack. A missing collapse still fails this check.
    @MainActor func requireCollapse(_ message: String) {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while surface.expanded && ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(!surface.expanded, message)
    }
    surface.mouseExited(with: hover)
    requireCollapse("Open bubbles must not prevent hover collapse")
    surface.handle.performClick(nil)
    requireCollapse("Clicking the handle must not latch the pill open")
    precondition(surface.strip.acceptsFirstMouse(for: nil) && surface.handle.acceptsFirstMouse(for: nil))
    precondition(surface.chatButton.acceptsFirstMouse(for: nil))
    print("PASS: hover collapse with bubbles, no permanent click latch, first-click controls and drag surfaces")

    precondition(!window.canBecomeKey && !window.canBecomeMain, "Avatar controls must not take keyboard focus")
    let bubbles = TempoBubbles()
    precondition(!bubbles.window.canBecomeKey && !bubbles.window.canBecomeMain, "Notice controls must not take keyboard focus")
    bubbles.openChat = { actions.append($0) }
    bubbles.update([.init(key: "a", title: "Planning the next release", detail: "Response ready", sessionID: "chat-1")], anchor: window, keepExisting: false)
    let scroll = bubbles.window.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!
    let stack = scroll.documentView as! NSStackView
    let row = (stack.arrangedSubviews[0] as! TempoMaterial).content.subviews[0] as! NSButton
    row.performClick(nil)
    precondition(actions.last == "chat-1", "Bubble must open its own chat")
    @MainActor func clickPadding(_ material: NSView) {
        let point = NSPoint(x: 8, y: material.bounds.midY)
        let hit = material.hitTest(material.convert(point, to: material.superview))!
        precondition(!(hit is NSButton), "Exercise the card outside the text button")
        let position = material.convert(point, to: nil)
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: position, modifierFlags: [], timestamp: 0,
            windowNumber: bubbles.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: position, modifierFlags: [], timestamp: 0,
            windowNumber: bubbles.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        app.postEvent(up, atStart: true); hit.mouseDown(with: down)
    }
    let beforePadding = actions.count
    clickPadding(stack.arrangedSubviews[0])
    precondition(actions.count == beforePadding + 1 && actions.last == "chat-1", "Card padding must open the chat too")
    precondition(bubbles.window.anchor === window && bubbles.window.parent == nil, "Bubbles must follow the avatar")
    bubbles.update([], anchor: window, keepExisting: true)
    precondition(!bubbles.window.isVisible, "No empty or stale bubble when activity clears")
    surface.updateStatus(connected: true, working: 0, unread: 0, detail: "Ready")
    precondition(surface.activityButton.isHidden && surface.strip.frame.width == 52)
    bubbles.close()
    precondition(!bubbles.window.isVisible && bubbles.window.anchor == nil)
    let many: [TempoBubbles.Row] = (0..<12).map { .init(key: "row-\($0)", title: "Chat \($0)", detail: "Response ready", sessionID: "chat-\($0)") }
    bubbles.update(many, anchor: window, keepExisting: false, attentionCount: 11)
    precondition(!bubbles.listExpanded && bubbles.window.frame.height == 54, "Many notices start in a compact single-line stack")
    let front = bubbles.window.contentView!.subviews.compactMap { $0 as? TempoMaterial }.last!
    clickPadding(front)
    precondition(bubbles.listExpanded && bubbles.window.frame.height == 210)
    let list = bubbles.window.contentView!.subviews.compactMap { $0 as? NoticeScrollView }.first!
    list.layoutSubtreeIfNeeded()
    let document = list.documentView as! NSStackView
    document.layoutSubtreeIfNeeded()
    let firstCard = document.arrangedSubviews[0], secondCard = document.arrangedSubviews[1]
    let gap = NSPoint(x: 160, y: (firstCard.frame.minY + secondCard.frame.maxY) / 2)
    precondition(document.hitTest(gap) != nil, "Gaps must be part of the scroll surface")
    precondition(!list.isOpaque && !list.contentView.isOpaque && !list.drawsBackground)
    precondition(firstCard.frame.height == 54, "Notices use compact two-line cards")
    let header = bubbles.window.contentView!.subviews.compactMap { $0 as? TempoMaterial }.first!
    let collapseList = header.content.subviews.compactMap { $0 as? NoticeButton }.first!
    precondition(collapseList.acceptsFirstMouse(for: nil))
    precondition(collapseList.title.hasPrefix("11 updates"), "Ongoing work must not increase attention counters")
    // Optional real WindowServer routing check: a wheel over a transparent gap
    // must reach this panel and scroll it just like a wheel over a card.
    if CommandLine.arguments.contains("--wheel-check"), CGPreflightPostEventAccess(), let screen = NSScreen.main {
        let previousMouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 360, y: screen.visibleFrame.midY - 200))
        bubbles.position(window); bubbles.window.orderFrontRegardless(); app.updateWindows(); bubbles.window.displayIfNeeded(); CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        let visible = document.visibleRect
        let cards = document.arrangedSubviews.sorted { $0.frame.minY < $1.frame.minY }
        let gaps = zip(cards, cards.dropFirst()).map { NSPoint(x: 160, y: ($0.frame.maxY + $1.frame.minY) / 2) }
        let point = gaps.first { visible.insetBy(dx: 0, dy: 10).contains($0) }!
        let cardPoint = NSPoint(x: point.x, y: point.y + 16)
        if let directory = ProcessInfo.processInfo.environment["AMPLIFIER_CAPTURE_DIR"] {
            try! String(bubbles.window.windowNumber).write(toFile: directory + "/window-id", atomically: true, encoding: .utf8)
            // Capture from the authorized desktop harness, not this unsigned process.
            let deadline = Date().addingTimeInterval(30)
            while !FileManager.default.fileExists(atPath: directory + "/notices.png") && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            let image = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: directory + "/notices.png")))!
            let inWindow = document.convert(point, to: nil)
            let sx = CGFloat(image.pixelsWide) / bubbles.window.frame.width
            let sy = CGFloat(image.pixelsHigh) / bubbles.window.frame.height
            let color = image.colorAt(x: Int(inWindow.x * sx), y: Int((bubbles.window.frame.height - inWindow.y) * sy))!
            print("Captured gap alpha", color.alphaComponent)
            fflush(stdout)
            precondition(color.alphaComponent <= 0.01, "The gap must stay visually transparent, never an opaque scroll backing")
        }

        for local in [point, cardPoint] {
            let before = list.contentView.bounds.origin
            let onScreen = bubbles.window.convertPoint(toScreen: document.convert(local, to: nil))
            let quartz = NSPoint(x: onScreen.x, y: screen.frame.maxY - onScreen.y)
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: quartz, mouseButton: .left)?.post(tap: .cghidEventTap)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 24, wheel2: 0, wheel3: 0)!
            print("Wheel target", local, quartz, "window", bubbles.window.frame, "viewport", list.contentView.bounds)
            fflush(stdout)
            wheel.location = quartz; wheel.post(tap: .cghidEventTap)
            guard let delivered = app.nextEvent(matching: .scrollWheel, until: Date().addingTimeInterval(2), inMode: .default, dequeue: true) else { fatalError("Wheel was not delivered to the test process") }
            precondition(delivered.window === bubbles.window, "WindowServer must route gaps to the notice panel")
            app.sendEvent(delivered)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            precondition(list.contentView.bounds.origin != before, "Both gap and card wheel events must scroll the list")
        }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: NSPoint(x: previousMouse.x, y: screen.frame.maxY - previousMouse.y), mouseButton: .left)?.post(tap: .cghidEventTap)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        print("PASS: real WindowServer wheel routing over gaps and cards")
    }
    collapseList.performClick(nil)
    precondition(!bubbles.listExpanded && bubbles.window.frame.height == 54)
    bubbles.close()
    bubbles.update(Array(many.prefix(2)), anchor: window, keepExisting: false, attentionCount: 0)
    let workingFront = bubbles.window.contentView!.subviews.compactMap { $0 as? TempoMaterial }.last!
    let workingTitle = (workingFront.content.subviews.first as! NSButton).attributedTitle.string
    precondition(workingTitle.hasPrefix("Ongoing work"), "Work alone must not be labeled unread updates")
    bubbles.close()
    print("PASS: twelve rows, eleven attention items, work-only labeling, stack, bounded scroll and collapse")
    surface.setBubblesVisible(true)
    precondition(surface.activityButton.toolTip == "Collapse updates")
    surface.setBubblesVisible(false)
    print("PASS: empty activity hidden, exact chat action, parent attachment and collapse")

    // Screen geometry: all corners, display origins, varying input height, and
    // progressive recentering after leaving either edge.
    for screen in [NSRect(x: 0, y: 25, width: 1440, height: 850), NSRect(x: -1920, y: -400, width: 1920, height: 1080)] {
        for x in [screen.minX - 70, screen.minX, screen.midX, screen.maxX - 160, screen.maxX + 30] {
            for y in [screen.minY - 100, screen.midY, screen.maxY] {
                for height: CGFloat in [88, 120, 240] {
                    let avatar = TempoPlacement.avatar(NSRect(x: x, y: y, width: 160, height: 154), visible: screen, composerHeight: height)
                    let input = TempoPlacement.composer(anchor: avatar, size: NSSize(width: 360, height: height), visible: screen)
                    precondition(screen.contains(avatar) && screen.contains(input), "Whole arrangement must stay visible")
                    precondition(input.maxY < avatar.minY + 46, "Input must stay below artwork")
                    let expectedCenter = min(max(avatar.midX, screen.minX + TempoPlacement.margin + 180), screen.maxX - TempoPlacement.margin - 180)
                    precondition(input.midX == expectedCenter, "Input must recenter as avatar leaves edge")
                }
            }
        }
    }
    print("PASS: 90 screen-edge, bottom, recentering, resizing and secondary-display cases")

    let tightAnchor = NSRect(x: 200, y: 200, width: 160, height: 112)
    let tightBubble = TempoPlacement.bubbles(anchor: tightAnchor, size: NSSize(width: 320, height: 70), visible: NSRect(x: 0, y: 0, width: 1200, height: 1000))
    precondition(tightBubble.minY == tightAnchor.maxY + 8, "Place notices just above the ink envelope")
    let opaque = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    opaque.setFillColor(NSColor.white.cgColor); opaque.fill(CGRect(x: 4, y: 2, width: 12, height: 6))
    let ink = AvatarAppearance.inkBounds(opaque.makeImage()!)
    precondition(abs(ink.minX - 0.2) < 0.001 && abs(ink.minY - 0.1) < 0.001 && abs(ink.maxY - 0.4) < 0.001)
    var lastX: CGFloat?
    let dragScreen = NSRect(x: -1000, y: -100, width: 1600, height: 1000)
    for x in stride(from: CGFloat(-1100), through: 650, by: 1) {
        let frame = TempoPlacement.bubbles(anchor: NSRect(x: x, y: 200, width: 160, height: 154),
            size: NSSize(width: 320, height: 258), visible: dragScreen)
        precondition(TempoPlacement.inset(dragScreen).contains(frame), "Notices need screen margins")
        if let lastX { precondition(frame.minX >= lastX && frame.minX - lastX <= 1, "Edge recentering must track every pixel smoothly") }
        lastX = frame.minX
    }
    print("PASS: inset bubble placement and continuous edge-to-center drag")
    let composer = TempoComposer(chats: [("chat-1", "Existing chat")], anchor: window.frame)
    let send = composer.sendButton
    precondition(!send.isEnabled, "Empty messages must not send")
    precondition(composer.editor.frame.height > 0 && composer.editor.acceptsFirstMouse(for: nil))
    precondition(!composer.window!.styleMask.contains(.titled) && composer.window!.level.rawValue > NSWindow.Level.floating.rawValue)
    precondition(composer.window!.frame.height == 88, "Composer must start compact")
    composer.editor.string = "   "
    composer.textDidChange(Notification(name: NSText.didChangeNotification))
    precondition(!send.isEnabled)
    composer.editor.string = "Hello from Tempo"
    composer.textDidChange(Notification(name: NSText.didChangeNotification))
    precondition(send.isEnabled)
    var submitted = false
    composer.onSend = { target, text in
        precondition(target == nil && text == "Hello from Tempo")
        submitted = true
        return "new-chat"
    }
    send.performClick(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    precondition(submitted && composer.editor.string.isEmpty, "Composer must send without opening a browser")
    let picker = composer.target
    precondition(picker.titleOfSelectedItem == "This chat", "Follow-ups must stay in the newly created chat")
    print("PASS: empty composer, direct submission and follow-up target")
    let suite = "tempo-check-" + UUID().uuidString
    let preferences = UserDefaults(suiteName: suite)!
    preferences.set("http://127.0.0.1:8941", forKey: "endpoint")
    defer { preferences.removePersistentDomain(forName: suite) }
    var changes: [String] = []; var connections = 0; var connectionActions: [ConnectionAction] = []
    let settings = SettingsWindow(defaults: preferences, recoveryPath: nil, artwork: { _, _, _ in nil },
        preferenceChanged: { changes.append($0) },
        connectionAction: { action in
            connectionActions.append(action)
            preferences.set(action != .resume, forKey: "connectionPaused")
        }, connect: { _, _ in connections += 1 })
    precondition(settings.window!.level == .normal, "Settings must not float over other apps")
    precondition(!settings.window!.styleMask.contains(.fullSizeContentView), "Sidebar must stay below the title bar")
    let tabs = settings.window!.contentView!.subviews.compactMap { $0 as? NSTabView }.first!
    let appearance = tabs.tabViewItems[0].view!
    let relay = appearance.subviews.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "relay" }!
    relay.performClick(nil)
    precondition(preferences.string(forKey: "shape") == "relay" && changes == ["shape"] && connections == 0)
    let work = tabs.tabViewItems[1].view!.subviews.compactMap { $0 as? NSSwitch }.first { $0.identifier?.rawValue == "workBubbles" }!
    work.state = .on; NSApp.sendAction(work.action!, to: work.target, from: work)
    precondition(preferences.bool(forKey: "workBubbles") && connections == 0)
    let fields = tabs.tabViewItems[2].view!.subviews.compactMap { $0 as? NSTextField }
    fields.first { $0.isEditable && !($0 is NSSecureTextField) }!.stringValue = "https://example.invalid"
    precondition(connections == 0 && preferences.string(forKey: "endpoint") == "http://127.0.0.1:8941")
    let color = appearance.subviews.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "palette:cyan-amber" }!
    color.performClick(nil)
    precondition(preferences.string(forKey: "palette") == "cyan-amber" && changes.last == "palette" && connections == 0)
    let swatches = appearance.subviews.compactMap { $0 as? NSButton }.filter { $0.identifier?.rawValue.hasPrefix("palette:") == true }
    precondition(swatches.count == 8 && swatches.filter { $0.state == .on }.count == 1)
    precondition(appearance.subviews.compactMap { $0 as? NSPopUpButton }.isEmpty, "Appearance choices must not hide behind menus")
    let cards = appearance.subviews.compactMap { $0 as? NSButton }.filter { AvatarAppearance.shapes.contains($0.identifier?.rawValue ?? "") }
    precondition(cards.count == 6 && !AvatarAppearance.shapes.contains("fold"))
    precondition(Set(cards.map { $0.frame.minX }).count == 3 && Set(cards.map { $0.frame.minY }).count == 2)
    let finish = appearance.subviews.compactMap { $0 as? NSSegmentedControl }.first!
    precondition(finish.segmentCount == 2 && finish.selectedSegment == 0, "Default to Clear in a native segmented control")
    finish.selectedSegment = 1; NSApp.sendAction(finish.action!, to: finish.target, from: finish)
    precondition(preferences.string(forKey: "finish") == "dark" && changes.last == "finish" && connections == 0)
    precondition((cards + swatches).allSatisfy { !$0.isBordered && $0.bezelColor == nil }, "Content choices should not be prominent glass tiles")
    precondition(settings.window!.toolbar!.items.count == 3 && !settings.window!.toolbar!.allowsUserCustomization)
    settings.showConnection()
    precondition(settings.window!.title == "Connection" && preferences.integer(forKey: "settingsPane") == 2)
    let connectionButtons = tabs.tabViewItems[2].view!.subviews.compactMap { $0 as? NSButton }
    let pause = connectionButtons.first { $0.title == "Disconnect" }!
    pause.performClick(nil)
    precondition(preferences.bool(forKey: "connectionPaused") && pause.title == "Resume")
    pause.performClick(nil)
    precondition(!preferences.bool(forKey: "connectionPaused") && pause.title == "Disconnect")
    precondition(connectionActions == [.pause, .resume] && connections == 0,
                 "Connection actions must target saved settings, never the edited address draft")
    let reopened = SettingsWindow(defaults: preferences, recoveryPath: nil, artwork: { _, _, _ in nil }, preferenceChanged: {_ in}, connect: {_,_ in})
    precondition(reopened.window!.title == "Connection", "Restore last settings pane")
    precondition(TempoControls.statusSymbol(attention: false, working: false) == nil)
    precondition(TempoControls.statusSymbol(attention: true, working: false) != TempoControls.statusSymbol(attention: false, working: true))
    precondition(TempoControls.statusImage(attention: true, working: true) != nil)
    precondition(AttentionDot().hitTest(.zero) == nil, "Menu badge must preserve menu clicks")
    for shape in AvatarAppearance.shapes {
        precondition(AvatarAppearance.resourceName(shape, finish: "dark") == shape + "-dark")
        precondition(AvatarAppearance.resourceName(shape, finish: "clear") == shape)
    }
    surface.handle.isHidden = false
    for palette in AvatarAppearance.palettes {
        surface.handle.setTheme("relay", palette: palette.id)
        surface.handle.update(connected: true, working: false, attention: false)
        precondition(surface.handle.statusColor == .systemGray)
        surface.handle.update(connected: true, working: true, attention: false)
        precondition(surface.handle.statusColor == .systemTeal)
        surface.handle.update(connected: true, working: true, attention: true)
        precondition(surface.handle.statusColor == .systemBlue)
        surface.handle.update(connected: true, working: true, attention: true, error: true)
        precondition(surface.handle.statusColor == .systemRed)
        surface.handle.update(connected: false, working: true, attention: true, error: true)
        precondition(surface.handle.statusColor == .systemOrange)
    }
    surface.handle.update(connected: true, working: true, attention: true)
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        precondition(surface.handle.activeAnimations == ["flow", "attention"], "Working and attention compose independently")
        surface.handle.update(connected: true, working: true, attention: false)
        precondition(surface.handle.activeAnimations == ["flow"], "Clearing attention must preserve work animation")
    }
    surface.handle.refreshAnimation(reduceMotion: true)
    precondition(surface.handle.activeAnimations.isEmpty, "Reduce Motion keeps the indicators still")
    surface.handle.animationsEnabled = false
    precondition(surface.handle.activeAnimations.isEmpty, "Hidden avatar must not keep animating")
    surface.handle.animationsEnabled = true
    surface.handle.update(connected: false, working: true, attention: true)
    precondition(surface.handle.activeAnimations.isEmpty, "Offline must clear stale work and attention")
    print("PASS: six shapes, exposed color swatches and glass choices, combined work/attention, hidden/offline animation suspension")
    print("PASS: avatar and preferences apply immediately; editing connection fields does not connect")
    window.orderOut(nil)

    // Optional visual review: render actual controls with the approved atlas art.
    // This harness never loads credentials, connects to a host, or reads the desktop.
    if CommandLine.arguments.count == 3 {
        let atlasURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        let source = NSImage(contentsOf: atlasURL)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let frame = source.cropping(to: CGRect(x: 0, y: 0, width: 192, height: 208))!
        for dark in [false, true] {
            let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 330))
            canvas.wantsLayer = true
            canvas.layer?.backgroundColor = (dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.95, alpha: 1)).cgColor
            canvas.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let preview = TempoPanel(contentRect: canvas.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            preview.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            preview.contentView = canvas
            for (index, label) in ["At rest", "Unread at rest", "Quick controls", "New activity"].enumerated() {
                let image = NSImageView(); image.image = NSImage(cgImage: frame, size: NSSize(width: 192, height: 208))
                let controls = TempoSurface(artwork: image)
                controls.handle.setTheme("relay", palette: "blue")
                controls.frame.origin = NSPoint(x: 50 + index * 245, y: 70)
                canvas.addSubview(controls)
                if index > 1 { controls.handle.performClick(nil) }
                if index == 1 || index == 3 { controls.updateStatus(connected: true, working: 0, unread: 3, detail: "3 updates") }
                let title = NSTextField(labelWithString: label)
                title.font = .systemFont(ofSize: 15, weight: .medium)
                title.frame = NSRect(x: 35 + index * 245, y: 28, width: 190, height: 24)
                title.alignment = .center; canvas.addSubview(title)
            }
            preview.orderFrontRegardless()
            canvas.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(dark ? "tempo-controls-dark.png" : "tempo-controls-light.png"))
            preview.orderOut(nil)
            let styledSettings = SettingsWindow(defaults: preferences, recoveryPath: nil, artwork: { name, palette, finish in
                let url = atlasURL.deletingLastPathComponent().appendingPathComponent(AvatarAppearance.resourceName(name, finish: finish) + ".png")
                guard let atlas = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let image = Optional(AvatarAppearance.thumbnail(atlas, palette: palette)) else { return nil }
                return image
            }, preferenceChanged: { _ in }, connect: { _, _ in })
            let styledComposer = TempoComposer(chats: [("chat-1", "Planning a trip")], anchor: window.frame)
            for (name, controller) in [("settings", styledSettings as NSWindowController), ("composer", styledComposer as NSWindowController)] {
                let sample = controller.window!
                sample.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                sample.setFrameOrigin(NSPoint(x: -10000, y: -10000)); sample.orderFrontRegardless()
                let content = sample.contentView!
                if name == "settings" {
                    sample.backgroundColor = .windowBackgroundColor
                }
                content.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("tempo-" + name + (dark ? "-dark.png" : "-light.png")))
                sample.orderOut(nil)
            }
        }
    }
}
