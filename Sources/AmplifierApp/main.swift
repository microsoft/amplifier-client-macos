#if os(macOS)
import AppKit
import ClientCore
import CryptoKit
import Darwin
import Security
import UserNotifications

enum Keychain {
    static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.microsoft.amplifier.macos",
         kSecAttrAccount as String: account]
    }
    static func read(_ account: String) throws -> String? {
        var q = query(account); q[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return token
    }
    static func remove(for account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
    static func save(_ token: String, for account: String) throws {
        let q = query(account), data = Data(token.utf8)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q; add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    // App-owned connection and delivery state is shared by every native surface.
    private let defaults = UserDefaults.standard
    private let updater = AppUpdater()
    private let journalURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Amplifier for Mac/journal.json")
    private var journal = Journal()
    private var storageReady = false
    private var journalLock: Int32 = -1
    private var registry = ServiceRegistry()
    private var registryReady = false
    private var connections: [String: ServiceConnection] = [:]
    private var orderedConnections: [ServiceConnection] { registry.services.compactMap { connections[$0.id] } }
    private var online: [ServiceConnection] { orderedConnections.filter { $0.connected } }
    private var selected: ServiceConnection? { registry.preferredID.flatMap { connections[$0] } ?? orderedConnections.first }
    private var bubbleTargets: [String: ServiceTarget] = [:]
    private var composerTargets: [String: ServiceTarget] = [:]
    private var nextDetailService = 0
    private var sends = Set<String>()
    private var notificationWaits = Set<String>()
    private var status = "Not connected"
    private var connected: Bool { !online.isEmpty }
    private var connecting: Bool { orderedConnections.contains { $0.connecting } }
    private var notificationStatus = "Checking notification permission…"
    private var notificationError: String?
    private var item: NSStatusItem!
    private let menuAttention = AttentionDot()
    private var panel: TempoPanel!
    private var surface: TempoSurface!
    private var sprite: SpriteView!
    private var settings: SettingsWindow?
    private var composer: TempoComposer?
    private var positioning = false
    private let bubbles = TempoBubbles()
    private var bubblesOpen = false
    private var bubblesManual = false
    private var autoBubblesSuppressed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            journalLock = Darwin.open(journalURL.deletingLastPathComponent().appendingPathComponent("client.lock").path,
                                     O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard journalLock >= 0, flock(journalLock, LOCK_EX | LOCK_NB) == 0 else {
                NSApp.terminate(nil); return
            }
            journal = try Journal.load(from: journalURL); storageReady = true
        }
        catch { status = "Saved replies could not be read. Open Settings for details." }
        do {
            registry = try ServiceRegistry.load(data: defaults.data(forKey: ServiceRegistry.defaultsKey),
                legacyAddress: defaults.string(forKey: "endpoint"), legacyPaused: defaults.bool(forKey: "connectionPaused"))
            defaults.set(try JSONEncoder().encode(registry), forKey: ServiceRegistry.defaultsKey)
            registryReady = true
        } catch { status = "Saved services could not be read. Existing credentials and replies are kept." }
        UNUserNotificationCenter.current().delegate = self
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [],
            textInputButtonTitle: "Send", textInputPlaceholder: "Reply to this chat")
        let open = UNNotificationAction(identifier: "open", title: "Open chat", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "response", actions: [reply], intentIdentifiers: []),
            UNNotificationCategory(identifier: "attention", actions: [open], intentIdentifiers: [])])
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.module.url(forResource: "MenuBarIcon@2x", withExtension: "png", subdirectory: "Resources"),
           let logo = NSImage(contentsOf: url) {
            logo.size = NSSize(width: 18, height: 18); logo.isTemplate = true
            logo.accessibilityDescription = "Amplifier for Mac"; item.button?.image = logo
        }
        if let button = item.button {
            menuAttention.translatesAutoresizingMaskIntoConstraints = false
            menuAttention.isHidden = true; menuAttention.setAccessibilityElement(false)
            button.addSubview(menuAttention)
            // Pin to the visual lower-right, independent of NSButton’s flipped coordinates.
            NSLayoutConstraint.activate([
                menuAttention.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: 7),
                menuAttention.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1),
                menuAttention.widthAnchor.constraint(equalToConstant: 10),
                menuAttention.heightAnchor.constraint(equalToConstant: 10)
            ])
        }
        panel = TempoPanel(contentRect: NSRect(origin: NSPoint(x: 80, y: 100), size: TempoSurface.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = TempoWindows.avatar
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setFrameAutosaveName("TempoPosition")
        panel.setContentSize(TempoSurface.size)
        sprite = SpriteView(frame: panel.contentView!.bounds)
        sprite.open = { [weak self] in self?.openHost() }
        surface = TempoSurface(artwork: sprite)
        bubbles.artworkFrame = { [weak self] in
            guard let self, let sprite = self.sprite, let panel = self.panel else { return nil }
            return panel.convertToScreen(sprite.convert(sprite.visibleArtworkBounds, to: nil))
        }
        surface.onChat = { [weak self] in self?.showComposer() }
        surface.onActivity = { [weak self] anchor in self?.showActivity(anchor) }
        surface.installContextMenu(makeOptionsMenu())
        panel.onEscape = { [weak self] in
            self?.autoBubblesSuppressed = true; self?.closeBubbles(); self?.surface.dismissControls()
        }
        panel.contentView = surface
        // A wider control strip must remain reachable after restoring an old position.
        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: min(max(panel.frame.minX, visible.minX), visible.maxX - panel.frame.width),
                                         y: min(max(panel.frame.minY, visible.minY), visible.maxY - panel.frame.height)))
        }
        NotificationCenter.default.addObserver(self, selector: #selector(positionBubbles), name: NSWindow.didMoveNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(positionBubbles), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        applyAppearance(); rebuildMenu()
        refreshNotificationSettings()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake),
            name: NSWorkspace.didWakeNotification, object: nil)
        updater.start()
        connect()
        if registry.services.isEmpty { showSettings() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        for connection in orderedConnections { connection.stop() }
        if journalLock >= 0 { Darwin.close(journalLock) }
    }
    @objc private func wake() { connect() }
    private func persist() throws {
        guard storageReady else { throw NSError(domain: "Companion", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Saved replies could not be loaded. Keep the journal file for recovery; no reply was sent."] ) }
        try journal.save(to: journalURL)
    }
    private func saveRegistry(_ next: ServiceRegistry) throws {
        guard registryReady else { throw CompanionError.uncertain }
        defaults.set(try JSONEncoder().encode(next), forKey: ServiceRegistry.defaultsKey)
        registry = next
    }
    private func serviceTitle(_ state: ServiceConnection) -> String {
        let name = state.registration.displayName
        return registry.services.filter { $0.displayName == name }.count > 1
            ? name + " (" + state.registration.address + ")" : name
    }
    private func connect() {
        guard registryReady, storageReady else { rebuildMenu(); return }
        do { try persist() } catch { status = error.localizedDescription; rebuildMenu(); return }
        for record in registry.services {
            let state = connections[record.id] ?? ServiceConnection(record)
            connections[record.id] = state; state.registration = record
            state.onSnapshot = { [weak self] state, value, client in self?.receive(value, client: client, state: state) }
            state.onChange = { [weak self] in self?.rebuildMenu() }
            start(state)
        }
        rebuildMenu()
    }
    private func start(_ state: ServiceConnection) {
        state.start(clientID: journal.clientID, token: { address in
            try await Task.detached { try Keychain.read(address) }.value
        })
    }
    private func receive(_ value: CompanionSnapshot, client: HostClient, state: ServiceConnection) {
        let value = value.visibleChats { id in
            self.journal.follows(id, endpoint: client.endpoint.url.absoluteString, hostIdentity: value.hostIdentity)
        }
        guard connections[state.registration.id] === state, state.owns(client) else { return }
        if state.registration.hostIdentity == nil {
            var record = state.registration; record.hostIdentity = value.hostIdentity
            var next = registry; next.replace(record)
            do { try saveRegistry(next); state.registration = record }
            catch { state.stop(); state.status = error.localizedDescription; rebuildMenu(); return }
        }
        state.latest = value
        let keys = Set(value.items.map(\.key))
        state.previews = state.previews.filter { keys.contains($0.key) }
        state.previewAttempts.formIntersection(keys)
        let working = Set(value.sessions.filter { $0.isWorking }.map(\.id))
        state.workLabels = state.workLabels.filter { working.contains($0.key) }
        state.status = value.workingCount > 0 ? "\(value.workingCount) working" : "Ready"
        var next = journal
        let alerts = next.observe(value, endpoint: client.endpoint.url.absoluteString,
            enabled: defaults.bool(forKey: "notifications"), pinnedOnly: !defaults.bool(forKey: "notifyAll"))
        do {
            // Persist the seen ledger before any OS side effect.
            if next.seen != journal.seen { try next.save(to: journalURL) }
            journal = next
            for alert in alerts {
                Task {
                    let preview = await responsePreview(alert, client: client, snapshot: value, state: state)
                    guard state.owns(client), state.connected else { return }
                    self.deliver(alert, snapshot: value, endpoint: client.endpoint, preview: preview, serviceName: self.serviceTitle(state))
                }
            }
        } catch { status = "Could not save notification state; notifications paused." }
        rebuildMenu()
        // Only visible running work requests bounded tool labels.
        requestVisibleDetails()
    }
    private func deliver(_ alert: AttentionItem, snapshot: CompanionSnapshot, endpoint: Endpoint, preview: String?, serviceName: String) {
        let content = UNMutableNotificationContent()
        content.title = registry.services.count > 1 ? "Amplifier · " + serviceName : "Amplifier"; content.subtitle = alert.title; content.body = preview ?? alert.summary
        content.categoryIdentifier = alert.allowsReply ? "response" : "attention"
        content.threadIdentifier = endpoint.url.absoluteString + "|" + snapshot.hostIdentity + ":" + alert.sessionId
        content.userInfo = ["endpoint": endpoint.url.absoluteString, "host": snapshot.hostIdentity,
                            "session": alert.sessionId, "replyAllowed": alert.allowsReply]
        let key = try! JSONEncoder().encode([endpoint.url.absoluteString, snapshot.hostIdentity, alert.key])
        let id = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { [weak self] error in
            Task { @MainActor in self?.recordNotificationResult(error) }
        }
    }
    private func recordNotificationResult(_ error: Error?) {
        notificationError = error?.localizedDescription
        refreshNotificationSettings()
    }
    private func refreshNotificationSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                guard let self else { return }
                switch settings.authorizationStatus {
                case .authorized: self.notificationStatus = settings.alertSetting == .enabled
                    ? "Desktop notifications allowed" : "Desktop banners disabled in macOS"
                case .denied: self.notificationStatus = "Desktop notifications blocked in macOS"
                case .notDetermined: self.notificationStatus = "Desktop notification permission not granted yet"
                case .provisional: self.notificationStatus = "Quiet notifications only; enable banners in macOS"
                @unknown default: self.notificationStatus = "Check macOS notification settings"
                }
                let diagnostic: [String: Any] = ["checkedAt": ISO8601DateFormatter().string(from: Date()),
                    "authorization": settings.authorizationStatus.rawValue,
                    "alerts": settings.alertSetting.rawValue,
                    "notificationCenter": settings.notificationCenterSetting.rawValue,
                    "enabledInAmplifier": self.defaults.bool(forKey: "notifications"),
                    "lastDeliveryError": self.notificationError ?? ""]
                let path = self.journalURL.deletingLastPathComponent().appendingPathComponent("notification-status.json")
                if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]) {
                    try? data.write(to: path, options: .atomic)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
                }
                self.rebuildMenu()
            }
        }
    }
    @objc private func testNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Amplifier"
        content.body = "Desktop notifications are working. This is a test; no chat message was sent."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "tempo-test-" + UUID().uuidString,
            content: content, trigger: nil)) { [weak self] error in
                Task { @MainActor in self?.recordNotificationResult(error) }
            }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            defer { completionHandler() }
            let info = response.notification.request.content.userInfo
            guard let endpoint = info["endpoint"] as? String, let hostID = info["host"] as? String,
                  let sessionID = info["session"] as? String else { return }
            if let text = response as? UNTextInputNotificationResponse, info["replyAllowed"] as? Bool == true,
               !text.userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    try persist()
                    var next = journal
                    let (entry, isNew) = next.enqueue(notificationID: response.notification.request.identifier,
                        endpoint: endpoint, hostIdentity: hostID, sessionID: sessionID, text: text.userText)
                    try next.save(to: journalURL) // Commit before publishing the in-memory outbox.
                    journal = next
                    if isNew { deliverNotificationReply(entry) }
                } catch { status = error.localizedDescription; rebuildMenu() }
            } else if response.actionIdentifier != UNNotificationDismissActionIdentifier {
                if let url = try? Endpoint(endpoint).chatURL(sessionID) { WebAppOpener.open(url) }
            }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    private func deliverNotificationReply(_ entry: PendingReply) {
        guard notificationWaits.insert(entry.id).inserted else { return }
        Task { @MainActor in
            defer { notificationWaits.remove(entry.id); rebuildMenu() }
            let deadline = Date().addingTimeInterval(30)
            while !Task.isCancelled {
                let state = orderedConnections.first { $0.registration.address == entry.endpoint }
                let decision = NotificationDelivery.decision(for: entry,
                    endpoint: state?.registration.address, hostIdentity: state?.latest?.hostIdentity,
                    connected: state?.connected == true, paused: state?.registration.paused ?? true, expired: Date() >= deadline)
                switch decision {
                case .send:
                    notificationWaits.remove(entry.id); send(entry); return
                case .keepSaved:
                    status = "Reply saved. Connect to its host, then use Retry."; return
                case .wait:
                    if status != "Connecting to deliver your reply…" {
                        status = "Connecting to deliver your reply…"; rebuildMenu()
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
    }
    private func send(_ entry: PendingReply) {
        guard let state = orderedConnections.first(where: { $0.registration.address == entry.endpoint }),
              state.connected, !state.registration.paused, state.latest?.hostIdentity == entry.hostIdentity,
              let host = state.client, !sends.contains(entry.id), !notificationWaits.contains(entry.id) else { status = "Reply saved. Connect to its host, then use Retry."; rebuildMenu(); return }
        do { try persist() } catch { status = error.localizedDescription; rebuildMenu(); return }
        sends.insert(entry.id); status = "Sending reply…"; rebuildMenu()
        Task {
            do {
                try await host.send(entry)
                journal.mark(entry.id, "accepted"); try persist()
                status = "Reply accepted by the host"
            } catch {
                journal.mark(entry.id, "unconfirmed")
                do { try persist(); status = error.localizedDescription }
                catch { status = "Reply delivery is unconfirmed; its recovery record could not be updated." }
            }
            sends.remove(entry.id); rebuildMenu()
        }
    }
    private func rebuildMenu() {
        guard item != nil else { return }
        updateSettingsServices()
        let menu = NSMenu()
        let attention = online.flatMap { state in
            (state.latest?.items.filter { included($0, state: state) } ?? []).map {
                $0.scoped(to: state.registration.id + ":" + (state.latest?.hostIdentity ?? ""))
            }
        }
        let unread = attention.count
        let work = online.reduce(0) { $0 + ($1.latest?.workingCount ?? 0) }
        let unavailable = orderedConnections.filter { !$0.connected && !$0.registration.paused }.count
        let detail = connected ? "\(unread) updates · \(work) working" + (unavailable > 0 ? " · \(unavailable) unavailable" : "") : "No services connected"
        sprite.update(connected: connected, connecting: connecting, working: work, items: attention, scope: "services")
        menu.addItem(withTitle: detail, action: nil, keyEquivalent: "").isEnabled = false
        let compose = menu.addItem(withTitle: "New message…", action: #selector(newMessage), keyEquivalent: "n")
        compose.target = self; compose.isEnabled = connected
        menu.addItem(withTitle: "Open Amplifier", action: #selector(openHost), keyEquivalent: "o").target = self
        item.button?.title = ""; menuAttention.isHidden = unread == 0; item.button?.toolTip = detail
        let services = menu.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
        let serviceMenu = NSMenu(); serviceMenu.autoenablesItems = false
        for state in orderedConnections {
            let row = serviceMenu.addItem(withTitle: serviceTitle(state) + " · " + state.status, action: #selector(selectService(_:)), keyEquivalent: "")
            row.representedObject = state.registration.id; row.target = self
            row.state = state.registration.id == registry.preferredID ? .on : .off
            row.toolTip = state.registration.address + " · Use as the default for opening Amplifier and new chats"
        }
        serviceMenu.addItem(.separator())
        let manage = serviceMenu.addItem(withTitle: "Manage services…", action: #selector(showServiceSettings), keyEquivalent: ""); manage.target = self
        services.submenu = serviceMenu
        let chats = menu.addItem(withTitle: "Your chats", action: nil, keyEquivalent: "")
        chats.image = TempoControls.statusImage(attention: unread > 0, working: work > 0)
        let list = NSMenu()
        for state in online {
            guard let snapshot = state.latest else { continue }
            let attentionChats = Set(snapshot.items.filter { included($0, state: state) }.map(\.sessionId))
            let destination: NSMenu
            if registry.services.count > 1 {
                let group = list.addItem(withTitle: serviceTitle(state), action: nil, keyEquivalent: "")
                destination = NSMenu(); group.submenu = destination
            } else { destination = list }
            for chat in snapshot.sessions.prefix(8) {
                let row = destination.addItem(withTitle: String(chat.title.prefix(55)), action: #selector(openChat(_:)), keyEquivalent: "")
                row.image = TempoControls.statusImage(attention: attentionChats.contains(chat.id), working: chat.isWorking)
                row.representedObject = ServiceTarget(service: state.registration, hostIdentity: snapshot.hostIdentity, sessionID: chat.id)
                row.toolTip = serviceTitle(state) + " · " + chat.title; row.target = self
            }
        }
        chats.submenu = list
        let pending = journal.replies.filter { $0.status != "accepted" }
        if !pending.isEmpty {
            let saved = menu.addItem(withTitle: "Saved messages (\(pending.count))", action: nil, keyEquivalent: "")
            let list = NSMenu()
            list.addItem(withTitle: "Check the chat before retrying", action: nil, keyEquivalent: "").isEnabled = false
            for entry in pending.prefix(10) {
                let row = list.addItem(withTitle: (registry.services.count > 1 ? (registry.service(address: entry.endpoint)?.displayName ?? entry.endpoint) + " · " : "") + String(entry.text.prefix(40)), action: nil, keyEquivalent: "")
                let actions = NSMenu(); actions.autoenablesItems = false
                let review = actions.addItem(withTitle: "Review saved message…", action: #selector(reviewReply(_:)), keyEquivalent: "")
                review.representedObject = entry.id; review.target = self
                let view = actions.addItem(withTitle: "Open chat", action: #selector(openReplyChat(_:)), keyEquivalent: "")
                view.representedObject = entry.id; view.target = self
                let retry = actions.addItem(withTitle: "Retry message", action: #selector(retry(_:)), keyEquivalent: "")
                retry.representedObject = entry.id; retry.target = self; retry.isEnabled = !sends.contains(entry.id) && !notificationWaits.contains(entry.id) && online.contains { $0.registration.address == entry.endpoint && $0.latest?.hostIdentity == entry.hostIdentity }
                row.submenu = actions
            }
            saved.submenu = list
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: panel.isVisible ? "Hide Tempo" : "Show Tempo", action: #selector(toggleTempo), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        updater.addItems(to: menu)
        if defaults.bool(forKey: "showAdvanced") {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Advanced", action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(withTitle: defaults.bool(forKey: "notifications") ? notificationStatus : "Desktop notifications off",
                         action: nil, keyEquivalent: "").isEnabled = false
            if let notificationError { menu.addItem(withTitle: notificationError, action: nil, keyEquivalent: "").isEnabled = false }
            let test = menu.addItem(withTitle: "Send test notification", action: #selector(testNotification), keyEquivalent: "")
            test.target = self; test.isEnabled = defaults.bool(forKey: "notifications")
            menu.addItem(withTitle: "Reconnect", action: #selector(wake), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Browser profile…", action: #selector(chooseBrowserProfile), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Amplifier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu; sprite.setAccessibilityLabel("Amplifier: " + detail)
        surface.updateStatus(connected: connected, working: work, unread: unread,
                             error: attention.contains { $0.isError },
                             detail: detail)
        surface.setActivityAvailable(connected && (unread > 0 || (defaults.bool(forKey: "workBubbles") && work > 0)))
        refreshBubbles()
        surface.setBubblesVisible(bubblesOpen)
    }
    private func makeOptionsMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil); settings.target = self
        let hide = menu.addItem(withTitle: "Hide Tempo", action: #selector(toggleTempo), keyEquivalent: "")
        hide.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil); hide.target = self
        return menu
    }
    private func included(_ item: AttentionItem, state: ServiceConnection) -> Bool {
        defaults.bool(forKey: "notifyAll") || item.pinned || journal.follows(item.sessionId,
            endpoint: state.registration.address, hostIdentity: state.latest?.hostIdentity ?? "")
    }
    private func showComposer() {
        guard connected else { showServiceSettings(); return }
        var choices: [(String, String)] = []
        let states = online.sorted { ($0.registration.id == registry.preferredID ? 0 : 1) < ($1.registration.id == registry.preferredID ? 0 : 1) }
        for state in states {
            guard let snapshot = state.latest else { continue }
            let prefix = registry.services.count > 1 ? serviceTitle(state) + " · " : ""
            let new = ServiceTarget(service: state.registration, hostIdentity: snapshot.hostIdentity, sessionID: nil)
            composerTargets[new.key] = new; choices.append((new.key, prefix + "New chat"))
            for chat in snapshot.sessions.prefix(30) {
                let target = ServiceTarget(service: state.registration, hostIdentity: snapshot.hostIdentity, sessionID: chat.id)
                composerTargets[target.key] = target; choices.append((target.key, prefix + chat.title))
            }
        }
        if let composer {
            composer.updateChoices(choices); composer.present(); surface.setComposing(true); return
        }
        let compose = TempoComposer(chats: choices, anchor: panel.frame, includesDefaultNewChat: false)
        compose.titleForTarget = { [weak self] key in
            guard let self, let target = self.composerTargets[key], let state = self.connections[target.serviceID] else { return nil }
            return self.serviceTitle(state) + " · This chat"
        }
        compose.onSend = { [weak self] key, text in
            guard let self, let key, let target = self.composerTargets[key],
                  let state = self.connections[target.serviceID], state.connected,
                  target.matches(service: state.registration, hostIdentity: state.latest?.hostIdentity),
                  let client = state.client else { throw ComposerError.unavailable("This service is unavailable or changed. Your draft is kept; reconnect or choose a destination.") }
            var next = self.journal
            let entry = next.compose(endpoint: target.address, hostIdentity: target.hostIdentity, sessionID: target.sessionID, text: text)
            do {
                guard self.storageReady else { throw CompanionError.uncertain }
                try next.save(to: self.journalURL); self.journal = next
            } catch { throw ComposerError.unavailable("Could not save this message. Your draft is kept; nothing was sent.") }
            self.sends.insert(entry.id); self.rebuildMenu()
            defer { self.sends.remove(entry.id); self.rebuildMenu() }
            do {
                try await client.send(entry)
                self.journal.mark(entry.id, "accepted"); try self.persist()
                let follow = ServiceTarget(service: state.registration, hostIdentity: target.hostIdentity, sessionID: entry.sessionID)
                self.composerTargets[follow.key] = follow
                return follow.key
            } catch {
                self.journal.mark(entry.id, "unconfirmed"); try? self.persist(); throw CompanionError.uncertain
            }
        }
        compose.onClose = { [weak self, weak compose] in
            self?.surface.setComposing(false)
            if compose?.canDiscardOnClose == true { self?.composer = nil; self?.composerTargets = [:] }
        }
        compose.onResize = { [weak self] in self?.positionBubbles() }
        composer = compose; surface.setComposing(true); compose.present(); positionBubbles()
    }
    private func responsePreview(_ alert: AttentionItem, client: HostClient, snapshot: CompanionSnapshot, state: ServiceConnection) async -> String? {
        guard alert.allowsReply else { return nil }
        if let cached = state.previews[alert.key] { return cached }
        guard state.previewAttempts.insert(alert.key).inserted else { return nil }
        guard let text = try? await client.responsePreview(sessionID: alert.sessionId),
              let check = try? await client.snapshot(), check.hostIdentity == snapshot.hostIdentity,
              check.items.contains(where: { $0.key == alert.key }), state.owns(client), state.connected else { return nil }
        // Do not mix an older completion with text from a new in-progress turn.
        guard !check.sessions.contains(where: { $0.id == alert.sessionId && $0.isWorking }) else { return nil }
        state.previews[alert.key] = text
        refreshBubbles()
        return text
    }
    @objc private func newMessage() { showComposer() }
    @objc private func positionBubbles() {
        guard !positioning, let panel, let screen = panel.screen ?? NSScreen.main else { return }
        positioning = true
        defer { positioning = false }
        let height = composer?.window?.isVisible == true ? composer!.window!.frame.height : 0
        let frame = TempoPlacement.avatar(panel.frame, visible: screen.visibleFrame, composerHeight: height)
        if frame.origin != panel.frame.origin { panel.setFrameOrigin(frame.origin) }
        if bubblesOpen { bubbles.position(panel) }
        composer?.position(panel.frame)
    }
    private func closeBubbles() {
        bubbles.close(); bubblesOpen = false; bubblesManual = false
        surface?.setBubblesVisible(false); surface?.setPresenting(false)
    }
    private func showActivity(_ anchor: NSView) {
        if bubblesOpen { autoBubblesSuppressed = true; closeBubbles(); return }
        guard connected else { showSettings(); return }
        bubblesManual = true; bubblesOpen = true; refreshBubbles(); requestVisibleDetails()
    }
    /// Keep ongoing work visible without adding it to the attention count.
    private func activityRows() -> [TempoBubbles.Row] {
        var all: [TempoBubbles.Row] = []; bubbleTargets = [:]
        var saved = defaults.dictionary(forKey: "dismissedTempoNotices") as? [String: String] ?? [:]
        let original = saved
        for state in online {
            guard let latest = state.latest else { continue }
            let prefix = state.registration.address + "|" + latest.hostIdentity + "|"
            let label = registry.services.count > 1 ? serviceTitle(state) + " · " : ""
            func route(_ id: String) -> String {
                let target = ServiceTarget(service: state.registration, hostIdentity: latest.hostIdentity, sessionID: id)
                bubbleTargets[target.key] = target; return target.key
            }
            let items = latest.items.filter { included($0, state: state) }
            var rows = items.map { item in
                let session = latest.sessions.first { $0.id == item.sessionId }
                let status = NoticeStatus.attention(kind: item.kind, working: session?.isWorking == true)
                let detail = status == .working ? "Unread · " + (state.workLabels[item.sessionId]?.text ?? WorkPreview.fallback(status: session?.status ?? "working")) : state.previews[item.key] ?? item.summary
                return TempoBubbles.Row(key: prefix + item.key, title: item.title, detail: label + detail, sessionID: route(item.sessionId), status: status, dismissalState: item.key)
            }
            let noticed = Set(items.map(\.sessionId))
            if defaults.bool(forKey: "workBubbles") {
                rows += latest.sessions.filter { $0.isWorking && !noticed.contains($0.id) }.map {
                    TempoBubbles.Row(key: prefix + "work:" + $0.id, title: $0.title,
                        detail: label + (state.workLabels[$0.id]?.text ?? WorkPreview.fallback(status: $0.status)),
                        sessionID: route($0.id), status: .working,
                        dismissalState: "work|" + $0.status + "|" + (state.workLabels[$0.id]?.stateID ?? ""))
                }
            }
            let scoped = saved.filter { $0.key.hasPrefix(prefix) }
            let kept = NoticeDismissal.reconcile(scoped, current: Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.dismissalState) }))
            saved = saved.filter { !$0.key.hasPrefix(prefix) }; saved.merge(kept) { _, new in new }
            all += rows.filter { kept[$0.key] == nil }
        }
        // Offline services retain their dismissal records until they can reconcile.
        if saved != original { defaults.set(saved, forKey: "dismissedTempoNotices") }
        return all
    }
    private func refreshBubbles() {
        guard connected, panel.isVisible else { closeBubbles(); return }
        let work = online.reduce(0) { $0 + ($1.latest?.workingCount ?? 0) }
        if work == 0 { autoBubblesSuppressed = false }
        if defaults.bool(forKey: "workBubbles") && work > 0 && !autoBubblesSuppressed { bubblesOpen = true }
        guard bubblesOpen else { return }
        let rows = activityRows()
        if rows.isEmpty { closeBubbles(); return }
        bubbles.openChat = { [weak self] key in
            guard let self, let target = self.bubbleTargets[key] else { return }
            self.open(target)
        }
        bubbles.dismiss = { [weak self] row in
            guard let self, self.bubbleTargets[row.sessionID] != nil else { return }
            var saved = self.defaults.dictionary(forKey: "dismissedTempoNotices") as? [String: String] ?? [:]
            saved[row.key] = row.dismissalState
            self.defaults.set(saved, forKey: "dismissedTempoNotices"); self.refreshBubbles()
        }
        let count = online.reduce(0) { count, state in count + (state.latest?.items.filter { included($0, state: state) }.count ?? 0) }
        bubbles.update(rows, anchor: panel, keepExisting: bubblesManual, attentionCount: count)
        surface.setBubblesVisible(true)
    }
    private func requestVisibleDetails() {
        guard panel.isVisible, !online.isEmpty else { return }
        // Rotate the starting service; one host cannot monopolize the five work reads.
        let states = online, start = nextDetailService % online.count
        nextDetailService = (start + 1) % states.count
        for offset in states.indices {
            let state = states[(start + offset) % states.count]
            guard let latest = state.latest, let client = state.client else { continue }
            for alert in latest.items.filter({ bubblesOpen && included($0, state: state) && $0.allowsReply }).prefix(10)
                where state.previews[alert.key] == nil && !state.previewAttempts.contains(alert.key) {
                if orderedConnections.reduce(0, { $0 + $1.detailRequests.filter { $0.hasPrefix("response:") }.count }) >= 10 { break }
                let key = "response:" + alert.key
                guard state.detailRequests.insert(key).inserted else { continue }
                Task {
                    _ = await responsePreview(alert, client: client, snapshot: latest, state: state)
                    if state.owns(client) { state.detailRequests.remove(key) }
                }
            }
            guard defaults.bool(forKey: "workBubbles") else { continue }
            let working = latest.sessions.filter { $0.isWorking }
            guard !working.isEmpty else { continue }
            let start = state.nextWorkDetail % working.count
            state.nextWorkDetail = (start + min(5, working.count)) % working.count
            for offset in 0..<min(5, working.count) {
                if orderedConnections.reduce(0, { $0 + $1.detailRequests.filter { $0.hasPrefix("work:") }.count }) >= 5 { break }
                let chat = working[(start + offset) % working.count], key = "work:" + working[(start + offset) % working.count].id
                guard state.detailRequests.insert(key).inserted else { continue }
                Task {
                    defer { if state.owns(client) { state.detailRequests.remove(key) } }
                    do {
                        let text = try await client.workPreview(sessionID: chat.id)
                        guard state.owns(client), state.connected,
                              state.latest?.sessions.contains(where: { $0.id == chat.id && $0.isWorking }) == true else { return }
                        state.workLabels[chat.id] = text; refreshBubbles()
                    } catch { }
                }
            }
        }
    }
    @objc private func reviewReply(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let entry = journal.replies.first(where: { $0.id == id }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Saved message"
        alert.informativeText = "Host: \(entry.endpoint)\nSaved: \(entry.createdAt.formatted())\nDelivery: \(entry.status == "saved" ? "Not confirmed" : entry.status.capitalized). Check the chat before retrying."
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.string = entry.text; text.isEditable = false; text.isSelectable = true
        text.font = .systemFont(ofSize: 13); text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true; text.setAccessibilityLabel("Saved message text")
        scroll.documentView = text; alert.accessoryView = scroll
        alert.addButton(withTitle: "Done"); alert.addButton(withTitle: "Open chat")
        if alert.runModal() == .alertSecondButtonReturn { openReplyChat(sender) }
    }
    private func requireIdle(_ address: String) throws {
        guard !journal.replies.contains(where: { $0.endpoint == address && (sends.contains($0.id) || notificationWaits.contains($0.id)) }) else {
            throw NSError(domain: "Tempo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Wait for this service's current message delivery to finish."])
        }
    }
    private func changeConnection(_ action: ConnectionAction, id: String) throws {
        guard registryReady, let state = connections[id] else { return }
        let address = state.registration.address; try requireIdle(address)
        if action == .resume, try Keychain.read(address)?.isEmpty != false { throw CompanionError.rejected(401) }
        var next = registry
        if action == .forget {
            try Keychain.remove(for: address); next.remove(id)
        } else {
            var record = state.registration; record.paused = action == .pause; next.replace(record)
        }
        try saveRegistry(next)
        if action == .forget { state.stop(); connections.removeValue(forKey: id) }
        else { state.registration = registry.services.first { $0.id == id }!; start(state) }
        rebuildMenu()
    }
    @objc private func selectService(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, registry.services.contains(where: { $0.id == id }) else { return }
        do { var next = registry; next.preferredID = id; try saveRegistry(next); rebuildMenu() }
        catch { status = error.localizedDescription; rebuildMenu() }
    }
    private func open(_ target: ServiceTarget) {
        guard let state = connections[target.serviceID], state.connected,
              target.matches(service: state.registration, hostIdentity: state.latest?.hostIdentity) else { return }
        WebAppOpener.open(target.url)
    }
    @objc private func retry(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let entry = journal.replies.first(where: { $0.id == id }) else { return }
        send(entry)
    }
    @objc private func openReplyChat(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let entry = journal.replies.first(where: { $0.id == id }),
              let url = try? Endpoint(entry.endpoint).chatURL(entry.sessionID) else { return }
        WebAppOpener.open(url)
    }
    @objc private func openChat(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? ServiceTarget else { return }
        open(target)
    }
    @objc private func openHost() {
        if let selected { WebAppOpener.open(selected.registration.endpoint.url, focusExisting: true) }
        else { showServiceSettings() }
    }
    @objc private func chooseBrowserProfile() {
        if let selected { WebAppOpener.chooseProfile(for: selected.registration.endpoint.url) }
    }
    @objc private func toggleTempo() {
        composer?.close(); closeBubbles()
        defaults.set(panel.isVisible, forKey: "hideTempo"); applyAppearance(); rebuildMenu()
    }
    private func applyAppearance() {
        let shape = AvatarCatalog.canonical(defaults.string(forKey: "shape") ?? "relay")
        defaults.set(shape, forKey: "shape")
        sprite.load(shape, palette: defaults.string(forKey: "palette") ?? "blue", finish: defaults.string(forKey: "finish") ?? "clear")
        let visible = !defaults.bool(forKey: "hideTempo")
        if visible { panel.orderFrontRegardless() } else {
            panel.orderOut(nil); composer?.window?.orderOut(nil); surface.setComposing(false)
        }
        surface.handle.setTheme(defaults.string(forKey: "shape") ?? "relay", palette: defaults.string(forKey: "palette") ?? "blue")
        surface.handle.animationsEnabled = visible
        sprite.animate(visible)
        if bubblesOpen { bubbles.position(panel) }
    }
    private func preferenceChanged(_ key: String) {
        if key == "shape" || key == "palette" || key == "finish" { applyAppearance() }
        if key == "notifications", defaults.bool(forKey: key) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshNotificationSettings() }
            }
        }
        if key == "workBubbles" {
            autoBubblesSuppressed = false
            if !defaults.bool(forKey: key) && !bubblesManual { closeBubbles() }
        }
        rebuildMenu(); requestVisibleDetails()
    }
    private func updateSettingsServices() {
        settings?.updateServices(registry.services, preferredID: registry.preferredID,
            statuses: Dictionary(uniqueKeysWithValues: orderedConnections.map { ($0.registration.id, $0.status) }),
            catalogError: registryReady ? nil : "Saved services could not be read. Existing credentials and replies are kept. Keep your settings for recovery before trying again.")
    }
    @objc private func showServiceSettings() { showSettings(); settings?.showConnection() }
    @objc private func showSettings() {
        if settings == nil {
            settings = SettingsWindow(defaults: defaults, recoveryPath: storageReady ? nil : journalURL.path,
                artwork: { name, palette, finish in
                    guard let url = Bundle.module.url(forResource: AvatarAppearance.resourceName(name, finish: finish), withExtension: "png", subdirectory: "Resources"),
                          let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
                    return AvatarAppearance.thumbnail(source, palette: palette, shape: name)
                }, preferenceChanged: { [weak self] key in self?.preferenceChanged(key) },
                connectionAction: { [weak self] action, id in try self?.changeConnection(action, id: id) },
                selectService: { [weak self] id in
                    guard let self, self.registry.services.contains(where: { $0.id == id }) else { return }
                    var next = self.registry; next.preferredID = id
                    try self.saveRegistry(next); self.rebuildMenu()
                },
                renameService: { [weak self] id, name in
                    guard let self, let state = self.connections[id] else { return }
                    var record = state.registration; record.name = NoticeText.plain(name, limit: 60)
                    var next = self.registry; next.replace(record); try self.saveRegistry(next)
                    state.registration = record; self.rebuildMenu()
                },
                manageDevices: { address in
                    let endpoint = try Endpoint(address)
                    NSWorkspace.shared.open(endpoint.route("devices"))
                }, pair: { address, showCode in
                    let endpoint = try Endpoint(address)
                    var random = [UInt8](repeating: 0, count: 32)
                    guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw PairingError.unavailable }
                    func encoded(_ data: Data) -> String {
                        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                    }
                    let verifier = encoded(Data(random))
                    let challenge = encoded(Data(SHA256.hash(data: Data(verifier.utf8))))
                    let client = PairingClient(endpoint: endpoint)
                    let request = try await client.begin(name: "Amplifier on " + String((Host.current().localizedName ?? "this Mac").prefix(60)), challenge: challenge)
                    try Task.checkCancellation()
                    showCode(request.code)
                    guard NSWorkspace.shared.open(try request.browserURL(endpoint: endpoint)) else { throw PairingError.unavailable }
                    let deadline = Date().addingTimeInterval(TimeInterval(request.expiresIn))
                    while Date() < deadline {
                        try await Task.sleep(nanoseconds: UInt64(request.interval) * 1_000_000_000)
                        if let token = try await client.poll(id: request.id, verifier: verifier) { return token }
                    }
                    throw PairingError.expired
                }, connect: { [weak self] address, token, name in
                    guard let self, self.registryReady, self.storageReady else { throw CompanionError.uncertain }
                    let endpoint = try Endpoint(address)
                    let saved = self.registry.service(address: endpoint.url.absoluteString)
                    let account = saved?.address ?? endpoint.url.absoluteString
                    try self.requireIdle(account)
                    var next = self.registry
                    let record = try next.register(address: account, name: name, reapproved: !token.isEmpty)
                    if !token.isEmpty { try Keychain.save(token, for: account) }
                    guard try Keychain.read(account)?.isEmpty == false else { throw CompanionError.rejected(401) }
                    try self.saveRegistry(next)
                    let state = self.connections[record.id] ?? ServiceConnection(record)
                    self.connections[record.id] = state; state.registration = record
                    state.onSnapshot = { [weak self] state, value, client in self?.receive(value, client: client, state: state) }
                    state.onChange = { [weak self] in self?.rebuildMenu() }
                    self.start(state); self.rebuildMenu()
                })
        }
        updateSettingsServices()
        if !connected { settings?.showConnection() }
        settings?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }

}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    withExtendedLifetime(controller) { app.run() }
}
#else
print("Amplifier for Mac requires macOS 13 or later.")
#endif
