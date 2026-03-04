import Foundation

enum QwenASRModelPreset: String, CaseIterable, Identifiable {
    case model0_6B = "Qwen/Qwen3-ASR-0.6B"
    case model1_7B = "Qwen/Qwen3-ASR-1.7B"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model0_6B:
            return "Qwen3-ASR-0.6B"
        case .model1_7B:
            return "Qwen3-ASR-1.7B"
        }
    }

    var approximateSizeText: String {
        switch self {
        case .model0_6B:
            return "0.6B"
        case .model1_7B:
            return "1.7B"
        }
    }

    var cacheDirectoryName: String {
        switch self {
        case .model0_6B:
            return "Qwen3-ASR-0.6B"
        case .model1_7B:
            return "Qwen3-ASR-1.7B"
        }
    }
}

enum QwenCLIError: LocalizedError {
    case executableNotFound
    case modelNotInstalled(String)
    case runtimeDirectoryUnavailable
    case commandFailed(command: String, code: Int32, stderr: String)

    var errorDescription: String? {
        let language = AppLanguage.current()
        switch self {
        case .executableNotFound:
            return L10n.text(L10nKey.errorQwenExecutableNotAvailable, language: language)
        case let .modelNotInstalled(modelName):
            return L10n.text(L10nKey.errorQwenModelNotInstalledFormat, language: language, modelName)
        case .runtimeDirectoryUnavailable:
            return L10n.text(L10nKey.errorQwenRuntimeDirectoryUnavailable, language: language)
        case let .commandFailed(command, code, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return L10n.text(L10nKey.errorCommandFailedNoDetailFormat, language: language, code, command)
            }
            return L10n.text(L10nKey.errorCommandFailedWithDetailFormat, language: language, code, command, detail)
        }
    }
}

private struct QwenCommandResult {
    let terminationStatus: Int32
    let stdout: String
    let stderr: String
}

@MainActor
final class QwenCLIService: ObservableObject {
    @Published var selectedPreset: QwenASRModelPreset = .model0_6B

    @Published private(set) var qwenCLIPath: String?
    @Published private(set) var isRuntimeInstalled = false
    @Published private(set) var runtimeStatusText = L10n.text(L10nKey.qwenRuntimeNotDetected)
    @Published private(set) var runtimeErrorText: String?

    @Published private(set) var isInstallingModel = false
    @Published private(set) var modelInstallStatus = L10n.text(L10nKey.qwenModelNotInstalled)
    @Published private(set) var modelInstallError: String?

    private let fileManager = FileManager.default
    private var modelInstallProcess: Process?

    init() {
        refreshEnvironment()
    }

    deinit {
        modelInstallProcess?.terminate()
    }

    func refreshEnvironment() {
        qwenCLIPath = resolveQwenCLIPath()
        isRuntimeInstalled = qwenCLIPath != nil
        runtimeErrorText = nil
        if let qwenCLIPath {
            runtimeStatusText = L10n.text(L10nKey.qwenRuntimeDetectedFormat, qwenCLIPath)
        } else {
            runtimeStatusText = L10n.text(L10nKey.qwenRuntimeNotDetected)
        }
    }

    func installSelectedModel() async {
        guard !isInstallingModel else { return }

        refreshEnvironment()
        guard let qwenCLIPath else {
            modelInstallStatus = L10n.text(L10nKey.qwenInstallFailed)
            modelInstallError = QwenCLIError.executableNotFound.localizedDescription
            return
        }

        let installPreset = selectedPreset
        isInstallingModel = true
        modelInstallError = nil
        modelInstallStatus = L10n.text(L10nKey.qwenInstallingFormat, installPreset.title)

        defer {
            isInstallingModel = false
            modelInstallProcess = nil
        }

        do {
            let modelsRoot = try Self.qwenModelsBaseDirectoryURL(
                fileManager: fileManager,
                createIfMissing: true
            )
            let command = "\(qwenCLIPath) install-model --model \(installPreset.rawValue) --target-dir \(modelsRoot.path)"
            let result = try await runCommand(
                executablePath: qwenCLIPath,
                arguments: [
                    "install-model",
                    "--model", installPreset.rawValue,
                    "--target-dir", modelsRoot.path,
                ]
            )

            guard result.terminationStatus == 0 else {
                let detail = Self.importantError(stderr: result.stderr, stdout: result.stdout)
                throw QwenCLIError.commandFailed(
                    command: command,
                    code: result.terminationStatus,
                    stderr: detail
                )
            }

            guard isModelInstalled(modelIdentifier: installPreset.rawValue) else {
                throw QwenCLIError.modelNotInstalled(installPreset.title)
            }

            modelInstallStatus = L10n.text(L10nKey.qwenInstalledFormat, installPreset.title)
            modelInstallError = nil
        } catch {
            modelInstallStatus = L10n.text(L10nKey.qwenInstallFailed)
            modelInstallError = error.localizedDescription
        }
    }

    func uninstallSelectedModel() {
        guard !isInstallingModel else { return }
        modelInstallError = nil

        guard let localModelDirectory = Self.installedLocalModelCacheDirectory(
            for: selectedPreset,
            fileManager: fileManager
        ) else {
            modelInstallStatus = L10n.text(L10nKey.qwenModelNotInstalled)
            return
        }

        do {
            try fileManager.removeItem(at: localModelDirectory)
            modelInstallStatus = L10n.text(L10nKey.qwenUninstalledFormat, selectedPreset.title)
        } catch {
            modelInstallStatus = L10n.text(L10nKey.qwenUninstallFailed)
            modelInstallError = error.localizedDescription
        }
    }

    func isModelInstalled(modelIdentifier: String?) -> Bool {
        let trimmed = modelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIdentifier: String
        if let trimmed, !trimmed.isEmpty {
            resolvedIdentifier = trimmed
        } else {
            resolvedIdentifier = selectedPreset.rawValue
        }

        if let preset = QwenASRModelPreset(rawValue: resolvedIdentifier) {
            guard let localDirectory = Self.installedLocalModelCacheDirectory(
                for: preset,
                fileManager: fileManager
            ) else {
                return false
            }
            return Self.isUsableModelDirectory(localDirectory, fileManager: fileManager)
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: resolvedIdentifier, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return Self.isUsableModelDirectory(
                URL(fileURLWithPath: resolvedIdentifier, isDirectory: true),
                fileManager: fileManager
            )
        }
        return false
    }

    nonisolated static func isUsableModelDirectory(
        _ directoryURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        let configExists = fileManager.fileExists(
            atPath: directoryURL.appendingPathComponent("config.json").path
        )
        let files = (try? fileManager.contentsOfDirectory(
            atPath: directoryURL.path
        )) ?? []
        let hasWeights = files.contains {
            $0.hasSuffix(".safetensors") || $0.hasSuffix(".bin") || $0.hasSuffix(".pth")
        }
        return configExists && hasWeights
    }

    nonisolated static func installedLocalModelCacheDirectory(
        for preset: QwenASRModelPreset,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let directory = try? modelCacheDirectory(for: preset, fileManager: fileManager, createIfMissing: false),
              isUsableModelDirectory(directory, fileManager: fileManager)
        else {
            return nil
        }
        return directory
    }

    nonisolated static func modelCacheDirectory(
        for preset: QwenASRModelPreset,
        fileManager: FileManager = .default,
        createIfMissing: Bool
    ) throws -> URL {
        let base = try qwenModelsBaseDirectoryURL(fileManager: fileManager, createIfMissing: createIfMissing)
        let modelDirectory = base.appendingPathComponent(preset.cacheDirectoryName, isDirectory: true)
        if createIfMissing {
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        }
        return modelDirectory
    }

    nonisolated static func qwenModelsBaseDirectoryURL(
        fileManager: FileManager = .default,
        createIfMissing: Bool
    ) throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw QwenCLIError.runtimeDirectoryUnavailable
        }
        let root = appSupport
            .appendingPathComponent("echotype", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("qwen", isDirectory: true)
        if createIfMissing {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    private func runCommand(
        executablePath: String,
        arguments: [String]
    ) async throws -> QwenCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { [weak self] proc in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

                Task { @MainActor [weak self] in
                    if self?.modelInstallProcess === proc {
                        self?.modelInstallProcess = nil
                    }
                }

                continuation.resume(
                    returning: QwenCommandResult(
                        terminationStatus: proc.terminationStatus,
                        stdout: stdoutText,
                        stderr: stderrText
                    )
                )
            }

            do {
                try process.run()
                modelInstallProcess = process
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func resolveQwenCLIPath() -> String? {
        if let env = ProcessInfo.processInfo.environment["QWEN_ASR_CLI_PATH"],
           fileManager.isExecutableFile(atPath: env) {
            return env
        }

        let candidates = [
            "/opt/homebrew/bin/qwen-asr",
            "/usr/local/bin/qwen-asr",
        ]
        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return path
        }

        return Self.which(named: "qwen-asr")
    }

    private static func which(named binary: String) -> String? {
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
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty else { return nil }
            return path
        } catch {
            return nil
        }
    }

    private static func importantError(stderr: String, stdout: String) -> String {
        let cleanedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedStderr.isEmpty {
            return cleanedStderr
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
