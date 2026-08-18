@preconcurrency import Photos
import UIKit

/// Loads a downscaled CGImage for OCR/visual. Releases UIImage after extracting CGImage.
/// Bounded so a single stuck PHAsset cannot block the queue forever.
final class PhotoKitOCRImageLoader: OCRImageLoading, @unchecked Sendable {
    private let manager = PHCachingImageManager()
    /// Hard ceiling for PhotoKit delivery (iCloud / hung callbacks).
    private let requestTimeoutNanoseconds: UInt64 = 20_000_000_000
    /// Long-edge pixel budget for this loader instance (OCR and Visual may differ).
    private let longEdge: CGFloat

    init(longEdge: CGFloat = OCRPipeline.imageLongEdge) {
        self.longEdge = longEdge
    }

    func loadCGImage(localIdentifier: String) async throws -> CGImage {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            throw OCRJobError.photokitMissingAsset
        }

        let target = CGSize(width: longEdge, height: longEdge)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        final class RequestState: @unchecked Sendable {
            let lock = NSLock()
            var resumed = false
            var timedOut = false
        }
        let state = RequestState()

        enum LoadResult: Sendable {
            case image(UIImage)
            case empty
        }

        let loadResult: LoadResult = await withCheckedContinuation { continuation in
            let resumeOnce: (LoadResult) -> Void = { result in
                state.lock.lock()
                defer { state.lock.unlock() }
                guard !state.resumed else { return }
                state.resumed = true
                continuation.resume(returning: result)
            }

            var requestID: PHImageRequestID = PHInvalidImageRequestID
            requestID = manager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                if cancelled {
                    resumeOnce(.empty)
                    return
                }
                if degraded, image != nil { return }
                if let image {
                    resumeOnce(.image(image))
                } else {
                    resumeOnce(.empty)
                }
            }
            let cancellableRequestID = requestID

            Task {
                try? await Task.sleep(nanoseconds: self.requestTimeoutNanoseconds)
                state.lock.lock()
                state.timedOut = true
                let alreadyResumed = state.resumed
                state.lock.unlock()
                if cancellableRequestID != PHInvalidImageRequestID {
                    self.manager.cancelImageRequest(cancellableRequestID)
                }
                if !alreadyResumed {
                    resumeOnce(.empty)
                }
            }
        }

        switch loadResult {
        case .image(let image):
            guard let cgImage = image.cgImage else {
                throw OCRJobError.photokitNoCGImage
            }
            return cgImage
        case .empty:
            state.lock.lock()
            let timedOut = state.timedOut
            state.lock.unlock()
            if timedOut {
                throw OCRJobError.photokitTimeout
            }
            throw OCRJobError.photokitNoCGImage
        }
    }
}
