import SwiftUI

// MARK: - View model

@MainActor
@Observable
final class SearchViewModel {
    private let searchProvider: any SearchProviding
    private let suggestionsProvider: any SearchSuggestionsProviding

    var query: String = ""
    /// Latest completed response for the active query (or empty when idle).
    private(set) var response: SearchResponse = .empty
    private(set) var isSearching = false
    private(set) var errorMessage: String?
    /// Empty-state prompts (static mock in Sprint 2; provider-backed for later personalization).
    private(set) var suggestions: [SearchSuggestion] = []

    private var searchTask: Task<Void, Never>?
    private var searchGeneration: UInt = 0

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasQuery: Bool { !trimmedQuery.isEmpty }

    /// Binding that updates query and kicks off debounced search on every keystroke.
    var queryBinding: Binding<String> {
        Binding(
            get: { self.query },
            set: { newValue in
                self.query = newValue
                self.scheduleSearch(immediate: false)
            }
        )
    }

    init(
        searchProvider: any SearchProviding,
        suggestionsProvider: any SearchSuggestionsProviding
    ) {
        self.searchProvider = searchProvider
        self.suggestionsProvider = suggestionsProvider
    }

    func loadSuggestions() async {
        suggestions = await suggestionsProvider.suggestions()
    }

    /// Return / clear — search immediately (no debounce).
    func submit() {
        scheduleSearch(immediate: true)
    }

    /// Chip tap or Home handoff — populate field and search immediately.
    func applyExternalQuery(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != trimmed else {
            if hasQuery { scheduleSearch(immediate: true) }
            return
        }
        query = trimmed
        scheduleSearch(immediate: true)
    }

    func selectSuggestion(_ suggestion: SearchSuggestion) {
        applyExternalQuery(suggestion.title)
    }

    private func scheduleSearch(immediate: Bool) {
        searchTask?.cancel()
        errorMessage = nil

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchGeneration &+= 1
            response = .empty
            isSearching = false
            return
        }

        isSearching = true
        searchGeneration &+= 1
        let generation = searchGeneration
        let provider = searchProvider

        searchTask = Task { @MainActor in
            if !immediate {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(STMotion.searchDebounceDuration * 1_000_000_000)
                    )
                } catch {
                    return // Cancelled during debounce — a newer search owns the UI.
                }
            }

            guard !Task.isCancelled, generation == self.searchGeneration else { return }

            do {
                let result = try await provider.search(query: q)
                guard !Task.isCancelled, generation == self.searchGeneration else { return }
                self.response = result
                self.isSearching = false
                AppLog.search.debug(
                    "Search “\(q, privacy: .public)” → \(result.hits.count) shots, \(result.collections.count) collections"
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, generation == self.searchGeneration else { return }
                self.errorMessage = error.localizedDescription
                self.isSearching = false
                AppLog.search.error(
                    "Search failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}

// MARK: - View

struct SearchView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: SearchViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SearchScreen(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(STColor.background.ignoresSafeArea())
            }
        }
        .task {
            let vm = viewModel ?? SearchViewModel(
                searchProvider: dependencies.searchProvider,
                suggestionsProvider: dependencies.searchSuggestions
            )
            if viewModel == nil {
                viewModel = vm
            }
            await vm.loadSuggestions()
        }
    }
}

private struct SearchScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: SearchViewModel
    @FocusState private var isSearchFocused: Bool
    @AppStorage(STGalleryDensity.storageKey) private var densityRaw = STGalleryDensity.default.rawValue
    @State private var viewerPresentation: ScreenshotViewerPresentation?
    @State private var viewerFocusedID: ScreenshotMemoryID?
    @Namespace private var screenshotZoomNS

    private var galleryDensity: STGalleryDensity {
        STGalleryDensity.resolved(rawValue: densityRaw)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: STSpacing.md) {
                    Text("Search")
                        .font(STTypography.greeting)
                        .foregroundStyle(STColor.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { dismissKeyboard() }

                    if !viewModel.response.hits.isEmpty {
                        galleryDensityMenu
                    }
                }

                STSearchField(
                    text: viewModel.queryBinding,
                    placeholder: "Search your screenshots",
                    isFocused: $isSearchFocused,
                    onSubmit: {
                        dismissKeyboard()
                        viewModel.submit()
                    }
                )
                .padding(.top, STSpacing.md)

                results
                    .padding(.top, viewModel.hasQuery ? STSpacing.homeSection : STSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
            }
            .padding(.horizontal, STSpacing.page)
            .padding(.top, STSpacing.lg)
            .padding(.bottom, STSpacing.tabBarHeight + STSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .stTabRootAtmosphere()
        }
        .scrollDismissesKeyboard(.immediately)
        .coordinateSpace(name: STHomeAtmosphereTokens.scrollCoordinateSpace)
        .stTabRootScrollBackground()
        .toolbar(.hidden, for: .navigationBar)
        // Tab roots keep the tab bar; hide it while the fullscreen viewer is up
        // (pushed Collection Detail already hides via RootView destination).
        .toolbar(viewerPresentation == nil ? .automatic : .hidden, for: .tabBar)
        .stScreenshotViewerOverlay(
            presentation: $viewerPresentation,
            focusedID: $viewerFocusedID,
            namespace: screenshotZoomNS
        )
        .onAppear { consumePendingSearchQuery() }
        .onChange(of: dependencies.navigator.pendingSearchQuery) { _, _ in
            consumePendingSearchQuery()
        }
        .onChange(of: dependencies.navigator.selectedTab) { _, tab in
            guard tab == .search else { return }
            consumePendingSearchQuery()
        }
        .onChange(of: viewerPresentation) { _, presentation in
            if presentation != nil { dismissKeyboard() }
        }
    }

    private func dismissKeyboard() {
        isSearchFocused = false
    }

    private func consumePendingSearchQuery() {
        guard let pending = dependencies.navigator.pendingSearchQuery else { return }
        dependencies.navigator.pendingSearchQuery = nil
        viewModel.applyExternalQuery(pending)
    }

    @ViewBuilder
    private var results: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(STTypography.rowMeta)
                .foregroundStyle(STColor.secondaryLabel)
        } else if !viewModel.hasQuery {
            searchReadyState
        } else if viewModel.response.isEmpty && viewModel.isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, STSpacing.xl)
        } else if viewModel.response.isEmpty {
            searchNoResultsState
        } else {
            VStack(alignment: .leading, spacing: STSpacing.homeSection) {
                if !viewModel.response.collections.isEmpty {
                    collectionsSection
                }
                screenshotsSection
            }
        }
    }

    private var searchNoResultsState: some View {
        VStack(spacing: STSpacing.lg) {
            STSearchEmptyIllustration()
                // Keep soft shadows from colliding with the title.
                .padding(.bottom, STSpacing.sm)

            VStack(spacing: STSpacing.sm) {
                Text("No screenshots found")
                    .font(STTypography.emptyTitle)
                    .foregroundStyle(STColor.label)
                    .multilineTextAlignment(.center)
                Text("Try another word or description.")
                    .font(STTypography.emptyMessage)
                    .foregroundStyle(STColor.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, STSpacing.md)
        .padding(.bottom, STSpacing.lg)
    }

    private var searchReadyState: some View {
        VStack(alignment: .leading, spacing: STSpacing.xl) {
            VStack(alignment: .leading, spacing: STSpacing.sm) {
                Text("Find any screenshot")
                    .font(STTypography.sectionTitle)
                    .foregroundStyle(STColor.label)
                Text("Search by text, objects, places, or Collections.")
                    .font(STTypography.aiLine)
                    .foregroundStyle(STColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if !viewModel.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: STSpacing.md) {
                    Text("Try searching for")
                        .font(STTypography.caption)
                        .foregroundStyle(STColor.secondaryLabel)
                        .textCase(.uppercase)
                        .tracking(0.4)

                    SearchSuggestionFlowLayout(spacing: STSpacing.sm, lineSpacing: STSpacing.sm) {
                        ForEach(viewModel.suggestions) { suggestion in
                            SearchSuggestionChip(title: suggestion.title) {
                                dismissKeyboard()
                                viewModel.selectSuggestion(suggestion)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: STSpacing.md) {
            Text("Collections")
                .font(STTypography.sectionTitle)
                .foregroundStyle(STColor.label)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: STSpacing.collectionGridGutter),
                    GridItem(.flexible(), spacing: STSpacing.collectionGridGutter)
                ],
                spacing: STSpacing.collectionGridRow
            ) {
                ForEach(viewModel.response.collections) { context in
                    NavigationLink(value: AppRoute.contextDetail(context.id)) {
                        ContextCollectionPocketView(collection: context)
                    }
                    .buttonStyle(STCardPressStyle())
                }
            }
        }
    }

    private var screenshotsSection: some View {
        let showsRationale = viewModel.response.hits.contains(where: { $0.matchedSignals.contains(.ocr) })
        let hasCollections = !viewModel.response.collections.isEmpty

        return VStack(alignment: .leading, spacing: STSpacing.md) {
            if hasCollections {
                Text("Screenshots")
                    .font(STTypography.sectionTitle)
                    .foregroundStyle(STColor.label)
            }

            if showsRationale {
                Text(matchRationaleLabel)
                    .font(STTypography.caption)
                    .foregroundStyle(STColor.secondaryLabel)
            }

            let galleryIDs = viewModel.response.screenshotIDs
            LazyVGrid(columns: galleryDensity.columns, spacing: galleryDensity.gutter) {
                ForEach(viewModel.response.hits) { hit in
                    Button {
                        openViewer(for: hit.screenshot, galleryIDs: galleryIDs)
                    } label: {
                        STScreenshotGridItem(memory: hit.screenshot)
                            .matchedGeometryEffect(
                                id: hit.screenshot.id,
                                in: screenshotZoomNS,
                                properties: .frame,
                                anchor: .center,
                                isSource: viewerFocusedID != hit.screenshot.id
                            )
                            .opacity(viewerFocusedID == hit.screenshot.id ? 0 : 1)
                    }
                    .buttonStyle(STCardPressStyle())
                }
            }
        }
    }

    private var galleryDensityMenu: some View {
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
                .font(.body.weight(.semibold))
                .foregroundStyle(STColor.primary)
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(STColor.pocket)
                        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
                        .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
                }
                .contentShape(Circle())
        }
        .accessibilityLabel("Gallery layout")
        .accessibilityValue(galleryDensity.title)
    }

    private var matchRationaleLabel: String {
        let hasCollection = viewModel.response.hits.contains { $0.matchedSignals.contains(.collection) }
            || !viewModel.response.collections.isEmpty
        if hasCollection {
            return "Found in screenshots & collections"
        }
        return "Found in screenshots"
    }

    private func openViewer(for shot: ScreenshotMemory, galleryIDs: [ScreenshotMemoryID]) {
        dismissKeyboard()
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
}

// MARK: - Suggestion chips

private struct SearchSuggestionChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(STTypography.rowMeta.weight(.medium))
                .foregroundStyle(STColor.label)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(STColor.pocket)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(STColor.hairline, lineWidth: 0.5)
                )
                .shadow(
                    color: Color.black.opacity(0.04),
                    radius: 4,
                    x: 0,
                    y: 1
                )
        }
        .buttonStyle(SearchSuggestionChipButtonStyle())
        .accessibilityLabel("Search for \(title)")
    }
}

private struct SearchSuggestionChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .overlay {
                if configuration.isPressed {
                    Capsule(style: .continuous)
                        .fill(STColor.primary.opacity(0.08))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Wrapping horizontal flow for suggestion chips.
private struct SearchSuggestionFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var height: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            height = y + rowHeight
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

#Preview("Search") {
    NavigationStack {
        SearchView()
    }
    .environment(AppDependencies())
}
