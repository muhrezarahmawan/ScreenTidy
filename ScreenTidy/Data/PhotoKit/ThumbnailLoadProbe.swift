import Foundation
import UIKit

/// DEBUG diagnostics sink for thumbnail loads.
/// Intentionally NOT `@Observable` — probe mutations must never invalidate SwiftUI
/// parents that own `PhotosThumbnailImage` (that caused thousands of `.task` restarts).
@MainActor
final class ThumbnailLoadProbe {
    enum State: String {
        case idle
        case requesting
        case degradedReceived = "degraded_received"
        case finalReceived = "final_received"
        case timedOut = "timed_out"
        case cancelled
        case failed
        case completed
    }

    enum DisplayedQuality: String {
        case none
        case degraded
        case final
    }

    private(set) var assetLocalIdentifier: String = ""
    private(set) var requestID: String = "—"
    private(set) var state: State = .idle
    private(set) var requestStartedAt: Date?
    private(set) var callbackCount: Int = 0
    private(set) var degradedCallback: Bool = false
    private(set) var finalCallback: Bool = false
    private(set) var photoKitCancelled: Bool = false
    private(set) var taskRestartCount: Int = 0
    private(set) var lastEvent: String = "—"
    private(set) var assetFound: Bool?
    private(set) var inCloudHint: Bool?
    private(set) var photoKitError: String?
    private(set) var imageWidth: Int?
    private(set) var imageHeight: Int?
    private(set) var degradedWidth: Int?
    private(set) var degradedHeight: Int?
    private(set) var finalWidth: Int?
    private(set) var finalHeight: Int?
    private(set) var displayedQuality: DisplayedQuality = .none
    private(set) var timedOut: Bool = false
    private(set) var isolatedTestNote: String = "—"

    var shortAssetID: String {
        let id = assetLocalIdentifier
        guard !id.isEmpty else { return "—" }
        if id.count <= 20 { return id }
        return String(id.prefix(10)) + "…" + String(id.suffix(6))
    }

    func elapsedSeconds(at date: Date = Date()) -> Double {
        guard let requestStartedAt else { return 0 }
        return max(0, date.timeIntervalSince(requestStartedAt))
    }

    func noteTaskStart(assetID: String) {
        taskRestartCount += 1
        assetLocalIdentifier = assetID
        lastEvent = "task_start #\(taskRestartCount)"
    }

    func noteRequestStart(assetID: String, requestID: UUID, assetFound: Bool) {
        assetLocalIdentifier = assetID
        self.requestID = String(requestID.uuidString.prefix(8))
        self.assetFound = assetFound
        state = assetFound ? .requesting : .failed
        requestStartedAt = Date()
        callbackCount = 0
        degradedCallback = false
        finalCallback = false
        photoKitCancelled = false
        photoKitError = nil
        imageWidth = nil
        imageHeight = nil
        degradedWidth = nil
        degradedHeight = nil
        finalWidth = nil
        finalHeight = nil
        displayedQuality = .none
        timedOut = false
        inCloudHint = nil
        lastEvent = assetFound ? "request_start" : "asset_missing"
    }

    func noteCallback(
        degraded: Bool,
        cancelled: Bool,
        inCloud: Bool?,
        error: String?,
        image: UIImage?
    ) {
        callbackCount += 1
        if cancelled { photoKitCancelled = true }
        if let inCloud { inCloudHint = inCloud }
        if let error, !error.isEmpty { photoKitError = error }
        if degraded { degradedCallback = true }
        if !degraded, !cancelled { finalCallback = true }
        if let image {
            let w = Int(image.size.width * image.scale)
            let h = Int(image.size.height * image.scale)
            imageWidth = w
            imageHeight = h
            if degraded {
                degradedWidth = w
                degradedHeight = h
            } else if !cancelled {
                finalWidth = w
                finalHeight = h
            }
        }
        if cancelled {
            state = .cancelled
            lastEvent = "callback_cancelled"
        } else if degraded, image != nil {
            state = .degradedReceived
            lastEvent = "callback_degraded"
        } else if image != nil {
            state = .finalReceived
            lastEvent = "callback_final"
        } else {
            lastEvent = "callback_empty"
        }
    }

    func noteDisplayed(image: UIImage?, quality: DisplayedQuality) {
        displayedQuality = quality
        if let image {
            imageWidth = Int(image.size.width * image.scale)
            imageHeight = Int(image.size.height * image.scale)
        }
        lastEvent = "displayed_\(quality.rawValue)"
    }

    func noteCompleted(image: UIImage?, quality: DisplayedQuality) {
        if let image {
            imageWidth = Int(image.size.width * image.scale)
            imageHeight = Int(image.size.height * image.scale)
            displayedQuality = quality == .none ? .final : quality
            state = .completed
            lastEvent = "ui_completed_\(displayedQuality.rawValue)"
        } else if timedOut {
            state = .timedOut
            lastEvent = "ui_timed_out"
        } else if photoKitCancelled {
            state = .cancelled
            lastEvent = "ui_cancelled_empty"
        } else {
            state = .failed
            lastEvent = "ui_failed_empty"
        }
    }

    func noteTimeout() {
        timedOut = true
        if displayedQuality == .none {
            state = .timedOut
        }
        lastEvent = "timeout_fired"
    }

    func noteIsolatedTestSummary(_ summary: String) {
        isolatedTestNote = summary
        lastEvent = summary
    }
}

enum PhotoKitImageDeliveryStyle: String, Hashable, Sendable {
    /// Neighbors / grids — accept first usable frame (often degraded) and finish.
    case firstUsable
    /// Visual Eval main preview — show degraded immediately, keep request for final.
    case progressive
}

enum PhotoKitImageQuality: String, Sendable {
    case degraded
    case final
}

/// Stable identity for a thumbnail load — only these values may restart `.task`.
struct ThumbnailLoadIdentity: Hashable, Sendable {
    var localIdentifier: String
    var retryGeneration: Int
    var targetWidth: Int
    var targetHeight: Int
    var allowsNetworkAccess: Bool
    var deliveryStyle: PhotoKitImageDeliveryStyle
}

/// Pure UI phase machine for screenshot preview (unit-tested; no SwiftUI).
enum ScreenshotPreviewPhase: Equatable, Sendable {
    case idle
    case loading
    case degraded
    case final
    case failed
}

struct ScreenshotPreviewLoadDecision: Equatable, Sendable {
    var phase: ScreenshotPreviewPhase
    var clearExistingImage: Bool
    var shouldStartRequest: Bool
}

enum ScreenshotPreviewLoadController {
    static func decisionForTaskStart(
        identity: ThumbnailLoadIdentity,
        previousIdentity: ThumbnailLoadIdentity?,
        currentlyHasImage: Bool,
        currentPhase: ScreenshotPreviewPhase
    ) -> ScreenshotPreviewLoadDecision {
        let identityChanged = previousIdentity != identity
        if !identityChanged, currentlyHasImage {
            let phase: ScreenshotPreviewPhase =
                (currentPhase == .degraded || currentPhase == .final) ? currentPhase : .final
            return ScreenshotPreviewLoadDecision(
                phase: phase,
                clearExistingImage: false,
                shouldStartRequest: false
            )
        }
        return ScreenshotPreviewLoadDecision(
            phase: .loading,
            clearExistingImage: true,
            shouldStartRequest: true
        )
    }

    static func phaseAfterProgressiveUpdate(quality: PhotoKitImageQuality) -> ScreenshotPreviewPhase {
        switch quality {
        case .degraded: return .degraded
        case .final: return .final
        }
    }

    /// Timeout / cancel with no pixels → failed. With pixels → keep degraded/final (never wipe).
    static func phaseAfterTimeoutOrCancel(
        hasImage: Bool,
        currentPhase: ScreenshotPreviewPhase
    ) -> ScreenshotPreviewPhase {
        if hasImage {
            if currentPhase == .final { return .final }
            return .degraded
        }
        return .failed
    }

    static func canShowLoadingSpinner(phase: ScreenshotPreviewPhase, hasImage: Bool) -> Bool {
        phase == .loading && !hasImage
    }
}
