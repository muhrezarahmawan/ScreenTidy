@preconcurrency import Photos
import Foundation

/// Reconciles PhotoKit screenshot identities with local metadata. It never performs a Photos
/// mutation: full-access disappearance only removes ScreenTidy's local metadata.
final class PhotoKitScreenshotSyncService: NSObject, ScreenshotSyncing, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let repository: any PhotoLibraryPersisting
    private let photos: any PhotosProviding
    private let discovery: PhotoKitScreenshotDiscovery
    private let lock = NSLock()
    private var retainedFetchResult: PHFetchResult<PHAsset>?

    /// Invoked on the main actor after an observer-driven sync so UI can refresh.
    var onDidSync: (@MainActor () -> Void)?

    init(
        repository: any PhotoLibraryPersisting,
        photos: any PhotosProviding,
        discovery: PhotoKitScreenshotDiscovery = PhotoKitScreenshotDiscovery()
    ) {
        self.repository = repository
        self.photos = photos
        self.discovery = discovery
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func initialImport(progress: @Sendable (Double) -> Void) async throws -> ScreenshotSyncResult {
        let status = await photos.authorizationStatus
        guard status == .full || status == .limited else { return .failed }
        progress(0)
        try await repository.clearFixtureScreenshots()
        progress(0.15)
        let result = discovery.fetchResult()
        let assets = discovery.metadata(from: result)
        progress(0.55)
        let inserted = try await repository.upsertPhotoScreenshots(assets)
        try await repository.setPhotosSyncCheckpoint(Date())
        retain(result)
        progress(1)
        return inserted > 0 ? .organized(newCount: inserted) : .synced
    }

    func syncIncremental() async throws -> ScreenshotSyncResult {
        let status = await photos.authorizationStatus
        guard status == .full || status == .limited else { return .failed }
        // One-time fixture → Photos handoff (keyed; safe on every reconcile).
        try await repository.clearFixtureScreenshots()
        let result = discovery.fetchResult()
        let assets = discovery.metadata(from: result)
        let current = Set(assets.map(\.localIdentifier))
        let persisted = try await repository.photoScreenshotIdentifiers()
        let missing = persisted.subtracting(current)
        if status == .full {
            try await repository.removePhotoScreenshots(identifiers: missing)
        } else {
            try await repository.markPhotoScreenshotsInaccessible(identifiers: missing)
        }
        let inserted = try await repository.upsertPhotoScreenshots(assets)
        retain(result)
        // UX checkpoint only; this is not a PhotoKit change token.
        try await repository.setPhotosSyncCheckpoint(Date())
        if inserted > 0 { return .organized(newCount: inserted) }
        return missing.isEmpty ? .upToDate : .synced
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        lock.lock()
        let result = retainedFetchResult
        if let result, let details = changeInstance.changeDetails(for: result) {
            retainedFetchResult = details.fetchResultAfterChanges
        }
        lock.unlock()
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.syncIncremental()
            let notify = self.onDidSync
            await MainActor.run {
                notify?()
            }
        }
    }

    private func retain(_ result: PHFetchResult<PHAsset>) {
        lock.lock()
        retainedFetchResult = result
        lock.unlock()
    }
}
