#if os(macOS)
import AppKit
import ClientCore

@MainActor enum WebAppOpener {
    private static let profilesKey = "webAppProfiles"

    private static func matchingApp(_ url: URL) -> URL? {
        // Inspect launcher metadata only, never browser profiles or account data.
        // Chrome and Edge publish the launch URL in their app shim Info.plist.
        let roots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                     URL(fileURLWithPath: "/Applications")]
        var matches: [URL] = []
        func scan(_ root: URL, depth: Int) {
            guard depth <= 2, let children = try? FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return }
            for child in children {
                if child.pathExtension == "app" {
                    guard let info = NSDictionary(contentsOf: child.appendingPathComponent("Contents/Info.plist")),
                          let address = info["CrAppModeShortcutURL"] as? String, let launch = URL(string: address),
                          WebAppMatch.matches(launch, target: url) else { continue }
                    matches.append(child)
                } else if let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                          values.isDirectory == true, values.isSymbolicLink != true {
                    scan(child, depth: depth + 1)
                }
            }
        }
        roots.forEach { scan($0, depth: 0) }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleURL))
        matches.sort { running.contains($0) != running.contains($1) ? running.contains($0) : $0.path < $1.path }
        return matches.first
    }

    static func open(_ url: URL, focusExisting: Bool = false) {
        guard let app = matchingApp(url) else { NSWorkspace.shared.open(url); return }
        if focusExisting {
            // A normal app activation also reopens a closed window, without sending
            // a navigation URL or depending on the browser's last-used profile.
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            NSWorkspace.shared.openApplication(at: app, configuration: config) { _, error in
                if error != nil { DispatchQueue.main.async { showLaunchError() } }
            }
            return
        }
        // App shims treat ordinary HTTPS open events as a normal relaunch on some
        // Chromium builds, losing the target. Use Chromium's explicit app launch URL.
        if let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
           let id = info["CrAppModeShortcutID"] as? String,
           let bundleID = info["CFBundleIdentifier"] as? String,
           let browserID = WebAppLaunch.browserID(for: bundleID, appID: id),
           let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserID) {
            let saved = UserDefaults.standard.dictionary(forKey: profilesKey)?[bundleID] as? String
            let profile = WebAppLaunch.profileDirectory(saved) ?? WebAppLaunch.profileDirectory(info["CrAppModeProfileDir"] as? String)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            // Deliver arguments even when the browser is already running. Chromium's
            // singleton hands them to that browser; the PWA's launch handler reuses its window.
            config.createsNewApplicationInstance = true
            config.arguments = WebAppLaunch.arguments(appID: id, target: url, profile: profile)
            NSWorkspace.shared.openApplication(at: browser, configuration: config) { _, error in
                if error != nil { DispatchQueue.main.async { showLaunchError() } }
            }
            return
        }
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config) { _, error in
            if error != nil { DispatchQueue.main.async { showLaunchError() } }
        }
    }

    private static func showLaunchError() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Amplifier could not be opened"
        alert.informativeText = "Try opening Amplifier from Applications. If you use several browser profiles, choose Browser profile from Tempo’s advanced menu."
        alert.runModal()
    }

    static func chooseProfile(for url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        guard let app = matchingApp(url), let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let bundleID = info["CFBundleIdentifier"] as? String,
              let appID = info["CrAppModeShortcutID"] as? String,
              let browserID = WebAppLaunch.browserID(for: bundleID, appID: appID) else {
            let alert = NSAlert(); alert.messageText = "Install Amplifier as a browser app first"
            alert.informativeText = "No installed Edge or Chrome app matches this Amplifier address."; alert.runModal(); return
        }
        let saved = UserDefaults.standard.dictionary(forKey: profilesKey)?[bundleID] as? String ?? ""
        let field = NSTextField(string: saved); field.frame = NSRect(x: 0, y: 0, width: 320, height: 26)
        field.placeholderString = "Automatic"; field.setAccessibilityLabel("Browser profile folder")
        let alert = NSAlert(); alert.messageText = "Amplifier browser profile"
        let page = browserID == "com.microsoft.edgemac" ? "edge://version" : "chrome://version"
        alert.informativeText = "Use the profile where you installed Amplifier. Open \(page) in that profile and enter the last folder in Profile Path (for example, Default or Profile 1). Leave blank for automatic selection. This applies only to this installed Amplifier app."
        alert.accessoryView = field; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty || WebAppLaunch.profileDirectory(value) != nil else {
                alert.informativeText = "Enter just the profile folder, such as Default or Profile 1, without slashes. Leave blank for automatic selection."
                NSSound.beep(); continue
            }
            var profiles = UserDefaults.standard.dictionary(forKey: profilesKey) ?? [:]
            profiles[bundleID] = value.isEmpty ? nil : value
            UserDefaults.standard.set(profiles, forKey: profilesKey); return
        }
    }
}
#endif
