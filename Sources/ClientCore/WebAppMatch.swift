import Foundation

public enum WebAppMatch {
    /// Match the origin, never an application name or a hostname alone.
    public static func matches(_ launch: URL, target: URL) -> Bool {
        guard launch.user == nil, launch.password == nil,
              launch.scheme?.lowercased() == target.scheme?.lowercased(),
              launch.host?.lowercased() == target.host?.lowercased(), launch.host != nil else { return false }
        let port: (URL) -> Int = { $0.port ?? ($0.scheme == "https" ? 443 : 80) }
        let path = launch.path
        let scope = path.isEmpty || path == "/" ? "/" : (path as NSString).deletingLastPathComponent
        return port(launch) == port(target) && (scope.isEmpty || scope == "/" || target.path == scope || target.path.hasPrefix(scope + "/"))
    }
}
