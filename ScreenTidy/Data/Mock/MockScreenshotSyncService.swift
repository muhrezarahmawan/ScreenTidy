import Foundation

/// Sprint 2 mock for Home pull-to-refresh.
/// Simulates an incremental Photos resync; replace with real PhotoKit delta sync later.
actor MockScreenshotSyncService: ScreenshotSyncing {
    private let ingest: any ScreenshotIngesting
    /// Cycles outcomes so Simulator review can see up-to-date / organized / failure.
    private var pullCount = 0

    init(ingest: any ScreenshotIngesting) {
        self.ingest = ingest
    }

    func initialImport(progress: @Sendable (Double) -> Void) async throws -> ScreenshotSyncResult {
        progress(0)
        let added = try await ingest.mockIngestNewScreenshots(count: 12)
        progress(1)
        return added == 0 ? .synced : .organized(newCount: added)
    }

    func syncIncremental() async throws -> ScreenshotSyncResult {
        // Native refresh control stays visible for a short, calm delay.
        try await Task.sleep(nanoseconds: 850_000_000)
        pullCount += 1

        // Every 4th pull: failure (truthful toast — never “Screenshots synced”).
        if pullCount.isMultiple(of: 4) {
            AppLog.general.error("Mock screenshot sync: failed")
            throw AppError.underlying(message: "Mock sync failure")
        }

        // Every 3rd successful-cycle pull that isn't a failure: nothing changed.
        // pullCount 3, 6, 9… but 4, 8 already fail — so 3, 6, 9 show up-to-date when not failed.
        if pullCount.isMultiple(of: 3) {
            AppLog.general.info("Mock screenshot sync: up to date")
            return .upToDate
        }

        let newCount = (pullCount % 3) + 1
        let added = try await ingest.mockIngestNewScreenshots(count: newCount)
        AppLog.general.info("Mock screenshot sync: organized \(added) new")
        if added == 0 {
            return .synced
        }
        return .organized(newCount: added)
    }
}
