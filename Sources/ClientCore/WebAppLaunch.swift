import Foundation

public enum WebAppLaunch {
    // A profile is a browser-owned directory name, never a path or account name.
    public static func profileDirectory(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.range(of: "^[A-Za-z0-9][A-Za-z0-9 _.-]{0,99}$", options: .regularExpression) != nil else { return nil }
        return value
    }

    public static func browserID(for bundleID: String, appID: String) -> String? {
        guard appID.range(of: "^[a-p]{32}$", options: .regularExpression) != nil else { return nil }
        return ["com.microsoft.edgemac", "com.google.Chrome"].first { bundleID == $0 + ".app." + appID }
    }

    public static func arguments(appID: String, target: URL, profile: String?) -> [String] {
        var arguments = ["--app-id=" + appID, "--app-launch-url-for-shortcuts-menu-item=" + target.absoluteString]
        if let profile = profileDirectory(profile) { arguments.append("--profile-directory=" + profile) }
        return arguments
    }
}
