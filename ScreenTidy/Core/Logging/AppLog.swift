import Foundation
import OSLog

/// Centralized logging. Prefer categories over ad-hoc print().
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.screentidy.app"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let navigation = Logger(subsystem: subsystem, category: "navigation")
    static let data = Logger(subsystem: subsystem, category: "data")
    /// Reserved for later sprints (Photos, OCR, AI, Search).
    static let photos = Logger(subsystem: subsystem, category: "photos")
    static let ocr = Logger(subsystem: subsystem, category: "ocr")
    static let organization = Logger(subsystem: subsystem, category: "organization")
    static let search = Logger(subsystem: subsystem, category: "search")
}
