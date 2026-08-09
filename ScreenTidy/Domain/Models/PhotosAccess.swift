import Foundation

/// Product-level Photos authorization state. `.readWrite` is intentionally requested:
/// it is the only PhotoKit level that can enumerate, read, and delete existing assets
/// (user-confirmed deletes). `.addOnly` cannot power ScreenTidy's library.
enum PhotosAccessStatus: String, Sendable {
    case notDetermined
    case full
    case limited
    case denied

    /// Settings trailing copy — Sprint 2 mock only.
    var settingsLabel: String {
        switch self {
        case .full: return "Full Access"
        case .limited: return "Limited Access"
        case .denied: return "Access Off"
        case .notDetermined: return "Not connected"
        }
    }
}

typealias MockPhotosAccess = PhotosAccessStatus
