import Foundation

enum WhisperModelSize: String, CaseIterable, Identifiable {
    case tiny
    case base
    case small
    case medium
    case largeV3 = "large-v3"
    case largeV3Turbo = "large-v3-turbo"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiny:
            return "tiny"
        case .base:
            return "base"
        case .small:
            return "small"
        case .medium:
            return "medium"
        case .largeV3:
            return "large-v3"
        case .largeV3Turbo:
            return "large-v3-turbo"
        }
    }

    var approximateSizeText: String {
        switch self {
        case .tiny:
            return "~75 MB"
        case .base:
            return "~142 MB"
        case .small:
            return "~466 MB"
        case .medium:
            return "~1.5 GB"
        case .largeV3:
            return "~3.1 GB"
        case .largeV3Turbo:
            return "~1.6 GB"
        }
    }

    var supportsEnglishVariant: Bool {
        switch self {
        case .tiny, .base, .small, .medium:
            return true
        case .largeV3, .largeV3Turbo:
            return false
        }
    }
}

enum WhisperModelLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var title: String {
        title(in: .current())
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .chinese:
            return L10n.text(L10nKey.whisperLanguageChinese, language: language)
        case .english:
            return L10n.text(L10nKey.whisperLanguageEnglish, language: language)
        }
    }

    func modelSuffix(for size: WhisperModelSize) -> String {
        guard self == .english, size.supportsEnglishVariant else { return "" }
        return ".en"
    }

    var transcriptionLanguageCode: String {
        switch self {
        case .chinese:
            return "zh"
        case .english:
            return "en"
        }
    }

    static func fromTranscriptionLanguageCode(_ code: String) -> WhisperModelLanguage? {
        switch code.lowercased() {
        case "zh":
            return .chinese
        case "en":
            return .english
        default:
            return nil
        }
    }
}

enum WhisperTranscriptionLanguage: String, CaseIterable, Identifiable {
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

    static func fromTranscriptionLanguageCode(_ code: String) -> WhisperTranscriptionLanguage? {
        switch code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "auto", "":
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

struct WhisperModelDescriptor {
    let size: WhisperModelSize
    let language: WhisperModelLanguage
    let modelSuffix: String
    let fileName: String
    let downloadURL: URL

    var selectionKey: String {
        "\(size.rawValue)|\(language.rawValue)"
    }

    var displayName: String {
        let modelName = "\(size.title)\(modelSuffix)"
        return "\(modelName) (\(size.approximateSizeText))"
    }
}

struct WhisperInstalledModel: Identifiable, Hashable {
    let fileName: String

    var id: String { fileName }

    var displayName: String {
        fileName
            .replacingOccurrences(of: "ggml-", with: "")
            .replacingOccurrences(of: ".bin", with: "")
    }
}

enum WhisperModelCatalog {
    static func descriptor(
        size: WhisperModelSize,
        language: WhisperModelLanguage
    ) -> WhisperModelDescriptor {
        let suffix = language.modelSuffix(for: size)
        let fileName = "ggml-\(size.rawValue)\(suffix).bin"
        let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
        return WhisperModelDescriptor(
            size: size,
            language: language,
            modelSuffix: suffix,
            fileName: fileName,
            downloadURL: url
        )
    }

    static func recommendedSize(for language: WhisperModelLanguage) -> WhisperModelSize {
        switch language {
        case .chinese:
            return .base
        case .english:
            return .small
        }
    }
}
