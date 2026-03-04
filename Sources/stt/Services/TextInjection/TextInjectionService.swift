import Foundation

enum TextInjectionMode: String, CaseIterable, Identifiable {
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

enum TextInjectionResult: String {
    case clipboardOnly
    case pasted
}

enum TextInjectionError: LocalizedError {
    case clipboardFailed
    case pasteFailed

    var errorDescription: String? {
        let language = AppLanguage.current()
        switch self {
        case .clipboardFailed:
            return L10n.text(L10nKey.errorClipboardFailed, language: language)
        case .pasteFailed:
            return L10n.text(L10nKey.errorPasteFailed, language: language)
        }
    }
}

final class TextInjectionService {
    private let clipboardInjector = ClipboardInjector()
    private let pasteInjector = PasteShortcutInjector()

    func inject(text: String, mode: TextInjectionMode) throws -> TextInjectionResult {
        guard clipboardInjector.copy(text: text) else {
            throw TextInjectionError.clipboardFailed
        }

        guard mode == .clipboardThenPaste else {
            return .clipboardOnly
        }

        if pasteInjector.pasteFromClipboard() {
            return .pasted
        }

        // Auto-paste failed, but clipboard path already succeeded.
        return .clipboardOnly
    }
}
