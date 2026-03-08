import AudioCommon
import Foundation
@preconcurrency import Qwen3ASR
@preconcurrency import WhisperKit

protocol STTEngine: Sendable {
    func transcribe(audioURL: URL) async throws -> String
    func preload() async throws
}

enum STTEngineError: LocalizedError {
    case modelNotInstalled(String)
    case whisperKitLoadFailed(String)
    case qwenLoadFailed(String)
    case transcriptionFailed(String)
    case timedOut(Int)
    case outputMissing

    var errorDescription: String? {
        let language = AppLanguage.current()
        switch self {
        case .modelNotInstalled(let modelName):
            return L10n.text(L10nKey.errorSTTModelNotInstalledFormat, language: language, modelName)
        case .whisperKitLoadFailed(let message):
            return L10n.text(L10nKey.errorWhisperKitLoadFailedFormat, language: language, message)
        case .qwenLoadFailed(let message):
            return L10n.text(L10nKey.errorQwenLoadFailedFormat, language: language, message)
        case .transcriptionFailed(let message):
            return L10n.text(L10nKey.errorSTTTranscriptionFailedFormat, language: language, message)
        case .timedOut(let seconds):
            return L10n.text(L10nKey.errorSTTTimeoutFormat, language: language, seconds)
        case .outputMissing:
            return L10n.text(L10nKey.errorTranscriptionOutputEmpty, language: language)
        }
    }
}

actor WhisperKitRuntimeStore {
    static let shared = WhisperKitRuntimeStore()

    private struct LoadKey: Hashable {
        let model: STTModelOption
        let folder: String
    }

    private struct LoadingEntry {
        let token = UUID()
        let task: Task<WhisperKit, Error>
    }

    private var cachedKey: LoadKey?
    private var whisperKit: WhisperKit?
    private var loadingTasks: [LoadKey: LoadingEntry] = [:]

    func preload(configuration: STTConfiguration) async throws {
        guard configuration.isModelInstalled,
              let folder = configuration.whisperModelFolder
        else {
            return
        }
        let preloadStart = Date()
        _ = try await resolveWhisperKit(for: configuration.selectedModel, folder: folder)
        let preloadSeconds = Self.formattedSeconds(Date().timeIntervalSince(preloadStart))
        AppLogger.stt.info("WhisperKit preload ready for \(configuration.selectedModel.title, privacy: .public) in \(preloadSeconds, privacy: .public)s")
    }

    func transcribe(audioURL: URL, configuration: STTConfiguration) async throws -> String {
        guard configuration.isModelInstalled else {
            throw STTEngineError.modelNotInstalled(configuration.selectedModel.title)
        }
        guard let folder = configuration.whisperModelFolder else {
            throw STTEngineError.modelNotInstalled(configuration.selectedModel.title)
        }

        let resolveStart = Date()
        let pipe = try await resolveWhisperKit(for: configuration.selectedModel, folder: folder)
        let resolveDuration = Date().timeIntervalSince(resolveStart)
        let options = DecodingOptions(language: configuration.languageHint.whisperKitLanguageCode)
        let transcriptionStart = Date()
        let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: options)
        let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
        let resolveSeconds = Self.formattedSeconds(resolveDuration)
        let decodeSeconds = Self.formattedSeconds(transcriptionDuration)
        AppLogger.stt.info("WhisperKit transcribe model=\(configuration.selectedModel.title, privacy: .public) resolve=\(resolveSeconds, privacy: .public)s decode=\(decodeSeconds, privacy: .public)s")
        let text = results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw STTEngineError.outputMissing
        }
        return text
    }

    func invalidate(model: STTModelOption) {
        if cachedKey?.model == model {
            whisperKit = nil
            cachedKey = nil
        }

        let matchingKeys = loadingTasks.keys.filter { $0.model == model }
        for key in matchingKeys {
            loadingTasks[key]?.task.cancel()
            loadingTasks.removeValue(forKey: key)
        }
    }

    private func resolveWhisperKit(for model: STTModelOption, folder: String) async throws -> WhisperKit {
        let key = LoadKey(model: model, folder: folder)

        if cachedKey == key,
           let whisperKit {
            AppLogger.stt.info("WhisperKit cache hit: \(model.title, privacy: .public)")
            return whisperKit
        }

        if let loadingTask = loadingTasks[key] {
            AppLogger.stt.info("WhisperKit awaiting in-flight load: \(model.title, privacy: .public)")
            do {
                return try await loadingTask.task.value
            } catch let error as STTEngineError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw STTEngineError.whisperKitLoadFailed(error.localizedDescription)
            }
        }

        let modelName = model.whisperVariant ?? model.title
        let tokenizerFolder = tokenizerFolderURL(for: folder)
        let task = Task<WhisperKit, Error> {
            try Task.checkCancellation()
            let loadStart = Date()
            let config = WhisperKitConfig(
                model: modelName,
                modelFolder: folder,
                tokenizerFolder: tokenizerFolder,
                verbose: false,
                prewarm: false,
                load: true,
                download: false
            )
            let pipe = try await WhisperKit(config)
            try Task.checkCancellation()
            let loadSeconds = Self.formattedSeconds(Date().timeIntervalSince(loadStart))
            AppLogger.stt.info("WhisperKit loaded model=\(model.title, privacy: .public) in \(loadSeconds, privacy: .public)s")
            return pipe
        }

        let entry = LoadingEntry(task: task)
        loadingTasks[key] = entry

        do {
            let pipe = try await task.value
            if loadingTasks[key]?.token == entry.token {
                loadingTasks.removeValue(forKey: key)
                cachedKey = key
                whisperKit = pipe
            }
            return pipe
        } catch let error as STTEngineError {
            if loadingTasks[key]?.token == entry.token {
                loadingTasks.removeValue(forKey: key)
            }
            throw error
        } catch is CancellationError {
            if loadingTasks[key]?.token == entry.token {
                loadingTasks.removeValue(forKey: key)
            }
            throw CancellationError()
        } catch {
            if loadingTasks[key]?.token == entry.token {
                loadingTasks.removeValue(forKey: key)
            }
            throw STTEngineError.whisperKitLoadFailed(error.localizedDescription)
        }
    }

    private func tokenizerFolderURL(for folder: String) -> URL {
        URL(fileURLWithPath: folder, isDirectory: true)
            .appendingPathComponent("tokenizer", isDirectory: true)
    }

    nonisolated private static func formattedSeconds(_ duration: TimeInterval) -> String {
        String(format: "%.2f", duration)
    }
}

actor Qwen3ASRRuntimeStore {
    static let shared = Qwen3ASRRuntimeStore()

    private struct LoadingEntry {
        let token = UUID()
        let task: Task<Qwen3ASRModel, Error>
    }

    private var cachedModel: STTModelOption?
    private var qwenModel: Qwen3ASRModel?
    private var loadingTasks: [STTModelOption: LoadingEntry] = [:]

    func preload(configuration: STTConfiguration) async throws {
        guard configuration.isModelInstalled else { return }
        _ = try await resolveQwenModel(for: configuration.selectedModel)
    }

    func transcribe(audioURL: URL, configuration: STTConfiguration) async throws -> String {
        guard configuration.isModelInstalled else {
            throw STTEngineError.modelNotInstalled(configuration.selectedModel.title)
        }
        let model = try await resolveQwenModel(for: configuration.selectedModel)

        do {
            let audio = try AudioFileLoader.load(url: audioURL, targetSampleRate: 16000)
            let text = model.transcribe(
                audio: audio,
                sampleRate: 16000,
                language: configuration.languageHint.qwenLanguageValue
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw STTEngineError.outputMissing
            }
            return text
        } catch let error as STTEngineError {
            throw error
        } catch {
            throw STTEngineError.transcriptionFailed(error.localizedDescription)
        }
    }

    func invalidate(model: STTModelOption) {
        if cachedModel == model {
            qwenModel = nil
            cachedModel = nil
        }
        if let loadingTask = loadingTasks[model] {
            loadingTask.task.cancel()
            loadingTasks.removeValue(forKey: model)
        }
    }

    private func resolveQwenModel(for model: STTModelOption) async throws -> Qwen3ASRModel {
        if cachedModel == model,
           let qwenModel {
            return qwenModel
        }

        if let loadingTask = loadingTasks[model] {
            do {
                return try await loadingTask.task.value
            } catch let error as STTEngineError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw STTEngineError.qwenLoadFailed(error.localizedDescription)
            }
        }

        guard let modelID = model.qwenModelID else {
            throw STTEngineError.modelNotInstalled(model.title)
        }

        let task = Task<Qwen3ASRModel, Error> {
            try Task.checkCancellation()
            let loadedModel = try await Qwen3ASRModel.fromPretrained(modelId: modelID)
            try Task.checkCancellation()
            return loadedModel
        }

        let entry = LoadingEntry(task: task)
        loadingTasks[model] = entry

        do {
            let loadedModel = try await task.value
            if loadingTasks[model]?.token == entry.token {
                loadingTasks.removeValue(forKey: model)
                cachedModel = model
                qwenModel = loadedModel
            }
            return loadedModel
        } catch let error as STTEngineError {
            if loadingTasks[model]?.token == entry.token {
                loadingTasks.removeValue(forKey: model)
            }
            throw error
        } catch is CancellationError {
            if loadingTasks[model]?.token == entry.token {
                loadingTasks.removeValue(forKey: model)
            }
            throw CancellationError()
        } catch {
            if loadingTasks[model]?.token == entry.token {
                loadingTasks.removeValue(forKey: model)
            }
            throw STTEngineError.qwenLoadFailed(error.localizedDescription)
        }
    }
}
