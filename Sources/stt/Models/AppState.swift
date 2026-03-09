import Foundation

enum AppState: Equatable {
    case idle
    case recording
    case processing

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
        }
    }

    var symbolName: String {
        "mic"
    }
}
