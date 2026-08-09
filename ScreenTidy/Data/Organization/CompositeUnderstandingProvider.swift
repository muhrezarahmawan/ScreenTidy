import Foundation

/// Routes to the ephemeral gateway when consent + URL allow; otherwise on-device stand-in.
/// Gateway base URL is resolved **per request** so DEBUG Inspector Save takes effect immediately.
struct CompositeUnderstandingProvider: UnderstandingProviding {
    var configuration: AppConfiguration
    var onDevice: OnDeviceStructuredUnderstandingProvider
    var imageLoader: PhotoKitMultimodalImageLoader

    init(
        configuration: AppConfiguration,
        onDevice: OnDeviceStructuredUnderstandingProvider = OnDeviceStructuredUnderstandingProvider(),
        imageLoader: PhotoKitMultimodalImageLoader = PhotoKitMultimodalImageLoader()
    ) {
        self.configuration = configuration
        self.onDevice = onDevice
        self.imageLoader = imageLoader
    }

    func understand(_ input: UnderstandingInput) async throws -> ScreenshotUnderstanding {
        var enriched = input
        let normalized = OrganizationOCRNormalizer.normalize(input.ocrText)
        let cloudURL = UnderstandingGatewayConfiguration.baseURL(from: configuration)
        let needsImage = input.allowMultimodal && (normalized.isEmpty || cloudURL != nil)

        OrganizationPipelineDebugStore.update(
            screenshotID: input.screenshotID,
            stage: .preparing,
            detail: cloudURL.map { "Gateway URL resolved: \($0.absoluteString)" } ?? "No gateway URL — on-device path",
            gatewayHost: cloudURL?.host,
            ocrAttached: !normalized.isEmpty,
            collectionContextAttached: !input.eligibleCollectionContexts.isEmpty,
            batchContext: input.batchMemberIDs.count > 1
        )

        if needsImage, enriched.imageJPEGData == nil, let localID = input.photosLocalIdentifier {
            if let uiImage = await imageLoader.loadUIImage(localIdentifier: localID),
               let jpeg = MultimodalImageEncoder.jpegData(from: uiImage) {
                enriched.imageJPEGData = jpeg
            }
        }

        OrganizationPipelineDebugStore.update(
            screenshotID: input.screenshotID,
            stage: enriched.imageJPEGData == nil ? .ocrAttached : .imageLoaded,
            detail: enriched.imageJPEGData == nil
                ? "Image not attached (OCR-only or load failed)"
                : "JPEG attached (\(enriched.imageJPEGData?.count ?? 0) bytes metadata only)",
            imageAttached: enriched.imageJPEGData != nil,
            ocrAttached: !normalized.isEmpty
        )

        if input.allowMultimodal, let cloudURL {
            let cloud = EphemeralMultimodalUnderstandingProvider(baseURL: cloudURL)
            // Image-only must have pixels for multimodal attempt.
            if normalized.isEmpty, enriched.imageJPEGData == nil {
                OrganizationPipelineDebugStore.update(
                    screenshotID: input.screenshotID,
                    stage: .failed,
                    detail: "Multimodal required image but PhotoKit load failed",
                    failureCategory: .malformedResponse,
                    gatewayHost: cloudURL.host,
                    imageAttached: false,
                    ocrAttached: false
                )
                return ScreenshotUnderstanding(
                    summary: nil,
                    typeFacets: [],
                    entities: [],
                    locations: [],
                    dates: [],
                    visualDescriptors: ["image_unavailable"],
                    candidateCollections: [],
                    proposedNewCollection: nil,
                    reasonSignals: ["image_unavailable"],
                    provider: "gateway-skipped",
                    normalizedOCRPreview: nil
                )
            }
            do {
                // Do not fall back to on-device when a gateway URL is configured —
                // smoke tests must prove the real multimodal path.
                return try await cloud.understand(enriched)
            } catch UnderstandingError.pendingNetwork {
                throw UnderstandingError.pendingNetwork
            } catch {
                OrganizationPipelineDebugStore.update(
                    screenshotID: input.screenshotID,
                    stage: .failed,
                    detail: "Gateway understand failed closed (no on-device fallback)",
                    failureCategory: .malformedResponse,
                    gatewayHost: cloudURL.host
                )
                throw UnderstandingError.malformed
            }
        }

        let onDeviceResult = try await onDevice.understand(enriched)
        OrganizationPipelineDebugStore.update(
            screenshotID: input.screenshotID,
            stage: .structuredCandidateDecoded,
            detail: "On-device provider (gateway not used)",
            provider: onDeviceResult.provider
        )
        return onDeviceResult
    }
}
