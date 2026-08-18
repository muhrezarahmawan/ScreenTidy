@preconcurrency import Photos
import UIKit

/// PhotoKit callback policy for UI thumbnails.
enum PhotoKitThumbnailDelivery {
    enum Decision: Equatable {
        case ignore
        case acceptUsable
        case finishEmpty
        case keepWaiting
    }

    enum ProgressiveDecision: Equatable {
        case ignore
        case publishDegradedAndKeepWaiting
        case publishFinalAndFinish
        case finishEmpty
        case keepWaiting
    }

    /// Neighbors: first usable frame (including degraded) wins.
    static func decide(
        alreadyResumed: Bool,
        cancelled: Bool,
        hasImage: Bool,
        isDegraded: Bool
    ) -> Decision {
        if alreadyResumed { return .ignore }
        if cancelled { return .finishEmpty }
        if hasImage { return .acceptUsable }
        if isDegraded { return .keepWaiting }
        return .finishEmpty
    }

    /// Main preview: publish degraded, keep request alive until final / timeout / cancel.
    static func decideProgressive(
        alreadyFinished: Bool,
        cancelled: Bool,
        hasImage: Bool,
        isDegraded: Bool
    ) -> ProgressiveDecision {
        if alreadyFinished { return .ignore }
        if cancelled { return .finishEmpty }
        if hasImage, isDegraded { return .publishDegradedAndKeepWaiting }
        if hasImage { return .publishFinalAndFinish }
        if isDegraded { return .keepWaiting }
        return .finishEmpty
    }
}

/// Continues a thumbnail await with an independent timeout (not cancelled by SwiftUI `.task`).
enum PhotoKitThumbnailAwait {
    struct Outcome: Sendable {
        let image: UIImage?
        let timedOut: Bool
        let receivedFinal: Bool
    }

    /// Returns on first accepted image, empty final/cancel, or timeout — whichever comes first.
    static func firstUsableImage(
        timeoutNanoseconds: UInt64,
        start: (@escaping @Sendable (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID,
        cancelRequest: @escaping @Sendable (PHImageRequestID) -> Void
    ) async -> Outcome {
        final class RequestState: @unchecked Sendable {
            let lock = NSLock()
            var resumed = false
        }
        let state = RequestState()

        return await withCheckedContinuation { continuation in
            let resumeOnce: @Sendable (UIImage?, Bool) -> Void = { image, timedOut in
                state.lock.lock()
                defer { state.lock.unlock() }
                guard !state.resumed else { return }
                state.resumed = true
                continuation.resume(
                    returning: Outcome(image: image, timedOut: timedOut, receivedFinal: image != nil && !timedOut)
                )
            }

            let photoRequestID = start { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                state.lock.lock()
                let already = state.resumed
                state.lock.unlock()

                switch PhotoKitThumbnailDelivery.decide(
                    alreadyResumed: already,
                    cancelled: cancelled,
                    hasImage: image != nil,
                    isDegraded: degraded
                ) {
                case .ignore, .keepWaiting:
                    return
                case .acceptUsable:
                    resumeOnce(image, false)
                case .finishEmpty:
                    resumeOnce(nil, false)
                }
            }

            Task.detached(priority: .utility) {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                state.lock.lock()
                let alreadyResumed = state.resumed
                state.lock.unlock()
                if !alreadyResumed {
                    cancelRequest(photoRequestID)
                    resumeOnce(nil, true)
                }
            }
        }
    }

    /// Progressive: may call `onUpdate` for degraded, then finish on final / timeout / cancel.
    /// Timeout after degraded keeps the best image (does not force nil).
    static func progressiveImage(
        timeoutNanoseconds: UInt64,
        start: (@escaping @Sendable (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID,
        cancelRequest: @escaping @Sendable (PHImageRequestID) -> Void,
        onUpdate: @escaping @Sendable (UIImage, PhotoKitImageQuality) -> Void
    ) async -> Outcome {
        final class RequestState: @unchecked Sendable {
            let lock = NSLock()
            var finished = false
            var bestImage: UIImage?
            var receivedFinal = false
        }
        let state = RequestState()

        return await withCheckedContinuation { continuation in
            let finish: @Sendable (Bool) -> Void = { timedOut in
                state.lock.lock()
                defer { state.lock.unlock() }
                guard !state.finished else { return }
                state.finished = true
                let image = state.bestImage
                let receivedFinal = state.receivedFinal
                continuation.resume(
                    returning: Outcome(image: image, timedOut: timedOut, receivedFinal: receivedFinal)
                )
            }

            let photoRequestID = start { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                state.lock.lock()
                let already = state.finished
                state.lock.unlock()

                switch PhotoKitThumbnailDelivery.decideProgressive(
                    alreadyFinished: already,
                    cancelled: cancelled,
                    hasImage: image != nil,
                    isDegraded: degraded
                ) {
                case .ignore, .keepWaiting:
                    return
                case .publishDegradedAndKeepWaiting:
                    guard let image else { return }
                    state.lock.lock()
                    state.bestImage = image
                    state.lock.unlock()
                    onUpdate(image, .degraded)
                case .publishFinalAndFinish:
                    guard let image else {
                        finish(false)
                        return
                    }
                    state.lock.lock()
                    state.bestImage = image
                    state.receivedFinal = true
                    state.lock.unlock()
                    onUpdate(image, .final)
                    finish(false)
                case .finishEmpty:
                    finish(false)
                }
            }

            Task.detached(priority: .utility) {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                state.lock.lock()
                let already = state.finished
                state.lock.unlock()
                if !already {
                    cancelRequest(photoRequestID)
                    finish(true)
                }
            }
        }
    }
}

/// Shared, cancellable PhotoKit image loader. Grid calls disable network access so iCloud-only
/// assets stay placeholders; fullscreen/viewer/DEBUG calls may opt in and receive download progress.
final class PhotoKitThumbnailProvider: ThumbnailProviding, @unchecked Sendable {
    private let manager = PHCachingImageManager()
    private let lock = NSLock()
    private var requestIDs: [UUID: PHImageRequestID] = [:]
    private let requestTimeoutNanoseconds: UInt64

    init(timeoutNanoseconds: UInt64 = 12_000_000_000) {
        self.requestTimeoutNanoseconds = timeoutNanoseconds
    }

    func requestThumbnail(
        localIdentifier: String,
        targetSize: CGSize,
        contentMode: ThumbnailContentMode,
        allowsNetworkAccess: Bool,
        progressHandler: (@Sendable (Double) -> Void)?,
        requestID token: UUID
    ) async -> ThumbnailResult? {
        let outcome = await requestThumbnailDetailed(
            localIdentifier: localIdentifier,
            targetSize: targetSize,
            contentMode: contentMode,
            allowsNetworkAccess: allowsNetworkAccess,
            progressHandler: progressHandler,
            requestID: token,
            probe: nil,
            deliveryStyle: .firstUsable,
            onImageUpdate: nil
        )
        return outcome.image.map { ThumbnailResult(image: $0, requestID: token) }
    }

    struct DetailedOutcome: Sendable {
        let image: UIImage?
        let timedOut: Bool
        let assetFound: Bool
        let receivedFinal: Bool
    }

    func requestThumbnailDetailed(
        localIdentifier: String,
        targetSize: CGSize,
        contentMode: ThumbnailContentMode,
        allowsNetworkAccess: Bool,
        progressHandler: (@Sendable (Double) -> Void)?,
        requestID token: UUID,
        probe: ThumbnailLoadProbe?,
        deliveryStyle: PhotoKitImageDeliveryStyle = .firstUsable,
        onImageUpdate: (@Sendable (UIImage, PhotoKitImageQuality) -> Void)? = nil
    ) async -> DetailedOutcome {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            if let probe {
                await MainActor.run {
                    probe.noteRequestStart(assetID: localIdentifier, requestID: token, assetFound: false)
                    probe.noteCompleted(image: nil, quality: .none)
                }
            }
            return DetailedOutcome(image: nil, timedOut: false, assetFound: false, receivedFinal: false)
        }

        if let probe {
            await MainActor.run {
                probe.noteRequestStart(assetID: localIdentifier, requestID: token, assetFound: true)
            }
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowsNetworkAccess
        options.isSynchronous = false
        if allowsNetworkAccess, let progressHandler {
            options.progressHandler = { progress, _, _, _ in
                progressHandler(Double(progress))
            }
        }

        let start: (@escaping @Sendable (UIImage?, [AnyHashable: Any]?) -> Void) -> PHImageRequestID = { onDelivery in
            let photoRequestID = self.manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode == .aspectFill ? .aspectFill : .aspectFit,
                options: options
            ) { image, info in
                if let probe {
                    let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                    let inCloud = info?[PHImageResultIsInCloudKey] as? Bool
                    let error = (info?[PHImageErrorKey] as? NSError)?.localizedDescription
                    Task { @MainActor in
                        probe.noteCallback(
                            degraded: degraded,
                            cancelled: cancelled,
                            inCloud: inCloud,
                            error: error,
                            image: image
                        )
                    }
                }
                onDelivery(image, info)
            }
            self.lock.lock()
            self.requestIDs[token] = photoRequestID
            self.lock.unlock()
            return photoRequestID
        }

        let cancelRequest: @Sendable (PHImageRequestID) -> Void = { photoRequestID in
            self.manager.cancelImageRequest(photoRequestID)
            self.remove(token)
        }

        let outcome: PhotoKitThumbnailAwait.Outcome
        switch deliveryStyle {
        case .firstUsable:
            outcome = await PhotoKitThumbnailAwait.firstUsableImage(
                timeoutNanoseconds: requestTimeoutNanoseconds,
                start: start,
                cancelRequest: cancelRequest
            )
        case .progressive:
            outcome = await PhotoKitThumbnailAwait.progressiveImage(
                timeoutNanoseconds: requestTimeoutNanoseconds,
                start: start,
                cancelRequest: cancelRequest,
                onUpdate: { image, quality in
                    onImageUpdate?(image, quality)
                }
            )
        }

        remove(token)

        if let probe {
            await MainActor.run {
                if outcome.timedOut { probe.noteTimeout() }
                let quality: ThumbnailLoadProbe.DisplayedQuality =
                    outcome.receivedFinal ? .final : (outcome.image != nil ? .degraded : .none)
                probe.noteCompleted(image: outcome.image, quality: quality)
            }
        }

        return DetailedOutcome(
            image: outcome.image,
            timedOut: outcome.timedOut,
            assetFound: true,
            receivedFinal: outcome.receivedFinal
        )
    }

    func cancelRequest(_ requestID: UUID) {
        lock.lock()
        let photoRequestID = requestIDs.removeValue(forKey: requestID)
        lock.unlock()
        if let photoRequestID { manager.cancelImageRequest(photoRequestID) }
    }

    private func remove(_ token: UUID) {
        lock.lock()
        requestIDs.removeValue(forKey: token)
        lock.unlock()
    }
}

#if DEBUG
/// Isolated one-shot PhotoKit preview probe for Visual Eval (bypasses PhotosThumbnailImage).
enum DebugPhotoKitPreviewTester {
    struct Report: Sendable {
        var assetFound: Bool
        var callbackCount: Int
        var degradedCallback: Bool
        var finalCallback: Bool
        var timedOut: Bool
        var cancelled: Bool
        var inCloud: Bool?
        var error: String?
        var imageWidth: Int?
        var imageHeight: Int?
        var elapsedSeconds: Double
    }

    static func run(
        localIdentifier: String,
        targetSize: CGSize,
        timeoutNanoseconds: UInt64 = 12_000_000_000
    ) async -> Report {
        let started = Date()
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            return Report(
                assetFound: false,
                callbackCount: 0,
                degradedCallback: false,
                finalCallback: false,
                timedOut: false,
                cancelled: false,
                inCloud: nil,
                error: "PHAsset not found",
                imageWidth: nil,
                imageHeight: nil,
                elapsedSeconds: Date().timeIntervalSince(started)
            )
        }

        final class Acc: @unchecked Sendable {
            let lock = NSLock()
            var callbackCount = 0
            var degraded = false
            var final = false
            var cancelled = false
            var inCloud: Bool?
            var error: String?
        }
        let acc = Acc()
        let manager = PHCachingImageManager()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let outcome = await PhotoKitThumbnailAwait.progressiveImage(
            timeoutNanoseconds: timeoutNanoseconds,
            start: { onDelivery in
                manager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    acc.lock.lock()
                    acc.callbackCount += 1
                    let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                    if cancelled { acc.cancelled = true }
                    if degraded { acc.degraded = true }
                    if !degraded, !cancelled { acc.final = true }
                    acc.inCloud = info?[PHImageResultIsInCloudKey] as? Bool
                    acc.error = (info?[PHImageErrorKey] as? NSError)?.localizedDescription
                    acc.lock.unlock()
                    onDelivery(image, info)
                }
            },
            cancelRequest: { id in
                manager.cancelImageRequest(id)
            },
            onUpdate: { _, _ in }
        )

        acc.lock.lock()
        let report = Report(
            assetFound: true,
            callbackCount: acc.callbackCount,
            degradedCallback: acc.degraded,
            finalCallback: acc.final,
            timedOut: outcome.timedOut,
            cancelled: acc.cancelled,
            inCloud: acc.inCloud,
            error: acc.error,
            imageWidth: outcome.image.map { Int($0.size.width * $0.scale) },
            imageHeight: outcome.image.map { Int($0.size.height * $0.scale) },
            elapsedSeconds: Date().timeIntervalSince(started)
        )
        acc.lock.unlock()
        return report
    }
}
#endif
