import Foundation

struct WhisperModelDownloadProgress: Sendable {
    let downloadedBytes: Int64
    let totalBytes: Int64
}

enum WhisperModelInstallerError: LocalizedError {
    case invalidResponse
    case serverStatus(Int)
    case downloadedFileEmpty
    case applicationSupportUnavailable
    case modelAlreadyInstalled(String)
    case downloadCancelled
    case commandFailed(command: String, code: Int32, stderr: String)

    var errorDescription: String? {
        let language = AppLanguage.current()
        switch self {
        case .invalidResponse:
            return L10n.text(L10nKey.errorInvalidModelDownloadResponse, language: language)
        case let .serverStatus(code):
            return L10n.text(L10nKey.errorModelDownloadFailedHttpFormat, language: language, code)
        case .downloadedFileEmpty:
            return L10n.text(L10nKey.errorDownloadedModelEmpty, language: language)
        case .applicationSupportUnavailable:
            return L10n.text(L10nKey.errorApplicationSupportUnavailable, language: language)
        case let .modelAlreadyInstalled(name):
            return L10n.text(L10nKey.errorModelAlreadyInstalledFormat, language: language, name)
        case .downloadCancelled:
            return L10n.text(L10nKey.errorModelDownloadCancelled, language: language)
        case let .commandFailed(command, code, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return L10n.text(L10nKey.errorCommandFailedNoDetailFormat, language: language, code, command)
            }
            return L10n.text(L10nKey.errorCommandFailedWithDetailFormat, language: language, code, command, detail)
        }
    }
}

struct WhisperModelInstallerService {
    private let fileManager: FileManager
    private let urlSession: URLSession

    init(
        fileManager: FileManager = .default,
        urlSession: URLSession = .shared
    ) {
        self.fileManager = fileManager
        self.urlSession = urlSession
    }

    func installModel(
        size: WhisperModelSize,
        language: WhisperModelLanguage,
        onProgress: (@Sendable (WhisperModelDownloadProgress) -> Void)? = nil
    ) async throws -> URL {
        let descriptor = WhisperModelCatalog.descriptor(size: size, language: language)
        let destinationDirectory = try Self.modelsDirectoryURL(fileManager: fileManager)
        let destinationURL = destinationDirectory.appendingPathComponent(descriptor.fileName)
        let partialURL = destinationURL.appendingPathExtension("part")

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw WhisperModelInstallerError.modelAlreadyInstalled(descriptor.fileName)
        }

        let totalBytes = (try? await remoteFileSize(from: descriptor.downloadURL)) ?? 0
        let initialBytes = fileSize(at: partialURL)
        onProgress?(WhisperModelDownloadProgress(downloadedBytes: initialBytes, totalBytes: totalBytes))

        do {
            try await runCurlDownload(
                sourceURL: descriptor.downloadURL,
                partialURL: partialURL,
                totalBytes: totalBytes,
                onProgress: onProgress
            )
        } catch is CancellationError {
            throw WhisperModelInstallerError.downloadCancelled
        }

        let partialFileSize = fileSize(at: partialURL)
        guard partialFileSize > 0 else {
            throw WhisperModelInstallerError.downloadedFileEmpty
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: partialURL, to: destinationURL)

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0 else {
            throw WhisperModelInstallerError.downloadedFileEmpty
        }

        onProgress?(WhisperModelDownloadProgress(downloadedBytes: fileSize, totalBytes: max(totalBytes, fileSize)))
        return destinationURL
    }

    static func modelsDirectoryPath(fileManager: FileManager = .default) throws -> String {
        try modelsDirectoryURL(fileManager: fileManager).path
    }

    static func modelsDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        guard let appSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw WhisperModelInstallerError.applicationSupportUnavailable
        }

        let directory = appSupportDirectory
            .appendingPathComponent("echotype", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("whisper", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func runCurlDownload(
        sourceURL: URL,
        partialURL: URL,
        totalBytes: Int64,
        onProgress: (@Sendable (WhisperModelDownloadProgress) -> Void)?
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-L",
            "--fail",
            "--continue-at", "-",
            "--output", partialURL.path,
            sourceURL.absoluteString,
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try await withTaskCancellationHandler(operation: {
            try process.run()

            while process.isRunning {
                try Task.checkCancellation()
                onProgress?(
                    WhisperModelDownloadProgress(
                        downloadedBytes: fileSize(at: partialURL),
                        totalBytes: totalBytes
                    )
                )
                try await Task.sleep(nanoseconds: 300_000_000)
            }

            process.waitUntilExit()

            let finalSize = fileSize(at: partialURL)
            onProgress?(WhisperModelDownloadProgress(downloadedBytes: finalSize, totalBytes: totalBytes))

            guard process.terminationStatus == 0 else {
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
                throw WhisperModelInstallerError.commandFailed(
                    command: "/usr/bin/curl",
                    code: process.terminationStatus,
                    stderr: stderrText
                )
            }
        }, onCancel: {
            if process.isRunning {
                process.terminate()
            }
        })
    }

    private func remoteFileSize(from url: URL) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 60

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperModelInstallerError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw WhisperModelInstallerError.serverStatus(httpResponse.statusCode)
        }

        if let lengthHeader = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let total = Int64(lengthHeader),
           total > 0 {
            return total
        }
        return 0
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return 0
        }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
