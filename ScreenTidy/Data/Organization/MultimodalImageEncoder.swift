import UIKit

/// Encodes a PhotoKit-backed screenshot for ephemeral multimodal understanding.
enum MultimodalImageEncoder {
    static func jpegData(
        from image: UIImage,
        policy: MultimodalImagePolicy = .current
    ) -> Data? {
        let scaled = scaledPreservingAspect(image, longEdge: policy.longEdge)
        return scaled.jpegData(compressionQuality: policy.jpegQuality)
    }

    static func scaledPreservingAspect(_ image: UIImage, longEdge: Double) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let longest = max(size.width, size.height)
        // Never upscale.
        guard Double(longest) > longEdge else { return image }
        let scale = CGFloat(longEdge) / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
