#if os(macOS)
import AppKit
import ServiceManagement

enum ConnectionAction { case pause, resume, forget }

@MainActor final class SettingsWindow: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private let loginItem = LoginItemController()
    private let loginSwitch = NSSwitch()
    private let loginDetail = NSTextField(wrappingLabelWithString: "")
    private let loginSettings = NSButton(title: "Review in System Settings…", target: nil, action: nil)
    private let defaults: UserDefaults
    private let address = NSTextField(string: "")
    private let token = NSSecureTextField(string: "")
    private let connectionState = NSTextField(wrappingLabelWithString: "")
    private let result = NSTextField(wrappingLabelWithString: "")
    private let pages = NSTabView()
    private var swatches: [NSButton] = []
    private let finish = NSSegmentedControl(labels: ["Clear", "Dark"], trackingMode: .selectOne, target: nil, action: nil)
    private let paneNames = ["Appearance", "Notifications", "Connection"]
    private let paneIcons = ["paintpalette", "bell", "network"]
    private var previewCache: [String: NSImage] = [:]
    private var avatars: [NSButton] = []
    private let artwork: (String, String, String) -> NSImage?
    private let preferenceChanged: (String) -> Void
    private var pairingTask: Task<Void, Never>?
    private let pairingButton = NSButton(title: "Connect in browser…", target: nil, action: nil)
    private let manualButton = NSButton(title: "Use an access token…", target: nil, action: nil)
    private var manualControls: [NSView] = []
    private let manageDevices: ((String) throws -> Void)?
    private let pair: ((String, @escaping (String) -> Void) async throws -> String)?
    private let connect: (String, String) throws -> Void
    private let connectionAction: ((ConnectionAction) throws -> Void)?
    private let pauseButton = NSButton(title: "Disconnect", target: nil, action: nil)
    private let forgetButton = NSButton(title: "Forget…", target: nil, action: nil)
    private let browserSetup: ((String) async throws -> Void)?
    private let browserButton = NSButton(title: "Browser access…", target: nil, action: nil)
    private var browserTask: Task<Void, Never>?

    init(defaults: UserDefaults, recoveryPath: String?, artwork: @escaping (String, String, String) -> NSImage?,
         preferenceChanged: @escaping (String) -> Void, connectionAction: ((ConnectionAction) throws -> Void)? = nil, manageDevices: ((String) throws -> Void)? = nil, browserSetup: ((String) async throws -> Void)? = nil, pair: ((String, @escaping (String) -> Void) async throws -> String)? = nil, connect: @escaping (String, String) throws -> Void) {
        self.defaults = defaults; self.artwork = artwork
        self.preferenceChanged = preferenceChanged; self.connect = connect; self.connectionAction = connectionAction; self.pair = pair; self.manageDevices = manageDevices
        self.browserSetup = browserSetup
        let window = EditingWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 508),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Amplifier Settings"; window.titlebarAppearsTransparent = true
        window.center(); window.isReleasedWhenClosed = false; window.level = .normal
        super.init(window: window)
        window.delegate = self
        let root = window.contentView!
        let toolbar = NSToolbar(identifier: "AmplifierSettings")
        toolbar.delegate = self; toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        window.toolbarStyle = .preference; window.toolbar = toolbar
        pages.tabViewType = .noTabsNoBorder
        pages.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(pages)
        NSLayoutConstraint.activate([
            pages.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            pages.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            pages.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            pages.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
        func page(_ name: String) -> NSView {
            let item = NSTabViewItem(identifier: name); item.label = name
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 492, height: 468))
            item.view = view; pages.addTabViewItem(item); return view
        }
        func label(_ text: String, x: CGFloat = 0, y: CGFloat, width: CGFloat = 492, secondary: Bool = false) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.frame = NSRect(x: x, y: y, width: width, height: secondary ? 34 : 24)
            label.font = .systemFont(ofSize: secondary ? 12 : 18, weight: secondary ? .regular : .semibold)
            label.textColor = secondary ? .secondaryLabelColor : .labelColor; return label
        }
        func group(y: CGFloat, height: CGFloat, in view: NSView) {
            let box = NSBox()
            box.boxType = .custom; box.titlePosition = .noTitle; box.cornerRadius = 10
            box.borderWidth = 0; box.fillColor = .controlBackgroundColor
            box.frame = NSRect(x: 0, y: y, width: 492, height: height)
            view.addSubview(box)
        }
        func toggle(_ title: String, detail: String, key: String, y: CGFloat, in view: NSView) {
            group(y: y, height: 76, in: view)
            let heading = label(title, x: 16, y: y + 42, width: 392)
            heading.font = .systemFont(ofSize: 13, weight: .medium); view.addSubview(heading)
            view.addSubview(label(detail, x: 16, y: y + 8, width: 392, secondary: true))
            let toggle = NSSwitch(frame: NSRect(x: 430, y: y + 24, width: 42, height: 28))
            toggle.identifier = NSUserInterfaceItemIdentifier(key); toggle.setAccessibilityLabel(title)
            toggle.state = defaults.bool(forKey: key) ? .on : .off
            toggle.target = self; toggle.action = #selector(changeToggle(_:)); view.addSubview(toggle)
        }
        let appearance = page("appearance")
        appearance.addSubview(label("Make Tempo yours", y: 436))
        appearance.addSubview(label("Choose your avatar, color and finish. Changes appear immediately.", y: 398, secondary: true))
        let finishLabel = label("Avatar finish", y: 368, width: 106); finishLabel.font = .systemFont(ofSize: 13)
        appearance.addSubview(finishLabel)
        finish.frame = NSRect(x: 112, y: 364, width: 220, height: 32)
        finish.target = self; finish.action = #selector(selectFinish(_:))
        finish.setAccessibilityLabel("Avatar finish")
        appearance.addSubview(finish)
        let colorLabel = label("Color", y: 320, width: 60); colorLabel.font = .systemFont(ofSize: 13)
        appearance.addSubview(colorLabel)
        for (index, palette) in AvatarAppearance.palettes.enumerated() {
            let button = SelectionButton(title: "", target: self, action: #selector(selectPalette(_:)))
            button.identifier = NSUserInterfaceItemIdentifier("palette:" + palette.id)
            button.frame = NSRect(x: 68 + index * 53, y: 312, width: 46, height: 38)
            button.setButtonType(.pushOnPushOff); button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                NSGradient(starting: palette.colors[0], ending: palette.colors[1])?.draw(in: path, angle: 0)
                return true
            }
            button.toolTip = palette.title; button.setAccessibilityLabel(palette.title + " color")
            appearance.addSubview(button); swatches.append(button)
        }
        for (index, name) in AvatarAppearance.shapes.enumerated() {
            let button = SelectionButton(title: name.capitalized, target: self, action: #selector(selectAvatar(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(name)
            button.setButtonType(.pushOnPushOff); button.isBordered = false
            button.bezelStyle = .regularSquare
            button.frame = NSRect(x: CGFloat(index % 3 * 168), y: CGFloat(196 - index / 3 * 112), width: 156, height: 104)
            button.imagePosition = .imageAbove; button.imageScaling = .scaleProportionallyDown
            button.font = .systemFont(ofSize: 12, weight: .medium); button.setAccessibilityLabel(name.capitalized + " avatar")
            appearance.addSubview(button); avatars.append(button)
        }
        toggle("Show advanced menu options", detail: "Connection diagnostics in the menu bar menu.", key: "showAdvanced", y: 0, in: appearance)
        refreshAvatars()

        let notifications = page("notifications")
        notifications.addSubview(label("Notifications", y: 436))
        notifications.addSubview(label("Choose how Amplifier keeps you up to date.", y: 398, secondary: true))
        toggle("Desktop notifications", detail: "Replies and requests for your input.", key: "notifications", y: 308, in: notifications)
        toggle("Include all chats", detail: "Otherwise, include pinned chats and chats you use in Amplifier.", key: "notifyAll", y: 220, in: notifications)
        toggle("Show ongoing work above the avatar", detail: "See what’s running. The chevron tucks the bubbles away.", key: "workBubbles", y: 132, in: notifications)
        group(y: 8, height: 104, in: notifications)
        let loginHeading = label("Open Amplifier at login", x: 16, y: 76, width: 392)
        loginHeading.font = .systemFont(ofSize: 13, weight: .medium)
        notifications.addSubview(loginHeading)
        loginDetail.frame = NSRect(x: 16, y: 36, width: 392, height: 36)
        loginDetail.font = .systemFont(ofSize: 12); loginDetail.textColor = .secondaryLabelColor
        notifications.addSubview(loginDetail)
        loginSwitch.frame = NSRect(x: 430, y: 70, width: 42, height: 28)
        loginSwitch.identifier = NSUserInterfaceItemIdentifier("openAtLogin")
        loginSwitch.setAccessibilityLabel("Open Amplifier at login")
        loginSwitch.target = self; loginSwitch.action = #selector(changeLoginItem(_:))
        notifications.addSubview(loginSwitch)
        loginSettings.frame = NSRect(x: 16, y: 12, width: 240, height: 24)
        loginSettings.isBordered = false; loginSettings.alignment = .left
        loginSettings.contentTintColor = .linkColor
        loginSettings.target = self; loginSettings.action = #selector(reviewLoginItem)
        notifications.addSubview(loginSettings)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLoginItem),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        refreshLoginItem()

        let connection = page("connection")
        connection.addSubview(label("Your Amplifier", y: 436))
        connection.addSubview(label("Connect to the Amplifier where your chats live.", y: 398, secondary: true))
        group(y: 160, height: 222, in: connection)
        connection.addSubview(label("Amplifier address", x: 16, y: 338, width: 460, secondary: true))
        address.stringValue = defaults.string(forKey: "endpoint") ?? ""
        address.frame = NSRect(x: 16, y: 312, width: 460, height: 26); address.setAccessibilityLabel("Amplifier address")
        address.placeholderString = "https://your-amplifier-host"
        address.bezelStyle = .roundedBezel
        connection.addSubview(address)
        pairingButton.frame = NSRect(x: 16, y: 264, width: 210, height: 32)
        pairingButton.bezelStyle = .rounded; pairingButton.target = self; pairingButton.action = #selector(beginPairing)
        connection.addSubview(pairingButton)
        browserButton.frame = NSRect(x: 246, y: 264, width: 230, height: 32)
        browserButton.bezelStyle = .rounded; browserButton.target = self; browserButton.action = #selector(openBrowserSetup)
        browserButton.isEnabled = browserSetup != nil
        browserButton.toolTip = "Open separate browser setup for this address. Use Edge or Chrome with the Amplifier extension."
        browserButton.setAccessibilityHelp(browserButton.toolTip)
        connection.addSubview(browserButton)
        connection.addSubview(label("Approve chat access in your browser. Browser access needs separate approval.", x: 16, y: 214, width: 460, secondary: true))
        manualButton.frame = NSRect(x: 16, y: 174, width: 210, height: 28)
        manualButton.isBordered = false; manualButton.alignment = .left; manualButton.contentTintColor = .linkColor
        manualButton.target = self; manualButton.action = #selector(toggleManual)
        connection.addSubview(manualButton)
        let devices = NSButton(title: "Manage connected devices…", target: self, action: #selector(openDevices))
        devices.frame = NSRect(x: 246, y: 174, width: 230, height: 28)
        devices.isBordered = false; devices.alignment = .right; devices.contentTintColor = .linkColor
        connection.addSubview(devices)
        token.placeholderString = "Access token (blank keeps the saved token)"
        token.frame = NSRect(x: 0, y: 120, width: 370, height: 26); token.setAccessibilityLabel("Access token")
        token.bezelStyle = .roundedBezel; connection.addSubview(token)
        let button = NSButton(title: "Connect", target: self, action: #selector(commit))
        button.frame = NSRect(x: 390, y: 116, width: 102, height: 32); button.bezelStyle = .rounded; connection.addSubview(button)
        manualControls = [token, button]; manualControls.forEach { $0.isHidden = true }
        connectionState.frame = NSRect(x: 0, y: 82, width: 260, height: 30)
        connectionState.font = .systemFont(ofSize: 12); connectionState.textColor = .secondaryLabelColor; connection.addSubview(connectionState)
        pauseButton.frame = NSRect(x: 270, y: 80, width: 116, height: 28)
        pauseButton.bezelStyle = .rounded; pauseButton.target = self; pauseButton.action = #selector(toggleConnection)
        pauseButton.setAccessibilityLabel("Disconnect or resume this host")
        connection.addSubview(pauseButton)
        forgetButton.frame = NSRect(x: 394, y: 80, width: 98, height: 28)
        forgetButton.bezelStyle = .rounded; forgetButton.target = self; forgetButton.action = #selector(forgetConnection)
        forgetButton.setAccessibilityLabel("Forget this host credential")
        connection.addSubview(forgetButton)
        refreshConnectionActions()
        result.frame = NSRect(x: 0, y: 20, width: 492, height: 60); result.font = .systemFont(ofSize: 12); connection.addSubview(result)
        if let recoveryPath { result.stringValue = "Saved messages need recovery: \(recoveryPath)"; result.textColor = .systemRed }
        selectPage(at: min(2, max(0, defaults.integer(forKey: "settingsPane"))))
        if defaults.string(forKey: "endpoint") == nil || recoveryPath != nil { showConnection() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updateConnection(connected: Bool, message: String) {
        refreshConnectionActions()
        connectionState.stringValue = connected ? "Connected" : message; connectionState.toolTip = connected ? nil : message
    }
    override func showWindow(_ sender: Any?) {
        refreshLoginItem()
        super.showWindow(sender)
    }
    @objc private func refreshLoginItem() {
        loginItem.refresh()
        loginSwitch.state = loginItem.requested ? .on : .off
        loginDetail.stringValue = loginItem.detail
        loginDetail.toolTip = loginItem.detail
        loginDetail.textColor = loginItem.error == nil ? .secondaryLabelColor : .systemRed
        loginSettings.isHidden = !loginItem.needsApproval
        loginSwitch.setAccessibilityHelp(loginItem.detail)
    }
    @objc private func changeLoginItem(_ sender: NSSwitch) {
        loginItem.setEnabled(sender.state == .on)
        refreshLoginItem()
    }
    @objc private func reviewLoginItem() { SMAppService.openSystemSettingsLoginItems() }
    func showConnection() { selectPage(at: 2) }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneNames.map { NSToolbarItem.Identifier($0) }
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(toolbar) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        guard let index = paneNames.firstIndex(of: id.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = id.rawValue; item.paletteLabel = id.rawValue
        item.image = NSImage(systemSymbolName: paneIcons[index], accessibilityDescription: id.rawValue)
        item.target = self; item.action = #selector(selectPane(_:)); item.tag = index
        return item
    }
    @objc private func selectPane(_ sender: NSToolbarItem) { selectPage(at: sender.tag) }
    private func selectPage(at index: Int) {
        pages.selectTabViewItem(at: index)
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(paneNames[index])
        window?.title = paneNames[index]
        defaults.set(index, forKey: "settingsPane")
    }
    @objc private func changeToggle(_ sender: NSSwitch) {
        guard let key = sender.identifier?.rawValue else { return }
        defaults.set(sender.state == .on, forKey: key); preferenceChanged(key)
    }
    @objc private func selectAvatar(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue else { return }
        defaults.set(name, forKey: "shape"); refreshAvatars(); preferenceChanged("shape")
    }
    @objc private func selectPalette(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        defaults.set(String(key.dropFirst("palette:".count)), forKey: "palette")
        refreshAvatars(); preferenceChanged("palette")
    }
    @objc private func selectFinish(_ sender: NSSegmentedControl) {
        defaults.set(sender.selectedSegment == 1 ? "dark" : "clear", forKey: "finish")
        refreshAvatars(); preferenceChanged("finish")
    }
    private func refreshAvatars() {
        let shape = defaults.string(forKey: "shape") ?? "relay"
        let palette = defaults.string(forKey: "palette") ?? "blue"
        let finish = defaults.string(forKey: "finish") ?? "clear"
        for button in swatches { button.state = button.identifier?.rawValue == "palette:" + palette ? .on : .off; button.needsDisplay = true }
        self.finish.selectedSegment = finish == "dark" ? 1 : 0
        for button in avatars {
            let name = button.identifier!.rawValue
            button.state = name == shape ? .on : .off
            button.needsDisplay = true
            let key = name + ":" + palette + ":" + finish
            if previewCache[key] == nil { previewCache[key] = artwork(name, palette, finish) }
            button.image = previewCache[key]; button.image?.size = NSSize(width: 70, height: 70)
            button.needsDisplay = true
        }
    }
    private func refreshConnectionActions() {
        let available = connectionAction != nil && defaults.string(forKey: "endpoint") != nil && pairingTask == nil
        pauseButton.title = defaults.bool(forKey: "connectionPaused") ? "Resume" : "Disconnect"
        pauseButton.isEnabled = available; forgetButton.isEnabled = available
    }
    @objc private func toggleConnection() {
        do {
            try connectionAction?(defaults.bool(forKey: "connectionPaused") ? .resume : .pause)
            result.stringValue = ""; refreshConnectionActions()
        } catch { result.textColor = .systemRed; result.stringValue = error.localizedDescription }
    }
    @objc private func forgetConnection() {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "Forget this host on this Mac?"
        alert.informativeText = "Host: \(defaults.string(forKey: "endpoint") ?? "Unknown")\n\nRemoves the saved credential and disconnects Amplifier. Saved messages are kept. To revoke the device on the host too, use Manage connected devices."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Forget credential")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            do {
                try self.connectionAction?(.forget)
                self.token.stringValue = ""; self.result.textColor = .secondaryLabelColor
                self.result.stringValue = "Credential removed. Connect in browser to approve this Mac again."
                self.refreshConnectionActions()
            } catch { self.result.textColor = .systemRed; self.result.stringValue = error.localizedDescription }
        }
    }
    @objc private func openDevices() {
        do { try manageDevices?(address.stringValue) }
        catch { result.textColor = .systemRed; result.stringValue = error.localizedDescription }
    }
    @objc private func openBrowserSetup() {
        guard let browserSetup, browserTask == nil, pairingTask == nil else { return }
        let target = address.stringValue
        browserButton.isEnabled = false; pairingButton.isEnabled = false
        result.textColor = .secondaryLabelColor; result.stringValue = "Checking browser setup…"
        browserTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.browserTask = nil; self.browserButton.isEnabled = true
                self.pairingButton.isEnabled = true
            }
            do {
                try await browserSetup(target)
                try Task.checkCancellation()
                self.result.stringValue = "Continue in Edge or Chrome with the Amplifier extension. Select a tab or stop access in the extension. Quitting this app does not stop browser access."
            } catch {
                if !Task.isCancelled {
                    self.result.textColor = .systemRed; self.result.stringValue = error.localizedDescription
                }
            }
        }
    }
    func windowWillClose(_ notification: Notification) { browserTask?.cancel() }
    @objc private func toggleManual() {
        let show = token.isHidden
        manualControls.forEach { $0.isHidden = !show }
        manualButton.title = show ? "Hide access token" : "Use an access token…"
    }
    @objc private func beginPairing() {
        if let task = pairingTask { task.cancel(); return }
        guard let pair else { return }
        let target = address.stringValue
        address.isEnabled = false; manualButton.isEnabled = false
        browserButton.isEnabled = false
        manualControls.forEach { ($0 as? NSControl)?.isEnabled = false }
        pairingButton.title = "Cancel connection"
        pauseButton.isEnabled = false; forgetButton.isEnabled = false
        result.textColor = .secondaryLabelColor; result.stringValue = "Opening browser approval…"
        pairingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.pairingTask = nil; self.address.isEnabled = true; self.manualButton.isEnabled = true
                self.manualControls.forEach { ($0 as? NSControl)?.isEnabled = true }
                self.pairingButton.title = "Connect in browser…"
                self.browserButton.isEnabled = self.browserSetup != nil
                self.refreshConnectionActions()
            }
            do {
                let credential = try await pair(target) { [weak self] code in
                    self?.result.stringValue = "Match code \(code) in your browser, then allow the connection."
                }
                try Task.checkCancellation()
                try self.connect(target, credential)
                self.token.stringValue = ""; self.result.stringValue = "Connection approved. Amplifier is connecting…"
            } catch is CancellationError {
                self.result.stringValue = "Connection cancelled. Your existing connection is unchanged."
            } catch {
                self.result.textColor = .systemRed; self.result.stringValue = error.localizedDescription
            }
        }
    }
    @objc private func commit() {
        do {
            try connect(address.stringValue, token.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            token.stringValue = ""; result.textColor = .secondaryLabelColor; result.stringValue = "Connection saved. Amplifier is connecting…"
        } catch { result.textColor = .systemRed; result.stringValue = error.localizedDescription }
    }
}

/// Ordinary content selection: quiet outline and check, not another glass layer.
@MainActor private final class SelectionButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if state == .on {
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
            outline.lineWidth = 2; outline.stroke()
            let mark = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.white, .controlAccentColor]))
            mark?.draw(in: NSRect(x: bounds.maxX - 18, y: isFlipped ? 4 : bounds.maxY - 18, width: 14, height: 14))
        }
    }
}
#endif
