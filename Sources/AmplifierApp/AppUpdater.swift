#if os(macOS)
import AppKit
import Sparkle

/// Sparkle owns verification, staging, installation, rollback and relaunch.
/// A development build without an update channel does not poll a feed.
@MainActor final class AppUpdater: NSObject, NSMenuItemValidation {
    private var controller: SPUStandardUpdaterController?
    private var failure: String?
    func start() {
        guard controller == nil else { return }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URLComponents(string: feed), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: publicKey)?.count == 32 else { return }
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try updater.updater.start()
            controller = updater
        } catch { failure = error.localizedDescription }
    }
    func addItems(to menu: NSMenu) {
        menu.addItem(withTitle: "Check for Updates…", action: #selector(check(_:)), keyEquivalent: "").target = self
        if let controller {
            let automatic = menu.addItem(withTitle: "Automatically Check for Updates", action: #selector(toggleAutomatic(_:)), keyEquivalent: "")
            automatic.target = self
            automatic.state = controller.updater.automaticallyChecksForUpdates ? .on : .off
        }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(check(_:)) { return controller?.updater.canCheckForUpdates ?? true }
        if menuItem.action == #selector(toggleAutomatic(_:)) {
            menuItem.state = controller?.updater.automaticallyChecksForUpdates == true ? .on : .off
            return controller != nil
        }
        return false
    }
    @objc private func toggleAutomatic(_ sender: NSMenuItem) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
    }
    @objc private func check(_ sender: Any?) {
        if let controller { controller.checkForUpdates(sender); return }
        let alert = NSAlert()
        alert.messageText = "Preview updates"
        alert.informativeText = failure ?? "This preview does not have an automatic update channel yet. Official downloads are available on GitHub."
        alert.addButton(withTitle: "Open Downloads"); alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/microsoft/amplifier-client-macos/releases")!)
        }
    }
}
#endif
