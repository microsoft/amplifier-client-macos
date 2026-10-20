#if os(macOS)
import AppKit

/// Accessory apps have no standard Edit menu to route keyboard equivalents.
/// Send these to the active field editor, including NSSecureTextField's editor.
@MainActor enum TempoEditing {
    static func route(_ event: NSEvent, in window: NSWindow) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if modifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            let action: Selector?
            switch key {
            case "v": action = #selector(NSText.paste(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "x": action = #selector(NSText.cut(_:))
            case "a": action = #selector(NSText.selectAll(_:))
            default: action = nil
            }
            if let action, window.firstResponder?.tryToPerform(action, with: window) == true { return true }
        }
        return false
    }
}
@MainActor final class EditingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        TempoEditing.route(event, in: self) || super.performKeyEquivalent(with: event)
    }
}
#endif
