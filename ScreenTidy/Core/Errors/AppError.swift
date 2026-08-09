import Foundation

/// App-level errors. Feature-specific errors can nest or map into these for UI.
enum AppError: LocalizedError, Sendable, Equatable {
    case unavailable(feature: String)
    case cancelled
    case notFound
    case permissionDenied(resource: String)
    case underlying(message: String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let feature):
            return "\(feature) isn’t available yet."
        case .cancelled:
            return "Cancelled."
        case .notFound:
            return "We couldn’t find that memory."
        case .permissionDenied(let resource):
            return "ScreenTidy needs access to \(resource)."
        case .underlying(let message):
            return message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "You can enable access in Settings."
        case .unavailable:
            return "This arrives in a later update."
        default:
            return nil
        }
    }
}

/// Lightweight result wrapper for async ViewModel surfaces.
enum LoadState<Value: Equatable>: Equatable {
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)
}
