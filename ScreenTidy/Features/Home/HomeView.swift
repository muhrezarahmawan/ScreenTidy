import SwiftUI

struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: HomeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                QuietPocketHomeScreen(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(STColor.background.ignoresSafeArea())
            }
        }
        // Task must live outside the ProgressView branch. Assigning `viewModel`
        // swaps that branch away and would cancel an in-flight load as CancellationError.
        .task {
            let vm = viewModel ?? HomeViewModel(
                memory: dependencies.memoryStore,
                screenshotSync: dependencies.screenshotSync
            )
            if viewModel == nil {
                viewModel = vm
            }
            await vm.reload()
        }
    }
}

private struct QuietPocketHomeScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Bindable var viewModel: HomeViewModel
    @State private var showNewCollection = false

    private let columns = [
        GridItem(.flexible(), spacing: STSpacing.collectionGridGutter),
        GridItem(.flexible(), spacing: STSpacing.collectionGridGutter)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: STSpacing.homeSection) {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, STSpacing.xxl)
                case .failed(let error):
                    STEmptyState(
                        title: "Something went wrong",
                        message: error.localizedDescription,
                        systemImage: "exclamationmark.triangle",
                        actionTitle: "Try Again"
                    ) {
                        Task { await viewModel.reload() }
                    }
                case .loaded(let content):
                    STGreetingHeader(
                        greeting: viewModel.greeting,
                        organizingMessage: viewModel.subtitle
                    )

                    if let needsReview = content.needsReview {
                        NavigationLink(value: AppRoute.contextDetail(needsReview.contextID)) {
                            STNeedsReviewCard(
                                count: needsReview.count,
                                previews: needsReview.previews
                            )
                        }
                        .buttonStyle(STCardPressStyle())
                    }

                    VStack(alignment: .leading, spacing: STSpacing.md) {
                        STCollectionsSectionHeader(showsNew: !content.contexts.isEmpty) {
                            showNewCollection = true
                        }

                        if content.contexts.isEmpty {
                            collectionsEmptyState
                        } else {
                            ReorderableCollectionsGrid(
                                contexts: content.contexts,
                                columns: columns,
                                onReorderCommitted: { ordered in
                                    viewModel.replaceContexts(ordered)
                                    Task {
                                        do {
                                            try await dependencies.memoryStore.reorderContexts(
                                                orderedIDs: ordered.map(\.id)
                                            )
                                            dependencies.noteMemoryMutation()
                                        } catch {
                                            AppLog.ui.error(
                                                "Reorder collections failed: \(error.localizedDescription, privacy: .public)"
                                            )
                                            await viewModel.refreshContent()
                                            dependencies.feedback.show("Couldn’t reorder collections")
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, STSpacing.page)
            .padding(.top, STSpacing.lg)
            // Floating system tab bar overlays content — keep enough scroll room to clear it.
            .padding(.bottom, STSpacing.tabBarHeight + STSpacing.xl)
            .stTabRootAtmosphere()
        }
        .coordinateSpace(name: STHomeAtmosphereTokens.scrollCoordinateSpace)
        .refreshable {
            let result = await viewModel.refreshScreenshots()
            dependencies.noteMemoryMutation()
            dependencies.ocrScheduler.kick()
            dependencies.visualScheduler.kick()
            dependencies.feedback.show(STFeedbackCopy.sync(result))
        }
        .stTabRootScrollBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNewCollection) {
            CollectionEditorSheet(
                mode: .create,
                onCancel: { showNewCollection = false },
                onSave: { title, emoji, badgeColor in
                    // Mutate + refresh before dismiss so sheet teardown cannot cancel work.
                    do {
                        _ = try await dependencies.memoryStore.createContext(
                            title: title,
                            badgeEmoji: emoji,
                            badgeColor: badgeColor
                        )
                        await viewModel.refreshContent()
                        dependencies.noteMemoryMutation()
                        dependencies.feedback.show(STFeedbackCopy.collectionCreated)
                        showNewCollection = false
                    } catch {
                        AppLog.ui.error(
                            "Create collection failed: \(error.localizedDescription, privacy: .public)"
                        )
                        dependencies.feedback.show("Couldn’t create collection")
                    }
                }
            )
        }
        // Home stays mounted under tab opacity — refresh data when returning to the root.
        .onChange(of: dependencies.navigator.homePath.count) { _, count in
            guard count == 0 else { return }
            Task { await viewModel.refreshContent() }
        }
        .onChange(of: dependencies.navigator.selectedTab) { _, tab in
            if tab == .home {
                viewModel.noteHomeBecameActive()
                Task { await viewModel.refreshContent() }
            } else {
                viewModel.noteHomeBecameInactive()
            }
        }
        .onChange(of: dependencies.memoryEpoch) { _, _ in
            Task { await viewModel.refreshContent() }
        }
    }

    private var collectionsEmptyState: some View {
        VStack(spacing: STSpacing.lg) {
            STCollectionsEmptyIllustration()

            VStack(spacing: STSpacing.sm) {
                Text("No Collections yet")
                    .font(STTypography.emptyTitle)
                    .foregroundStyle(STColor.label)
                    .multilineTextAlignment(.center)
                Text("Create a collection to start organizing screenshots.")
                    .font(STTypography.emptyMessage)
                    .foregroundStyle(STColor.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            STPrimaryButton(title: "Create Collection") {
                showNewCollection = true
            }
            .padding(.top, STSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, STSpacing.md)
        .padding(.bottom, STSpacing.lg)
    }
}

// MARK: - Drag reorder

private struct ReorderableCollectionsGrid: View {
    @Environment(AppDependencies.self) private var dependencies

    let contexts: [ContextCollection]
    let columns: [GridItem]
    let onReorderCommitted: ([ContextCollection]) -> Void

    @State private var ordered: [ContextCollection] = []
    @State private var draggingID: ContextCollectionID?

    var body: some View {
        LazyVGrid(columns: columns, spacing: STSpacing.collectionGridRow) {
            ForEach(ordered) { context in
                NavigationLink(value: AppRoute.contextDetail(context.id)) {
                    ContextCollectionPocketView(collection: context)
                }
                .buttonStyle(STCardPressStyle())
                // Folder silhouette for the system lift preview (avoids a square chrome plate).
                .contentShape(.dragPreview, FolderDragPreviewShape())
                .onDrag {
                    draggingID = context.id
                    return NSItemProvider(object: context.id.rawValue.uuidString as NSString)
                } preview: {
                    // Drag previews render outside the normal hierarchy — re-inject DI.
                    CollectionDragLiftPreview(collection: context)
                        .environment(dependencies)
                }
                .onDrop(
                    of: [.plainText],
                    delegate: CollectionReorderDropDelegate(
                        targetID: context.id,
                        ordered: $ordered,
                        draggingID: $draggingID,
                        onReorderCommitted: {
                            // Clear lift state on MainActor — DropDelegate binding writes
                            // can leave views stuck in the dragging appearance.
                            draggingID = nil
                            onReorderCommitted($0)
                        }
                    )
                )
            }
        }
        .onAppear {
            ordered = contexts
        }
        .onChange(of: contexts) { _, newValue in
            draggingID = nil
            ordered = newValue
        }
    }
}

/// Drag lift preview clipped to the folder silhouette — not a square plate.
private struct CollectionDragLiftPreview: View {
    let collection: ContextCollection

    private let width: CGFloat = 168

    var body: some View {
        let layout = FolderLayout(width: width)
        ContextCollectionPocketView(collection: collection)
            .frame(width: width, height: layout.totalHeight)
            .mask(FolderDragPreviewShape())
            .compositingGroup()
    }
}

/// Scales folder metrics to whatever rect SwiftUI uses for the drag preview.
private struct FolderDragPreviewShape: Shape {
    func path(in rect: CGRect) -> Path {
        FolderBackShape(layout: FolderLayout(width: rect.width)).path(in: rect)
    }
}

private struct CollectionReorderDropDelegate: DropDelegate {
    let targetID: ContextCollectionID
    @Binding var ordered: [ContextCollection]
    @Binding var draggingID: ContextCollectionID?
    let onReorderCommitted: ([ContextCollection]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID,
              draggingID != targetID,
              let from = ordered.firstIndex(where: { $0.id == draggingID }),
              let to = ordered.firstIndex(where: { $0.id == targetID }),
              from != to
        else { return }

        // Keep reordering local only — pushing into the ViewModel mid-drag freezes the grid.
        withAnimation(.snappy(duration: 0.22)) {
            ordered.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        onReorderCommitted(ordered)
        return true
    }

    func dropExited(info: DropInfo) {}
}

#Preview("Home") {
    NavigationStack {
        HomeView()
    }
    .environment(AppDependencies())
    .appTheme(.default)
}
