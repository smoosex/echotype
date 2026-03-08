import Foundation

struct STTConfiguration {
    let selectedModel: STTModelOption
    let languageHint: STTLanguageHint
    let whisperModelFolder: String?
    let isModelInstalled: Bool

    var isReady: Bool {
        isModelInstalled
    }
}
