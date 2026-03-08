import Foundation

enum TextInjectionMode: String, CaseIterable, Identifiable, Sendable {
    case clipboardOnly
    case clipboardThenPaste

    var id: String { rawValue }

    var title: String {
        title(in: .current())
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .clipboardOnly:
            return L10n.text(L10nKey.injectionModeClipboardOnly, language: language)
        case .clipboardThenPaste:
            return L10n.text(L10nKey.injectionModeClipboardPaste, language: language)
        }
    }
}

enum TextInjectionResult: Equatable, Sendable {
    case clipboardOnly
    case pasteShortcutSent
    case fallbackToClipboard(PasteShortcutFailureReason)

    var persistenceValue: String {
        switch self {
        case .clipboardOnly:
            return "clipboard_only"
        case .pasteShortcutSent:
            return "paste_shortcut_sent"
        case .fallbackToClipboard:
            return "fallback_to_clipboard"
        }
    }
}

enum PasteShortcutFailureReason: Equatable, Sendable {
    case accessibilityPermissionDenied
    case eventSourceUnavailable
    case eventCreationFailed
}

enum TextInjectionError: LocalizedError, Sendable {
    case clipboardFailed

    var errorDescription: String? {
        let language = AppLanguage.current()
        switch self {
        case .clipboardFailed:
            return L10n.text(L10nKey.errorClipboardFailed, language: language)
        }
    }
}

final class TextInjectionService: @unchecked Sendable {
    private let clipboardInjector = ClipboardInjector()
    private let pasteInjector = PasteShortcutInjector()

    func inject(text: String, mode: TextInjectionMode) throws -> TextInjectionResult {
        guard clipboardInjector.copy(text: text) else {
            throw TextInjectionError.clipboardFailed
        }

        guard mode == .clipboardThenPaste else {
            return .clipboardOnly
        }

        switch pasteInjector.sendPasteShortcut() {
        case .sent:
            return .pasteShortcutSent
        case .failed(let reason):
            return .fallbackToClipboard(reason)
        }
    }
}
