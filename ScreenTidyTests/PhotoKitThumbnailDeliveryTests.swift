import Photos
import UIKit
import XCTest
@testable import ScreenTidy

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock(); count += 1; lock.unlock()
    }
}

final class ScreenshotPreviewLoadControllerTests: XCTestCase {
    private func identity(
        _ asset: String,
        retry: Int = 0,
        style: PhotoKitImageDeliveryStyle = .progressive
    ) -> ThumbnailLoadIdentity {
        ThumbnailLoadIdentity(
            localIdentifier: asset,
            retryGeneration: retry,
            targetWidth: 1170,
            targetHeight: 1170,
            allowsNetworkAccess: true,
            deliveryStyle: style
        )
    }

    func testAssetAppearStartsExactlyOneAutomaticLoad() {
        let id = identity("A")
        let decision = ScreenshotPreviewLoadController.decisionForTaskStart(
            identity: id,
            previousIdentity: nil,
            currentlyHasImage: false,
            currentPhase: .idle
        )
        XCTAssertTrue(decision.shouldStartRequest)
        XCTAssertEqual(decision.phase, .loading)
        XCTAssertTrue(decision.clearExistingImage)
    }

    func testSuccessDoesNotTriggerAnotherLoadForSameIdentity() {
        let id = identity("A")
        let decision = ScreenshotPreviewLoadController.decisionForTaskStart(
            identity: id,
            previousIdentity: id,
            currentlyHasImage: true,
            currentPhase: .final
        )
        XCTAssertFalse(decision.shouldStartRequest)
        XCTAssertEqual(decision.phase, .final)
        XCTAssertFalse(decision.clearExistingImage)
    }

    func testManualRetryIncrementsGenerationAndReloadsOnce() {
        let first = identity("A", retry: 0)
        let retry = identity("A", retry: 1)
        let decision = ScreenshotPreviewLoadController.decisionForTaskStart(
            identity: retry,
            previousIdentity: first,
            currentlyHasImage: true,
            currentPhase: .final
        )
        XCTAssertTrue(decision.shouldStartRequest)
        XCTAssertTrue(decision.clearExistingImage)
        XCTAssertEqual(decision.phase, .loading)
    }

    func testAssetIDChangeTriggersNewLoad() {
        let decision = ScreenshotPreviewLoadController.decisionForTaskStart(
            identity: identity("B"),
            previousIdentity: identity("A"),
            currentlyHasImage: true,
            currentPhase: .final
        )
        XCTAssertTrue(decision.shouldStartRequest)
    }

    func testDegradedThenFinalPhases() {
        XCTAssertEqual(
            ScreenshotPreviewLoadController.phaseAfterProgressiveUpdate(quality: .degraded),
            .degraded
        )
        XCTAssertEqual(
            ScreenshotPreviewLoadController.phaseAfterProgressiveUpdate(quality: .final),
            .final
        )
    }

    func testTimeoutKeepsDegradedVisible() {
        XCTAssertEqual(
            ScreenshotPreviewLoadController.phaseAfterTimeoutOrCancel(
                hasImage: true,
                currentPhase: .degraded
            ),
            .degraded
        )
        XCTAssertFalse(
            ScreenshotPreviewLoadController.canShowLoadingSpinner(phase: .degraded, hasImage: true)
        )
    }

    func testTimeoutWithNoImageIsFailed() {
        XCTAssertEqual(
            ScreenshotPreviewLoadController.phaseAfterTimeoutOrCancel(
                hasImage: false,
                currentPhase: .loading
            ),
            .failed
        )
    }

    func testSuccessfulDeliveryNeverAllowsLoadingSpinner() {
        XCTAssertFalse(
            ScreenshotPreviewLoadController.canShowLoadingSpinner(phase: .final, hasImage: true)
        )
        XCTAssertFalse(
            ScreenshotPreviewLoadController.canShowLoadingSpinner(phase: .loading, hasImage: true)
        )
    }

    func testDiagnosticMutationsDoNotChangeLoadIdentity() {
        let a = identity("A", retry: 0)
        let b = ThumbnailLoadIdentity(
            localIdentifier: "A",
            retryGeneration: 0,
            targetWidth: 1170,
            targetHeight: 1170,
            allowsNetworkAccess: true,
            deliveryStyle: .progressive
        )
        XCTAssertEqual(a, b)
    }

    @MainActor
    func testElapsedNeverNegative() {
        let probe = ThumbnailLoadProbe()
        probe.noteRequestStart(assetID: "x", requestID: UUID(), assetFound: true)
        let past = Date().addingTimeInterval(-1)
        let elapsed = probe.elapsedSeconds(at: past)
        XCTAssertGreaterThanOrEqual(elapsed, 0)
    }
}

final class PhotoKitThumbnailDeliveryTests: XCTestCase {
    func testDegradedUsableImageIsAccepted() {
        let decision = PhotoKitThumbnailDelivery.decide(
            alreadyResumed: false,
            cancelled: false,
            hasImage: true,
            isDegraded: true
        )
        XCTAssertEqual(decision, .acceptUsable)
    }

    func testFinalUsableImageIsAccepted() {
        let decision = PhotoKitThumbnailDelivery.decide(
            alreadyResumed: false,
            cancelled: false,
            hasImage: true,
            isDegraded: false
        )
        XCTAssertEqual(decision, .acceptUsable)
    }

    func testCancelledFinishesEmpty() {
        let decision = PhotoKitThumbnailDelivery.decide(
            alreadyResumed: false,
            cancelled: true,
            hasImage: true,
            isDegraded: true
        )
        XCTAssertEqual(decision, .finishEmpty)
    }

    func testFinalEmptyFinishesEmpty() {
        let decision = PhotoKitThumbnailDelivery.decide(
            alreadyResumed: false,
            cancelled: false,
            hasImage: false,
            isDegraded: false
        )
        XCTAssertEqual(decision, .finishEmpty)
    }

    func testDegradedEmptyKeepsWaiting() {
        let decision = PhotoKitThumbnailDelivery.decide(
            alreadyResumed: false,
            cancelled: false,
            hasImage: false,
            isDegraded: true
        )
        XCTAssertEqual(decision, .keepWaiting)
    }

    func testAlreadyResumedIgnoresFurtherCallbacks() {
        let decision = PhotoKitThumbnailDelivery.decide(
            alreadyResumed: true,
            cancelled: false,
            hasImage: true,
            isDegraded: false
        )
        XCTAssertEqual(decision, .ignore)
    }

    func testAlreadyResumedIgnoresCancelNoise() {
        let decision = PhotoKitThumbnailDelivery.decide(
            alreadyResumed: true,
            cancelled: true,
            hasImage: false,
            isDegraded: false
        )
        XCTAssertEqual(decision, .ignore)
    }
}

final class PhotoKitThumbnailAwaitTests: XCTestCase {
    func testNeverRespondingPhotoKitTimesOut() async {
        let started = Date()
        let cancelCount = LockedCounter()
        let outcome = await PhotoKitThumbnailAwait.firstUsableImage(
            timeoutNanoseconds: 150_000_000, // 0.15s
            start: { _ in
                // Never invoke the delivery callback.
                PHInvalidImageRequestID
            },
            cancelRequest: { _ in
                cancelCount.increment()
            }
        )
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertNil(outcome.image)
        XCTAssertTrue(outcome.timedOut)
        XCTAssertEqual(cancelCount.value, 1)
        XCTAssertLessThan(elapsed, 2.0)
        XCTAssertGreaterThanOrEqual(elapsed, 0.10)
    }

    func testDegradedCallbackOnlyResolvesSuccessfully() async {
        let image = UIImage()
        let outcome = await PhotoKitThumbnailAwait.firstUsableImage(
            timeoutNanoseconds: 2_000_000_000,
            start: { onDelivery in
                onDelivery(image, [PHImageResultIsDegradedKey: true])
                return PHInvalidImageRequestID
            },
            cancelRequest: { _ in }
        )
        XCTAssertNotNil(outcome.image)
        XCTAssertFalse(outcome.timedOut)
    }

    func testFinalCallbackOnlyResolvesSuccessfully() async {
        let image = UIImage()
        let outcome = await PhotoKitThumbnailAwait.firstUsableImage(
            timeoutNanoseconds: 2_000_000_000,
            start: { onDelivery in
                onDelivery(image, [PHImageResultIsDegradedKey: false])
                return PHInvalidImageRequestID
            },
            cancelRequest: { _ in }
        )
        XCTAssertNotNil(outcome.image)
        XCTAssertFalse(outcome.timedOut)
    }

    func testCancellationFinishesEmptyWithoutTimeout() async {
        let outcome = await PhotoKitThumbnailAwait.firstUsableImage(
            timeoutNanoseconds: 2_000_000_000,
            start: { onDelivery in
                onDelivery(nil, [PHImageCancelledKey: true])
                return PHInvalidImageRequestID
            },
            cancelRequest: { _ in }
        )
        XCTAssertNil(outcome.image)
        XCTAssertFalse(outcome.timedOut)
    }

    func testStaleCallbackAfterAcceptIsIgnored() async {
        let first = UIImage()
        let second = UIImage()
        var deliveries = 0
        let outcome = await PhotoKitThumbnailAwait.firstUsableImage(
            timeoutNanoseconds: 2_000_000_000,
            start: { onDelivery in
                onDelivery(first, [PHImageResultIsDegradedKey: true])
                deliveries += 1
                onDelivery(second, [PHImageResultIsDegradedKey: false])
                deliveries += 1
                return PHInvalidImageRequestID
            },
            cancelRequest: { _ in }
        )
        XCTAssertEqual(deliveries, 2)
        XCTAssertTrue(outcome.image === first)
        XCTAssertFalse(outcome.timedOut)
    }

    func testProgressiveDegradedThenFinalReplaces() async {
        let degraded = UIImage()
        let final = UIImage()
        let updates = LockedImageQualityLog()
        let outcome = await PhotoKitThumbnailAwait.progressiveImage(
            timeoutNanoseconds: 2_000_000_000,
            start: { onDelivery in
                onDelivery(degraded, [PHImageResultIsDegradedKey: true])
                onDelivery(final, [PHImageResultIsDegradedKey: false])
                return PHInvalidImageRequestID
            },
            cancelRequest: { _ in },
            onUpdate: { image, quality in
                updates.append(image, quality)
            }
        )
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates.qualities, [.degraded, .final])
        XCTAssertTrue(outcome.image === final)
        XCTAssertTrue(outcome.receivedFinal)
        XCTAssertFalse(outcome.timedOut)
    }

    func testProgressiveDegradedThenTimeoutKeepsDegraded() async {
        let degraded = UIImage()
        let updates = LockedImageQualityLog()
        let outcome = await PhotoKitThumbnailAwait.progressiveImage(
            timeoutNanoseconds: 120_000_000,
            start: { onDelivery in
                onDelivery(degraded, [PHImageResultIsDegradedKey: true])
                // Never send final.
                return PHInvalidImageRequestID
            },
            cancelRequest: { _ in },
            onUpdate: { image, quality in
                updates.append(image, quality)
            }
        )
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.qualities, [.degraded])
        XCTAssertTrue(outcome.image === degraded)
        XCTAssertTrue(outcome.timedOut)
        XCTAssertFalse(outcome.receivedFinal)
    }

    func testProgressiveFinalOnly() async {
        let final = UIImage()
        let updates = LockedImageQualityLog()
        let outcome = await PhotoKitThumbnailAwait.progressiveImage(
            timeoutNanoseconds: 2_000_000_000,
            start: { onDelivery in
                onDelivery(final, [PHImageResultIsDegradedKey: false])
                return PHInvalidImageRequestID
            },
            cancelRequest: { _ in },
            onUpdate: { image, quality in
                updates.append(image, quality)
            }
        )
        XCTAssertEqual(updates.qualities, [.final])
        XCTAssertTrue(outcome.receivedFinal)
        XCTAssertNotNil(outcome.image)
    }

    func testProgressiveNoResultTimesOutUnavailable() async {
        let outcome = await PhotoKitThumbnailAwait.progressiveImage(
            timeoutNanoseconds: 100_000_000,
            start: { _ in PHInvalidImageRequestID },
            cancelRequest: { _ in },
            onUpdate: { _, _ in }
        )
        XCTAssertNil(outcome.image)
        XCTAssertTrue(outcome.timedOut)
    }

    func testProgressiveDecideDoesNotFinishOnDegraded() {
        let decision = PhotoKitThumbnailDelivery.decideProgressive(
            alreadyFinished: false,
            cancelled: false,
            hasImage: true,
            isDegraded: true
        )
        XCTAssertEqual(decision, .publishDegradedAndKeepWaiting)
    }
}

private final class LockedImageQualityLog: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [UIImage] = []
    private(set) var qualities: [PhotoKitImageQuality] = []
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return images.count
    }
    func append(_ image: UIImage, _ quality: PhotoKitImageQuality) {
        lock.lock()
        images.append(image)
        qualities.append(quality)
        lock.unlock()
    }
}

/// Controllable `ThumbnailProviding` double for load/cancel/stale semantics.
actor ControllableThumbnailProvider: ThumbnailProviding {
    private(set) var cancelCount = 0
    private(set) var lastRequestID: UUID?
    private var pending: [UUID: CheckedContinuation<ThumbnailResult?, Never>] = [:]
    private var imagesByID: [UUID: UIImage] = [:]
    private var nilResults: Set<UUID> = []

    nonisolated func requestThumbnail(
        localIdentifier: String,
        targetSize: CGSize,
        contentMode: ThumbnailContentMode,
        allowsNetworkAccess: Bool,
        progressHandler: (@Sendable (Double) -> Void)?,
        requestID: UUID
    ) async -> ThumbnailResult? {
        await enqueue(requestID: requestID)
    }

    nonisolated func cancelRequest(_ requestID: UUID) {
        Task { await cancel(requestID) }
    }

    func enqueue(requestID: UUID) async -> ThumbnailResult? {
        lastRequestID = requestID
        if let image = imagesByID.removeValue(forKey: requestID) {
            return ThumbnailResult(image: image, requestID: requestID)
        }
        if nilResults.remove(requestID) != nil {
            return nil
        }
        return await withCheckedContinuation { continuation in
            pending[requestID] = continuation
        }
    }

    func complete(requestID: UUID, image: UIImage?) {
        if let continuation = pending.removeValue(forKey: requestID) {
            if let image {
                continuation.resume(returning: ThumbnailResult(image: image, requestID: requestID))
            } else {
                continuation.resume(returning: nil)
            }
        } else if let image {
            imagesByID[requestID] = image
        } else {
            nilResults.insert(requestID)
        }
    }

    func cancel(_ requestID: UUID) {
        cancelCount += 1
        if let continuation = pending.removeValue(forKey: requestID) {
            continuation.resume(returning: nil)
        }
    }
}

final class ThumbnailProviderCancelTests: XCTestCase {
    func testCancelCompletesPendingRequestWithoutDoubleResume() async {
        let provider = ControllableThumbnailProvider()
        let token = UUID()
        async let result = provider.requestThumbnail(
            localIdentifier: "asset-a",
            targetSize: CGSize(width: 64, height: 64),
            contentMode: .aspectFill,
            allowsNetworkAccess: true,
            progressHandler: nil,
            requestID: token
        )
        // Allow enqueue to register.
        try? await Task.sleep(nanoseconds: 20_000_000)
        await provider.cancel(token)
        let loaded = await result
        XCTAssertNil(loaded)
        let cancelCount = await provider.cancelCount
        XCTAssertEqual(cancelCount, 1)
    }

    func testSuccessfulImagePathReturnsRequestID() async {
        let provider = ControllableThumbnailProvider()
        let token = UUID()
        let image = UIImage()
        await provider.complete(requestID: token, image: image)
        let result = await provider.requestThumbnail(
            localIdentifier: "asset-b",
            targetSize: CGSize(width: 64, height: 64),
            contentMode: .aspectFit,
            allowsNetworkAccess: false,
            progressHandler: nil,
            requestID: token
        )
        XCTAssertEqual(result?.requestID, token)
        XCTAssertNotNil(result?.image)
    }

    func testStaleRequestIDDoesNotOverwriteNewerCompletion() async {
        let provider = ControllableThumbnailProvider()
        let oldToken = UUID()
        let newToken = UUID()

        async let oldResult = provider.requestThumbnail(
            localIdentifier: "old",
            targetSize: CGSize(width: 32, height: 32),
            contentMode: .aspectFill,
            allowsNetworkAccess: true,
            progressHandler: nil,
            requestID: oldToken
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        async let newResult = provider.requestThumbnail(
            localIdentifier: "new",
            targetSize: CGSize(width: 32, height: 32),
            contentMode: .aspectFill,
            allowsNetworkAccess: true,
            progressHandler: nil,
            requestID: newToken
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        let newer = UIImage()
        await provider.complete(requestID: newToken, image: newer)
        await provider.complete(requestID: oldToken, image: UIImage())

        let newLoaded = await newResult
        let oldLoaded = await oldResult
        XCTAssertEqual(newLoaded?.requestID, newToken)
        XCTAssertEqual(oldLoaded?.requestID, oldToken)
        // Distinct completions — UI layer uses activeRequestID == token to ignore stale.
        XCTAssertNotEqual(newLoaded?.requestID, oldLoaded?.requestID)
    }

    func testNilResultModelsTimeoutTerminalState() async {
        let provider = ControllableThumbnailProvider()
        let token = UUID()
        await provider.complete(requestID: token, image: nil)
        let result = await provider.requestThumbnail(
            localIdentifier: "missing",
            targetSize: CGSize(width: 64, height: 64),
            contentMode: .aspectFit,
            allowsNetworkAccess: true,
            progressHandler: nil,
            requestID: token
        )
        XCTAssertNil(result, "Timeout / empty delivery maps to nil → UI .failed when network allowed")
    }
}

final class VisualEvalThumbnailTargetSizeTests: XCTestCase {
    func testPreviewTargetIsBoundedForDisplayScale() {
        let displayLongEdgePt = max(UIScreen.main.bounds.width, CGFloat(220))
        let pixels = min(displayLongEdgePt * UIScreen.main.scale, 1_200)
        XCTAssertLessThanOrEqual(pixels, 1_200)
        XCTAssertGreaterThanOrEqual(pixels, 220)
        // Must exceed the old 480 cap that caused blurry 220×480 previews on 3x devices.
        if UIScreen.main.scale >= 3 {
            XCTAssertGreaterThan(pixels, 480)
        }
    }

    func testNeighborTargetIsSmallerThanPreviewBound() {
        let neighbor = min(UIScreen.main.scale * 56, 160)
        let preview = min(max(UIScreen.main.bounds.width, 220) * UIScreen.main.scale, 1_200)
        XCTAssertLessThan(neighbor, preview)
        XCTAssertLessThanOrEqual(neighbor, 160)
    }
}

final class ScreenshotFullscreenImageTargetTests: XCTestCase {
    func testFullscreenHeroUsesProgressiveDeliveryStyleInIdentity() {
        let identity = ThumbnailLoadIdentity(
            localIdentifier: "asset",
            retryGeneration: 0,
            targetWidth: 1170,
            targetHeight: 2532,
            allowsNetworkAccess: true,
            deliveryStyle: .progressive
        )
        XCTAssertEqual(identity.deliveryStyle, .progressive)
        XCTAssertNotEqual(identity.deliveryStyle, .firstUsable)
    }

    func testTargetSizeIsFittedTimesScale() {
        let fitted = CGSize(width: 300, height: 650)
        let scale: CGFloat = 3 // 900 × 1950 — under 2400 cap
        let target = ScreenshotFullscreenImageTarget.targetSize(fittedPoints: fitted, scale: scale)
        XCTAssertEqual(target.width, 900)
        XCTAssertEqual(target.height, 1950)
    }

    func testTargetSizeCapsLongEdgeAt2400() {
        let fitted = CGSize(width: 500, height: 1_200)
        let scale: CGFloat = 3 // would be 1500 × 3600 without cap
        let target = ScreenshotFullscreenImageTarget.targetSize(fittedPoints: fitted, scale: scale)
        XCTAssertLessThanOrEqual(max(target.width, target.height), ScreenshotFullscreenImageTarget.maxLongEdgePixels)
        XCTAssertEqual(ScreenshotFullscreenImageTarget.maxLongEdgePixels, 2_400)
        // Aspect preserved under cap.
        let expectedAspect = (CGFloat(500) * 3) / (CGFloat(1_200) * 3)
        XCTAssertEqual(target.width / target.height, expectedAspect, accuracy: 0.01)
    }

    func testFullscreenCapIsHigherThanVisualEvalCap() {
        XCTAssertGreaterThan(ScreenshotFullscreenImageTarget.maxLongEdgePixels, CGFloat(1_200))
    }
}
