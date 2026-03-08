import Darwin
import Foundation

enum STTPathResolverError: LocalizedError {
    case applicationSupportDirectoryUnavailable
    case cachesDirectoryUnavailable
    case environmentConfigurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return "Application Support directory is unavailable."
        case .cachesDirectoryUnavailable:
            return "Caches directory is unavailable."
        case .environmentConfigurationFailed(let message):
            return "Failed to configure speech runtime environment: \(message)"
        }
    }
}

enum STTPathResolver {
    static func applicationSupportRoot(fileManager: FileManager = .default) throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw STTPathResolverError.applicationSupportDirectoryUnavailable
        }
        let root = appSupport.appendingPathComponent("echotype", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func cachesRoot(fileManager: FileManager = .default) throws -> URL {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw STTPathResolverError.cachesDirectoryUnavailable
        }
        let root = caches.appendingPathComponent("echotype", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func whisperDownloadBase(fileManager: FileManager = .default) throws -> URL {
        let base = try applicationSupportRoot(fileManager: fileManager)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("whisperkit", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func qwenCacheRoot(fileManager: FileManager = .default) throws -> URL {
        let base = try cachesRoot(fileManager: fileManager)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func configureSpeechSwiftEnvironment(fileManager: FileManager = .default) {
        do {
            let root = try qwenCacheRoot(fileManager: fileManager)
            guard setenv("QWEN3_CACHE_DIR", root.path, 1) == 0 else {
                let reason = String(cString: strerror(errno))
                throw STTPathResolverError.environmentConfigurationFailed(reason)
            }
        } catch {
            AppLogger.stt.error("Speech runtime environment configuration failed: \(error.localizedDescription)")
        }
    }
}
