import AppKit
@preconcurrency import AudioCommon
import Foundation
@preconcurrency import Qwen3ASR
@preconcurrency import WhisperKit

struct ModelInstallRowState: Equatable {
    enum Activity: Equatable {
        case idle
        case installing
        case deleting
    }

    let activity: Activity
    let isInstalled: Bool
    let progressFraction: Double?
    let transferText: String?
    let error: String?

    var isBusy: Bool {
        activity != .idle
    }

    var showsIndeterminateProgress: Bool {
        isBusy && progressFraction == nil
    }
}

@MainActor
final class STTConfigurationStore: ObservableObject {
    @Published var selectedModelID: String {
        didSet {
            persist()
            advanceReadinessRevision()
        }
    }

    @Published var languageHintCode: String {
        didSet { persist() }
    }

    @Published private(set) var readinessRevision: Int = 0
    @Published private var modelOperationStates: [String: ModelOperationState]

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private var whisperModelFolders: [String: String]
    private var modelOperationTasks: [String: Task<Void, Never>] = [:]

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private final class ProgressBridge: @unchecked Sendable {
        private weak var store: STTConfigurationStore?
        private let modelID: String

        init(store: STTConfigurationStore, modelID: String) {
            self.store = store
            self.modelID = modelID
        }

        func publish(
            fraction: Double,
            downloadedBytes: Int64? = nil,
            totalBytes: Int64? = nil,
            isEstimated: Bool = false
        ) {
            Task { @MainActor [weak store] in
                store?.updateInstallProgress(
                    for: modelID,
                    fraction: fraction,
                    downloadedBytes: downloadedBytes,
                    totalBytes: totalBytes,
                    isEstimated: isEstimated
                )
            }
        }
    }

    private struct ModelOperationState {
        var activity: ModelInstallRowState.Activity = .idle
        var progressFraction: Double?
        var downloadedBytes: Int64?
        var totalBytes: Int64?
        var isEstimated = false
        var error: String?
    }

    private enum Keys {
        static let selectedModelID = "stt.selectedModelID"
        static let languageHintCode = "stt.languageHintCode"
        static let whisperModelFolders = "stt.whisperModelFolders"

        static let legacyBackend = "echotype.backend"
        static let legacySelectedModelFileName = "whisper.selectedModelFileName"
        static let legacyQwenModelName = "qwen.modelName"
    }

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        modelOperationStates = [:]

        STTPathResolver.configureSpeechSwiftEnvironment(fileManager: fileManager)

        let migratedSelection = STTModelOption.migratedSelection(
            selectedModelID: defaults.string(forKey: Keys.selectedModelID),
            legacyBackend: defaults.string(forKey: Keys.legacyBackend),
            legacyWhisperFileName: defaults.string(forKey: Keys.legacySelectedModelFileName),
            legacyQwenModelName: defaults.string(forKey: Keys.legacyQwenModelName)
        )

        selectedModelID = migratedSelection.rawValue
        languageHintCode = defaults.string(forKey: Keys.languageHintCode) ?? "auto"
        whisperModelFolders = defaults.dictionary(forKey: Keys.whisperModelFolders) as? [String: String] ?? [:]

        persist()
        advanceReadinessRevision()
    }

    deinit {
        modelOperationTasks.values.forEach { $0.cancel() }
    }

    var selectedModel: STTModelOption {
        STTModelOption(rawValue: selectedModelID) ?? .default
    }

    var languageHint: STTLanguageHint {
        STTLanguageHint.fromTranscriptionLanguageCode(languageHintCode) ?? .auto
    }

    func makeConfiguration() -> STTConfiguration {
        STTConfiguration(
            selectedModel: selectedModel,
            languageHint: languageHint,
            whisperModelFolder: whisperModelFolders[selectedModel.id],
            isModelInstalled: isModelInstalled(selectedModel)
        )
    }

    var readinessText: String {
        guard isModelInstalled(selectedModel) else {
            return L10n.text(L10nKey.sttSelectedModelNotInstalledFormat, selectedModel.title)
        }
        return L10n.text(L10nKey.sttReady)
    }

    func installState(for model: STTModelOption) -> ModelInstallRowState {
        let operation = modelOperationStates[model.id]
        return ModelInstallRowState(
            activity: operation?.activity ?? .idle,
            isInstalled: isModelInstalled(model),
            progressFraction: operation?.progressFraction,
            transferText: transferText(for: operation),
            error: operation?.error
        )
    }

    func isModelInstalled(_ model: STTModelOption) -> Bool {
        switch model.family {
        case .whisperKit:
            guard let storedPath = whisperModelFolders[model.id] else { return false }
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: storedPath, isDirectory: &isDirectory) && isDirectory.boolValue
        case .qwen3ASR:
            guard let modelID = model.qwenModelID,
                  let cacheDirectory = try? HuggingFaceDownloader.getCacheDirectory(for: modelID)
            else {
                return false
            }
            return HuggingFaceDownloader.weightsExist(in: cacheDirectory)
        }
    }

    func installModel(_ model: STTModelOption) {
        guard modelOperationTasks[model.id] == nil else { return }

        guard !isModelInstalled(model) else {
            clearModelOperationState(for: model)
            return
        }

        let task = Task { @MainActor [weak self] in
            if let self {
                await self.runInstall(model)
            }
        }
        modelOperationTasks[model.id] = task
    }

    func deleteModel(_ model: STTModelOption) {
        guard modelOperationTasks[model.id] == nil else { return }

        guard isModelInstalled(model) else {
            clearModelOperationState(for: model)
            return
        }

        let task = Task { @MainActor [weak self] in
            if let self {
                await self.runDelete(model)
            }
        }
        modelOperationTasks[model.id] = task
    }

    func revealModelInFinder(_ model: STTModelOption) {
        guard let location = installedLocation(for: model) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([location])
    }

    func installSelectedModel() {
        installModel(selectedModel)
    }

    func deleteSelectedModel() {
        deleteModel(selectedModel)
    }

    private func runInstall(_ model: STTModelOption) async {
        beginOperation(
            for: model,
            activity: .installing,
            initialTotalBytes: model.estimatedDownloadSizeBytes,
            isEstimated: model.estimatedDownloadSizeBytes != nil
        )

        defer {
            modelOperationTasks[model.id] = nil
        }

        do {
            switch model.family {
            case .whisperKit:
                try await installWhisperKitModel(model)
            case .qwen3ASR:
                try await installQwenModel(model)
            }

            persist()
            clearModelOperationState(for: model)

            if selectedModelID == model.id {
                advanceReadinessRevision()
            }
        } catch is CancellationError {
            clearModelOperationState(for: model)
        } catch {
            setOperationError(for: model, message: error.localizedDescription)
        }
    }

    private func runDelete(_ model: STTModelOption) async {
        beginOperation(for: model, activity: .deleting)

        defer {
            modelOperationTasks[model.id] = nil
        }

        do {
            switch model.family {
            case .whisperKit:
                guard let folder = whisperModelFolders[model.id] else {
                    throw STTEngineError.modelNotInstalled(model.title)
                }
                try await removeItemInBackground(at: URL(fileURLWithPath: folder, isDirectory: true))
                whisperModelFolders.removeValue(forKey: model.id)
                await WhisperKitRuntimeStore.shared.invalidate(model: model)
            case .qwen3ASR:
                guard let modelID = model.qwenModelID else {
                    throw STTEngineError.modelNotInstalled(model.title)
                }
                let cacheDirectory = try HuggingFaceDownloader.getCacheDirectory(for: modelID)
                if fileManager.fileExists(atPath: cacheDirectory.path) {
                    try await removeItemInBackground(at: cacheDirectory)
                }
                await Qwen3ASRRuntimeStore.shared.invalidate(model: model)
            }

            persist()
            clearModelOperationState(for: model)

            if selectedModelID == model.id {
                advanceReadinessRevision()
            }
        } catch is CancellationError {
            clearModelOperationState(for: model)
        } catch {
            let message = L10n.text(
                L10nKey.sttDeleteFailedWithDetailFormat,
                model.title,
                error.localizedDescription
            )
            setOperationError(for: model, message: message)
        }
    }

    private func installWhisperKitModel(_ model: STTModelOption) async throws {
        guard let variant = model.whisperVariant else {
            throw STTEngineError.modelNotInstalled(model.title)
        }

        let downloadBase = try STTPathResolver.whisperDownloadBase(fileManager: fileManager)
        let progressBridge = ProgressBridge(store: self, modelID: model.id)
        let modelFolder = try await WhisperKit.download(
            variant: variant,
            downloadBase: downloadBase,
            progressCallback: Self.makeWhisperProgressCallback(progressBridge)
        )
        whisperModelFolders[model.id] = modelFolder.path
    }

    private func installQwenModel(_ model: STTModelOption) async throws {
        guard let modelID = model.qwenModelID else {
            throw STTEngineError.modelNotInstalled(model.title)
        }

        let cacheDirectory = try HuggingFaceDownloader.getCacheDirectory(for: modelID)
        let progressBridge = ProgressBridge(store: self, modelID: model.id)
        try await HuggingFaceDownloader.downloadWeights(
            modelId: modelID,
            to: cacheDirectory,
            additionalFiles: ["vocab.json", "merges.txt", "tokenizer_config.json"],
            progressHandler: Self.makeQwenProgressCallback(
                progressBridge,
                estimatedTotalBytes: model.estimatedDownloadSizeBytes
            )
        )
    }

    nonisolated private static func makeWhisperProgressCallback(_ bridge: ProgressBridge) -> (Progress) -> Void {
        { progress in
            let totalUnitCount = progress.totalUnitCount > 0 ? progress.totalUnitCount : 0
            let completedUnitCount = progress.completedUnitCount > 0 ? progress.completedUnitCount : 0
            bridge.publish(
                fraction: progress.fractionCompleted,
                downloadedBytes: completedUnitCount > 0 ? completedUnitCount : nil,
                totalBytes: totalUnitCount > 0 ? totalUnitCount : nil,
                isEstimated: false
            )
        }
    }

    nonisolated private static func makeQwenProgressCallback(
        _ bridge: ProgressBridge,
        estimatedTotalBytes: Int64?
    ) -> (Double) -> Void {
        { fraction in
            let totalBytes = estimatedTotalBytes
            let downloadedBytes = totalBytes.map { Int64(Double($0) * fraction) }
            bridge.publish(
                fraction: fraction,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                isEstimated: totalBytes != nil
            )
        }
    }

    private func beginOperation(
        for model: STTModelOption,
        activity: ModelInstallRowState.Activity,
        initialTotalBytes: Int64? = nil,
        isEstimated: Bool = false
    ) {
        modelOperationStates[model.id] = ModelOperationState(
            activity: activity,
            progressFraction: activity == .installing ? 0 : nil,
            downloadedBytes: activity == .installing ? 0 : nil,
            totalBytes: initialTotalBytes,
            isEstimated: isEstimated,
            error: nil
        )
    }

    private func updateInstallProgress(
        for modelID: String,
        fraction: Double,
        downloadedBytes: Int64?,
        totalBytes: Int64?,
        isEstimated: Bool
    ) {
        var state = modelOperationStates[modelID] ?? ModelOperationState(activity: .installing)
        state.activity = .installing
        state.progressFraction = max(0, min(fraction, 1))
        if let downloadedBytes {
            state.downloadedBytes = max(0, downloadedBytes)
        }
        if let totalBytes {
            state.totalBytes = max(0, totalBytes)
        }
        state.isEstimated = isEstimated
        state.error = nil
        modelOperationStates[modelID] = state
    }

    private func clearModelOperationState(for model: STTModelOption) {
        modelOperationStates.removeValue(forKey: model.id)
    }

    private func setOperationError(for model: STTModelOption, message: String) {
        var state = modelOperationStates[model.id] ?? ModelOperationState()
        state.activity = .idle
        state.progressFraction = nil
        state.downloadedBytes = nil
        state.totalBytes = nil
        state.isEstimated = false
        state.error = message
        modelOperationStates[model.id] = state
    }

    private func transferText(for operation: ModelOperationState?) -> String? {
        guard let operation,
              let totalBytes = operation.totalBytes
        else {
            return nil
        }

        let downloadedBytes = min(operation.downloadedBytes ?? 0, totalBytes)
        let downloadedText = Self.byteCountFormatter.string(fromByteCount: downloadedBytes)
        let totalText = Self.byteCountFormatter.string(fromByteCount: totalBytes)
        let prefix = operation.isEstimated ? "~" : ""
        return "\(prefix)\(downloadedText) / \(prefix)\(totalText)"
    }

    private func installedLocation(for model: STTModelOption) -> URL? {
        switch model.family {
        case .whisperKit:
            guard let folder = whisperModelFolders[model.id] else { return nil }
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                return nil
            }
            return url
        case .qwen3ASR:
            guard let modelID = model.qwenModelID,
                  let cacheDirectory = try? HuggingFaceDownloader.getCacheDirectory(for: modelID),
                  HuggingFaceDownloader.weightsExist(in: cacheDirectory)
            else {
                return nil
            }
            return cacheDirectory
        }
    }

    private func persist() {
        defaults.set(selectedModelID, forKey: Keys.selectedModelID)
        defaults.set(languageHint.transcriptionLanguageCode, forKey: Keys.languageHintCode)
        defaults.set(whisperModelFolders, forKey: Keys.whisperModelFolders)
    }

    private func advanceReadinessRevision() {
        readinessRevision &+= 1
    }

    private func removeItemInBackground(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try FileManager.default.removeItem(at: url)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
