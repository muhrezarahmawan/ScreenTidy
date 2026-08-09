import Foundation
import UIKit

/// Sprint 2 mock Photos authorization. Settings and onboarding share this status.
/// Replace with PhotoKit-backed provider in a later sprint.
actor MockPhotosProvider: PhotosProviding {
    private var status: MockPhotosAccess

    init(initialStatus: MockPhotosAccess = .notDetermined) {
        self.status = initialStatus
    }

    func setStatus(_ status: MockPhotosAccess) {
        self.status = status
    }

    var authorizationStatus: MockPhotosAccess {
        get async { status }
    }

    var authorizationDescription: String {
        get async { status.settingsLabel }
    }

    func requestAuthorization() async -> PhotosAccessStatus {
        status
    }

    @MainActor
    func presentLimitedLibraryPicker() {}

    func exportAssetsForRestore(localIdentifiers: [String]) async throws -> [PhotosAssetBackup] {
        // Preview / mock — nothing to export.
        []
    }

    func deleteAssets(localIdentifiers: [String]) async throws {
        // Preview / mock — no PhotoKit library to mutate.
    }

    func restoreAssets(_ backups: [PhotosAssetBackup]) async throws -> [String: String] {
        // Preview / mock — map old → old so callers can still exercise remap.
        Dictionary(uniqueKeysWithValues: backups.map { ($0.previousLocalIdentifier, $0.previousLocalIdentifier) })
    }
}

struct MockThumbnailProvider: ThumbnailProviding {
    func requestThumbnail(
        localIdentifier: String,
        targetSize: CGSize,
        contentMode: ThumbnailContentMode,
        allowsNetworkAccess: Bool,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async -> ThumbnailResult? { nil }

    func cancelRequest(_ requestID: UUID) {}
}
