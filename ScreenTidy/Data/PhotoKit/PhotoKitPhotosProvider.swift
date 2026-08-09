@preconcurrency import Photos
import PhotosUI
import UIKit

/// PhotoKit authorization + delete/restore adapter (user-confirmed destructive deletes).
/// `.readWrite` is the least PhotoKit level that can enumerate, read, and delete.
final class PhotoKitPhotosProvider: PhotosProviding, @unchecked Sendable {
    var authorizationStatus: PhotosAccessStatus {
        get async { Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }
    }

    var authorizationDescription: String {
        get async { await authorizationStatus.settingsLabel }
    }

    func requestAuthorization() async -> PhotosAccessStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return Self.map(status)
    }

    @MainActor
    func presentLimitedLibraryPicker() {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited,
              let viewController = UIApplication.shared.topmostViewController
        else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController)
    }

    func exportAssetsForRestore(localIdentifiers: [String]) async throws -> [PhotosAssetBackup] {
        let unique = Array(Set(localIdentifiers.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return [] }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotosDeleteError.notAuthorized
        }

        var backups: [PhotosAssetBackup] = []
        backups.reserveCapacity(unique.count)

        for identifier in unique {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            guard let asset = assets.firstObject else { continue }
            guard let backup = await Self.exportBackup(for: asset, previousLocalIdentifier: identifier) else {
                throw PhotosDeleteError.exportFailed
            }
            backups.append(backup)
        }

        guard backups.count == unique.count else {
            throw PhotosDeleteError.exportFailed
        }
        return backups
    }

    func deleteAssets(localIdentifiers: [String]) async throws {
        let unique = Array(Set(localIdentifiers.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotosDeleteError.notAuthorized
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: unique, options: nil)
        guard assets.count > 0 else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            if Self.isUserCancelledPhotosChange(error) {
                throw PhotosDeleteError.userCancelled
            }
            AppLog.general.error(
                "PhotoKit delete failed: \(error.localizedDescription, privacy: .public)"
            )
            throw PhotosDeleteError.photoKitFailed
        }
    }

    func restoreAssets(_ backups: [PhotosAssetBackup]) async throws -> [String: String] {
        guard !backups.isEmpty else { return [:] }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotosDeleteError.notAuthorized
        }

        var mapping: [String: String] = [:]
        mapping.reserveCapacity(backups.count)

        for backup in backups {
            let newIdentifier: String = try await withCheckedThrowingContinuation { continuation in
                var placeholderIdentifier: String?
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    if let uti = backup.uniformTypeIdentifier, !uti.isEmpty {
                        options.uniformTypeIdentifier = uti
                    }
                    request.addResource(with: .photo, data: backup.imageData, options: options)
                    if let creationDate = backup.creationDate {
                        request.creationDate = creationDate
                    }
                    placeholderIdentifier = request.placeholderForCreatedAsset?.localIdentifier
                }, completionHandler: { success, error in
                    if success, let placeholderIdentifier, !placeholderIdentifier.isEmpty {
                        continuation.resume(returning: placeholderIdentifier)
                        return
                    }
                    if let error, Self.isUserCancelledPhotosChange(error) {
                        continuation.resume(throwing: PhotosDeleteError.userCancelled)
                        return
                    }
                    AppLog.general.error(
                        "PhotoKit restore failed: \(error?.localizedDescription ?? "unknown", privacy: .public)"
                    )
                    continuation.resume(throwing: PhotosDeleteError.photoKitFailed)
                })
            }
            mapping[backup.previousLocalIdentifier] = newIdentifier
        }

        return mapping
    }

    /// System delete sheet — “Don’t Allow” surfaces as `PHPhotosError.userCancelled` (3072).
    private static func isUserCancelledPhotosChange(_ error: Error) -> Bool {
        if let photosError = error as? PHPhotosError, photosError.code == .userCancelled {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain,
           nsError.code == PHPhotosError.Code.userCancelled.rawValue {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isUserCancelledPhotosChange(underlying)
        }
        return false
    }

    private static func exportBackup(
        for asset: PHAsset,
        previousLocalIdentifier: String
    ) async -> PhotosAssetBackup? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred = resources.first(where: { $0.type == .fullSizePhoto })
            ?? resources.first(where: { $0.type == .photo })
        if let preferred {
            if let data = await requestResourceData(preferred) {
                return PhotosAssetBackup(
                    previousLocalIdentifier: previousLocalIdentifier,
                    imageData: data,
                    uniformTypeIdentifier: preferred.uniformTypeIdentifier,
                    creationDate: asset.creationDate
                )
            }
        }

        // Fallback when resource export isn't available (e.g. some iCloud states).
        guard let (data, uti) = await requestImageData(for: asset) else { return nil }
        return PhotosAssetBackup(
            previousLocalIdentifier: previousLocalIdentifier,
            imageData: data,
            uniformTypeIdentifier: uti,
            creationDate: asset.creationDate
        )
    }

    private static func requestResourceData(_ resource: PHAssetResource) async -> Data? {
        await withCheckedContinuation { continuation in
            var buffer = Data()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { chunk in
                    buffer.append(chunk)
                },
                completionHandler: { error in
                    if error != nil || buffer.isEmpty {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: buffer)
                    }
                }
            )
        }
    }

    private static func requestImageData(for asset: PHAsset) async -> (Data, String?)? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, uti, _, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                if cancelled || data == nil || data?.isEmpty == true {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (data!, uti))
            }
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotosAccessStatus {
        switch status {
        case .authorized: .full
        case .limited: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}

private extension UIApplication {
    var topmostViewController: UIViewController? {
        connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .rootViewController?
            .topmostPresented
    }
}

private extension UIViewController {
    var topmostPresented: UIViewController {
        if let presentedViewController { return presentedViewController.topmostPresented }
        if let navigation = self as? UINavigationController, let visible = navigation.visibleViewController {
            return visible.topmostPresented
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.topmostPresented
        }
        return self
    }
}
