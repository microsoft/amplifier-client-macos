import Foundation
import ServiceManagement

MainActor.assumeIsolated {
    var status: SMAppService.Status = .notRegistered
    var registrations = 0, removals = 0
    var denied = false, approval = false
    let item = LoginItemController(readStatus: { status }, register: {
        registrations += 1
        if denied { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Registration denied"]) }
        status = approval ? .requiresApproval : .enabled
    }, unregister: { removals += 1; status = .notRegistered })
    precondition(!item.requested && registrations == 0, "Opening settings must never register automatically")
    item.setEnabled(true)
    precondition(item.status == .enabled && registrations == 1)
    item.setEnabled(true)
    precondition(registrations == 1, "Repeated enable must not re-register")
    // A change made in macOS is authoritative, even with the app still running.
    status = .notRegistered; item.refresh()
    precondition(!item.requested && registrations == 1)
    denied = true; item.setEnabled(true)
    precondition(!item.requested && item.error == "Registration denied")
    denied = false; approval = true; item.setEnabled(true)
    precondition(item.requested && item.needsApproval && item.error == nil)
    item.setEnabled(true)
    precondition(registrations == 3, "Awaiting approval must not trigger a registration loop")
    status = .enabled; item.refresh()
    precondition(!item.needsApproval && item.requested)
    item.setEnabled(false)
    precondition(!item.requested && removals == 1)
    item.setEnabled(false)
    precondition(removals == 1)
    status = .notFound; item.refresh()
    precondition(!item.requested && !item.needsApproval)
    print("PASS: login item opt-in, system state, approval, registration failure, idempotence and disable")
}
