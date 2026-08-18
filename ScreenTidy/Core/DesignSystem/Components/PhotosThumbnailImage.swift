import SwiftUI

/// PhotoKit-backed image surface. Always fills and clips to the parent frame —
/// never lets source image aspect ratio change layout.
struct PhotosThumbnailImage<Placeholder: View>: View {
    /// Optional so drag-lift previews (outside the main hierarchy) don't crash if DI isn't injected.
    @Environment(AppDependencies.self) private var dependencies: AppDependencies?
    let localIdentifier: String?
    let targetSize: CGSize
    let contentMode: ThumbnailContentMode
    var allowsNetworkAccess = false
    /// Manual remount token (Visual Eval Retry). Must not change unless the user retries.
    var retryGeneration: Int = 0
    /// Main Visual Eval preview uses progressive degraded→final; neighbors stay first-usable.
    var deliveryStyle: PhotoKitImageDeliveryStyle = .firstUsable
    /// Non-observable diagnostics sink — mutations must not invalidate this view's parents.
    var loadProbe: ThumbnailLoadProbe? = nil
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var activeRequestID: UUID?
    @State private var phase: ScreenshotPreviewPhase = .idle
    @State private var loadedIdentity: ThumbnailLoadIdentity?
    @State private var loadingProgress: Double?

    private var loadIdentity: ThumbnailLoadIdentity? {
        guard let localIdentifier, !localIdentifier.isEmpty else { return nil }
        return ThumbnailLoadIdentity(
            localIdentifier: localIdentifier,
            retryGeneration: retryGeneration,
            targetWidth: Int(targetSize.width.rounded()),
            targetHeight: Int(targetSize.height.rounded()),
            allowsNetworkAccess: allowsNetworkAccess,
            deliveryStyle: deliveryStyle
        )
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode == .aspectFill ? .fill : .fit)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else if ScreenshotPreviewLoadController.canShowLoadingSpinner(phase: phase, hasImage: false),
                      allowsNetworkAccess {
                iCloudDownloadProgress(progress: loadingProgress)
            } else if phase == .failed {
                previewUnavailable
            } else {
                placeholder()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .task(id: loadIdentity) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        let thumbnails = dependencies?.thumbnailProvider
        guard let identity = loadIdentity, let thumbnails else {
            image = nil
            phase = .idle
            loadedIdentity = nil
            activeRequestID = nil
            return
        }

        let decision = ScreenshotPreviewLoadController.decisionForTaskStart(
            identity: identity,
            previousIdentity: loadedIdentity,
            currentlyHasImage: image != nil,
            currentPhase: phase
        )

        loadProbe?.noteTaskStart(assetID: identity.localIdentifier)

        guard decision.shouldStartRequest else {
            phase = decision.phase
            return
        }

        if let previous = activeRequestID {
            thumbnails.cancelRequest(previous)
        }

        let token = UUID()
        activeRequestID = token
        if decision.clearExistingImage {
            image = nil
        }
        phase = .loading
        loadingProgress = nil
        loadedIdentity = identity

        let progressHandler: (@Sendable (Double) -> Void)?
        var progressTask: Task<Void, Never>?
        var finishProgress: (@Sendable () -> Void)?
        if allowsNetworkAccess {
            let stream = AsyncStream<Double>.makeStream()
            progressHandler = { progress in
                stream.continuation.yield(min(1, max(0, progress)))
            }
            finishProgress = { stream.continuation.finish() }
            progressTask = Task { @MainActor in
                for await progress in stream.stream {
                    guard activeRequestID == token, image == nil else { continue }
                    loadingProgress = progress
                }
            }
        } else {
            progressHandler = nil
        }

        let applyUpdate: @MainActor (UIImage, PhotoKitImageQuality) -> Void = { img, quality in
            guard activeRequestID == token, loadedIdentity == identity else { return }
            image = img
            phase = ScreenshotPreviewLoadController.phaseAfterProgressiveUpdate(quality: quality)
            let probeQuality: ThumbnailLoadProbe.DisplayedQuality =
                quality == .final ? .final : .degraded
            loadProbe?.noteDisplayed(image: img, quality: probeQuality)
        }

        let detailed: PhotoKitThumbnailProvider.DetailedOutcome
        if let concrete = thumbnails as? PhotoKitThumbnailProvider {
            detailed = await concrete.requestThumbnailDetailed(
                localIdentifier: identity.localIdentifier,
                targetSize: targetSize,
                contentMode: contentMode,
                allowsNetworkAccess: allowsNetworkAccess,
                progressHandler: progressHandler,
                requestID: token,
                probe: loadProbe,
                deliveryStyle: deliveryStyle,
                onImageUpdate: { img, quality in
                    Task { @MainActor in
                        applyUpdate(img, quality)
                    }
                }
            )
            // firstUsable path never calls onImageUpdate — apply once at end.
            if deliveryStyle == .firstUsable, let loaded = detailed.image {
                applyUpdate(loaded, detailed.receivedFinal ? .final : .degraded)
            }
        } else {
            let result = await thumbnails.requestThumbnail(
                localIdentifier: identity.localIdentifier,
                targetSize: targetSize,
                contentMode: contentMode,
                allowsNetworkAccess: allowsNetworkAccess,
                progressHandler: progressHandler,
                requestID: token
            )
            detailed = .init(
                image: result?.image,
                timedOut: false,
                assetFound: result != nil,
                receivedFinal: result != nil
            )
            if let loaded = detailed.image {
                applyUpdate(loaded, .final)
            }
        }

        finishProgress?()
        progressTask?.cancel()

        guard activeRequestID == token, loadedIdentity == identity else { return }

        if Task.isCancelled {
            thumbnails.cancelRequest(token)
            phase = ScreenshotPreviewLoadController.phaseAfterTimeoutOrCancel(
                hasImage: image != nil,
                currentPhase: phase
            )
            activeRequestID = nil
            return
        }

        if image == nil, let loaded = detailed.image {
            // Safety net if updates were missed.
            image = loaded
            phase = detailed.receivedFinal ? .final : .degraded
        } else if image == nil {
            phase = .failed
        } else if detailed.timedOut {
            // Keep degraded/final — never replace a usable preview with unavailable.
            phase = ScreenshotPreviewLoadController.phaseAfterTimeoutOrCancel(
                hasImage: true,
                currentPhase: phase
            )
        } else if detailed.receivedFinal {
            phase = .final
        } else if phase == .loading {
            phase = image != nil ? .degraded : .failed
        }
        activeRequestID = nil
    }

    @ViewBuilder
    private var previewUnavailable: some View {
        ZStack {
            Color(red: 0.16, green: 0.17, blue: 0.19)
            Text("Preview unavailable")
                .font(STTypography.caption)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(12)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .accessibilityLabel("Preview unavailable")
    }

    @ViewBuilder
    private func iCloudDownloadProgress(progress: Double?) -> some View {
        ZStack {
            Color(red: 0.16, green: 0.17, blue: 0.19)

            VStack(spacing: 14) {
                Group {
                    if let progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.circular)
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                .controlSize(.large)
                .tint(.white)

                VStack(spacing: 4) {
                    Text("Downloading…")
                        .font(STTypography.caption)
                        .foregroundStyle(.white.opacity(0.92))
                    if let progress {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(STTypography.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .monospacedDigit()
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progressAccessibilityLabel(progress))
    }

    private func progressAccessibilityLabel(_ progress: Double?) -> String {
        if let progress {
            return "Downloading from iCloud, \(Int((progress * 100).rounded())) percent"
        }
        return "Downloading from iCloud"
    }
}
