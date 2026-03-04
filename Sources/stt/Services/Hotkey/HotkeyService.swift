import Carbon
import Foundation
@preconcurrency import KeyboardShortcuts

struct HotkeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let supportedModifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    static let defaultShortcut = HotkeyShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey | cmdKey)
    )

    var normalizedModifiers: UInt32 {
        modifiers & Self.supportedModifierMask
    }

    var hint: String {
        HotkeyDisplayFormatter.hint(forKeyCode: keyCode, modifiers: normalizedModifiers)
    }

    var glyphHint: String {
        HotkeyDisplayFormatter.glyphHint(forKeyCode: keyCode, modifiers: normalizedModifiers)
    }
}

extension HotkeyShortcut {
    init?(keyboardShortcut: KeyboardShortcuts.Shortcut) {
        let keyCode = UInt32(keyboardShortcut.carbonKeyCode)
        let modifiers = UInt32(keyboardShortcut.carbonModifiers)
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    var keyboardShortcut: KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(
            carbonKeyCode: Int(keyCode),
            carbonModifiers: Int(normalizedModifiers)
        )
    }
}

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
}

enum HotkeyDisplayFormatter {
    static func hint(forKeyCode keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 { parts.append("Control") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Command") }

        parts.append(keyName(for: keyCode))
        return parts.joined(separator: " + ")
    }

    static func glyphHint(forKeyCode keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        parts.append(glyphKeyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return:
            return "Return"
        case kVK_Tab:
            return "Tab"
        case kVK_Delete:
            return "Delete"
        case kVK_Escape:
            return "Escape"
        case kVK_ANSI_KeypadEnter:
            return "Keypad Enter"
        case kVK_LeftArrow:
            return "Left Arrow"
        case kVK_RightArrow:
            return "Right Arrow"
        case kVK_UpArrow:
            return "Up Arrow"
        case kVK_DownArrow:
            return "Down Arrow"
        case kVK_ANSI_Minus:
            return "-"
        case kVK_ANSI_Equal:
            return "="
        case kVK_ANSI_LeftBracket:
            return "["
        case kVK_ANSI_RightBracket:
            return "]"
        case kVK_ANSI_Backslash:
            return "\\"
        case kVK_ANSI_Semicolon:
            return ";"
        case kVK_ANSI_Quote:
            return "'"
        case kVK_ANSI_Comma:
            return ","
        case kVK_ANSI_Period:
            return "."
        case kVK_ANSI_Slash:
            return "/"
        case kVK_ANSI_Grave:
            return "`"
        case kVK_F1:
            return "F1"
        case kVK_F2:
            return "F2"
        case kVK_F3:
            return "F3"
        case kVK_F4:
            return "F4"
        case kVK_F5:
            return "F5"
        case kVK_F6:
            return "F6"
        case kVK_F7:
            return "F7"
        case kVK_F8:
            return "F8"
        case kVK_F9:
            return "F9"
        case kVK_F10:
            return "F10"
        case kVK_F11:
            return "F11"
        case kVK_F12:
            return "F12"
        case kVK_F13:
            return "F13"
        case kVK_F14:
            return "F14"
        case kVK_F15:
            return "F15"
        case kVK_F16:
            return "F16"
        case kVK_F17:
            return "F17"
        case kVK_F18:
            return "F18"
        case kVK_F19:
            return "F19"
        case kVK_ANSI_0:
            return "0"
        case kVK_ANSI_1:
            return "1"
        case kVK_ANSI_2:
            return "2"
        case kVK_ANSI_3:
            return "3"
        case kVK_ANSI_4:
            return "4"
        case kVK_ANSI_5:
            return "5"
        case kVK_ANSI_6:
            return "6"
        case kVK_ANSI_7:
            return "7"
        case kVK_ANSI_8:
            return "8"
        case kVK_ANSI_9:
            return "9"
        case kVK_ANSI_A:
            return "A"
        case kVK_ANSI_B:
            return "B"
        case kVK_ANSI_C:
            return "C"
        case kVK_ANSI_D:
            return "D"
        case kVK_ANSI_E:
            return "E"
        case kVK_ANSI_F:
            return "F"
        case kVK_ANSI_G:
            return "G"
        case kVK_ANSI_H:
            return "H"
        case kVK_ANSI_I:
            return "I"
        case kVK_ANSI_J:
            return "J"
        case kVK_ANSI_K:
            return "K"
        case kVK_ANSI_L:
            return "L"
        case kVK_ANSI_M:
            return "M"
        case kVK_ANSI_N:
            return "N"
        case kVK_ANSI_O:
            return "O"
        case kVK_ANSI_P:
            return "P"
        case kVK_ANSI_Q:
            return "Q"
        case kVK_ANSI_R:
            return "R"
        case kVK_ANSI_S:
            return "S"
        case kVK_ANSI_T:
            return "T"
        case kVK_ANSI_U:
            return "U"
        case kVK_ANSI_V:
            return "V"
        case kVK_ANSI_W:
            return "W"
        case kVK_ANSI_X:
            return "X"
        case kVK_ANSI_Y:
            return "Y"
        case kVK_ANSI_Z:
            return "Z"
        default:
            return "KeyCode \(keyCode)"
        }
    }

    private static func glyphKeyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return "↩"
        case kVK_Tab:
            return "⇥"
        case kVK_Delete:
            return "⌫"
        case kVK_Escape:
            return "⎋"
        case kVK_LeftArrow:
            return "←"
        case kVK_RightArrow:
            return "→"
        case kVK_UpArrow:
            return "↑"
        case kVK_DownArrow:
            return "↓"
        default:
            return keyName(for: keyCode)
        }
    }
}

enum HotkeyConflictAdvisor {
    static func warning(for shortcut: HotkeyShortcut) -> String? {
        let modifiers = shortcut.normalizedModifiers

        if shortcut.keyCode == UInt32(kVK_Space), modifiers == UInt32(cmdKey) {
            return L10n.text(L10nKey.hotkeyConflictSpotlight)
        }

        if shortcut.keyCode == UInt32(kVK_Space), modifiers == UInt32(controlKey) {
            return L10n.text(L10nKey.hotkeyConflictInputSource)
        }

        if shortcut.keyCode == UInt32(kVK_Tab), modifiers == UInt32(cmdKey) {
            return L10n.text(L10nKey.hotkeyConflictAppSwitcher)
        }

        if shortcut.keyCode == UInt32(kVK_ANSI_Grave), modifiers == UInt32(cmdKey) {
            return L10n.text(L10nKey.hotkeyConflictWindowCycle)
        }

        if shortcut.keyCode == UInt32(kVK_ANSI_Q), modifiers == UInt32(cmdKey) {
            return L10n.text(L10nKey.hotkeyConflictQuit)
        }

        return nil
    }
}

enum HotkeyServiceError: LocalizedError {
    case registrationFailed(OSStatus, String)

    var errorDescription: String? {
        switch self {
        case let .registrationFailed(code, reason):
            return L10n.text(L10nKey.hotkeyRegistrationFailedFormat, code, reason)
        }
    }
}

@MainActor
final class HotkeyService {
    var onHotKeyPressed: (() -> Void)?
    private var didRegisterListener = false
    private let hotkeyName = KeyboardShortcuts.Name.toggleRecording

    init() {
        registerListenerIfNeeded()
    }

    func registerDefault() throws {
        try register(shortcut: .defaultShortcut)
    }

    func register(shortcut: HotkeyShortcut) throws {
        // Recorder already writes and registers before invoking onChange.
        // Always release existing registration for this name first, otherwise
        // validation may report a false "already in use" self-conflict.
        KeyboardShortcuts.disable(hotkeyName)
        try validateRegistration(for: shortcut)
        KeyboardShortcuts.setShortcut(shortcut.keyboardShortcut, for: hotkeyName)
    }

    func currentShortcut() -> HotkeyShortcut? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: hotkeyName) else {
            return nil
        }

        return HotkeyShortcut(keyboardShortcut: shortcut)
    }

    func unregister() {
        KeyboardShortcuts.disable(hotkeyName)
    }

    func enable() {
        KeyboardShortcuts.enable(hotkeyName)
    }

    private func registerListenerIfNeeded() {
        guard !didRegisterListener else { return }
        didRegisterListener = true
        KeyboardShortcuts.onKeyUp(for: hotkeyName) { [weak self] in
            self?.onHotKeyPressed?()
        }
    }

    private func validateRegistration(for shortcut: HotkeyShortcut) throws {
        guard let target = GetEventDispatcherTarget() else {
            throw HotkeyServiceError.registrationFailed(
                OSStatus(paramErr),
                L10n.text(L10nKey.hotkeyDispatcherUnavailable)
            )
        }

        var eventHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: 0x45435450, // "ECTP"
            id: UInt32.random(in: 10000...UInt32.max - 1)
        )

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.normalizedModifiers,
            hotKeyID,
            target,
            OptionBits(kEventHotKeyNoOptions),
            &eventHotKey
        )

        if let eventHotKey {
            UnregisterEventHotKey(eventHotKey)
        }

        guard status == noErr else {
            throw HotkeyServiceError.registrationFailed(status, Self.failureReason(for: status))
        }
    }

    private static func failureReason(for status: OSStatus) -> String {
        switch status {
        case OSStatus(eventHotKeyExistsErr):
            return L10n.text(L10nKey.hotkeyAlreadyInUse)
        case OSStatus(eventHotKeyInvalidErr):
            return L10n.text(L10nKey.hotkeyRejectedBySystem)
        case OSStatus(paramErr):
            return L10n.text(L10nKey.hotkeyInvalidCombination)
        default:
            return L10n.text(L10nKey.hotkeyUnknownError)
        }
    }
}
