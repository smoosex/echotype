import Foundation

@MainActor
final class STTService {
    private let engine: WhisperEngine

    init(engine: WhisperEngine) {
        self.engine = engine
    }

    convenience init(configuration: WhisperConfiguration = WhisperConfiguration()) {
        switch configuration.backend {
        case .whisperCpp:
            self.init(engine: WhisperCLIEngine(configuration: configuration))
        case .qwen3ASRServer:
            self.init(engine: QwenASRCLIEngine(configuration: configuration))
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        let engine = self.engine

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try engine.transcribe(audioURL: audioURL)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
