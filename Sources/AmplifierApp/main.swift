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
    private var host: HostClient?
    private var poll: Task<Void, Never>?
    private var sends = Set<String>()
    private var notificationWaits = Set<String>()
    private var latest: CompanionSnapshot?
    private var status = "Not connected"
    private var connected = false
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
    private var previews: [String: String] = [:]
    private var workLabels: [String: String] = [:]
    private var detailRequests = Set<String>()
    private var previewAttempts = Set<String>()

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
        if defaults.string(forKey: "endpoint") == nil { showSettings() }
        else { connect() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        poll?.cancel()
        if journalLock >= 0 { Darwin.close(journalLock) }
    }
    @objc private func wake() { connect() }
    private func persist() throws {
        guard storageReady else { throw NSError(domain: "Companion", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Saved replies could not be loaded. Keep the journal file for recovery; no reply was sent."] ) }
        try journal.save(to: journalURL)
    }
    private func connect() {
        poll?.cancel(); closeBubbles(); composer?.close(); composer = nil
        previews = [:]; workLabels = [:]; detailRequests = []; previewAttempts = []
        connected = false; latest = nil; host = nil
        guard !defaults.bool(forKey: "connectionPaused") else {
            status = "Disconnected. Saved messages are kept."; rebuildMenu(); return
        }
        do {
            let endpoint = try Endpoint(defaults.string(forKey: "endpoint") ?? "http://127.0.0.1:8941")
            status = "Connecting…"; rebuildMenu()
            poll = Task { [weak self] in
                let token: String?
                do {
                    token = try await Task.detached { try Keychain.read(endpoint.url.absoluteString) }.value
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    self.status = error.localizedDescription; self.rebuildMenu(); return
                }
                guard !Task.isCancelled, let self else { return }
                guard let token, !token.isEmpty else {
                    self.status = "Connect to your Unified host"; self.rebuildMenu(); self.showSettings(); return
                }
                do { try self.persist() }
                catch { self.status = error.localizedDescription; self.rebuildMenu(); return }
                let client = HostClient(endpoint: endpoint, token: token, clientID: self.journal.clientID)
                self.host = client
                var delay: UInt64 = 2
                while !Task.isCancelled {
                    do {
                        try await client.attach()
                        while !Task.isCancelled {
                            let value = try await client.snapshot()
                            guard !Task.isCancelled else { return }
                            self.receive(value, client: client); delay = 2
                            try await Task.sleep(nanoseconds: 5_000_000_000)
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        self.connected = false; self.status = error.localizedDescription
                        self.rebuildMenu()
                        try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                        delay = min(delay * 2, 60)
                    }
                }
            }
        } catch { status = error.localizedDescription; rebuildMenu() }
    }
    private func receive(_ value: CompanionSnapshot, client: HostClient) {
        let value = value.visibleChats { id in
            self.journal.follows(id, endpoint: client.endpoint.url.absoluteString, hostIdentity: value.hostIdentity)
        }
        latest = value; connected = true
        let keys = Set(value.items.map(\.key))
        previews = previews.filter { keys.contains($0.key) }
        previewAttempts.formIntersection(keys)
        let working = Set(value.sessions.filter { $0.isWorking }.map(\.id))
        workLabels = workLabels.filter { working.contains($0.key) }
        status = value.workingCount > 0 ? "\(value.workingCount) working" : "Ready"
        var next = journal
        let alerts = next.observe(value, endpoint: client.endpoint.url.absoluteString,
            enabled: defaults.bool(forKey: "notifications"), pinnedOnly: !defaults.bool(forKey: "notifyAll"))
        do {
            // Persist the seen ledger before any OS side effect.
            if next.seen != journal.seen { try next.save(to: journalURL) }
            journal = next
            for alert in alerts {
                Task {
                    let preview = await responsePreview(alert, client: client, snapshot: value)
                    guard self.host === client else { return }
                    self.deliver(alert, snapshot: value, endpoint: client.endpoint, preview: preview)
                }
            }
        } catch { status = "Could not save notification state; notifications paused." }
        rebuildMenu()
        // Only visible running work requests bounded tool labels.
        requestVisibleDetails()
    }
    private func deliver(_ alert: AttentionItem, snapshot: CompanionSnapshot, endpoint: Endpoint, preview: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Amplifier"; content.subtitle = alert.title; content.body = preview ?? alert.summary
        content.categoryIdentifier = alert.allowsReply ? "response" : "attention"
        content.threadIdentifier = snapshot.hostIdentity + ":" + alert.sessionId
        content.userInfo = ["endpoint": endpoint.url.absoluteString, "host": snapshot.hostIdentity,
                            "session": alert.sessionId, "replyAllowed": alert.allowsReply]
        let key = endpoint.url.absoluteString + snapshot.hostIdentity + alert.key
        let id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
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
                let decision = NotificationDelivery.decision(for: entry,
                    endpoint: defaults.string(forKey: "endpoint"), hostIdentity: latest?.hostIdentity,
                    connected: connected, paused: defaults.bool(forKey: "connectionPaused"), expired: Date() >= deadline)
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
        guard let host, !sends.contains(entry.id), !notificationWaits.contains(entry.id) else { status = "Reply saved. Connect to its host, then use Retry."; rebuildMenu(); return }
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
        settings?.updateConnection(connected: connected, message: status)
        let menu = NSMenu()
        let unread = connected ? (latest?.items.filter { included($0) }.count ?? 0) : 0
        let work = latest?.workingCount ?? 0
        let summary = !connected ? "Not connected" : (unread > 0 ? "\(unread) updates" + (work > 0 ? " · \(work) working" : "") : "")
        if !summary.isEmpty { menu.addItem(withTitle: summary, action: nil, keyEquivalent: "").isEnabled = false }
        let compose = menu.addItem(withTitle: "New message…", action: #selector(newMessage), keyEquivalent: "n")
        compose.target = self; compose.isEnabled = connected
        menu.addItem(withTitle: "Open Amplifier", action: #selector(openHost), keyEquivalent: "o").target = self
        if let latest {
            item.button?.title = ""
            menuAttention.isHidden = unread == 0
            item.button?.toolTip = "\(unread) updates · \(work) chats working"
            sprite.motion = Motion.status(connected: connected, working: work, attention: latest.items.filter { included($0) && $0.kind != "completion" }.count)
            if !latest.sessions.isEmpty {
                let chats = menu.addItem(withTitle: "Your chats", action: nil, keyEquivalent: "")
                let attentionChats = Set(latest.items.filter { included($0) }.map(\.sessionId))
                chats.image = TempoControls.statusImage(attention: unread > 0, working: work > 0)
                let list = NSMenu()
                for chat in latest.sessions.prefix(8) {
                    let title = String(chat.title.prefix(55))
                    let row = list.addItem(withTitle: title, action: #selector(openChat(_:)), keyEquivalent: "")
                    row.image = TempoControls.statusImage(attention: attentionChats.contains(chat.id), working: chat.isWorking)
                    row.toolTip = attentionChats.contains(chat.id) ? (chat.isWorking ? "Update available · Working" : "Update available") : (chat.isWorking ? "Working" : "No new updates")
                    row.representedObject = chat.id; row.target = self
                }
                chats.submenu = list
            }
        } else { item.button?.title = ""; menuAttention.isHidden = true; sprite.motion = .waiting }
        let pending = journal.replies.filter { $0.status != "accepted" }
        if !pending.isEmpty {
            let saved = menu.addItem(withTitle: "Saved messages (\(pending.count))", action: nil, keyEquivalent: "")
            let list = NSMenu()
            list.addItem(withTitle: "Check the chat before retrying", action: nil, keyEquivalent: "").isEnabled = false
            for entry in pending.prefix(10) {
                let row = list.addItem(withTitle: String(entry.text.prefix(40)), action: nil, keyEquivalent: "")
                let actions = NSMenu(); actions.autoenablesItems = false
                let review = actions.addItem(withTitle: "Review saved message…", action: #selector(reviewReply(_:)), keyEquivalent: "")
                review.representedObject = entry.id; review.target = self
                let view = actions.addItem(withTitle: "Open chat", action: #selector(openReplyChat(_:)), keyEquivalent: "")
                view.representedObject = entry.id; view.target = self
                let retry = actions.addItem(withTitle: "Retry message", action: #selector(retry(_:)), keyEquivalent: "")
                retry.representedObject = entry.id; retry.target = self; retry.isEnabled = !sends.contains(entry.id) && !notificationWaits.contains(entry.id) && connected && entry.endpoint == host?.endpoint.url.absoluteString && entry.hostIdentity == latest?.hostIdentity
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
        item.menu = menu; sprite.setAccessibilityLabel("Amplifier: " + status)
        surface.updateStatus(connected: connected, working: work, unread: unread,
                             error: latest?.items.contains { included($0) && $0.isError } ?? false,
                             detail: connected ? status : "Not connected")
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
    private func included(_ item: AttentionItem) -> Bool {
        defaults.bool(forKey: "notifyAll") || item.pinned || journal.follows(item.sessionId,
            endpoint: host?.endpoint.url.absoluteString ?? "", hostIdentity: latest?.hostIdentity ?? "")
    }
    private func showComposer() {
        guard connected, let client = host, let snapshot = latest else { showSettings(); return }
        if let composer {
            surface.setComposing(true); composer.present(); positionBubbles(); return
        }
        var chats = snapshot.sessions.map { ($0.id, $0.title) }
        for reply in journal.replies.reversed() where reply.endpoint == client.endpoint.url.absoluteString && reply.hostIdentity == snapshot.hostIdentity {
            if !chats.contains(where: { $0.0 == reply.sessionID }) { chats.append((reply.sessionID, "New chat · " + String(reply.text.prefix(35)))) }
            if chats.count >= 30 { break }
        }
        let compose = TempoComposer(chats: Array(chats.prefix(30)), anchor: panel.frame)
        compose.onSend = { [weak self] target, text in
            guard let self, self.host === client, self.latest?.hostIdentity == snapshot.hostIdentity else { throw CompanionError.changedHost }
            try self.persist()
            var next = self.journal
            let entry = next.compose(endpoint: client.endpoint.url.absoluteString, hostIdentity: snapshot.hostIdentity, sessionID: target, text: text)
            try next.save(to: self.journalURL); self.journal = next
            self.sends.insert(entry.id); self.rebuildMenu()
            defer { self.sends.remove(entry.id); self.rebuildMenu() }
            do {
                try await client.send(entry)
                self.journal.mark(entry.id, "accepted"); try self.persist()
                self.status = "Message sent"
                return entry.sessionID
            } catch {
                self.journal.mark(entry.id, "unconfirmed"); try? self.persist()
                throw CompanionError.uncertain
            }
        }
        compose.onClose = { [weak self] in self?.surface.setComposing(false) }
        compose.onResize = { [weak self] in self?.positionBubbles() }
        composer = compose
        surface.setComposing(true)

        compose.present(); positionBubbles()
    }
    private func responsePreview(_ alert: AttentionItem, client: HostClient, snapshot: CompanionSnapshot) async -> String? {
        guard alert.allowsReply else { return nil }
        if let cached = previews[alert.key] { return cached }
        guard previewAttempts.insert(alert.key).inserted else { return nil }
        guard let text = try? await client.responsePreview(sessionID: alert.sessionId),
              let check = try? await client.snapshot(), check.hostIdentity == snapshot.hostIdentity,
              check.items.contains(where: { $0.key == alert.key }), self.host === client else { return nil }
        // Do not mix an older completion with text from a new in-progress turn.
        guard !check.sessions.contains(where: { $0.id == alert.sessionId && $0.isWorking }) else { return nil }
        previews[alert.key] = text
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
        guard connected, let latest else { return [] }
        var rows = latest.items.filter { included($0) }.map {
            TempoBubbles.Row(key: $0.key, title: $0.title, detail: previews[$0.key] ?? $0.summary, sessionID: $0.sessionId)
        }
        let noticed = Set(rows.map(\.sessionID))
        if defaults.bool(forKey: "workBubbles") {
            rows += latest.sessions.filter { $0.isWorking && !noticed.contains($0.id) }.map {
                TempoBubbles.Row(key: "work:" + $0.id, title: $0.title, detail: workLabels[$0.id] ?? $0.status.capitalized, sessionID: $0.id)
            }
        }
        return rows
    }
    private func refreshBubbles() {
        guard connected, let latest, let client = host, panel.isVisible else { closeBubbles(); return }
        if latest.workingCount == 0 { autoBubblesSuppressed = false }
        let automatic = defaults.bool(forKey: "workBubbles") && latest.workingCount > 0 && !autoBubblesSuppressed
        if automatic { bubblesOpen = true }
        guard bubblesOpen else { return }
        let rows = activityRows()
        if rows.isEmpty { closeBubbles(); return }
        bubbles.openChat = { id in WebAppOpener.open(client.endpoint.chatURL(id)) }
        bubbles.update(rows, anchor: panel, keepExisting: bubblesManual, attentionCount: latest.items.filter { included($0) }.count)
        surface.setBubblesVisible(true)
    }
    private func requestVisibleDetails() {
        guard connected, bubblesOpen, let latest, let client = host else { return }
        for alert in latest.items.filter({ included($0) && $0.allowsReply }).prefix(10) where previews[alert.key] == nil && !previewAttempts.contains(alert.key) {
            let key = "response:" + alert.key
            guard detailRequests.insert(key).inserted else { continue }
            Task {
                _ = await responsePreview(alert, client: client, snapshot: latest)
                if self.host === client { detailRequests.remove(key) }
            }
        }
        guard defaults.bool(forKey: "workBubbles") else { return }
        for chat in latest.sessions.filter({ $0.isWorking }).prefix(5) {
            let key = "work:" + chat.id
            guard detailRequests.insert(key).inserted else { continue }
            Task {
                let text = try? await client.workPreview(sessionID: chat.id)
                guard self.host === client else { return }
                detailRequests.remove(key); workLabels[chat.id] = text
                refreshBubbles()
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
    private func changeConnection(_ action: ConnectionAction) throws {
        guard sends.isEmpty && notificationWaits.isEmpty else {
            throw NSError(domain: "Tempo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Wait for the current message delivery to finish before changing this connection."])
        }
        guard let address = defaults.string(forKey: "endpoint") else { return }
        if action == .resume {
            guard try Keychain.read(address)?.isEmpty == false else {
                throw NSError(domain: "Tempo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Connect in browser to approve this Mac again."])
            }
        } else if action == .forget { try Keychain.remove(for: address) }
        defaults.set(action != .resume, forKey: "connectionPaused")
        connect()
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
        guard let id = sender.representedObject as? String, let url = host?.endpoint.chatURL(id) else { return }
        WebAppOpener.open(url)
    }
    @objc private func openHost() {
        if let endpoint = try? Endpoint(defaults.string(forKey: "endpoint") ?? "http://127.0.0.1:8941") { WebAppOpener.open(endpoint.url, focusExisting: true) }
    }
    @objc private func chooseBrowserProfile() {
        if let endpoint = try? Endpoint(defaults.string(forKey: "endpoint") ?? "http://127.0.0.1:8941") { WebAppOpener.chooseProfile(for: endpoint.url) }
    }
    @objc private func toggleTempo() {
        composer?.close(); closeBubbles()
        defaults.set(panel.isVisible, forKey: "hideTempo"); applyAppearance(); rebuildMenu()
    }
    private func applyAppearance() {
        sprite.load(defaults.string(forKey: "shape") ?? "relay", palette: defaults.string(forKey: "palette") ?? "blue", finish: defaults.string(forKey: "finish") ?? "clear")
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
    @objc private func showSettings() {
        if settings == nil {
            settings = SettingsWindow(defaults: defaults, recoveryPath: storageReady ? nil : journalURL.path,
                artwork: { name, palette, finish in
                    guard let url = Bundle.module.url(forResource: AvatarAppearance.resourceName(name, finish: finish), withExtension: "png", subdirectory: "Resources"),
                          let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
                    return AvatarAppearance.thumbnail(source, palette: palette)
                }, preferenceChanged: { [weak self] key in self?.preferenceChanged(key) },
                connectionAction: { [weak self] action in try self?.changeConnection(action) },
                manageDevices: { address in
                    let endpoint = try Endpoint(address)
                    NSWorkspace.shared.open(endpoint.route("devices"))
                }, browserSetup: { address in
                    let url = try await BrowserSetupClient(endpoint: Endpoint(address)).setupURL()
                    try Task.checkCancellation()
                    guard NSWorkspace.shared.open(url) else { throw BrowserSetupError.unavailable }
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
                }, connect: { [weak self] address, token in
                    guard let self else { return }
                    guard self.sends.isEmpty && self.notificationWaits.isEmpty else {
                        throw NSError(domain: "Tempo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Wait for the current message delivery to finish before changing this connection."])
                    }
                    let endpoint = try Endpoint(address)
                    if !token.isEmpty { try Keychain.save(token, for: endpoint.url.absoluteString) }
                    guard try Keychain.read(endpoint.url.absoluteString)?.isEmpty == false else {
                        throw NSError(domain: "Tempo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Enter an access token for this Amplifier."])
                    }
                    self.defaults.set(endpoint.url.absoluteString, forKey: "endpoint")
                    self.defaults.set(false, forKey: "connectionPaused")
                    self.connect()
                })
        }
        settings?.updateConnection(connected: connected, message: status)
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
