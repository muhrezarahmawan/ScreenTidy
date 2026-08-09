import Foundation
import UIKit

/// Ports for later sprints. Sprint 0 ships mocks only — no Photos/DB/AI/network.

protocol MemoryReading: Sendable {
    func fetchPromotedContexts() async throws -> [ContextCollection]
    func fetchUnassignedCount() async throws -> Int
    func fetchUnassignedContext() async throws -> ContextCollection?
    func fetchRecentScreenshots(limit: Int) async throws -> [ScreenshotMemory]
    func fetchScreenshot(id: ScreenshotMemoryID) async throws -> ScreenshotMemory?
    func fetchContext(id: ContextCollectionID) async throws -> ContextCollection?
    func fetchScreenshots(in contextID: ContextCollectionID) async throws -> [ScreenshotMemory]
    /// Scale-safe peek/page fetch — Home Needs Review uses limit 3; galleries page with offset.
    func fetchScreenshots(in contextID: ContextCollectionID, limit: Int, offset: Int) async throws -> [ScreenshotMemory]
}

protocol MemoryWriting: Sendable {
    func fetchContextsForPicker(excluding excludedID: ContextCollectionID?) async throws -> [ContextCollection]
    /// Add picker: non-archived normal Collections, excluding IDs that already contain every selected screenshot.
    func fetchContextsForAddPicker(
        screenshotIDs: Set<ScreenshotMemoryID>,
        excluding excludedID: ContextCollectionID?
    ) async throws -> [ContextCollection]
    func createContext(title: String, badgeEmoji: String?, badgeColor: String?) async throws -> ContextCollection
    func updateContext(id: ContextCollectionID, title: String?, badgeEmoji: String?, badgeColor: String?) async throws
    /// `deleteScreenshots` false = collection only (orphans → Needs Review). true = mock-remove Photos assets.
    /// Returns a mock undo token while a snapshot is retained (Sprint 2). Production PhotoKit path TBD.
    @discardableResult
    func deleteContext(id: ContextCollectionID, deleteScreenshots: Bool) async throws -> MockUndoToken
    /// Exclusive reassignment: all prior memberships removed; destination only; `source = user`.
    @discardableResult
    func moveScreenshots(ids: Set<ScreenshotMemoryID>, to destinationID: ContextCollectionID) async throws -> MockUndoToken
    /// Additive membership; keeps other Collections; leaves Needs Review when adding to a normal Collection.
    @discardableResult
    func addScreenshots(ids: Set<ScreenshotMemoryID>, to destinationID: ContextCollectionID) async throws -> MockUndoToken
    /// Removes one Collection membership only. Zero normal memberships → Needs Review.
    @discardableResult
    func removeScreenshots(ids: Set<ScreenshotMemoryID>, from collectionID: ContextCollectionID) async throws -> MockUndoToken
    /// Persist Home Collection order after a drag-reorder (ids = new front-to-back order).
    func reorderContexts(orderedIDs: [ContextCollectionID]) async throws
    /// After Undo re-creates Photos assets, point ScreenTidy rows at the new local identifiers.
    func remapPhotosLocalIdentifiers(_ mapping: [String: String]) async throws
}

/// Mock (and later real) restore for reversible mutations. Sprint 2 = in-memory snapshot only.
protocol MemoryUndoProviding: Sendable {
    @discardableResult
    func undo(token: MockUndoToken) async -> Bool
    func discardUndo(token: MockUndoToken) async
}

/// Incremental mock ingest used by screenshot sync. Production PhotoKit delta sync replaces this.
protocol ScreenshotIngesting: Sendable {
    @discardableResult
    func mockIngestNewScreenshots(count: Int) async throws -> Int
}

/// Unified local search across OCR, visual labels, Collections, and semantic metadata.
/// Production will back this with indexes/embeddings; Sprint 2 uses an in-memory mock.
protocol SearchProviding: Sendable {
    func search(query: String) async throws -> SearchResponse
}

protocol CleanupProviding: Sendable {
    func fetchCleanupOverview() async throws -> CleanupOverview
    func fetchDuplicateGroups() async throws -> [DuplicateGroup]
    func fetchOldScreenshots() async throws -> [ScreenshotMemory]
    /// Sprint 2 mock deletion only — removes from in-memory demo data. Does **not** call PhotoKit.
    /// Returns a mock undo token. Do not treat as a promise of production Photos restore.
    @discardableResult
    func mockRemoveScreenshots(ids: Set<ScreenshotMemoryID>) async throws -> MockUndoToken
}

protocol PhotosProviding: Sendable {
    var authorizationStatus: PhotosAccessStatus { get async }
    /// User-facing Settings trailing copy (Full Access / Limited Access / Access Off).
    var authorizationDescription: String { get async }
    func requestAuthorization() async -> PhotosAccessStatus
    @MainActor func presentLimitedLibraryPicker()
    /// Loads original image bytes so Undo can re-create Photos assets after a confirmed delete.
    func exportAssetsForRestore(localIdentifiers: [String]) async throws -> [PhotosAssetBackup]
    /// Permanently deletes assets from the user's Photos library (system confirmation may appear).
    func deleteAssets(localIdentifiers: [String]) async throws
    /// Re-creates deleted photos from backups. Returns `previousLocalIdentifier → newLocalIdentifier`.
    func restoreAssets(_ backups: [PhotosAssetBackup]) async throws -> [String: String]
}

/// Image payload captured before a Photos delete so Undo can put the asset back in the library.
struct PhotosAssetBackup: Sendable {
    let previousLocalIdentifier: String
    let imageData: Data
    let uniformTypeIdentifier: String?
    let creationDate: Date?
}

enum PhotosDeleteError: LocalizedError, Equatable {
    case notAuthorized
    /// User tapped “Don’t Allow” on the system Photos confirmation — not a failure.
    case userCancelled
    case photoKitFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photos access is required to delete screenshots."
        case .userCancelled:
            return nil
        case .photoKitFailed:
            return "Couldn't delete from Photos. Try again."
        case .exportFailed:
            return "Couldn't prepare screenshots for delete. Try again."
        }
    }

    var isUserCancellation: Bool {
        if case .userCancelled = self { return true }
        return false
    }
}

protocol ThumbnailProviding: Sendable {
    func requestThumbnail(
        localIdentifier: String,
        targetSize: CGSize,
        contentMode: ThumbnailContentMode,
        allowsNetworkAccess: Bool,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async -> ThumbnailResult?
    func cancelRequest(_ requestID: UUID)
}

extension ThumbnailProviding {
    func requestThumbnail(
        localIdentifier: String,
        targetSize: CGSize,
        contentMode: ThumbnailContentMode,
        allowsNetworkAccess: Bool
    ) async -> ThumbnailResult? {
        await requestThumbnail(
            localIdentifier: localIdentifier,
            targetSize: targetSize,
            contentMode: contentMode,
            allowsNetworkAccess: allowsNetworkAccess,
            progressHandler: nil
        )
    }
}

enum ThumbnailContentMode: Sendable {
    case aspectFit
    case aspectFill
}

struct ThumbnailResult: @unchecked Sendable {
    let image: UIImage
    let requestID: UUID
}

protocol Organizing: Sendable {
    /// Core organization (always on). Sprint 8 wires real classification;
    /// may still separate on-device vs future network processing for privacy.
    func organizeIfNeeded(screenshotID: ScreenshotMemoryID) async throws
}

/// Incremental screenshot library sync (Photos → local metadata).
/// Production: detect added/removed/changed assets only — never reprocess the whole library.
protocol ScreenshotSyncing: Sendable {
    func initialImport(progress: @Sendable (Double) -> Void) async throws -> ScreenshotSyncResult
    func syncIncremental() async throws -> ScreenshotSyncResult
}

/// Outcome of an incremental sync pass.
enum ScreenshotSyncResult: Equatable, Sendable {
    /// No Photos / library changes detected.
    case upToDate
    /// Sync completed; library aligned (no newly organized items to call out).
    case synced
    /// New screenshots were discovered and organized (mock or real pipeline).
    case organized(newCount: Int)
    /// Sync could not complete — never present as success / “Screenshots synced”.
    case failed
}

/// Feature-facing memory port: read/write + mock undo. Swap MockMemoryStore without rewriting VMs.
typealias MemoryRepository = MemoryReading & MemoryWriting & MemoryUndoProviding

protocol PhotoLibraryPersisting: Sendable {
    func upsertPhotoScreenshots(_ assets: [PhotoAssetMetadata]) async throws -> Int
    func markPhotoScreenshotsInaccessible(identifiers: Set<String>) async throws
    func removePhotoScreenshots(identifiers: Set<String>) async throws
    func clearFixtureScreenshots() async throws
    func photoScreenshotIdentifiers() async throws -> Set<String>
    func fetchNeedsReviewCount() async throws -> Int
    func fetchNeedsReviewPreview(limit: Int) async throws -> [ScreenshotMemory]
    func fetchScreenshots(page: Int, pageSize: Int) async throws -> [ScreenshotMemory]
    func setPhotosSyncCheckpoint(_ date: Date) async throws
}

// MARK: - Search suggestions

/// A prompt chip on the Search empty state. Tapping runs the same search engine.
struct SearchSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    /// Query string inserted into the search field.
    let title: String
}

/// Supplies empty-state search prompts. Sprint 2 = static mock; later = library/recents-aware.
protocol SearchSuggestionsProviding: Sendable {
    func suggestions() async -> [SearchSuggestion]
}
