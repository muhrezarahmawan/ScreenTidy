import Foundation

/// Bounded visual analysis drain. Newest-first via repository claim SQL.
/// Mirrors OCR queue lifecycle (strong Task capture — do not use detached+weak for workers).
/// Does not mutate Collections. Does not run Vision on the main actor.
final class VisualAnalysisProcessingQueue: VisualAnalysisScheduling, @unchecked Sendable {
    private let repository: any VisualAnalysisPersisting
    private let analyzer: any VisualAnalysisProviding
    private let images: any OCRImageLoading
    private let onVisualFinished: (@Sendable (ScreenshotMemoryID) -> Void)?
    private let lock = NSLock()
    private var inFlight = 0
    private var isScheduling = false

    init(
        repository: any VisualAnalysisPersisting,
        analyzer: any VisualAnalysisProviding,
        images: any OCRImageLoading,
        onVisualFinished: (@Sendable (ScreenshotMemoryID) -> Void)? = nil
    ) {
        self.repository = repository
        self.analyzer = analyzer
        self.images = images
        self.onVisualFinished = onVisualFinished
    }

    func kick() {
        VisualAnalysisDebugRuntime.update {
            $0.lastWakeAt = Date()
            $0.workerState = .running
        }
        // Strong capture like OCRProcessingQueue — detached+weak can drop work after claim.
        Task(priority: .utility) { [self] in
            await self.schedule()
        }
    }

    func reprocess(id: ScreenshotMemoryID) async {
        try? await repository.requestVisualReprocess(id: id)
        kick()
    }

    func reprocessAll() async {
        try? await repository.requestVisualReprocessAll(currentVersion: VisualAnalysisPipeline.currentVersion)
        kick()
    }

    private func schedule() async {
        lock.lock()
        if isScheduling {
            lock.unlock()
            VisualAnalysisDebugRuntime.update {
                $0.lastClaimResult = "busy_already_scheduling"
            }
            return
        }
        isScheduling = true
        lock.unlock()

        defer {
            lock.lock()
            let stillInFlight = inFlight
            isScheduling = false
            lock.unlock()
            VisualAnalysisDebugRuntime.update {
                $0.workerState = stillInFlight > 0 ? .running : .idle
            }
        }

        do {
            let staleBefore = Date().addingTimeInterval(-VisualAnalysisPipeline.staleClaimInterval)
            _ = try await repository.recoverStaleVisualClaims(olderThan: staleBefore)
            _ = try await repository.enqueueStaleVersionVisual(
                currentVersion: VisualAnalysisPipeline.currentVersion
            )
        } catch {
            let message = VisualAnalysisErrorCode.sanitizeDebugNote(error.localizedDescription)
            AppLog.general.error("Visual recover failed: \(message, privacy: .public)")
            VisualAnalysisDebugRuntime.update {
                $0.lastError = "recover: \(message)"
                $0.workerState = .stopped
            }
        }

        while true {
            lock.lock()
            let canStart = inFlight < VisualAnalysisPipeline.maxConcurrency
            lock.unlock()
            guard canStart else {
                VisualAnalysisDebugRuntime.update {
                    $0.lastClaimResult = "concurrency_full"
                }
                break
            }

            VisualAnalysisDebugRuntime.update {
                $0.lastClaimAttemptAt = Date()
            }

            let claim: VisualAnalysisClaim?
            do {
                claim = try await repository.claimNextVisualJob(
                    currentVersion: VisualAnalysisPipeline.currentVersion,
                    now: Date()
                )
            } catch {
                let message = VisualAnalysisErrorCode.sanitizeDebugNote(error.localizedDescription)
                AppLog.general.error("Visual claim failed: \(message, privacy: .public)")
                VisualAnalysisDebugRuntime.update {
                    $0.lastError = "claim: \(message)"
                    $0.lastClaimResult = "error"
                    $0.workerState = .stopped
                }
                break
            }

            guard let claim else {
                VisualAnalysisDebugRuntime.update {
                    $0.lastClaimResult = "empty"
                    $0.workerState = .idle
                }
                break
            }

            VisualAnalysisDebugRuntime.update {
                $0.lastClaimedID = claim.id.rawValue.uuidString
                $0.lastClaimResult = "claimed"
            }

            lock.lock()
            inFlight += 1
            lock.unlock()

            Task(priority: .utility) { [self] in
                await self.run(claim)
            }
        }
    }

    private func run(_ claim: VisualAnalysisClaim) async {
        defer {
            lock.lock()
            inFlight = max(0, inFlight - 1)
            lock.unlock()
            kick()
        }

        do {
            let cgImage = try await images.loadCGImage(localIdentifier: claim.photosLocalIdentifier)
            let result = try await analyzer.analyze(cgImage: cgImage)
            try await repository.completeVisualSuccess(
                id: claim.id,
                result: result,
                version: VisualAnalysisPipeline.currentVersion
            )
            AppLog.general.info("Visual analysis completed for one screenshot")
            VisualAnalysisDebugRuntime.update {
                $0.lastCompletedID = claim.id.rawValue.uuidString
                $0.processedThisSession += 1
                if result.featurePrintStatus == "failed",
                   let code = result.featurePrintErrorCode {
                    $0.lastError = "partial: \(code)"
                } else {
                    $0.lastError = nil
                }
            }
            onVisualFinished?(claim.id)
        } catch let error as VisualAnalysisJobError {
            await finish(claimID: claim.id, jobError: error)
        } catch let error as OCRJobError {
            await finish(claimID: claim.id, jobError: mapOCRImageError(error))
        } catch {
            await finish(claimID: claim.id, jobError: .unknown)
            VisualAnalysisDebugRuntime.update {
                $0.lastError = "unknown: \(VisualAnalysisErrorCode.sanitizeDebugNote(error.localizedDescription))"
            }
        }
    }

    private func mapOCRImageError(_ error: OCRJobError) -> VisualAnalysisJobError {
        switch error {
        case .photokitTimeout:
            return .photokitTimeout
        case .photokitMissingAsset, .imageUnavailable:
            return .photokitMissingAsset
        case .photokitNoCGImage:
            return .photokitNoCGImage
        case .visionFailed:
            return .visionPerformFailed
        }
    }

    private func finish(claimID: ScreenshotMemoryID, jobError: VisualAnalysisJobError) async {
        let code = jobError.persistedCode
        if jobError.isTerminalInaccessible {
            try? await repository.completeVisualInaccessible(id: claimID, errorCode: code)
            VisualAnalysisDebugRuntime.update { $0.lastError = "terminal: \(code)" }
        } else {
            try? await repository.completeVisualFailure(id: claimID, errorCode: code)
            VisualAnalysisDebugRuntime.update { $0.lastError = "retryable: \(code)" }
        }
        onVisualFinished?(claimID)
    }
}

final class NoOpVisualAnalysisScheduler: VisualAnalysisScheduling, @unchecked Sendable {
    func kick() {}
    func reprocess(id: ScreenshotMemoryID) async {}
    func reprocessAll() async {}
}
