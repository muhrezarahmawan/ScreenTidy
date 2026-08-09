@preconcurrency import Photos
import UIKit

/// Loads a downscaled CGImage for OCR. Releases UIImage after extracting CGImage.
final class PhotoKitOCRImageLoader: OCRImageLoading, @unchecked Sendable {
    private let manager = PHCachingImageManager()

    func loadCGImage(localIdentifier: String) async throws -> CGImage {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            throw OCRJobError.imageUnavailable
        }

        let longEdge = OCRPipeline.imageLongEdge
        let target = CGSize(width: longEdge, height: longEdge)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let image: UIImage? = await withCheckedContinuation { continuation in
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

        guard let image, let cgImage = image.cgImage else {
            throw OCRJobError.imageUnavailable
        }
        return cgImage
    }
}
