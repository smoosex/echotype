import Foundation

enum STTModelFamily: String, Codable {
    case whisperKit = "whisperkit"
    case qwen3ASR = "qwen3asr"
}

enum STTLanguageHint: String, CaseIterable, Identifiable, Codable {
    case auto
    case chinese
    case english

    var id: String { rawValue }

    var title: String {
        title(in: .current())
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .auto:
            return L10n.text(L10nKey.whisperTranscriptionAuto, language: language)
        case .chinese:
            return L10n.text(L10nKey.whisperTranscriptionChinese, language: language)
        case .english:
            return L10n.text(L10nKey.whisperTranscriptionEnglish, language: language)
        }
    }

    var transcriptionLanguageCode: String {
        switch self {
        case .auto:
            return "auto"
        case .chinese:
            return "zh"
        case .english:
            return "en"
        }
    }

    var whisperKitLanguageCode: String? {
        switch self {
        case .auto:
            return nil
        case .chinese:
            return "zh"
        case .english:
            return "en"
        }
    }

    var qwenLanguageValue: String? {
        switch self {
        case .auto:
            return nil
        case .chinese:
            return "Chinese"
        case .english:
            return "English"
        }
    }

    static func fromTranscriptionLanguageCode(_ code: String) -> STTLanguageHint? {
        switch code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "auto":
            return .auto
        case "zh", "chinese":
            return .chinese
        case "en", "english":
            return .english
        default:
            return nil
        }
    }
}

enum STTModelOption: String, CaseIterable, Identifiable, Codable {
    case whisperTiny = "whisperkit.tiny"
    case whisperBase = "whisperkit.base"
    case whisperLargeV3v20240930 = "whisperkit.large-v3.v20240930"
    case qwen06B = "qwen3asr.0_6b"
    case qwen17B = "qwen3asr.1_7b"

    var id: String { rawValue }

    var family: STTModelFamily {
        rawValue.hasPrefix("qwen3asr.") ? .qwen3ASR : .whisperKit
    }

    var title: String {
        switch self {
        case .whisperTiny:
            return "Whisper Tiny"
        case .whisperBase:
            return "Whisper Base"
        case .whisperLargeV3v20240930:
            return "Whisper Large v3"
        case .qwen06B:
            return "Qwen3-ASR 0.6B"
        case .qwen17B:
            return "Qwen3-ASR 1.7B"
        }
    }

    var summary: String {
        switch self {
        case .whisperTiny:
            return "WhisperKit · ~73 MB"
        case .whisperBase:
            return "WhisperKit · ~140 MB"
        case .whisperLargeV3v20240930:
            return "WhisperKit · ~1.5 GB"
        case .qwen06B:
            return "speech-swift / MLX · ~400 MB"
        case .qwen17B:
            return "speech-swift / MLX · ~2.5 GB"
        }
    }

    var whisperVariant: String? {
        switch self {
        case .whisperTiny:
            return "openai_whisper-tiny"
        case .whisperBase:
            return "openai_whisper-base"
        case .whisperLargeV3v20240930:
            return "openai_whisper-large-v3-v20240930"
        case .qwen06B, .qwen17B:
            return nil
        }
    }

    var qwenModelID: String? {
        switch self {
        case .qwen06B:
            return "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
        case .qwen17B:
            return "aufklarer/Qwen3-ASR-1.7B-MLX-8bit"
        default:
            return nil
        }
    }

    var estimatedDownloadSizeBytes: Int64? {
        switch self {
        case .qwen06B:
            return 400 * 1_024 * 1_024
        case .qwen17B:
            return Int64(Double(1_024 * 1_024 * 1_024) * 2.5)
        default:
            return nil
        }
    }

    var fallbackLegacyWhisperFileNames: [String] {
        switch self {
        case .whisperTiny:
            return ["ggml-tiny.bin", "ggml-tiny.en.bin"]
        case .whisperBase:
            return ["ggml-base.bin", "ggml-base.en.bin", "ggml-small.bin", "ggml-small.en.bin", "ggml-medium.bin", "ggml-medium.en.bin"]
        case .whisperLargeV3v20240930:
            return ["ggml-large-v3.bin", "ggml-large-v3-turbo.bin"]
        default:
            return []
        }
    }

    static let `default`: STTModelOption = .whisperBase

    static func migratedSelection(
        selectedModelID: String?,
        legacyBackend: String?,
        legacyWhisperFileName: String?,
        legacyQwenModelName: String?
    ) -> STTModelOption {
        if let selectedModelID,
           let normalized = normalizedSelection(from: selectedModelID) {
            return normalized
        }

        if let legacyQwenModelName,
           legacyBackend == "qwen3_asr_server" || legacyQwenModelName.contains("Qwen") {
            return legacyQwenModelName.localizedCaseInsensitiveContains("1.7B") ? .qwen17B : .qwen06B
        }

        let legacyWhisperFileName = legacyWhisperFileName?.lowercased() ?? ""
        if legacyWhisperFileName.contains("tiny") {
            return .whisperTiny
        }
        if legacyWhisperFileName.contains("large") {
            return .whisperLargeV3v20240930
        }
        if legacyWhisperFileName.contains("small") || legacyWhisperFileName.contains("medium") {
            return .whisperBase
        }

        return .whisperBase
    }

    private static func normalizedSelection(from selectedModelID: String) -> STTModelOption? {
        if let current = STTModelOption(rawValue: selectedModelID) {
            return current
        }

        let value = selectedModelID.lowercased()
        if value.contains("qwen") {
            return value.contains("1_7") || value.contains("1.7") ? .qwen17B : .qwen06B
        }
        if value.contains("tiny") {
            return .whisperTiny
        }
        if value.contains("large") || value.contains("distil") || value.contains("turbo") {
            return .whisperLargeV3v20240930
        }
        if value.contains("base") || value.contains("small") || value.contains("medium") {
            return .whisperBase
        }

        return nil
    }
}
