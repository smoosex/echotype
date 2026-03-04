import Foundation

final class QwenASRCLIEngine: WhisperEngine, @unchecked Sendable {
    private let configuration: WhisperConfiguration
    private let fileManager = FileManager.default

    init(configuration: WhisperConfiguration) {
        self.configuration = configuration
    }

    func transcribe(audioURL: URL) throws -> String {
        let executablePath = resolvedExecutablePath()
        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw WhisperEngineError.qwenExecutableNotFound
        }

        let modelName = configuration.qwenModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            throw WhisperEngineError.qwenModelNotConfigured
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "transcribe",
            audioURL.path,
            "--model", resolvedModelArgument(from: modelName),
            "--language", resolvedLanguageCode(from: configuration.qwenLanguageHint),
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw WhisperEngineError.qwenProcessFailed(
                process.terminationStatus,
                Self.importantError(stderr: stderrText, stdout: stdoutText)
            )
        }

        let transcript = Self.normalizeTranscript(stdoutText)
        guard !transcript.isEmpty else {
            throw WhisperEngineError.outputMissing
        }
        return transcript
    }

    private func resolvedExecutablePath() -> String {
        if let configured = configuration.qwenCLIPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return configured
        }
        if let detected = WhisperConfiguration.detectQwenCLIPath() {
            return detected
        }
        return ""
    }

    private func resolvedModelArgument(from modelName: String) -> String {
        if let preset = QwenASRModelPreset(rawValue: modelName),
           let localDirectory = QwenCLIService.installedLocalModelCacheDirectory(for: preset) {
            return localDirectory.path
        }
        return modelName
    }

    private func resolvedLanguageCode(from persistedCode: String) -> String {
        guard let hint = QwenLanguageHint.fromPersistedCode(persistedCode) else {
            return "auto"
        }

        switch hint {
        case .auto:
            return "auto"
        case .chinese:
            return "zh"
        case .english:
            return "en"
        }
    }

    private static func normalizeTranscript(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // qwen-asr output may include model tags like <|zh|>, strip them.
        let tagPattern = #"<\|[^|]+?\|>"#
        return trimmed
            .replacingOccurrences(of: tagPattern, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func importantError(stderr: String, stdout: String) -> String {
        let stderrText = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderrText.isEmpty {
            return stderrText
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
