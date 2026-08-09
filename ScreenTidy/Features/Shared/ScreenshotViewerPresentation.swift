import SwiftUI

/// Session for the Photos-style fullscreen viewer presented **over** a gallery
/// (not pushed on the navigation stack), so swipe-down can reveal the real grid.
struct ScreenshotViewerPresentation: Identifiable, Equatable {
    let initialID: ScreenshotMemoryID
    let galleryIDs: [ScreenshotMemoryID]
    let contextID: ContextCollectionID?

    var id: ScreenshotMemoryID { initialID }
}

extension View {
    /// Hosts the fullscreen screenshot viewer as a full-screen overlay above this view.
    func stScreenshotViewerOverlay(
        presentation: Binding<ScreenshotViewerPresentation?>,
        focusedID: Binding<ScreenshotMemoryID?>,
        namespace: Namespace.ID
    ) -> some View {
        modifier(
            ScreenshotViewerOverlayModifier(
                presentation: presentation,
                focusedID: focusedID,
                namespace: namespace
            )
        )
    }
}

private struct ScreenshotViewerOverlayModifier: ViewModifier {
    @Binding var presentation: ScreenshotViewerPresentation?
    @Binding var focusedID: ScreenshotMemoryID?
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .overlay {
                if let session = presentation {
                    ScreenshotDetailView(
                        screenshotID: session.initialID,
                        galleryContextID: session.contextID,
                        galleryIDs: session.galleryIDs,
                        zoomNamespace: namespace,
                        onDismissRequest: {
                            // Clear focus before tearing down presentation so thumbs
                            // aren’t left opacity-0 without a destination.
                            focusedID = nil
                            presentation = nil
                        },
                        onCurrentIDChange: { focusedID = $0 }
                    )
                    .id(session.initialID)
                    .transition(.opacity)
                    .zIndex(100)
                    .ignoresSafeArea()
                }
            }
            .onChange(of: presentation) { _, newValue in
                if newValue == nil {
                    focusedID = nil
                } else if focusedID == nil {
                    focusedID = newValue?.initialID
                }
            }
    }
}
