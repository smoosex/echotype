import AudioCommon
import Foundation
@preconcurrency import Qwen3ASR
@preconcurrency import WhisperKit

protocol STTEngine: Sendable {
    func transcribe(audioURL: URL) async throws -> String
    func beginRecordingPreparation() async throws
    func endRecordingPreparation() async
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
    private static let idleUnloadDelay: Duration = .seconds(300)

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
    private var activeUseCount = 0
    private var idleGeneration: UInt64 = 0
    private var idleUnloadTask: Task<Void, Never>?

    func beginRecordingPreparation(configuration: STTConfiguration) async throws {
        guard let folder = configuration.whisperModelFolder else {
            return
        }

        beginActiveUse(modelTitle: configuration.selectedModel.title)
        do {
            let preloadStart = Date()
            _ = try await resolveWhisperKit(for: configuration.selectedModel, folder: folder)
            let preloadSeconds = Self.formattedSeconds(Date().timeIntervalSince(preloadStart))
            AppLogger.stt.info("WhisperKit recording preparation ready for \(configuration.selectedModel.title, privacy: .public) in \(preloadSeconds, privacy: .public)s")
        } catch {
            endActiveUse(modelTitle: configuration.selectedModel.title)
            throw error
        }
    }

    func endRecordingPreparation(configuration: STTConfiguration) {
        guard configuration.whisperModelFolder != nil else { return }
        endActiveUse(modelTitle: configuration.selectedModel.title)
    }

    func transcribe(audioURL: URL, configuration: STTConfiguration) async throws -> String {
        guard let folder = configuration.whisperModelFolder else {
            throw STTEngineError.modelNotInstalled(configuration.selectedModel.title)
        }

        return try await withActiveUse(modelTitle: configuration.selectedModel.title) {
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
    }

    func invalidate(model: STTModelOption) async {
        cancelIdleUnload(reason: "invalidate \(model.title)")
        if cachedKey?.model == model {
            if let whisperKit {
                await whisperKit.unloadModels()
            }
            whisperKit = nil
            cachedKey = nil
        }

        let matchingKeys = loadingTasks.keys.filter { $0.model == model }
        for key in matchingKeys {
            loadingTasks[key]?.task.cancel()
            loadingTasks.removeValue(forKey: key)
        }
    }

    func invalidateAll() async {
        cancelIdleUnload(reason: "invalidate all Whisper runtimes")
        if let whisperKit {
            await whisperKit.unloadModels()
        }
        whisperKit = nil
        cachedKey = nil
        loadingTasks.values.forEach { $0.task.cancel() }
        loadingTasks.removeAll()
    }

    private func resolveWhisperKit(for model: STTModelOption, folder: String) async throws -> WhisperKit {
        let key = LoadKey(model: model, folder: folder)

        await Qwen3ASRRuntimeStore.shared.invalidateAll()

        if cachedKey == key,
           let whisperKit {
            AppLogger.stt.info("WhisperKit cache hit: \(model.title, privacy: .public)")
            return whisperKit
        }

        if cachedKey != nil,
           cachedKey != key {
            if let whisperKit {
                await whisperKit.unloadModels()
            }
            whisperKit = nil
            cachedKey = nil
            cancelIdleUnload(reason: "switching Whisper runtime to \(model.title)")
            AppLogger.stt.info("WhisperKit unloaded previous runtime before loading \(model.title, privacy: .public)")
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

    private func withActiveUse<T>(
        modelTitle: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        beginActiveUse(modelTitle: modelTitle)
        defer { endActiveUse(modelTitle: modelTitle) }
        return try await operation()
    }

    private func beginActiveUse(modelTitle: String) {
        activeUseCount += 1
        idleGeneration &+= 1
        cancelIdleUnload(reason: "new activity for \(modelTitle)")
    }

    private func endActiveUse(modelTitle: String) {
        guard activeUseCount > 0 else { return }
        activeUseCount -= 1
        idleGeneration &+= 1
        guard activeUseCount == 0,
              cachedKey != nil
        else {
            return
        }
        scheduleIdleUnload(modelTitle: modelTitle, generation: idleGeneration)
    }

    private func scheduleIdleUnload(modelTitle: String, generation: UInt64) {
        cancelIdleUnload(reason: nil)
        let delaySeconds = Int(Self.idleUnloadDelay.components.seconds)
        AppLogger.stt.info("WhisperKit idle unload scheduled for \(modelTitle, privacy: .public) in \(delaySeconds, privacy: .public)s")
        idleUnloadTask = Task {
            do {
                try await Task.sleep(for: Self.idleUnloadDelay)
                await self.performIdleUnloadIfNeeded(expectedGeneration: generation)
            } catch is CancellationError {
            } catch {
                AppLogger.stt.error("WhisperKit idle unload task failed: \(error.localizedDescription)")
            }
        }
    }

    private func cancelIdleUnload(reason: String?) {
        guard let idleUnloadTask else { return }
        idleUnloadTask.cancel()
        self.idleUnloadTask = nil
        if let reason {
            AppLogger.stt.info("WhisperKit idle unload cancelled: \(reason, privacy: .public)")
        }
    }

    private func performIdleUnloadIfNeeded(expectedGeneration: UInt64) async {
        guard idleGeneration == expectedGeneration,
              activeUseCount == 0,
              loadingTasks.isEmpty,
              let whisperKit,
              let cachedKey
        else {
            return
        }

        idleUnloadTask = nil
        await whisperKit.unloadModels()
        self.whisperKit = nil
        self.cachedKey = nil
        AppLogger.stt.info("WhisperKit idle unload completed for \(cachedKey.model.title, privacy: .public)")
    }

    nonisolated private static func formattedSeconds(_ duration: TimeInterval) -> String {
        String(format: "%.2f", duration)
    }
}

actor Qwen3ASRRuntimeStore {
    static let shared = Qwen3ASRRuntimeStore()
    private static let idleUnloadDelay: Duration = .seconds(300)

    private struct LoadingEntry {
        let token = UUID()
        let task: Task<Qwen3ASRModel, Error>
    }

    private var cachedModel: STTModelOption?
    private var qwenModel: Qwen3ASRModel?
    private var loadingTasks: [STTModelOption: LoadingEntry] = [:]
    private var activeUseCount = 0
    private var idleGeneration: UInt64 = 0
    private var idleUnloadTask: Task<Void, Never>?

    func beginRecordingPreparation(configuration: STTConfiguration) async throws {
        guard configuration.isModelInstalled else { return }

        beginActiveUse(modelTitle: configuration.selectedModel.title)
        do {
            _ = try await resolveQwenModel(for: configuration.selectedModel)
            AppLogger.stt.info("Qwen3-ASR recording preparation ready for \(configuration.selectedModel.title, privacy: .public)")
        } catch {
            endActiveUse(modelTitle: configuration.selectedModel.title)
            throw error
        }
    }

    func endRecordingPreparation(configuration: STTConfiguration) {
        guard configuration.isModelInstalled else { return }
        endActiveUse(modelTitle: configuration.selectedModel.title)
    }

    func transcribe(audioURL: URL, configuration: STTConfiguration) async throws -> String {
        guard configuration.isModelInstalled else {
            throw STTEngineError.modelNotInstalled(configuration.selectedModel.title)
        }
        return try await withActiveUse(modelTitle: configuration.selectedModel.title) {
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
    }

    func invalidate(model: STTModelOption) {
        cancelIdleUnload(reason: "invalidate \(model.title)")
        if cachedModel == model {
            qwenModel?.unload()
            qwenModel = nil
            cachedModel = nil
        }
        if let loadingTask = loadingTasks[model] {
            loadingTask.task.cancel()
            loadingTasks.removeValue(forKey: model)
        }
    }

    func invalidateAll() {
        cancelIdleUnload(reason: "invalidate all Qwen runtimes")
        qwenModel?.unload()
        qwenModel = nil
        cachedModel = nil
        loadingTasks.values.forEach { $0.task.cancel() }
        loadingTasks.removeAll()
    }

    private func resolveQwenModel(for model: STTModelOption) async throws -> Qwen3ASRModel {
        await WhisperKitRuntimeStore.shared.invalidateAll()

        if cachedModel == model,
           let qwenModel {
            return qwenModel
        }

        if cachedModel != nil,
           cachedModel != model {
            qwenModel?.unload()
            qwenModel = nil
            cachedModel = nil
            cancelIdleUnload(reason: "switching Qwen runtime to \(model.title)")
            AppLogger.stt.info("Qwen3-ASR unloaded previous runtime before loading \(model.title, privacy: .public)")
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

    private func withActiveUse<T>(
        modelTitle: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        beginActiveUse(modelTitle: modelTitle)
        defer { endActiveUse(modelTitle: modelTitle) }
        return try await operation()
    }

    private func beginActiveUse(modelTitle: String) {
        activeUseCount += 1
        idleGeneration &+= 1
        cancelIdleUnload(reason: "new activity for \(modelTitle)")
    }

    private func endActiveUse(modelTitle: String) {
        guard activeUseCount > 0 else { return }
        activeUseCount -= 1
        idleGeneration &+= 1
        guard activeUseCount == 0,
              cachedModel != nil
        else {
            return
        }
        scheduleIdleUnload(modelTitle: modelTitle, generation: idleGeneration)
    }

    private func scheduleIdleUnload(modelTitle: String, generation: UInt64) {
        cancelIdleUnload(reason: nil)
        let delaySeconds = Int(Self.idleUnloadDelay.components.seconds)
        AppLogger.stt.info("Qwen3-ASR idle unload scheduled for \(modelTitle, privacy: .public) in \(delaySeconds, privacy: .public)s")
        idleUnloadTask = Task {
            do {
                try await Task.sleep(for: Self.idleUnloadDelay)
                await self.performIdleUnloadIfNeeded(expectedGeneration: generation)
            } catch is CancellationError {
            } catch {
                AppLogger.stt.error("Qwen3-ASR idle unload task failed: \(error.localizedDescription)")
            }
        }
    }

    private func cancelIdleUnload(reason: String?) {
        guard let idleUnloadTask else { return }
        idleUnloadTask.cancel()
        self.idleUnloadTask = nil
        if let reason {
            AppLogger.stt.info("Qwen3-ASR idle unload cancelled: \(reason, privacy: .public)")
        }
    }

    private func performIdleUnloadIfNeeded(expectedGeneration: UInt64) async {
        guard idleGeneration == expectedGeneration,
              activeUseCount == 0,
              loadingTasks.isEmpty,
              let qwenModel,
              let cachedModel
        else {
            return
        }

        idleUnloadTask = nil
        qwenModel.unload()
        self.qwenModel = nil
        self.cachedModel = nil
        AppLogger.stt.info("Qwen3-ASR idle unload completed for \(cachedModel.title, privacy: .public)")
    }
}
