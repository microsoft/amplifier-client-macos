#if os(macOS)
import AppKit

@MainActor final class MessageEditor: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            ("Ask Amplifier anything…" as NSString).draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height),
                withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.secondaryLabelColor])
        }
    }
}

@MainActor final class TempoComposer: NSWindowController, NSTextViewDelegate {
    let target = NSPopUpButton()
    let editor = MessageEditor()
    let sendButton = FirstClickButton(title: "Send", target: nil, action: nil)
    private let closeButton = FirstClickButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    private let material = TempoMaterial(radius: 24)
    private var ids: [String?] = [nil]
    private var sending = false
    private var recovery = false
    private var anchor: NSRect
    var onSend: ((String?, String) async throws -> String)?
    var onResize: (() -> Void)?
    var onClose: (() -> Void)?
    init(chats: [(String, String)], anchor: NSRect) {
        self.anchor = anchor
        let window = ComposerPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 88),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Chat with Amplifier"; window.level = TempoWindows.input; window.isReleasedWhenClosed = false
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.hidesOnDeactivate = false; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)
        window.onDismiss = { [weak self] in self?.close() }
        window.contentView = material
        target.addItem(withTitle: "New chat")
        for (id, title) in chats { ids.append(id); target.addItem(withTitle: title) }
        target.bezelStyle = .recessed; target.isBordered = false; target.font = .systemFont(ofSize: 12)
        target.toolTip = "Active and pinned chats, plus chats you use in Tempo"; target.setAccessibilityLabel("Chat")
        material.content.addSubview(target)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        editor.isRichText = false; editor.drawsBackground = false; editor.font = .systemFont(ofSize: 15)
        editor.textContainerInset = NSSize(width: 0, height: 4)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = .width; editor.textContainer?.widthTracksTextView = true
        editor.delegate = self; editor.setAccessibilityLabel("Message")
        scroll.documentView = editor; material.content.addSubview(scroll)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; material.content.addSubview(status)
        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send message")
        sendButton.imagePosition = .imageOnly; sendButton.imageScaling = .scaleProportionallyUpOrDown
        sendButton.isBordered = false; sendButton.contentTintColor = .controlAccentColor
        sendButton.target = self; sendButton.action = #selector(submit)
        sendButton.keyEquivalent = "\r"; sendButton.keyEquivalentModifierMask = .command
        sendButton.toolTip = "Send (Return). Shift-Return adds a line."; sendButton.setAccessibilityLabel("Send message")
        sendButton.isEnabled = false; material.content.addSubview(sendButton)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close composer")
        closeButton.isBordered = false; closeButton.target = self; closeButton.action = #selector(dismiss)
        closeButton.setAccessibilityLabel("Close composer"); material.content.addSubview(closeButton)
        layout(height: 88)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func layout(height: CGFloat) {
        window?.setContentSize(NSSize(width: 360, height: height))
        target.frame = NSRect(x: 14, y: 12, width: 278, height: 26)
        sendButton.frame = NSRect(x: 310, y: 10, width: 36, height: 36)
        let hasStatus = !status.stringValue.isEmpty
        status.isHidden = !hasStatus; status.frame = NSRect(x: 18, y: 44, width: 314, height: 30)
        let bottom: CGFloat = hasStatus ? 80 : 48
        scroll.frame = NSRect(x: 14, y: bottom, width: 312, height: height - bottom - 14)
        editor.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.frame.size = NSSize(width: scroll.contentSize.width, height: max(editor.frame.height, scroll.contentSize.height))
        closeButton.frame = NSRect(x: 332, y: height - 28, width: 16, height: 16)
        position(anchor)
        onResize?()
    }
    func position(_ anchor: NSRect) {
        self.anchor = anchor
        guard let window, let visible = (NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame else { return }
        window.setFrameOrigin(TempoPlacement.composer(anchor: anchor, size: window.frame.size, visible: visible).origin)
    }
    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(editor) }
    override func close() { super.close(); onClose?() }
    @objc private func dismiss() { close() }
    func textDidChange(_ notification: Notification) {
        sendButton.isEnabled = !sending && !recovery && !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        editor.needsDisplay = true
        if let layoutManager = editor.layoutManager, let container = editor.textContainer {
            layoutManager.ensureLayout(for: container)
            let height = max(88, min(240, layoutManager.usedRect(for: container).height + (status.stringValue.isEmpty ? 70 : 102)))
            layout(height: height)
        }
    }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText(),
           NSApp.currentEvent?.modifierFlags.contains(.shift) != true {
            submit(); return true
        }
        return false
    }
    @objc private func submit() {
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sending, !recovery, !text.isEmpty, let onSend else { return }
        let selected = ids[target.indexOfSelectedItem]
        sending = true; sendButton.isEnabled = false; target.isEnabled = false; editor.isEditable = false
        status.stringValue = "Sending…"; textDidChange(Notification(name: NSText.didChangeNotification))
        Task {
            do {
                let id = try await onSend(selected, text)
                if let index = ids.firstIndex(where: { $0 == id }) { target.selectItem(at: index) }
                else { ids.append(id); target.addItem(withTitle: "This chat"); target.selectItem(at: ids.count - 1) }
                editor.string = ""; status.stringValue = "Sent · replies will appear in Tempo."
                target.isEnabled = true; editor.isEditable = true
            } catch {
                recovery = true; status.stringValue = "Delivery unconfirmed. Check Saved messages in the Tempo menu."
                status.toolTip = error.localizedDescription
            }
            sending = false; textDidChange(Notification(name: NSText.didChangeNotification))
        }
    }
}
#endif
