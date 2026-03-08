@preconcurrency import AudioCommon
import Foundation
@preconcurrency import Qwen3ASR
@preconcurrency import WhisperKit

@MainActor
final class STTConfigurationStore: ObservableObject {
    @Published var selectedModelID: String {
        didSet {
            persist()
            refreshModelInstallStatus()
            scheduleBackgroundPreloadIfNeeded()
        }
    }

    @Published var languageHintCode: String {
        didSet { persist() }
    }

    @Published private(set) var isInstallingModel = false
    @Published private(set) var modelInstallStatus: String
    @Published private(set) var modelInstallError: String?
    @Published private(set) var modelInstallProgressFraction: Double?
    @Published private(set) var modelInstallDownloadedBytes: Int64?
    @Published private(set) var modelInstallTotalBytes: Int64?
    @Published private(set) var readinessRevision: Int = 0

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private var whisperModelFolders: [String: String]
    private var installProgressIsEstimated = false
    private var backgroundPreloadTask: Task<Void, Never>?

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

        init(store: STTConfigurationStore) {
            self.store = store
        }

        func publish(
            fraction: Double,
            downloadedBytes: Int64? = nil,
            totalBytes: Int64? = nil,
            isEstimated: Bool = false
        ) {
            Task { @MainActor [weak store] in
                store?.updateInstallProgress(
                    fraction: fraction,
                    downloadedBytes: downloadedBytes,
                    totalBytes: totalBytes,
                    isEstimated: isEstimated
                )
            }
        }
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
        modelInstallStatus = ""
        modelInstallError = nil
        modelInstallProgressFraction = nil
        modelInstallDownloadedBytes = nil
        modelInstallTotalBytes = nil

        persist()
        refreshModelInstallStatus()
        scheduleBackgroundPreloadIfNeeded()
    }

    deinit {
        backgroundPreloadTask?.cancel()
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

    var modelInstallTransferText: String? {
        guard let totalBytes = modelInstallTotalBytes else { return nil }
        let downloadedBytes = min(modelInstallDownloadedBytes ?? 0, totalBytes)
        let downloadedText = Self.byteCountFormatter.string(fromByteCount: downloadedBytes)
        let totalText = Self.byteCountFormatter.string(fromByteCount: totalBytes)
        let prefix = installProgressIsEstimated ? "~" : ""
        return "\(prefix)\(downloadedText) / \(prefix)\(totalText)"
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

    func installSelectedModel() async {
        guard !isInstallingModel else { return }
        let model = selectedModel

        if isModelInstalled(model) {
            modelInstallError = nil
            modelInstallProgressFraction = 1
            modelInstallStatus = L10n.text(L10nKey.sttInstalledFormat, model.title)
            advanceReadinessRevision()
            return
        }

        isInstallingModel = true
        modelInstallError = nil
        updateInstallProgress(
            fraction: 0,
            downloadedBytes: 0,
            totalBytes: model.estimatedDownloadSizeBytes,
            isEstimated: model.estimatedDownloadSizeBytes != nil
        )
        modelInstallStatus = L10n.text(L10nKey.sttInstallingFormat, model.title)

        do {
            switch model.family {
            case .whisperKit:
                try await installWhisperKitModel(model)
            case .qwen3ASR:
                try await installQwenModel(model)
            }

            persist()

            let configuration = makeConfiguration()
            if configuration.isModelInstalled {
                modelInstallStatus = L10n.text(L10nKey.sttLoadingFormat, model.title)
                do {
                    try await preloadModel(configuration)
                } catch is CancellationError {
                    AppLogger.stt.info("Model preload cancelled after install: \(model.title, privacy: .public)")
                } catch {
                    AppLogger.stt.error("Model preload failed after install: \(error.localizedDescription)")
                    modelInstallError = error.localizedDescription
                }
            }

            if let totalBytes = modelInstallTotalBytes {
                updateInstallProgress(
                    fraction: 1,
                    downloadedBytes: totalBytes,
                    totalBytes: totalBytes,
                    isEstimated: installProgressIsEstimated
                )
            } else {
                modelInstallProgressFraction = 1
            }
            modelInstallStatus = L10n.text(L10nKey.sttInstalledFormat, model.title)
            advanceReadinessRevision()
        } catch {
            clearInstallProgress()
            modelInstallStatus = L10n.text(L10nKey.sttInstallFailed)
            modelInstallError = error.localizedDescription
        }

        isInstallingModel = false
    }

    func deleteSelectedModel() async {
        let model = selectedModel
        guard !isInstallingModel else { return }

        isInstallingModel = true
        modelInstallError = nil
        clearInstallProgress()
        modelInstallStatus = L10n.text(L10nKey.sttDeletingFormat, model.title)

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
            modelInstallError = nil
            clearInstallProgress()
            modelInstallStatus = L10n.text(L10nKey.sttDeletedFormat, model.title)
            advanceReadinessRevision()
        } catch {
            modelInstallError = L10n.text(L10nKey.sttDeleteFailedWithDetailFormat, model.title, error.localizedDescription)
        }

        isInstallingModel = false
        refreshModelInstallStatus()
    }

    private func installWhisperKitModel(_ model: STTModelOption) async throws {
        guard let variant = model.whisperVariant else {
            throw STTEngineError.modelNotInstalled(model.title)
        }

        let downloadBase = try STTPathResolver.whisperDownloadBase(fileManager: fileManager)
        let progressBridge = ProgressBridge(store: self)
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
        let progressBridge = ProgressBridge(store: self)
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

    private func updateInstallProgress(
        fraction: Double,
        downloadedBytes: Int64?,
        totalBytes: Int64?,
        isEstimated: Bool
    ) {
        modelInstallProgressFraction = max(0, min(fraction, 1))
        if let downloadedBytes {
            modelInstallDownloadedBytes = max(0, downloadedBytes)
        }
        if let totalBytes {
            modelInstallTotalBytes = max(0, totalBytes)
        }
        installProgressIsEstimated = isEstimated
    }

    private func clearInstallProgress() {
        modelInstallProgressFraction = nil
        modelInstallDownloadedBytes = nil
        modelInstallTotalBytes = nil
        installProgressIsEstimated = false
    }

    private func scheduleBackgroundPreloadIfNeeded() {
        backgroundPreloadTask?.cancel()

        let configuration = makeConfiguration()
        guard configuration.isModelInstalled else { return }

        backgroundPreloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.preloadModel(configuration)
                AppLogger.stt.info("Background preload succeeded: \(configuration.selectedModel.title, privacy: .public)")
            } catch is CancellationError {
                AppLogger.stt.info("Background preload cancelled: \(configuration.selectedModel.title, privacy: .public)")
            } catch {
                AppLogger.stt.error("Background preload failed: \(error.localizedDescription)")
            }
        }
    }

    private func preloadModel(_ configuration: STTConfiguration) async throws {
        let sttService = STTService(configuration: configuration)
        try await sttService.preload()
    }

    private func persist() {
        defaults.set(selectedModelID, forKey: Keys.selectedModelID)
        defaults.set(languageHint.transcriptionLanguageCode, forKey: Keys.languageHintCode)
        defaults.set(whisperModelFolders, forKey: Keys.whisperModelFolders)
    }

    private func refreshModelInstallStatus() {
        guard !isInstallingModel else { return }
        modelInstallError = nil
        clearInstallProgress()
        modelInstallStatus = isModelInstalled(selectedModel)
            ? L10n.text(L10nKey.sttInstalledFormat, selectedModel.title)
            : L10n.text(L10nKey.sttSelectedModelNotInstalledFormat, selectedModel.title)
        advanceReadinessRevision()
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
