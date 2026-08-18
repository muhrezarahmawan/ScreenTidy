import Foundation

/// Bounded OCR drain (max concurrency = 2). Newest-first via repository claim SQL.
/// Does not mutate Collections. Does not log OCR text.
final class OCRProcessingQueue: OCRScheduling, @unchecked Sendable {
    private let repository: any OCRPersisting
    private let ocr: any OCRProviding
    private let images: any OCRImageLoading
    private let onOCRFinished: (@Sendable (ScreenshotMemoryID) -> Void)?
    private let lock = NSLock()
    private var inFlight = 0
    private var isScheduling = false

    init(
        repository: any OCRPersisting,
        ocr: any OCRProviding,
        images: any OCRImageLoading,
        onOCRFinished: (@Sendable (ScreenshotMemoryID) -> Void)? = nil
    ) {
        self.repository = repository
        self.ocr = ocr
        self.images = images
        self.onOCRFinished = onOCRFinished
    }

    func kick() {
        Task { await schedule() }
    }

    func reprocess(id: ScreenshotMemoryID) async {
        try? await repository.requestOCRReprocess(id: id)
        kick()
    }

    func reprocessAll() async {
        try? await repository.requestOCRReprocessAll(currentVersion: OCRPipeline.currentVersion)
        kick()
    }

    private func schedule() async {
        lock.lock()
        if isScheduling {
            lock.unlock()
            return
        }
        isScheduling = true
        lock.unlock()

        defer {
            lock.lock()
            isScheduling = false
            lock.unlock()
        }

        do {
            let staleBefore = Date().addingTimeInterval(-OCRPipeline.staleClaimInterval)
            _ = try await repository.recoverStaleOCRClaims(olderThan: staleBefore)
            _ = try await repository.enqueueStaleVersionOCR(currentVersion: OCRPipeline.currentVersion)
        } catch {
            AppLog.general.error("OCR recover failed: \(error.localizedDescription, privacy: .public)")
        }

        while true {
            lock.lock()
            let canStart = inFlight < OCRPipeline.maxConcurrency
            lock.unlock()
            guard canStart else { break }

            let claim: OCRClaim?
            do {
                claim = try await repository.claimNextOCRJob(
                    currentVersion: OCRPipeline.currentVersion,
                    now: Date()
                )
            } catch {
                AppLog.general.error("OCR claim failed: \(error.localizedDescription, privacy: .public)")
                break
            }
            guard let claim else { break }

            lock.lock()
            inFlight += 1
            lock.unlock()

            Task {
                await self.run(claim)
            }
        }
    }

    private func run(_ claim: OCRClaim) async {
        defer {
            lock.lock()
            inFlight = max(0, inFlight - 1)
            lock.unlock()
            kick()
        }

        do {
            let cgImage = try await images.loadCGImage(localIdentifier: claim.photosLocalIdentifier)
            let result = try await ocr.recognize(cgImage: cgImage)
            try await repository.completeOCRSuccess(
                id: claim.id,
                text: result.text,
                language: result.language,
                version: OCRPipeline.currentVersion
            )
            AppLog.general.info("OCR completed for one screenshot")
            onOCRFinished?(claim.id)
        } catch let error as OCRJobError {
            try? await repository.completeOCRFailure(id: claim.id, errorCode: errorCode(error))
            onOCRFinished?(claim.id)
        } catch {
            try? await repository.completeOCRFailure(id: claim.id, errorCode: "unknown")
            onOCRFinished?(claim.id)
        }
    }

    private func errorCode(_ error: OCRJobError) -> String {
        switch error {
        case .imageUnavailable: return "image_unavailable"
        case .photokitTimeout: return VisualAnalysisErrorCode.photokitTimeout
        case .photokitMissingAsset: return VisualAnalysisErrorCode.photokitMissingAsset
        case .photokitNoCGImage: return VisualAnalysisErrorCode.photokitNoCGImage
        case .visionFailed: return "vision_failed"
        }
    }
}
