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
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var activeRequestID: UUID?
    @State private var networkLoad: NetworkLoadState = .idle

    private enum NetworkLoadState: Equatable {
        case idle
        /// Waiting for PhotoKit; progress is nil until iCloud reports a fraction.
        case downloading(progress: Double?)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode == .aspectFill ? .fill : .fit)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else if case .downloading(let progress) = networkLoad {
                iCloudDownloadProgress(progress: progress)
            } else {
                placeholder()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .task(id: localIdentifier) {
            await loadImage()
        }
        .onDisappear {
            if let activeRequestID {
                dependencies?.thumbnailProvider.cancelRequest(activeRequestID)
                self.activeRequestID = nil
            }
        }
    }

    @MainActor
    private func loadImage() async {
        let thumbnails = dependencies?.thumbnailProvider
        if let activeRequestID {
            thumbnails?.cancelRequest(activeRequestID)
            self.activeRequestID = nil
        }
        guard let localIdentifier, let thumbnails else {
            image = nil
            networkLoad = .idle
            return
        }

        image = nil
        networkLoad = allowsNetworkAccess ? .downloading(progress: nil) : .idle

        let progressHandler: (@Sendable (Double) -> Void)?
        var progressTask: Task<Void, Never>?
        var finishProgress: (@Sendable () -> Void)?
        if allowsNetworkAccess {
            let stream = AsyncStream<Double>.makeStream()
            progressHandler = { progress in
                stream.continuation.yield(min(1, max(0, progress)))
            }
            finishProgress = {
                stream.continuation.finish()
            }
            progressTask = Task { @MainActor in
                for await progress in stream.stream {
                    networkLoad = .downloading(progress: progress)
                }
            }
        } else {
            progressHandler = nil
        }

        let result = await thumbnails.requestThumbnail(
            localIdentifier: localIdentifier,
            targetSize: targetSize,
            contentMode: contentMode,
            allowsNetworkAccess: allowsNetworkAccess,
            progressHandler: progressHandler
        )

        finishProgress?()
        progressTask?.cancel()

        if Task.isCancelled {
            if let requestID = result?.requestID {
                thumbnails.cancelRequest(requestID)
            }
            return
        }
        activeRequestID = result?.requestID
        image = result?.image
        networkLoad = .idle
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
