@preconcurrency import Photos
import UIKit

/// Loads a UIImage suitable for multimodal encoding (network allowed for iCloud).
final class PhotoKitMultimodalImageLoader: @unchecked Sendable {
    private let manager = PHCachingImageManager()

    func loadUIImage(
        localIdentifier: String,
        longEdge: Double = MultimodalImagePolicy.current.longEdge
    ) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let target = CGSize(width: longEdge, height: longEdge)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            var resumed = false
            manager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if cancelled {
                    if !resumed { resumed = true; continuation.resume(returning: nil) }
                    return
                }
                if degraded, image != nil { return }
                if !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }
}
