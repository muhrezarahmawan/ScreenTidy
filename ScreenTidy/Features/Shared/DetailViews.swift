import SwiftUI
import UIKit

/// Fit-to-screen PhotoKit target for `ScreenshotDetailView` hero images.
/// Uses display × scale (not Visual Eval’s 1200 cap). Caps long edge at 2400px to bound memory
/// without requesting original/full-resolution assets. No pinch-zoom ladder required today.
enum ScreenshotFullscreenImageTarget {
    static let maxLongEdgePixels: CGFloat = 2_400

    static func targetSize(fittedPoints: CGSize, scale: CGFloat = UIScreen.main.scale) -> CGSize {
        var width = max(1, fittedPoints.width * scale)
        var height = max(1, fittedPoints.height * scale)
        let longEdge = max(width, height)
        if longEdge > maxLongEdgePixels {
            let factor = maxLongEdgePixels / longEdge
            width *= factor
            height *= factor
        }
        return CGSize(width: width.rounded(), height: height.rounded())
    }
}

/// Context Collection Detail — configurable gallery density + lightweight management.
struct ContextDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    let contextID: ContextCollectionID

    @AppStorage(STGalleryDensity.storageKey) private var densityRaw = STGalleryDensity.default.rawValue

    @State private var title: String = "Context"
    @State private var badgeEmoji: String?
    @State private var badgeColor: String?
    @State private var kind: ContextCollectionKind = .aiContext
    @State private var memberCount: Int = 0
    @State private var screenshots: [ScreenshotMemory] = []
    @State private var selection = CleanupSelectionController()
    @State private var showEditor = false
    @State private var showDeleteCollection = false
    @State private var showMove = false
    @State private var isLoadingMore = false
    @State private var viewerPresentation: ScreenshotViewerPresentation?
    @State private var viewerFocusedID: ScreenshotMemoryID?
    /// Last opened / paged screenshot — used to restore gallery scroll after dismiss.
    @State private var scrollRestoreID: ScreenshotMemoryID?
    @State private var selectableFrames: [ScreenshotMemoryID: CGRect] = [:]
    @State private var dragSelectSession: STDragSelectSession?
    @Namespace private var screenshotZoomNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pageSize = 90
    private let selectCoordinateSpace = "contextDetailSelect"

    private var galleryDensity: STGalleryDensity {
        STGalleryDensity.resolved(rawValue: densityRaw)
    }

    private var allIDs: [ScreenshotMemoryID] { screenshots.map(\.id) }
    private var canManageCollection: Bool { kind != .unassigned }
    private var isNeedsReview: Bool { kind == .unassigned }
    private var hasMorePages: Bool { screenshots.count < memberCount }

    private var navigationTitleText: String {
        if isNeedsReview {
            return STNeedsReviewCopy.title
        }
        if let badgeEmoji, !badgeEmoji.isEmpty {
            return "\(badgeEmoji) \(title)"
        }
        return title
    }

    private var countLabel: String {
        let n = memberCount
        return n == 1 ? "1 screenshot" : "\(n) screenshots"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if screenshots.isEmpty && !selection.isSelecting {
                        STEmptyState(
                            title: isNeedsReview ? "You’re all caught up" : "No screenshots yet",
                            message: isNeedsReview
                                ? "Everything else is organized into Collections."
                                : "Screenshots in this collection will appear here.",
                            systemImage: isNeedsReview ? "checkmark.circle" : "photo.on.rectangle.angled"
                        )
                        .padding(.top, STSpacing.xxl)
                    } else {
                        VStack(alignment: .leading, spacing: STSpacing.md) {
                            Text(countLabel)
                                .font(STTypography.rowMeta)
                                .foregroundStyle(STColor.secondaryLabel)

                            LazyVGrid(
                                columns: galleryDensity.columns,
                                spacing: galleryDensity.gutter
                            ) {
                                ForEach(screenshots) { shot in
                                    thumb(shot)
                                        .id(shot.id)
                                        .onAppear {
                                            if shot.id == screenshots.last?.id {
                                                Task { await loadMoreIfNeeded() }
                                            }
                                        }
                                }
                            }
                            .stDragSelectContainer(
                                coordinateSpaceName: selectCoordinateSpace,
                                frames: $selectableFrames
                            )
                        }
                    }
                }
                .padding(.horizontal, STSpacing.page)
                .padding(.top, STSpacing.lg)
                .padding(.bottom, selection.isSelecting ? 110 : STSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Only lock scroll while a thumbnail drag-select stroke is active.
            .scrollDisabled(dragSelectSession != nil)
            .onChange(of: viewerPresentation) { _, newValue in
                // Restore after dismiss — large-title / overlay teardown can jump the grid.
                guard newValue == nil, let anchor = scrollRestoreID else { return }
                restoreGalleryScroll(proxy: proxy, to: anchor)
            }
            .onChange(of: viewerFocusedID) { _, newValue in
                // Follow horizontal paging in the viewer so dismiss lands on the last seen shot.
                if let newValue {
                    scrollRestoreID = newValue
                }
            }
        }
        .background(STColor.background.ignoresSafeArea())
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(selection.isSelecting)
        .toolbar { toolbarContent }
        // Keep the gallery nav bar mounted while the viewer overlays it — hiding/showing
        // the bar (esp. large title) resets ScrollView offset.
        .safeAreaInset(edge: .bottom) {
            if selection.isSelecting {
                selectionBar
            }
        }
        .stScreenshotViewerOverlay(
            presentation: $viewerPresentation,
            focusedID: $viewerFocusedID,
            namespace: screenshotZoomNS
        )
        .sheet(isPresented: $showEditor) {
            CollectionEditorSheet(
                mode: .rename(contextID),
                initialTitle: title,
                initialEmoji: badgeEmoji ?? "📁",
                initialBadgeColor: badgeColor,
                onCancel: { showEditor = false },
                onSave: { newTitle, emoji, color in
                    do {
                        try await dependencies.memoryStore.updateContext(
                            id: contextID,
                            title: newTitle,
                            badgeEmoji: emoji,
                            badgeColor: color
                        )
                        await reload()
                        dependencies.noteMemoryMutation()
                        dependencies.feedback.show(STFeedbackCopy.collectionRenamed)
                        showEditor = false
                    } catch {
                        AppLog.ui.error(
                            "Rename collection failed: \(error.localizedDescription, privacy: .public)"
                        )
                        dependencies.feedback.show("Couldn’t save collection")
                    }
                }
            )
        }
        .sheet(isPresented: $showDeleteCollection) {
            DeleteCollectionSheet(
                collectionTitle: title,
                screenshotCount: screenshots.count,
                onCancel: { showDeleteCollection = false },
                onDeleteCollectionOnly: {
                    Task {
                        do {
                            let token = try await dependencies.memoryStore.deleteContext(
                                id: contextID,
                                deleteScreenshots: false
                            )
                            showDeleteCollection = false
                            dependencies.noteMemoryMutation()
                            dependencies.presentUndoableFeedback(
                                message: STFeedbackCopy.collectionDeleted,
                                token: token,
                                restoredMessage: STFeedbackCopy.collectionRestored
                            )
                            dismiss()
                        } catch {
                            AppLog.ui.error(
                                "Delete collection failed: \(error.localizedDescription, privacy: .public)"
                            )
                            showDeleteCollection = false
                        }
                    }
                },
                onDeleteCollectionAndScreenshots: {
                    Task {
                        do {
                            // Sprint 2 mock: Undo restores in-memory state only.
                            // Production PhotoKit deletion must not offer Undo unless
                            // those Photos assets can be reliably restored.
                            let token = try await dependencies.memoryStore.deleteContext(
                                id: contextID,
                                deleteScreenshots: true
                            )
                            showDeleteCollection = false
                            dependencies.noteMemoryMutation()
                            dependencies.presentUndoableFeedback(
                                message: STFeedbackCopy.collectionDeleted,
                                token: token,
                                restoredMessage: STFeedbackCopy.collectionRestored
                            )
                            dismiss()
                        } catch {
                            AppLog.ui.error(
                                "Delete collection failed: \(error.localizedDescription, privacy: .public)"
                            )
                            showDeleteCollection = false
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $showMove) {
            MoveScreenshotsSheet(
                sourceContextID: contextID,
                screenshotIDs: selection.selectedIDs,
                mode: .move,
                onFinished: { _, token in
                    let count = selection.selectedCount
                    showMove = false
                    selection.exitSelecting()
                    Task {
                        await reload()
                        dependencies.noteMemoryMutation()
                        dependencies.presentUndoableFeedback(
                            message: STFeedbackCopy.screenshotsMoved(count: count),
                            token: token,
                            restoredMessage: STFeedbackCopy.moveUndone,
                            onRestored: { await reload() }
                        )
                    }
                },
                onCancel: { showMove = false }
            )
        }
        .task { await reload() }
        .onChange(of: dependencies.memoryEpoch) { _, _ in
            // After delete/undo the grid identity changes — drop any stale zoom pairing
            // so the next open isn’t a blank matched-geometry portal.
            if viewerPresentation == nil {
                viewerFocusedID = nil
            }
            Task { await reload() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selection.isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dragSelectSession = nil
                    selection.exitSelecting()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(selection.allSelected(from: allIDs) ? "Deselect All" : "Select All") {
                    if selection.allSelected(from: allIDs) {
                        selection.deselectAll()
                    } else {
                        selection.selectAll(from: allIDs)
                    }
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                if !screenshots.isEmpty {
                    Menu {
                        ForEach(STGalleryDensity.allCases) { option in
                            Button {
                                densityRaw = option.rawValue
                            } label: {
                                if option == galleryDensity {
                                    Label(option.menuTitle, systemImage: "checkmark")
                                } else {
                                    Text(option.menuTitle)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: galleryDensity.toolbarSystemImage)
                    }
                    .accessibilityLabel("Gallery layout")
                    .accessibilityValue(galleryDensity.title)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !screenshots.isEmpty {
                    Button("Select") { selection.enterSelecting() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if canManageCollection {
                    Menu {
                        Button("Edit Collection", systemImage: "pencil") {
                            showEditor = true
                        }
                        Divider()
                        Button("Delete Collection", systemImage: "trash", role: .destructive) {
                            showDeleteCollection = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Collection actions")
                }
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: STSpacing.md) {
            Text("\(selection.selectedCount) Selected")
                .font(STTypography.rowTitle)
                .foregroundStyle(STColor.label)
            Spacer()
            if selection.selectedCount > 0 {
                Button("Move") { showMove = true }
                    .font(STTypography.button)
                Button("Delete", role: .destructive) {
                    Task { await deleteSelectedScreenshots() }
                }
                .font(STTypography.button)
            }
        }
        .padding(.horizontal, STSpacing.page)
        .padding(.vertical, STSpacing.md)
        .background(.ultraThinMaterial)
    }

    /// Photos system confirmation first, then soft-remove + Undo (restores Photos + app).
    private func deleteSelectedScreenshots() async {
        let count = selection.selectedCount
        let ids = selection.selectedIDs
        guard count > 0 else { return }
        do {
            let token = try await dependencies.deleteScreenshotsFromCollectionAndPhotos(ids: ids)
            selection.exitSelecting()
            await reload()
            dependencies.presentUndoableFeedback(
                message: STFeedbackCopy.screenshotsDeleted(count: count),
                token: token,
                restoredMessage: STFeedbackCopy.screenshotsRestored(count: count),
                onRestored: { await reload() }
            )
        } catch {
            if let photosError = error as? PhotosDeleteError, photosError.isUserCancellation {
                return
            }
            AppLog.ui.error(
                "Delete screenshots failed: \(error.localizedDescription, privacy: .public)"
            )
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't delete screenshots. Try again."
            dependencies.feedback.show(message, style: .error)
        }
    }

    @ViewBuilder
    private func thumb(_ shot: ScreenshotMemory) -> some View {
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
                openViewer(for: shot)
            } label: {
                let tile = STScreenshotGridItem(memory: shot)
                if viewerPresentation != nil {
                    tile
                        .matchedGeometryEffect(
                            id: shot.id,
                            in: screenshotZoomNS,
                            properties: .frame,
                            anchor: .center,
                            isSource: viewerFocusedID != shot.id
                        )
                        .opacity(viewerFocusedID == shot.id ? 0 : 1)
                } else {
                    // No zoom pairing while closed — prevents blank holes after delete/undo.
                    tile
                }
            }
            .buttonStyle(STCardPressStyle())
        }
    }

    private func openViewer(for shot: ScreenshotMemory) {
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.2)
            : .smooth(duration: 0.36)
        scrollRestoreID = shot.id
        // Ensure a clean presentation; stale focused IDs after undo broke the zoom portal.
        viewerFocusedID = nil
        withAnimation(animation) {
            viewerFocusedID = shot.id
            viewerPresentation = ScreenshotViewerPresentation(
                initialID: shot.id,
                galleryIDs: allIDs,
                contextID: contextID
            )
        }
    }

    private func restoreGalleryScroll(proxy: ScrollViewProxy, to id: ScreenshotMemoryID) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(id, anchor: .center)
        }
        // Nav chrome / safe-area can settle one frame later after overlay teardown.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(32))
            withTransaction(transaction) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func reload() async {
        if let context = try? await dependencies.memoryStore.fetchContext(id: contextID) {
            title = STNeedsReviewCopy.displayTitle(for: context)
            badgeEmoji = context.kind == .unassigned ? nil : context.badgeEmoji
            badgeColor = context.kind == .unassigned ? nil : context.badgeColor
            kind = context.kind
            memberCount = context.memberCount
        }
        // Keep already-loaded pages so a background refresh doesn’t shrink the grid
        // back to the first page (and jump scroll to top).
        let limit = max(pageSize, screenshots.count)
        screenshots = (try? await dependencies.memoryStore.fetchScreenshots(
            in: contextID,
            limit: limit,
            offset: 0
        )) ?? []
    }

    private func loadMoreIfNeeded() async {
        guard hasMorePages, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = (try? await dependencies.memoryStore.fetchScreenshots(
            in: contextID,
            limit: pageSize,
            offset: screenshots.count
        )) ?? []
        guard !next.isEmpty else { return }
        let existing = Set(screenshots.map(\.id))
        screenshots.append(contentsOf: next.filter { !existing.contains($0.id) })
    }
}

/// Fullscreen screenshot viewer — Photos-style paging + interactive swipe-down dismiss.
///
/// Prefer presenting via `stScreenshotViewerOverlay` so the gallery stays live underneath.
/// Navigation push still works as a fallback (`Environment.dismiss`).
struct ScreenshotDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let screenshotID: ScreenshotMemoryID
    var galleryContextID: ContextCollectionID?
    var galleryIDs: [ScreenshotMemoryID]?
    /// When set, viewer is an overlay and dismisses by calling this (gallery stays visible).
    var zoomNamespace: Namespace.ID?
    var onDismissRequest: (() -> Void)?
    var onCurrentIDChange: ((ScreenshotMemoryID) -> Void)?

    @State private var gallery: [ScreenshotMemory] = []
    @State private var currentID: ScreenshotMemoryID
    @State private var shareItem: ShareSheetItem?
    @State private var showMove = false
    @State private var dismissDragOffset: CGFloat = 0
    @State private var dismissDragAxis: Axis?
    @State private var isDismissing = false

    private let chromeFill = Color.black.opacity(0.45)
    private let chromeControlSize: CGFloat = 44
    private let dismissDistance: CGFloat = 120
    private let dismissVelocity: CGFloat = 850

    private var isOverlayPresentation: Bool { onDismissRequest != nil }

    init(
        screenshotID: ScreenshotMemoryID,
        galleryContextID: ContextCollectionID? = nil,
        galleryIDs: [ScreenshotMemoryID]? = nil,
        zoomNamespace: Namespace.ID? = nil,
        onDismissRequest: (() -> Void)? = nil,
        onCurrentIDChange: ((ScreenshotMemoryID) -> Void)? = nil
    ) {
        self.screenshotID = screenshotID
        self.galleryContextID = galleryContextID
        self.galleryIDs = galleryIDs
        self.zoomNamespace = zoomNamespace
        self.onDismissRequest = onDismissRequest
        self.onCurrentIDChange = onCurrentIDChange
        _currentID = State(initialValue: screenshotID)
    }

    private var currentIndex: Int {
        gallery.firstIndex(where: { $0.id == currentID }) ?? 0
    }

    private var positionLabel: String? {
        guard gallery.count > 1 else { return nil }
        return "\(currentIndex + 1) of \(gallery.count)"
    }

    /// 0 = resting, 1 = fully dragged toward dismiss.
    private var dismissProgress: CGFloat {
        min(1, max(0, dismissDragOffset / 280))
    }

    private var contentScale: CGFloat {
        // Photos-like: shrink with the finger.
        max(0.55, 1 - dismissProgress * 0.45)
    }

    private var dimOpacity: Double {
        // Dim fades as the finger pulls down so the live gallery shows through.
        max(0, 0.88 * (1 - Double(dismissProgress)))
    }

    private var chromeOpacity: Double {
        max(0, 1 - Double(dismissProgress) * 1.6)
    }

    private var dismissCornerRadius: CGFloat {
        8 + dismissProgress * 20
    }

    var body: some View {
        ZStack {
            // Must stay clear — gallery (overlay host) is the real background.
            Color.clear.ignoresSafeArea()

            Color.black
                .opacity(isDismissing ? 0 : dimOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            photoPager
                .simultaneousGesture(photosStyleDismissGesture)
                .opacity(isDismissing ? 0 : 1)

            viewerChrome
                .opacity(chromeOpacity)
                .allowsHitTesting(dismissDragOffset < 12 && !isDismissing)
        }
        .background(Color.clear)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(isOverlayPresentation ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $shareItem) { item in
            STActivityView(activityItems: [item.image]) {
                shareItem = nil
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showMove) {
            MoveScreenshotsSheet(
                sourceContextID: galleryContextID,
                screenshotIDs: [currentID],
                mode: .move,
                onFinished: { _, token in
                    showMove = false
                    performPhotosStyleDismiss()
                    dependencies.noteMemoryMutation()
                    dependencies.presentUndoableFeedback(
                        message: STFeedbackCopy.screenshotsMoved(count: 1),
                        token: token,
                        restoredMessage: STFeedbackCopy.moveUndone
                    )
                },
                onCancel: { showMove = false }
            )
        }
        .task { await loadGallery() }
        .overlay {
            if gallery.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { onCurrentIDChange?(currentID) }
        .onChange(of: currentID) { _, newValue in
            shareItem = nil
            onCurrentIDChange?(newValue)
        }
        .accessibilityAction(.escape) { performPhotosStyleDismiss() }
    }

    private var photoPager: some View {
        TabView(selection: $currentID) {
            ForEach(gallery) { shot in
                GeometryReader { geo in
                    let fitted = STAspect.fittedIPhoneScreenshot(in: geo.size)
                    heroImage(for: shot, fitted: fitted)
                        .frame(width: fitted.width, height: fitted.height)
                        .clipShape(RoundedRectangle(cornerRadius: dismissCornerRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.35 * dismissProgress), radius: 24, y: 12)
                        // Scale/offset the photo only — not the page — so the live gallery shows through.
                        .scaleEffect(contentScale)
                        .offset(y: max(0, dismissDragOffset))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .background(Color.clear)
                .ignoresSafeArea()
                .tag(shot.id)
                .accessibilityLabel("Screenshot")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.clear)
        .background(STClearPageBackground())
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func heroImage(for shot: ScreenshotMemory, fitted: CGSize) -> some View {
        let image = PhotosThumbnailImage(
            localIdentifier: shot.photosLocalIdentifier,
            targetSize: ScreenshotFullscreenImageTarget.targetSize(fittedPoints: fitted),
            contentMode: .aspectFit,
            allowsNetworkAccess: true,
            deliveryStyle: .progressive
        ) {
            ScreenshotPreview(
                kind: MockShotKindResolver.kind(for: shot),
                seed: shot.id.rawValue.hashValue,
                showsDeviceChrome: false
            )
        }

        if let zoomNamespace, dismissDragOffset < 1, !isDismissing {
            image.matchedGeometryEffect(id: shot.id, in: zoomNamespace, properties: .frame, anchor: .center)
        } else {
            image
        }
    }

    private var viewerChrome: some View {
        GeometryReader { geo in
            let topInset = (geo.safeAreaInsets.top > 0 ? geo.safeAreaInsets.top : 59) + 4
            let bottomInset = (geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom : 20) + 8

            VStack(spacing: 0) {
                HStack(spacing: STSpacing.md) {
                    chromeButton(systemName: "chevron.left", accessibility: "Back") {
                        performPhotosStyleDismiss()
                    }

                    Spacer(minLength: 0)

                    if let positionLabel {
                        Text(positionLabel)
                            .font(STTypography.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: chromeControlSize)
                            .background(Capsule(style: .continuous).fill(chromeFill))
                            .accessibilityLabel(positionLabel)
                    }

                    Spacer(minLength: 0)

                    chromeButton(systemName: "square.and.arrow.up", accessibility: "Share", yOffset: -1) {
                        presentShareSheet()
                    }
                    .disabled(gallery.isEmpty)
                }
                .padding(.horizontal, STSpacing.page)
                .padding(.top, topInset)

                Spacer(minLength: 0)

                HStack {
                    chromeButton(systemName: "folder", accessibility: "Move") {
                        showMove = true
                    }
                    .disabled(gallery.isEmpty || isDismissing)

                    Spacer(minLength: 0)

                    chromeButton(systemName: "trash", accessibility: "Delete") {
                        Task { await deleteCurrentScreenshot() }
                    }
                    .disabled(gallery.isEmpty || isDismissing)
                }
                .padding(.horizontal, STSpacing.page)
                .padding(.bottom, bottomInset)
            }
        }
        .allowsHitTesting(true)
    }

    private func chromeButton(
        systemName: String,
        accessibility: String,
        yOffset: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .offset(y: yOffset)
                .frame(width: chromeControlSize, height: chromeControlSize)
                .contentShape(Circle())
                .background(Circle().fill(chromeFill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    /// Photos system confirmation first, then soft-remove + Undo (restores Photos + app).
    private func deleteCurrentScreenshot() async {
        let deletedID = currentID
        do {
            let token = try await dependencies.deleteScreenshotsFromCollectionAndPhotos(ids: [deletedID])
            performPhotosStyleDismiss()
            dependencies.presentUndoableFeedback(
                message: STFeedbackCopy.screenshotsDeleted(count: 1),
                token: token,
                restoredMessage: STFeedbackCopy.screenshotsRestored(count: 1)
            )
        } catch {
            if let photosError = error as? PhotosDeleteError, photosError.isUserCancellation {
                return
            }
            AppLog.ui.error(
                "Delete screenshot failed: \(error.localizedDescription, privacy: .public)"
            )
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't delete screenshot. Try again."
            dependencies.feedback.show(message, style: .error)
        }
    }

    /// Interactive dismiss — offset tracks the finger; dim fades over the live gallery.
    private var photosStyleDismissGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard !isDismissing else { return }

                if dismissDragAxis == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    if dx > 4 || dy > 4 {
                        dismissDragAxis = (dy > dx && value.translation.height > 0) ? .vertical : .horizontal
                    }
                }

                guard dismissDragAxis == .vertical else { return }
                let y = value.translation.height
                setDismissOffset(y > 0 ? y : y * 0.12)
            }
            .onEnded { value in
                let axis = dismissDragAxis
                dismissDragAxis = nil
                guard axis == .vertical, !isDismissing else {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.9)) {
                        dismissDragOffset = 0
                    }
                    return
                }

                let predicted = value.predictedEndTranslation.height
                let velocityY = value.velocity.height
                let shouldDismiss = dismissDragOffset > dismissDistance
                    || velocityY > dismissVelocity
                    || predicted > dismissDistance * 1.6

                if shouldDismiss {
                    performPhotosStyleDismiss()
                } else {
                    withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
                        dismissDragOffset = 0
                    }
                }
            }
    }

    /// Back + swipe-down: zoom/collapse back into the gallery thumbnail.
    private func performPhotosStyleDismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        dismissDragAxis = nil

        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.2)
            : .smooth(duration: 0.36)

        if let onDismissRequest {
            withAnimation(animation) {
                dismissDragOffset = 0
                onDismissRequest()
            }
        } else {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                dismissDragOffset = 0
            }
            withAnimation(animation) {
                dismiss()
            }
        }
    }

    private func setDismissOffset(_ value: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dismissDragOffset = value
        }
    }

    private func presentShareSheet() {
        Task {
            guard let shot = gallery.first(where: { $0.id == currentID }) else { return }
            if let identifier = shot.photosLocalIdentifier,
               let result = await dependencies.thumbnailProvider.requestThumbnail(
                    localIdentifier: identifier,
                    targetSize: CGSize(width: 2_048, height: 2_048),
                    contentMode: .aspectFit,
                    allowsNetworkAccess: true
               ) {
                shareItem = ShareSheetItem(image: result.image)
            } else if let image = renderCurrentScreenshotImage() {
                shareItem = ShareSheetItem(image: image)
            }
        }
    }

    private func renderCurrentScreenshotImage() -> UIImage? {
        guard let shot = gallery.first(where: { $0.id == currentID }) else { return nil }
        let preview = ScreenshotPreview(
            kind: MockShotKindResolver.kind(for: shot),
            seed: shot.id.rawValue.hashValue,
            showsDeviceChrome: false
        )
        .frame(width: 390, height: 390 / STAspect.iphoneScreenshot)

        let renderer = ImageRenderer(content: preview)
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage {
            return image
        }
        // Fallback so share always opens the system sheet in mock mode.
        let size = CGSize(width: 390, height: 390 / STAspect.iphoneScreenshot)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.secondarySystemFill.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func loadGallery() async {
        // Prefer live context membership after undo — snapshot IDs from open time can be stale.
        if let galleryContextID {
            let members = (try? await dependencies.memoryStore.fetchScreenshots(in: galleryContextID)) ?? []
            if !members.isEmpty {
                if let galleryIDs, !galleryIDs.isEmpty {
                    let allowed = Set(galleryIDs)
                    let ordered = galleryIDs.compactMap { id in members.first(where: { $0.id == id }) }
                    let extras = members.filter { !allowed.contains($0.id) }
                    let merged = ordered + extras
                    if !merged.isEmpty {
                        gallery = merged
                        currentID = merged.contains(where: { $0.id == screenshotID })
                            ? screenshotID
                            : merged[0].id
                        return
                    }
                }
                gallery = members
                currentID = members.contains(where: { $0.id == screenshotID })
                    ? screenshotID
                    : members[0].id
                return
            }
        }

        if let galleryIDs, !galleryIDs.isEmpty {
            var items: [ScreenshotMemory] = []
            for id in galleryIDs {
                if let memory = try? await dependencies.memoryStore.fetchScreenshot(id: id) {
                    items.append(memory)
                }
            }
            if !items.isEmpty {
                gallery = items
                currentID = items.contains(where: { $0.id == screenshotID }) ? screenshotID : items[0].id
                return
            }
        }

        if let memory = try? await dependencies.memoryStore.fetchScreenshot(id: screenshotID) {
            gallery = [memory]
            currentID = memory.id
        }
    }
}

/// Identifiable payload so SwiftUI reliably presents the system share sheet.
private struct ShareSheetItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Clears UIKit page-controller chrome so swipe-down can reveal the live gallery.
private struct STClearPageBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            var ancestor: UIView? = view.superview
            while let current = ancestor {
                current.backgroundColor = .clear
                if current is UIScrollView { break }
                ancestor = current.superview
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Native iOS share sheet (`UIActivityViewController`).
struct STActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
