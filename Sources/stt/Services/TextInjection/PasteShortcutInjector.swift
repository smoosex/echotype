import ApplicationServices

enum PasteShortcutDispatchResult: Equatable, Sendable {
    case sent
    case failed(PasteShortcutFailureReason)
}

struct PasteShortcutInjector: Sendable {
    func sendPasteShortcut() -> PasteShortcutDispatchResult {
        guard AXIsProcessTrusted() else {
            return .failed(.accessibilityPermissionDenied)
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return .failed(.eventSourceUnavailable)
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true), // keycode for V
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return .failed(.eventCreationFailed)
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .sent
    }
}
