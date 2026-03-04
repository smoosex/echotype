import Foundation

protocol WhisperEngine: Sendable {
    func transcribe(audioURL: URL) throws -> String
}

enum WhisperEngineError: LocalizedError {
    case executableNotFound
    case modelNotConfigured
    case qwenExecutableNotFound
    case qwenModelNotConfigured
    case processFailed(Int32, String)
    case qwenProcessFailed(Int32, String)
    case outputMissing

    var errorDescription: String? {
        let language = AppLanguage.current()
        switch self {
        case .executableNotFound:
            return L10n.text(L10nKey.errorWhisperExecutableNotFound, language: language)
        case .modelNotConfigured:
            return L10n.text(L10nKey.errorWhisperModelNotConfigured, language: language)
        case .qwenExecutableNotFound:
            return L10n.text(L10nKey.errorQwenExecutableNotFound, language: language)
        case .qwenModelNotConfigured:
            return L10n.text(L10nKey.errorQwenModelNotConfigured, language: language)
        case .processFailed(let code, let message):
            return L10n.text(L10nKey.errorWhisperProcessFailedFormat, language: language, code, message)
        case let .qwenProcessFailed(code, message):
            return L10n.text(L10nKey.errorQwenProcessFailedFormat, language: language, code, message)
        case .outputMissing:
            return L10n.text(L10nKey.errorTranscriptionOutputEmpty, language: language)
        }
    }
}
