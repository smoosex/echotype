import Foundation

enum STTBackend: String, CaseIterable, Identifiable {
    case whisperCpp = "whisper_cpp"
    case qwen3ASRServer = "qwen3_asr_server"

    var id: String { rawValue }

    var title: String {
        title(in: .current())
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .whisperCpp:
            return L10n.text(L10nKey.backendWhisperCLI, language: language)
        case .qwen3ASRServer:
            return L10n.text(L10nKey.backendQwenCLI, language: language)
        }
    }
}

enum QwenLanguageHint: String, CaseIterable, Identifiable {
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
            return L10n.text(L10nKey.qwenLanguageAuto, language: language)
        case .chinese:
            return L10n.text(L10nKey.qwenLanguageChinese, language: language)
        case .english:
            return L10n.text(L10nKey.qwenLanguageEnglish, language: language)
        }
    }

    var persistedCode: String {
        switch self {
        case .auto:
            return "auto"
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

    static func fromPersistedCode(_ code: String) -> QwenLanguageHint? {
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

struct WhisperConfiguration {
    var backend: STTBackend
    var executablePath: String?
    var modelPath: String?
    var language: String
    var qwenCLIPath: String?
    var qwenModelName: String
    var qwenLanguageHint: String

    init(
        backend: STTBackend = STTBackend(
            rawValue: ProcessInfo.processInfo.environment["STT_BACKEND"] ?? ""
        ) ?? .whisperCpp,
        executablePath: String? = ProcessInfo.processInfo.environment["WHISPER_CLI_PATH"],
        modelPath: String? = ProcessInfo.processInfo.environment["WHISPER_MODEL_PATH"],
        language: String = "auto",
        qwenCLIPath: String? = ProcessInfo.processInfo.environment["QWEN_ASR_CLI_PATH"],
        qwenModelName: String = ProcessInfo.processInfo.environment["QWEN_ASR_MODEL_NAME"] ?? "Qwen/Qwen3-ASR-0.6B",
        qwenLanguageHint: String = ProcessInfo.processInfo.environment["QWEN_ASR_LANGUAGE_HINT"] ?? "auto"
    ) {
        self.backend = backend
        self.executablePath = executablePath ?? WhisperConfiguration.detectExecutablePath()
        self.modelPath = modelPath
        self.language = language
        self.qwenCLIPath = qwenCLIPath ?? WhisperConfiguration.detectQwenCLIPath()
        self.qwenModelName = qwenModelName
        self.qwenLanguageHint = qwenLanguageHint
    }

    var isReady: Bool {
        switch backend {
        case .whisperCpp:
            guard let executablePath, let modelPath else { return false }
            return FileManager.default.isExecutableFile(atPath: executablePath) &&
                FileManager.default.fileExists(atPath: modelPath)
        case .qwen3ASRServer:
            guard let qwenCLIPath,
                  FileManager.default.isExecutableFile(atPath: qwenCLIPath)
            else {
                return false
            }
            guard !qwenModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return QwenLanguageHint.fromPersistedCode(qwenLanguageHint) != nil
        }
    }

    static func detectExecutablePath() -> String? {
        let fileManager = FileManager.default
        let directCandidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/opt/whisper-cpp/bin/whisper-cli",
            "/usr/local/opt/whisper-cpp/bin/whisper-cli",
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper",
            "/opt/homebrew/opt/whisper-cpp/bin/whisper",
            "/usr/local/opt/whisper-cpp/bin/whisper",
        ]
        for candidate in directCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        if let whisperCLI = locateBinary(named: "whisper-cli") {
            return whisperCLI
        }
        if let whisper = locateBinary(named: "whisper") {
            return whisper
        }
        return nil
    }

    static func detectQwenCLIPath() -> String? {
        let fileManager = FileManager.default
        if let env = ProcessInfo.processInfo.environment["QWEN_ASR_CLI_PATH"],
           fileManager.isExecutableFile(atPath: env) {
            return env
        }

        let directCandidates = [
            "/opt/homebrew/bin/qwen-asr",
            "/usr/local/bin/qwen-asr",
        ]
        for candidate in directCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return locateBinary(named: "qwen-asr")
    }

    private static func locateBinary(named binary: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty else { return nil }
            return path
        } catch {
            return nil
        }
    }
}
