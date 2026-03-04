import Foundation

@MainActor
final class WhisperConfigurationStore: ObservableObject {
    @Published var backend: STTBackend {
        didSet { persist() }
    }

    @Published var executablePath: String {
        didSet { persist() }
    }

    @Published var modelDirectoryPath: String {
        didSet {
            persist()
            refreshInstalledModels()
        }
    }

    @Published var selectedModelFileName: String {
        didSet { persist() }
    }

    @Published var language: String {
        didSet { persist() }
    }

    @Published var qwenCLIPath: String {
        didSet { persist() }
    }

    @Published var qwenModelName: String {
        didSet { persist() }
    }

    @Published var qwenLanguageHint: String {
        didSet { persist() }
    }

    @Published var selectedModelSize: WhisperModelSize {
        didSet { persist() }
    }

    @Published var selectedModelLanguage: WhisperModelLanguage {
        didSet { persist() }
    }

    @Published private(set) var isInstallingModel = false
    @Published private(set) var isModelInstallPaused = false
    @Published private(set) var modelInstallStatus: String
    @Published private(set) var modelInstallError: String?
    @Published private(set) var modelInstallDownloadedBytes: Int64
    @Published private(set) var modelInstallTotalBytes: Int64
    @Published private(set) var installedModels: [WhisperInstalledModel]

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private var modelInstallTask: Task<Void, Never>?
    private var modelInstallPauseRequested = false
    private var modelInstallCancellationRequested = false
    private var pausedModelDescriptor: WhisperModelDescriptor?

    private enum Keys {
        static let backend = "echotype.backend"
        static let executablePath = "whisper.executablePath"
        static let modelDirectoryPath = "whisper.modelDirectoryPath"
        static let selectedModelFileName = "whisper.selectedModelFileName"
        static let modelPath = "whisper.modelPath"
        static let language = "whisper.language"
        static let qwenCLIPath = "qwen.cliPath"
        static let qwenModelName = "qwen.modelName"
        static let qwenLanguageHint = "qwen.languageHint"
        static let selectedModelSize = "whisper.selectedModelSize"
        static let selectedModelLanguage = "whisper.selectedModelLanguage"
        static let modelInstallStatus = "whisper.modelInstallStatus"
    }

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        let detectedExecutable = WhisperConfiguration.detectExecutablePath() ?? ""
        let storedBackend = defaults.string(forKey: Keys.backend)
            .flatMap(STTBackend.init(rawValue:)) ?? .whisperCpp
        let storedSize = defaults.string(forKey: Keys.selectedModelSize)
            .flatMap(WhisperModelSize.init(rawValue:)) ?? .base
        let storedLanguage = defaults.string(forKey: Keys.language)
        let storedQwenCLIPath = defaults.string(forKey: Keys.qwenCLIPath)
        let storedQwenModelName = defaults.string(forKey: Keys.qwenModelName)
        let storedQwenLanguageHint = defaults.string(forKey: Keys.qwenLanguageHint)
        let legacyLanguage = defaults.string(forKey: Keys.language)
        let storedModelDirectoryPath = defaults.string(forKey: Keys.modelDirectoryPath)
        let storedSelectedModelFileName = defaults.string(forKey: Keys.selectedModelFileName)
        let legacyModelPath = defaults.string(forKey: Keys.modelPath)
        let migration = Self.migrateLegacyModelPath(
            legacyModelPath,
            fileManager: fileManager
        )

        let initialModelDirectoryPath = storedModelDirectoryPath?.nilIfEmpty ??
            migration.directoryPath ??
            (try? WhisperModelInstallerService.modelsDirectoryPath(fileManager: fileManager)) ??
            ""
        let initialSelectedModelFileName = storedSelectedModelFileName?.nilIfEmpty ??
            migration.fileName ??
            ""

        self.defaults = defaults
        self.fileManager = fileManager
        backend = storedBackend
        executablePath = defaults.string(forKey: Keys.executablePath) ?? detectedExecutable
        modelDirectoryPath = initialModelDirectoryPath
        selectedModelFileName = initialSelectedModelFileName
        language = WhisperTranscriptionLanguage
            .fromTranscriptionLanguageCode(storedLanguage ?? "auto")?
            .transcriptionLanguageCode ?? "auto"
        qwenCLIPath = storedQwenCLIPath ?? WhisperConfiguration.detectQwenCLIPath() ?? ""
        qwenModelName = storedQwenModelName ?? "Qwen/Qwen3-ASR-0.6B"
        qwenLanguageHint = QwenLanguageHint
            .fromPersistedCode(storedQwenLanguageHint ?? legacyLanguage ?? "auto")?
            .persistedCode ?? "auto"
        selectedModelSize = storedSize
        selectedModelLanguage = .chinese
        modelInstallStatus = defaults.string(forKey: Keys.modelInstallStatus) ?? L10n.text(L10nKey.whisperNoInAppInstallYet)
        modelInstallError = nil
        modelInstallDownloadedBytes = 0
        modelInstallTotalBytes = 0
        installedModels = []

        refreshInstalledModels()
    }

    deinit {
        modelInstallTask?.cancel()
    }

    var selectedModelPath: String? {
        guard let directoryPath = modelDirectoryPath.nilIfEmpty,
              let fileName = selectedModelFileName.nilIfEmpty
        else {
            return nil
        }
        return URL(fileURLWithPath: directoryPath)
            .appendingPathComponent(fileName)
            .path
    }

    func autoDetectExecutable() {
        executablePath = WhisperConfiguration.detectExecutablePath() ?? ""
    }

    func autoDetectQwenExecutable() {
        qwenCLIPath = WhisperConfiguration.detectQwenCLIPath() ?? ""
    }

    var isWhisperRuntimeInstalled: Bool {
        guard let executable = executablePath.nilIfEmpty else { return false }
        return fileManager.isExecutableFile(atPath: executable)
    }

    func makeConfiguration() -> WhisperConfiguration {
        WhisperConfiguration(
            backend: backend,
            executablePath: executablePath.nilIfEmpty,
            modelPath: selectedModelPath,
            language: language.nilIfEmpty ?? "auto",
            qwenCLIPath: qwenCLIPath.nilIfEmpty,
            qwenModelName: qwenModelName.nilIfEmpty ?? "Qwen/Qwen3-ASR-0.6B",
            qwenLanguageHint: qwenLanguageHint.nilIfEmpty ?? "auto"
        )
    }

    var readinessText: String {
        let configuration = makeConfiguration()
        if configuration.isReady {
            return L10n.text(L10nKey.whisperReady)
        }

        switch backend {
        case .whisperCpp:
            if executablePath.nilIfEmpty == nil {
                return L10n.text(L10nKey.whisperMissingExecutablePath)
            }

            if modelDirectoryPath.nilIfEmpty == nil {
                return L10n.text(L10nKey.whisperMissingModelDirectory)
            }

            if selectedModelFileName.nilIfEmpty == nil {
                return L10n.text(L10nKey.whisperMissingModelSelection)
            }
        case .qwen3ASRServer:
            if qwenCLIPath.nilIfEmpty == nil {
                return L10n.text(L10nKey.whisperMissingQwenExecutablePath)
            }

            if qwenModelName.nilIfEmpty == nil {
                return L10n.text(L10nKey.whisperMissingQwenModelName)
            }

            if QwenLanguageHint.fromPersistedCode(qwenLanguageHint) == nil {
                return L10n.text(L10nKey.whisperInvalidQwenLanguageHint)
            }
        }

        return L10n.text(L10nKey.whisperPathInvalid)
    }

    var selectedModelDescriptor: WhisperModelDescriptor {
        WhisperModelCatalog.descriptor(size: selectedModelSize, language: .chinese)
    }

    var recommendedModelDescriptor: WhisperModelDescriptor {
        let size = WhisperModelCatalog.recommendedSize(for: selectedModelLanguage)
        return WhisperModelCatalog.descriptor(size: size, language: .chinese)
    }

    var isSelectedModelDownloadInstalled: Bool {
        isModelInstalled(fileName: selectedModelDescriptor.fileName)
    }

    var isRecommendedModelDownloadInstalled: Bool {
        isModelInstalled(fileName: recommendedModelDescriptor.fileName)
    }

    var modelInstallProgressFraction: Double? {
        guard modelInstallTotalBytes > 0 else { return nil }
        return min(max(Double(modelInstallDownloadedBytes) / Double(modelInstallTotalBytes), 0), 1)
    }

    var modelInstallSizeText: String {
        let downloaded = Self.byteCountFormatter.string(fromByteCount: modelInstallDownloadedBytes)
        let total = modelInstallTotalBytes > 0
            ? Self.byteCountFormatter.string(fromByteCount: modelInstallTotalBytes)
            : "--"
        return "\(downloaded) / \(total)"
    }

    var canDeleteSelectedModel: Bool {
        guard !isInstallingModel, let selectedModelPath else { return false }
        return fileManager.fileExists(atPath: selectedModelPath)
    }

    func applyRecommendedModelPreset() {
        selectedModelSize = WhisperModelCatalog.recommendedSize(for: selectedModelLanguage)
    }

    func startInstallSelectedModel() {
        guard modelInstallTask == nil else { return }
        modelInstallTask = Task { [weak self] in
            guard let self else { return }
            await installSelectedModel()
            modelInstallTask = nil
        }
    }

    func cancelModelInstallation() {
        if isInstallingModel {
            modelInstallCancellationRequested = true
            modelInstallPauseRequested = false
            modelInstallStatus = L10n.text(L10nKey.whisperInstallCancelling)
            modelInstallTask?.cancel()
            return
        }

        guard isModelInstallPaused else { return }
        let descriptor = pausedModelDescriptor ?? selectedModelDescriptor
        removePartialDownload(for: descriptor)
        pausedModelDescriptor = nil
        isModelInstallPaused = false
        resetModelInstallProgress()
        modelInstallStatus = L10n.text(L10nKey.whisperInstallCancelledRemoved)
        modelInstallError = nil
        persist()
    }

    func pauseModelInstallation() {
        guard isInstallingModel else { return }
        modelInstallPauseRequested = true
        modelInstallCancellationRequested = false
        modelInstallStatus = L10n.text(L10nKey.whisperInstallPausing)
        modelInstallTask?.cancel()
    }

    func installSelectedModel() async {
        guard !isInstallingModel else { return }

        if isSelectedModelDownloadInstalled {
            resetModelInstallProgress()
            modelInstallStatus = L10n.text(L10nKey.whisperInstallAlreadyInstalled)
            modelInstallError = L10n.text(L10nKey.errorModelAlreadyInstalledFormat, selectedModelDescriptor.fileName)
            persist()
            return
        }

        isInstallingModel = true
        isModelInstallPaused = false
        modelInstallPauseRequested = false
        modelInstallCancellationRequested = false
        modelInstallError = nil
        if pausedModelDescriptor?.fileName != selectedModelDescriptor.fileName {
            resetModelInstallProgress()
        }

        let descriptor = selectedModelDescriptor
        modelInstallStatus = pausedModelDescriptor?.fileName == descriptor.fileName
            ? L10n.text(L10nKey.whisperInstallResumingFormat, descriptor.fileName)
            : L10n.text(L10nKey.whisperInstallDownloadingFormat, descriptor.fileName)
        pausedModelDescriptor = nil
        persist()

        defer { isInstallingModel = false }

        do {
            let installedModelURL = try await WhisperModelInstallerService().installModel(
                size: selectedModelSize,
                language: .chinese,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        modelInstallDownloadedBytes = progress.downloadedBytes
                        modelInstallTotalBytes = progress.totalBytes
                    }
                }
            )

            if let fileSize = (try? fileManager.attributesOfItem(atPath: installedModelURL.path)[.size] as? NSNumber)?
                .int64Value, fileSize > 0 {
                modelInstallDownloadedBytes = fileSize
                if modelInstallTotalBytes <= 0 {
                    modelInstallTotalBytes = fileSize
                }
            }

            modelDirectoryPath = installedModelURL.deletingLastPathComponent().path
            selectedModelFileName = installedModelURL.lastPathComponent
            if executablePath.nilIfEmpty == nil {
                autoDetectExecutable()
            }
            modelInstallStatus = L10n.text(L10nKey.whisperInstallInstalledFormat, installedModelURL.lastPathComponent)
            modelInstallError = nil
            isModelInstallPaused = false
            pausedModelDescriptor = nil
            persist()
        } catch let error as WhisperModelInstallerError {
            switch error {
            case .downloadCancelled:
                if modelInstallPauseRequested {
                    modelInstallStatus = L10n.text(L10nKey.whisperInstallPausedResume)
                    modelInstallError = nil
                    isModelInstallPaused = true
                    pausedModelDescriptor = descriptor
                } else if modelInstallCancellationRequested {
                    removePartialDownload(for: descriptor)
                    modelInstallStatus = L10n.text(L10nKey.whisperInstallCancelledRemoved)
                    modelInstallError = nil
                    isModelInstallPaused = false
                    pausedModelDescriptor = nil
                    resetModelInstallProgress()
                } else {
                    modelInstallStatus = L10n.text(L10nKey.whisperInstallInterruptedResume)
                    modelInstallError = nil
                    isModelInstallPaused = true
                    pausedModelDescriptor = descriptor
                }
            default:
                modelInstallStatus = L10n.text(L10nKey.whisperInstallFailed)
                modelInstallError = error.localizedDescription
                isModelInstallPaused = false
            }
            persist()
        } catch is CancellationError {
            if modelInstallPauseRequested {
                modelInstallStatus = L10n.text(L10nKey.whisperInstallPausedResume)
                modelInstallError = nil
                isModelInstallPaused = true
                pausedModelDescriptor = descriptor
            } else if modelInstallCancellationRequested {
                removePartialDownload(for: descriptor)
                modelInstallStatus = L10n.text(L10nKey.whisperInstallCancelledRemoved)
                modelInstallError = nil
                isModelInstallPaused = false
                pausedModelDescriptor = nil
                resetModelInstallProgress()
            } else {
                modelInstallStatus = L10n.text(L10nKey.whisperInstallInterruptedResume)
                modelInstallError = nil
                isModelInstallPaused = true
                pausedModelDescriptor = descriptor
            }
            persist()
        } catch {
            modelInstallStatus = L10n.text(L10nKey.whisperInstallFailed)
            modelInstallError = error.localizedDescription
            isModelInstallPaused = false
            persist()
        }
    }

    func installRecommendedModel() async {
        if isRecommendedModelDownloadInstalled {
            resetModelInstallProgress()
            modelInstallStatus = L10n.text(L10nKey.whisperInstallRecommendedAlreadyInstalled)
            modelInstallError = L10n.text(L10nKey.errorModelAlreadyInstalledFormat, recommendedModelDescriptor.fileName)
            persist()
            return
        }
        applyRecommendedModelPreset()
        await installSelectedModel()
    }

    func deleteSelectedModel() {
        guard !isInstallingModel else { return }

        guard let selectedModelPath,
              let selectedModelFileName = selectedModelFileName.nilIfEmpty
        else {
            modelInstallStatus = L10n.text(L10nKey.whisperDeleteFailed)
            modelInstallError = L10n.text(L10nKey.whisperDeleteNoSelection)
            persist()
            return
        }

        do {
            try fileManager.removeItem(atPath: selectedModelPath)
            modelInstallStatus = L10n.text(L10nKey.whisperDeleteDeletedFormat, selectedModelFileName)
            modelInstallError = nil
            refreshInstalledModels()
            persist()
        } catch {
            modelInstallStatus = L10n.text(L10nKey.whisperDeleteFailed)
            modelInstallError = L10n.text(
                L10nKey.whisperDeleteFailedWithDetailFormat,
                selectedModelFileName,
                error.localizedDescription
            )
            persist()
        }
    }

    private func refreshInstalledModels() {
        guard let directoryPath = modelDirectoryPath.nilIfEmpty else {
            installedModels = []
            if !selectedModelFileName.isEmpty {
                selectedModelFileName = ""
            }
            return
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            installedModels = []
            if !selectedModelFileName.isEmpty {
                selectedModelFileName = ""
            }
            return
        }

        let fileNames = (try? fileManager.contentsOfDirectory(atPath: directoryPath))?
            .filter { $0.hasSuffix(".bin") }
            .sorted() ?? []

        installedModels = fileNames.map { WhisperInstalledModel(fileName: $0) }

        if fileNames.isEmpty {
            if !selectedModelFileName.isEmpty {
                selectedModelFileName = ""
            }
            return
        }

        if fileNames.contains(selectedModelFileName) {
            return
        }

        if fileNames.contains(selectedModelDescriptor.fileName) {
            selectedModelFileName = selectedModelDescriptor.fileName
        } else {
            selectedModelFileName = fileNames[0]
        }
    }

    private func isModelInstalled(fileName: String) -> Bool {
        guard let directoryPath = modelDirectoryPath.nilIfEmpty else { return false }
        let targetPath = URL(fileURLWithPath: directoryPath)
            .appendingPathComponent(fileName)
            .path
        return fileManager.fileExists(atPath: targetPath)
    }

    private static func migrateLegacyModelPath(
        _ legacyModelPath: String?,
        fileManager: FileManager
    ) -> (directoryPath: String?, fileName: String?) {
        guard let legacyModelPath else { return (nil, nil) }
        let trimmed = legacyModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: trimmed, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return (trimmed, nil)
            }
            return (
                URL(fileURLWithPath: trimmed).deletingLastPathComponent().path,
                URL(fileURLWithPath: trimmed).lastPathComponent
            )
        }

        if trimmed.hasSuffix(".bin") {
            return (
                URL(fileURLWithPath: trimmed).deletingLastPathComponent().path,
                URL(fileURLWithPath: trimmed).lastPathComponent
            )
        }

        return (trimmed, nil)
    }

    private func resetModelInstallProgress() {
        modelInstallDownloadedBytes = 0
        modelInstallTotalBytes = 0
    }

    private func removePartialDownload(for descriptor: WhisperModelDescriptor) {
        guard let modelsDirectory = try? WhisperModelInstallerService.modelsDirectoryPath(fileManager: fileManager) else {
            return
        }

        let partialPath = URL(fileURLWithPath: modelsDirectory)
            .appendingPathComponent(descriptor.fileName)
            .appendingPathExtension("part")
            .path

        if fileManager.fileExists(atPath: partialPath) {
            try? fileManager.removeItem(atPath: partialPath)
        }
    }

    private func persist() {
        defaults.set(backend.rawValue, forKey: Keys.backend)
        defaults.set(executablePath, forKey: Keys.executablePath)
        defaults.set(modelDirectoryPath, forKey: Keys.modelDirectoryPath)
        defaults.set(selectedModelFileName, forKey: Keys.selectedModelFileName)
        defaults.set(selectedModelPath ?? "", forKey: Keys.modelPath)
        defaults.set(language, forKey: Keys.language)
        defaults.set(qwenCLIPath, forKey: Keys.qwenCLIPath)
        defaults.set(qwenModelName, forKey: Keys.qwenModelName)
        defaults.set(qwenLanguageHint, forKey: Keys.qwenLanguageHint)
        defaults.set(selectedModelSize.rawValue, forKey: Keys.selectedModelSize)
        defaults.set(selectedModelLanguage.rawValue, forKey: Keys.selectedModelLanguage)
        defaults.set(modelInstallStatus, forKey: Keys.modelInstallStatus)
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
