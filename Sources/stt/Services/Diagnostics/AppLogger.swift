import Foundation
@preconcurrency import OSLog

enum AppLogger {
    static let subsystem = "com.smoose.echotype"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let stt = Logger(subsystem: subsystem, category: "stt")
    static let injection = Logger(subsystem: subsystem, category: "injection")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
}
