import SwiftUI

/// App shell — native SwiftUI `TabView` (HIG + Liquid Glass on current iOS).
///
/// Decision gate (Sprint 4 nav correction): YES migrate from custom `FloatingTabBar`.
/// Native `TabView` preserves four tabs, per-tab `NavigationStack` state, `#008BFF` tint,
/// and system safe-area / glass behavior. Custom dock + horizontal drag removed.
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        @Bindable var navigator = dependencies.navigator

        ZStack(alignment: .bottom) {
            TabView(selection: $navigator.selectedTab) {
                tabRoot(path: $navigator.homePath, tab: .home) {
                    HomeView()
                }
                tabRoot(path: $navigator.searchPath, tab: .search) {
                    SearchView()
                }
                tabRoot(path: $navigator.cleanupPath, tab: .cleanup) {
                    CleanupView()
                }
                tabRoot(path: $navigator.settingsPath, tab: .settings) {
                    SettingsView()
                }
            }
            // ScreenTidy accent — selected tab uses system selection treatment + this tint.
            .tint(STColor.primary)

            STToastHost()
        }
        .stStatusBarCover()
        .sheet(isPresented: Binding(
            get: { dependencies.showCloudUnderstandingDisclosure },
            set: { dependencies.showCloudUnderstandingDisclosure = $0 }
        )) {
            CloudUnderstandingDisclosureSheet(
                onAccept: { dependencies.acceptCloudUnderstanding() },
                onDecline: { dependencies.declineCloudUnderstanding() }
            )
        }
        .onAppear {
            dependencies.presentCloudUnderstandingDisclosureIfNeeded()
        }
    }

    /// One tab = one `NavigationStack` so push state survives tab switches (HIG).
    /// Each stack owns a zoom namespace so fullscreen ↔ thumbnail matches Photos.
    private func tabRoot<Content: View>(
        path: Binding<NavigationPath>,
        tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        TabNavigationStack(path: path, root: content, destination: { route in
            destination(for: route)
                .toolbar(.hidden, for: .tabBar)
        })
        .tabItem {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .contextDetail(let id):
            ContextDetailView(contextID: id)
        case .screenshotDetail(let id, let contextID, let galleryIDs):
            ScreenshotDetailView(
                screenshotID: id,
                galleryContextID: contextID,
                galleryIDs: galleryIDs
            )
        case .cleanupDuplicates:
            CleanupDuplicatesView()
        case .cleanupOld:
            CleanupOldScreenshotsView()
        }
    }
}

#Preview("Root") {
    RootView()
        .environment(AppDependencies())
        .appTheme(.default)
}

/// Per-tab stack with a zoom namespace shared by gallery thumbs and the fullscreen viewer.
private struct TabNavigationStack<Root: View, Destination: View>: View {
    @Binding var path: NavigationPath
    @Namespace private var screenshotZoom
    private let root: Root
    private let destination: (AppRoute) -> Destination

    init(
        path: Binding<NavigationPath>,
        @ViewBuilder root: () -> Root,
        @ViewBuilder destination: @escaping (AppRoute) -> Destination
    ) {
        self._path = path
        self.root = root()
        self.destination = destination
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route)
                }
        }
        .environment(\.screenshotZoomNamespace, screenshotZoom)
    }
}
