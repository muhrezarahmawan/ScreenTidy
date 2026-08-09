@preconcurrency import Photos
import UIKit

/// Shared, cancellable PhotoKit image loader. Grid calls disable network access so iCloud-only
/// assets stay placeholders; fullscreen/viewer calls may opt in and receive download progress.
final class PhotoKitThumbnailProvider: ThumbnailProviding, @unchecked Sendable {
    private let manager = PHCachingImageManager()
    private let lock = NSLock()
    private var requestIDs: [UUID: PHImageRequestID] = [:]

    func requestThumbnail(
        localIdentifier: String,
        targetSize: CGSize,
        contentMode: ThumbnailContentMode,
        allowsNetworkAccess: Bool,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async -> ThumbnailResult? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let token = UUID()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowsNetworkAccess
        if allowsNetworkAccess, let progressHandler {
            options.progressHandler = { progress, _, _, _ in
                progressHandler(Double(progress))
            }
        }
        let image: UIImage? = await withCheckedContinuation { continuation in
            var hasResumed = false
            let resume: (UIImage?) -> Void = { image in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
            let requestID = manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode == .aspectFill ? .aspectFill : .aspectFit,
                options: options
            ) { [weak self] image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if cancelled {
                    self?.remove(token)
                    resume(nil)
                    return
                }
                // Keep waiting for the final (non-degraded) delivery when possible.
                if degraded, image != nil { return }
                self?.remove(token)
                resume(image)
            }
            lock.lock()
            requestIDs[token] = requestID
            lock.unlock()
        }
        return image.map { ThumbnailResult(image: $0, requestID: token) }
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
