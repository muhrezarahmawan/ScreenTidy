import SwiftUI

// MARK: - Frame reporting

struct STScreenshotFramePreferenceKey: PreferenceKey {
    static var defaultValue: [ScreenshotMemoryID: CGRect] = [:]

    static func reduce(
        value: inout [ScreenshotMemoryID: CGRect],
        nextValue: () -> [ScreenshotMemoryID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Drag session

/// Photos-style drag select: first cell sets select vs deselect; later cells follow.
struct STDragSelectSession {
    let shouldSelect: Bool
    var visited: Set<ScreenshotMemoryID> = []
}

// MARK: - Container (frames only — no gesture, so whitespace scrolls)

private struct STDragSelectContainerModifier: ViewModifier {
    let coordinateSpaceName: String
    @Binding var frames: [ScreenshotMemoryID: CGRect]

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(coordinateSpaceName))
            .onPreferenceChange(STScreenshotFramePreferenceKey.self) { frames = $0 }
    }
}

// MARK: - Cell gesture (only claims touches that begin on a thumbnail)

private struct STDragSelectCellModifier: ViewModifier {
    let id: ScreenshotMemoryID
    let isEnabled: Bool
    let coordinateSpaceName: String
    @Binding var frames: [ScreenshotMemoryID: CGRect]
    @Binding var session: STDragSelectSession?
    var isSelected: (ScreenshotMemoryID) -> Bool
    var apply: (ScreenshotMemoryID, inout STDragSelectSession) -> Void

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: STScreenshotFramePreferenceKey.self,
                        value: [id: geo.frame(in: .named(coordinateSpaceName))]
                    )
                }
            }
            .modifier(
                ConditionalCellDragGesture(
                    isEnabled: isEnabled,
                    gesture: cellDragGesture
                )
            )
    }

    private var cellDragGesture: some Gesture {
        // Gesture lives on the cell only — whitespace / gaps go to ScrollView.
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged(handleChanged)
            .onEnded { _ in session = nil }
    }

    private func handleChanged(_ value: DragGesture.Value) {
        if session == nil {
            // Touch began on this thumbnail.
            var next = STDragSelectSession(shouldSelect: !isSelected(id))
            apply(id, &next)
            session = next
        }

        guard var current = session else { return }
        // Keep selecting while the finger moves across other cells.
        if let hit = frames.first(where: { $0.value.contains(value.location) })?.key {
            apply(hit, &current)
            session = current
        }
    }
}

private struct ConditionalCellDragGesture<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if isEnabled {
            // Wins over scroll only when the touch starts on this cell.
            content.highPriorityGesture(gesture)
        } else {
            content
        }
    }
}

extension View {
    /// Named space + frame collection for drag-select. Does **not** install a grid gesture
    /// (so pans on whitespace scroll normally).
    func stDragSelectContainer(
        coordinateSpaceName: String,
        frames: Binding<[ScreenshotMemoryID: CGRect]>
    ) -> some View {
        modifier(
            STDragSelectContainerModifier(
                coordinateSpaceName: coordinateSpaceName,
                frames: frames
            )
        )
    }

    /// Frame reporter + per-cell drag-select. Attach to each thumbnail in selection mode.
    func stDragSelectCell(
        id: ScreenshotMemoryID,
        isEnabled: Bool,
        coordinateSpaceName: String,
        frames: Binding<[ScreenshotMemoryID: CGRect]>,
        session: Binding<STDragSelectSession?>,
        isSelected: @escaping (ScreenshotMemoryID) -> Bool,
        apply: @escaping (ScreenshotMemoryID, inout STDragSelectSession) -> Void
    ) -> some View {
        modifier(
            STDragSelectCellModifier(
                id: id,
                isEnabled: isEnabled,
                coordinateSpaceName: coordinateSpaceName,
                frames: frames,
                session: session,
                isSelected: isSelected,
                apply: apply
            )
        )
    }
}
