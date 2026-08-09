@preconcurrency import Photos
import Foundation

/// Fetches only image assets marked by Photos as screenshots.
final class PhotoKitScreenshotDiscovery: @unchecked Sendable {
    func fetchResult() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND ((mediaSubtypes & %d) != 0)",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: options)
    }

    func metadata(from result: PHFetchResult<PHAsset>) -> [PhotoAssetMetadata] {
        var assets: [PhotoAssetMetadata] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(
                PhotoAssetMetadata(
                    localIdentifier: asset.localIdentifier,
                    createdAt: asset.creationDate,
                    width: asset.pixelWidth,
                    height: asset.pixelHeight
                )
            )
        }
        return assets
    }
}
