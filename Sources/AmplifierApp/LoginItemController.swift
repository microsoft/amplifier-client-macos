#if os(macOS)
import Foundation
import ServiceManagement

/// macOS owns login-item state. Never restore a saved preference over an OS change.
@MainActor final class LoginItemController {
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var error: String?

    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.readStatus = readStatus; self.register = register; self.unregister = unregister
        refresh()
    }
    var requested: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }
    var detail: String {
        if let error { return error }
        switch status {
        case .enabled: return "Tempo will open when you sign in to this Mac."
        case .requiresApproval: return "Allow Tempo in System Settings to finish enabling startup."
        case .notFound: return "Turn this on to register Tempo for login startup."
        default: return "Keep Tempo available after signing in to this Mac."
        }
    }
    func refresh() {
        let current = readStatus()
        if current != status { error = nil }
        status = current
    }
    func setEnabled(_ enabled: Bool) {
        refresh()
        guard enabled != requested else { return }
        do {
            if enabled { try register() } else { try unregister() }
            refresh(); error = nil
        } catch {
            refresh(); self.error = error.localizedDescription
        }
    }
}
#endif
