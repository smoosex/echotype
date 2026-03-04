import Foundation

enum AppState: Equatable {
    case idle
    case recording
    case processing
    case error(String)

    var title: String {
        title(in: .current())
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .idle:
            return L10n.text(L10nKey.stateIdle, language: language)
        case .recording:
            return L10n.text(L10nKey.stateRecording, language: language)
        case .processing:
            return L10n.text(L10nKey.stateProcessing, language: language)
        case .error(let message):
            return L10n.text(L10nKey.stateErrorFormat, language: language, message)
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "mic"
        case .recording:
            return "waveform"
        case .processing:
            return "hourglass"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}
