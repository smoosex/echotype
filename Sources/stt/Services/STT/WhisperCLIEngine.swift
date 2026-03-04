import Foundation

final class WhisperCLIEngine: WhisperEngine, @unchecked Sendable {
    private let configuration: WhisperConfiguration

    init(configuration: WhisperConfiguration) {
        self.configuration = configuration
    }

    func transcribe(audioURL: URL) throws -> String {
        guard let executablePath = configuration.executablePath else {
            throw WhisperEngineError.executableNotFound
        }
        guard let modelPath = configuration.modelPath else {
            throw WhisperEngineError.modelNotConfigured
        }

        let outputBase = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("echotype-whisper-\(UUID().uuidString)")
        let outputURL = outputBase.appendingPathExtension("txt")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "-m", modelPath,
            "-f", audioURL.path,
            "-l", configuration.language,
            "-otxt",
            "-of", outputBase.path,
            "-nt"
        ]

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw WhisperEngineError.processFailed(process.terminationStatus, stderrText)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw WhisperEngineError.outputMissing
        }

        let rawText = try String(contentsOf: outputURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawText.isEmpty else {
            throw WhisperEngineError.outputMissing
        }

        return rawText
    }
}
