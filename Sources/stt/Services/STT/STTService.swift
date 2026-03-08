import Foundation

@MainActor
final class STTService {
    static let defaultTranscriptionTimeout: Duration = .seconds(30)

    private let engine: any STTEngine

    init(engine: any STTEngine) {
        self.engine = engine
    }

    convenience init(configuration: STTConfiguration) {
        switch configuration.selectedModel.family {
        case .whisperKit:
            self.init(engine: WhisperKitEngine(configuration: configuration))
        case .qwen3ASR:
            self.init(engine: SpeechSwiftQwenEngine(configuration: configuration))
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        let engine = self.engine
        return try await withTimeout(Self.defaultTranscriptionTimeout) {
            try await engine.transcribe(audioURL: audioURL)
        }
    }

    func preload() async throws {
        try await engine.preload()
    }

    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                throw STTEngineError.timedOut(Int(duration.components.seconds))
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw STTEngineError.timedOut(Int(duration.components.seconds))
            }
            return result
        }
    }
}

private struct WhisperKitEngine: STTEngine {
    let configuration: STTConfiguration

    func transcribe(audioURL: URL) async throws -> String {
        try await WhisperKitRuntimeStore.shared.transcribe(audioURL: audioURL, configuration: configuration)
    }

    func preload() async throws {
        try await WhisperKitRuntimeStore.shared.preload(configuration: configuration)
    }
}

private struct SpeechSwiftQwenEngine: STTEngine {
    let configuration: STTConfiguration

    func transcribe(audioURL: URL) async throws -> String {
        try await Qwen3ASRRuntimeStore.shared.transcribe(audioURL: audioURL, configuration: configuration)
    }

    func preload() async throws {
        try await Qwen3ASRRuntimeStore.shared.preload(configuration: configuration)
    }
}
