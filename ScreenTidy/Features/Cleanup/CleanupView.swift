import SwiftUI
import UIKit

// MARK: - Home

@MainActor
@Observable
final class CleanupViewModel {
    private let cleanupProvider: any CleanupProviding

    private(set) var state: LoadState<CleanupOverview> = .idle

    init(cleanupProvider: any CleanupProviding) {
        self.cleanupProvider = cleanupProvider
    }

    func reload() async {
        state = .loading
        do {
            let overview = try await cleanupProvider.fetchCleanupOverview()
            state = .loaded(overview)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(.underlying(message: error.localizedDescription))
        }
    }
}

struct CleanupView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: CleanupViewModel?

    var body: some View {
        Group {
            if let viewModel {
                CleanupScreen(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(STColor.background.ignoresSafeArea())
            }
        }
        .task {
            let vm = viewModel ?? CleanupViewModel(cleanupProvider: dependencies.cleanupProvider)
            if viewModel == nil {
                viewModel = vm
            }
            await vm.reload()
        }
    }
}

private struct CleanupScreen: View {
    @Bindable var viewModel: CleanupViewModel

    var body: some View {
        ScrollView {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, STSpacing.xxl)
                case .failed(let error):
                    STEmptyState(
                        title: "Couldn't load Cleanup",
                        message: error.localizedDescription,
                        actionTitle: "Try Again"
                    ) {
                        Task { await viewModel.reload() }
                    }
                case .loaded(let overview):
                    VStack(alignment: .leading, spacing: STSpacing.lg) {
                        Text("Cleanup")
                            .font(STTypography.greeting)
                            .foregroundStyle(STColor.label)

                        Text("What you can probably remove")
                            .font(STTypography.rowMeta)
                            .foregroundStyle(STColor.secondaryLabel)

                        NavigationLink(value: AppRoute.cleanupDuplicates) {
                            CleanupCategoryCard(
                                title: "Duplicates",
                                detail: "\(overview.duplicateScreenshotCount) screenshots · \(overview.duplicateGroupCount) groups",
                                systemImage: "square.on.square"
                            )
                        }
                        .buttonStyle(STCardPressStyle())

                        NavigationLink(value: AppRoute.cleanupOld) {
                            CleanupCategoryCard(
                                title: "Old Screenshots",
                                detail: "\(overview.oldScreenshotCount) screenshots",
                                subtitle: "Older than \(overview.oldThresholdMonths) months",
                                systemImage: "clock"
                            )
                        }
                        .buttonStyle(STCardPressStyle())
                    }
                }
            }
            .padding(.horizontal, STSpacing.page)
            .padding(.top, STSpacing.lg)
            .padding(.bottom, STSpacing.tabBarHeight + STSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .stTabRootAtmosphere()
        }
        .coordinateSpace(name: STHomeAtmosphereTokens.scrollCoordinateSpace)
        .stTabRootScrollBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.reload()
        }
    }
}

private struct CleanupCategoryCard: View {
    let title: String
    let detail: String
    var subtitle: String?
    let systemImage: String

    var body: some View {
        STPrimaryCard {
            HStack(alignment: .center, spacing: STSpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(STColor.secondaryLabel)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(STTypography.rowTitle)
                        .foregroundStyle(STColor.label)
                    Text(detail)
                        .font(STTypography.rowMeta)
                        .foregroundStyle(STColor.secondaryLabel)
                    if let subtitle {
                        Text(subtitle)
                            .font(STTypography.caption)
                            .foregroundStyle(STColor.tertiaryLabel)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(STColor.tertiaryLabel)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared selection + 3-column grid

enum CleanupGrid {
    static let columns = [
        GridItem(.flexible(), spacing: STSpacing.galleryGridGutter),
        GridItem(.flexible(), spacing: STSpacing.galleryGridGutter),
        GridItem(.flexible(), spacing: STSpacing.galleryGridGutter)
    ]
}

@MainActor
@Observable
final class CleanupSelectionController {
    var isSelecting = false
    var selectedIDs: Set<ScreenshotMemoryID> = []

    func exitSelecting() {
        isSelecting = false
        selectedIDs = []
    }

    func enterSelecting() {
        isSelecting = true
        selectedIDs = []
    }

    func toggle(_ id: ScreenshotMemoryID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func setSelected(_ id: ScreenshotMemoryID, selected: Bool) {
        if selected {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }

    /// Drag-select stroke: first cell sets mode; later cells follow without re-toggling.
    func applyDragSelect(id: ScreenshotMemoryID, session: inout STDragSelectSession) {
        guard !session.visited.contains(id) else { return }
        session.visited.insert(id)
        setSelected(id, selected: session.shouldSelect)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func selectAll(from ids: [ScreenshotMemoryID]) {
        selectedIDs = Set(ids)
    }

    func deselectAll() {
        selectedIDs = []
    }

    var selectedCount: Int { selectedIDs.count }

    func allSelected(from ids: [ScreenshotMemoryID]) -> Bool {
        !ids.isEmpty && selectedIDs.count == ids.count && ids.allSatisfy { selectedIDs.contains($0) }
    }
}

// MARK: - Duplicates review

struct CleanupDuplicatesView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var groups: [DuplicateGroup] = []
    @State private var screenshotsByID: [ScreenshotMemoryID: ScreenshotMemory] = [:]
    @State private var selection = CleanupSelectionController()
    @State private var showDeleteConfirm = false
    @State private var isLoading = true
    @State private var viewerPresentation: ScreenshotViewerPresentation?
    @State private var viewerFocusedID: ScreenshotMemoryID?
    @State private var selectableFrames: [ScreenshotMemoryID: CGRect] = [:]
    @State private var dragSelectSession: STDragSelectSession?
    @Namespace private var screenshotZoomNS

    private let selectCoordinateSpace = "cleanupDuplicatesSelect"

    private var allIDs: [ScreenshotMemoryID] {
        groups.flatMap(\.screenshotIDs)
    }

    private var galleryIDs: [ScreenshotMemoryID] { allIDs }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                STEmptyState(
                    title: "No duplicates",
                    message: "When ScreenTidy finds similar screenshots, they’ll show up here.",
                    systemImage: "square.on.square"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: STSpacing.xl) {
                        Text("\(allIDs.count) screenshots · \(groups.count) groups")
                            .font(STTypography.rowMeta)
                            .foregroundStyle(STColor.secondaryLabel)

                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            duplicateGroupSection(index: index, group: group)
                        }
                    }
                    .padding(.horizontal, STSpacing.page)
                    .padding(.top, STSpacing.lg)
                    .padding(.bottom, selection.isSelecting ? 100 : STSpacing.xl)
                    .stDragSelectContainer(
                        coordinateSpaceName: selectCoordinateSpace,
                        frames: $selectableFrames
                    )
                }
                .scrollDisabled(dragSelectSession != nil)
            }
        }
        .background(STColor.background.ignoresSafeArea())
        .navigationTitle("Duplicates")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(selection.isSelecting)
        .toolbar { cleanupToolbar }
        .safeAreaInset(edge: .bottom) {
            if selection.isSelecting {
                cleanupSelectionBar
            }
        }
        .alert(
            "Remove \(selection.selectedCount) Screenshots from ScreenTidy?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await performMockDelete() }
            }
        } message: {
            Text("This only removes local ScreenTidy metadata. Your Photos library is unchanged.")
        }
        .stScreenshotViewerOverlay(
            presentation: $viewerPresentation,
            focusedID: $viewerFocusedID,
            namespace: screenshotZoomNS
        )
        .task { await reload() }
    }

    @ViewBuilder
    private func duplicateGroupSection(index: Int, group: DuplicateGroup) -> some View {
        let memories = group.screenshotIDs.compactMap { screenshotsByID[$0] }
        VStack(alignment: .leading, spacing: STSpacing.sm) {
            Text("Group \(index + 1)")
                .font(STTypography.rowTitle)
                .foregroundStyle(STColor.label)
            Text("\(group.count) duplicates")
                .font(STTypography.rowMeta)
                .foregroundStyle(STColor.secondaryLabel)

            LazyVGrid(columns: CleanupGrid.columns, spacing: STSpacing.galleryGridGutter) {
                ForEach(memories) { shot in
                    cleanupThumb(shot, galleryIDs: galleryIDs)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var cleanupToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if selection.isSelecting {
                Button(selection.allSelected(from: allIDs) ? "Deselect All" : "Select All") {
                    if selection.allSelected(from: allIDs) {
                        selection.deselectAll()
                    } else {
                        selection.selectAll(from: allIDs)
                    }
                }
            } else if !groups.isEmpty {
                Button("Select") { selection.enterSelecting() }
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if selection.isSelecting {
                Button("Cancel") {
                    dragSelectSession = nil
                    selection.exitSelecting()
                }
            }
        }
    }

    private var cleanupSelectionBar: some View {
        HStack {
            Text("\(selection.selectedCount) Selected")
                .font(STTypography.rowTitle)
                .foregroundStyle(STColor.label)
            Spacer()
            if selection.selectedCount > 0 {
                Button("Remove \(selection.selectedCount)", role: .destructive) {
                    showDeleteConfirm = true
                }
                .font(STTypography.button)
            }
        }
        .padding(.horizontal, STSpacing.page)
        .padding(.vertical, STSpacing.md)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func cleanupThumb(_ shot: ScreenshotMemory, galleryIDs: [ScreenshotMemoryID]) -> some View {
        let selected = selection.selectedIDs.contains(shot.id)
        if selection.isSelecting {
            STScreenshotGridItem(
                memory: shot,
                isSelected: selected,
                showsSelectionChrome: true
            )
            .contentShape(Rectangle())
            .stDragSelectCell(
                id: shot.id,
                isEnabled: true,
                coordinateSpaceName: selectCoordinateSpace,
                frames: $selectableFrames,
                session: $dragSelectSession,
                isSelected: { selection.selectedIDs.contains($0) },
                apply: { id, session in
                    selection.applyDragSelect(id: id, session: &session)
                }
            )
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction {
                selection.toggle(shot.id)
            }
        } else {
            Button {
                openViewer(for: shot, galleryIDs: galleryIDs)
            } label: {
                STScreenshotGridItem(memory: shot)
                    .matchedGeometryEffect(
                        id: shot.id,
                        in: screenshotZoomNS,
                        properties: .frame,
                        anchor: .center,
                        isSource: viewerFocusedID != shot.id
                    )
                    .opacity(viewerFocusedID == shot.id ? 0 : 1)
            }
            .buttonStyle(STCardPressStyle())
        }
    }

    private func openViewer(for shot: ScreenshotMemory, galleryIDs: [ScreenshotMemoryID]) {
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.2)
            : .smooth(duration: 0.36)
        withAnimation(animation) {
            viewerFocusedID = shot.id
            viewerPresentation = ScreenshotViewerPresentation(
                initialID: shot.id,
                galleryIDs: galleryIDs,
                contextID: nil
            )
        }
    }

    private func reload() async {
        isLoading = true
        let loaded = (try? await dependencies.cleanupProvider.fetchDuplicateGroups()) ?? []
        groups = loaded
        var map: [ScreenshotMemoryID: ScreenshotMemory] = [:]
        for id in loaded.flatMap(\.screenshotIDs) {
            if let shot = try? await dependencies.memoryStore.fetchScreenshot(id: id) {
                map[id] = shot
            }
        }
        screenshotsByID = map
        isLoading = false
    }

    private func performMockDelete() async {
        let ids = selection.selectedIDs
        let count = ids.count
        // Sprint 2 mock — Undo restores demo data only, not Photos library assets.
        guard let token = try? await dependencies.cleanupProvider.mockRemoveScreenshots(ids: ids) else {
            return
        }
        selection.exitSelecting()
        await reload()
        dependencies.noteMemoryMutation()
        dependencies.presentUndoableFeedback(
            message: STFeedbackCopy.screenshotsDeleted(count: count),
            token: token,
            restoredMessage: STFeedbackCopy.screenshotsRestored(count: count),
            onRestored: { await reload() }
        )
    }
}

// MARK: - Old Screenshots review

struct CleanupOldScreenshotsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screenshots: [ScreenshotMemory] = []
    @State private var thresholdMonths = MockData.oldThresholdMonths
    @State private var selection = CleanupSelectionController()
    @State private var showDeleteConfirm = false
    @State private var isLoading = true
    @State private var viewerPresentation: ScreenshotViewerPresentation?
    @State private var viewerFocusedID: ScreenshotMemoryID?
    @State private var selectableFrames: [ScreenshotMemoryID: CGRect] = [:]
    @State private var dragSelectSession: STDragSelectSession?
    @Namespace private var screenshotZoomNS

    private let selectCoordinateSpace = "cleanupOldSelect"

    private var allIDs: [ScreenshotMemoryID] { screenshots.map(\.id) }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if screenshots.isEmpty {
                STEmptyState(
                    title: "No old screenshots",
                    message: "Nothing older than \(thresholdMonths) months right now.",
                    systemImage: "clock"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: STSpacing.md) {
                        Text("\(screenshots.count) screenshots")
                            .font(STTypography.rowMeta)
                            .foregroundStyle(STColor.secondaryLabel)
                        Text("Older than \(thresholdMonths) months")
                            .font(STTypography.caption)
                            .foregroundStyle(STColor.tertiaryLabel)

                        LazyVGrid(columns: CleanupGrid.columns, spacing: STSpacing.galleryGridGutter) {
                            ForEach(screenshots) { shot in
                                oldThumb(shot)
                            }
                        }
                    }
                    .padding(.horizontal, STSpacing.page)
                    .padding(.top, STSpacing.lg)
                    .padding(.bottom, selection.isSelecting ? 100 : STSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .stDragSelectContainer(
                        coordinateSpaceName: selectCoordinateSpace,
                        frames: $selectableFrames
                    )
                }
                .scrollDisabled(dragSelectSession != nil)
            }
        }
        .background(STColor.background.ignoresSafeArea())
        .navigationTitle("Old Screenshots")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(selection.isSelecting)
        .toolbar { oldToolbar }
        .safeAreaInset(edge: .bottom) {
            if selection.isSelecting {
                oldSelectionBar
            }
        }
        .alert(
            "Remove \(selection.selectedCount) Screenshots from ScreenTidy?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await performMockDelete() }
            }
        } message: {
            Text("This only removes local ScreenTidy metadata. Your Photos library is unchanged.")
        }
        .stScreenshotViewerOverlay(
            presentation: $viewerPresentation,
            focusedID: $viewerFocusedID,
            namespace: screenshotZoomNS
        )
        .task { await reload() }
    }

    @ToolbarContentBuilder
    private var oldToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if selection.isSelecting {
                Button(selection.allSelected(from: allIDs) ? "Deselect All" : "Select All") {
                    if selection.allSelected(from: allIDs) {
                        selection.deselectAll()
                    } else {
                        selection.selectAll(from: allIDs)
                    }
                }
            } else if !screenshots.isEmpty {
                Button("Select") { selection.enterSelecting() }
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if selection.isSelecting {
                Button("Cancel") {
                    dragSelectSession = nil
                    selection.exitSelecting()
                }
            }
        }
    }

    private var oldSelectionBar: some View {
        HStack {
            Text("\(selection.selectedCount) Selected")
                .font(STTypography.rowTitle)
                .foregroundStyle(STColor.label)
            Spacer()
            if selection.selectedCount > 0 {
                Button("Remove \(selection.selectedCount)", role: .destructive) {
                    showDeleteConfirm = true
                }
                .font(STTypography.button)
            }
        }
        .padding(.horizontal, STSpacing.page)
        .padding(.vertical, STSpacing.md)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func oldThumb(_ shot: ScreenshotMemory) -> some View {
        let selected = selection.selectedIDs.contains(shot.id)
        if selection.isSelecting {
            STScreenshotGridItem(
                memory: shot,
                isSelected: selected,
                showsSelectionChrome: true
            )
            .contentShape(Rectangle())
            .stDragSelectCell(
                id: shot.id,
                isEnabled: true,
                coordinateSpaceName: selectCoordinateSpace,
                frames: $selectableFrames,
                session: $dragSelectSession,
                isSelected: { selection.selectedIDs.contains($0) },
                apply: { id, session in
                    selection.applyDragSelect(id: id, session: &session)
                }
            )
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction {
                selection.toggle(shot.id)
            }
        } else {
            Button {
                openOldViewer(for: shot)
            } label: {
                STScreenshotGridItem(memory: shot)
                    .matchedGeometryEffect(
                        id: shot.id,
                        in: screenshotZoomNS,
                        properties: .frame,
                        anchor: .center,
                        isSource: viewerFocusedID != shot.id
                    )
                    .opacity(viewerFocusedID == shot.id ? 0 : 1)
            }
            .buttonStyle(STCardPressStyle())
        }
    }

    private func openOldViewer(for shot: ScreenshotMemory) {
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.2)
            : .smooth(duration: 0.36)
        withAnimation(animation) {
            viewerFocusedID = shot.id
            viewerPresentation = ScreenshotViewerPresentation(
                initialID: shot.id,
                galleryIDs: allIDs,
                contextID: nil
            )
        }
    }

    private func reload() async {
        isLoading = true
        if let overview = try? await dependencies.cleanupProvider.fetchCleanupOverview() {
            thresholdMonths = overview.oldThresholdMonths
        }
        screenshots = (try? await dependencies.cleanupProvider.fetchOldScreenshots()) ?? []
        isLoading = false
    }

    private func performMockDelete() async {
        let ids = selection.selectedIDs
        let count = ids.count
        // Sprint 2 mock — Undo restores demo data only, not Photos library assets.
        guard let token = try? await dependencies.cleanupProvider.mockRemoveScreenshots(ids: ids) else {
            return
        }
        selection.exitSelecting()
        await reload()
        dependencies.noteMemoryMutation()
        dependencies.presentUndoableFeedback(
            message: STFeedbackCopy.screenshotsDeleted(count: count),
            token: token,
            restoredMessage: STFeedbackCopy.screenshotsRestored(count: count),
            onRestored: { await reload() }
        )
    }
}

#Preview("Cleanup") {
    NavigationStack {
        CleanupView()
    }
    .environment(AppDependencies())
}
