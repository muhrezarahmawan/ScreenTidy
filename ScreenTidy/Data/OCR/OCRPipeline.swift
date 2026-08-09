import CoreGraphics
import Foundation

/// Sprint 5 OCR pipeline configuration. Bump `currentVersion` when recognition settings,
/// preprocessing, language handling, or text normalization change — stale rows requeue.
enum OCRPipeline {
    /// Pipeline / config version (not app CFBundle version).
    static let currentVersion = 1

    /// Long-edge pixel budget for Vision input (not full-resolution Photos originals).
    static let imageLongEdge: CGFloat = 1_800

    /// Max concurrent Vision jobs — do not scale with library size.
    static let maxConcurrency = 2

    /// `processing` claims older than this are recovered on launch.
    static let staleClaimInterval: TimeInterval = 5 * 60

    static let maxAttempts = 8

    static let confidenceFloor: Float = 0.3

    static func retryDelay(afterAttempt attempt: Int) -> TimeInterval {
        let base: TimeInterval = 30
        let delay = base * pow(2.0, Double(max(0, attempt - 1)))
        return min(delay, 3_600)
    }

    /// Searchable representation derived from raw OCR (Sprint 6 may evolve independently).
    static func normalizedForSearch(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OCRResult: Sendable, Equatable {
    /// Raw extracted text; empty string means "no text detected" (valid success).
    var text: String
    var language: String?
}

enum OCRJobError: Error, Sendable {
    case imageUnavailable
    case visionFailed(String)
}

protocol OCRProviding: Sendable {
    func recognize(cgImage: CGImage) async throws -> OCRResult
}

protocol OCRImageLoading: Sendable {
    func loadCGImage(localIdentifier: String) async throws -> CGImage
}

protocol OCRScheduling: AnyObject, Sendable {
    func kick()
    func reprocess(id: ScreenshotMemoryID) async
    func reprocessAll() async
}

struct OCRStatusCounts: Equatable, Sendable {
    var pending: Int
    var processing: Int
    var completed: Int
    var failed: Int
    var inaccessible: Int
}

struct OCRClaim: Sendable, Equatable {
    let id: ScreenshotMemoryID
    let photosLocalIdentifier: String
}

protocol OCRPersisting: Sendable {
    func recoverStaleOCRClaims(olderThan: Date) async throws -> Int
    func enqueueStaleVersionOCR(currentVersion: Int) async throws -> Int
    func claimNextOCRJob(currentVersion: Int, now: Date) async throws -> OCRClaim?
    func completeOCRSuccess(
        id: ScreenshotMemoryID,
        text: String,
        language: String?,
        version: Int
    ) async throws
    /// Increments attempt from DB; `attempt`/`nextRetryAt` ignored if you pass zeros — computed inside.
    func completeOCRFailure(id: ScreenshotMemoryID, errorCode: String) async throws
    func fetchOCRStatusCounts() async throws -> OCRStatusCounts
    func fetchOCRDebugRows(limit: Int) async throws -> [ScreenshotMemory]
    func requestOCRReprocess(id: ScreenshotMemoryID) async throws
    func requestOCRReprocessAll(currentVersion: Int) async throws
}
