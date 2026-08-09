import SwiftUI

/// Primary tabs — matches IA: Home, Search, Cleanup, Settings.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case search
    case cleanup
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .cleanup: "Cleanup"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .cleanup: "sparkles"
        case .settings: "gearshape"
        }
    }
}

/// Stack destinations shared across tabs (expand in later sprints).
enum AppRoute: Hashable {
    case contextDetail(ContextCollectionID)
    /// Fullscreen viewer. Prefer `contextID` or explicit `galleryIDs` for swipe scope.
    case screenshotDetail(
        ScreenshotMemoryID,
        contextID: ContextCollectionID?,
        galleryIDs: [ScreenshotMemoryID]?
    )
    case cleanupDuplicates
    case cleanupOld
}

/// Holds selected tab + per-tab paths. Kept simple — no Coordinator framework.
@Observable
@MainActor
final class AppNavigator {
    var selectedTab: AppTab = .home
    var homePath = NavigationPath()
    var searchPath = NavigationPath()
    var cleanupPath = NavigationPath()
    var settingsPath = NavigationPath()

    /// Seeded when navigating Home → Search so typing/submit carries the query over.
    var pendingSearchQuery: String?

    /// System tab bar only on tab roots — hidden on pushed detail screens via `.toolbar(.hidden, for: .tabBar)`.
    var showsTabBar: Bool {
        switch selectedTab {
        case .home: homePath.isEmpty
        case .search: searchPath.isEmpty
        case .cleanup: cleanupPath.isEmpty
        case .settings: settingsPath.isEmpty
        }
    }

    /// Compatibility alias — prefer `showsTabBar`.
    var showsFloatingTabBar: Bool { showsTabBar }

    func switchToSearch(query: String? = nil) {
        if let query {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingSearchQuery = trimmed.isEmpty ? nil : trimmed
        }
        selectedTab = .search
        AppLog.navigation.debug("Switched to Search tab")
    }

    func popToRoot(of tab: AppTab) {
        switch tab {
        case .home: homePath = NavigationPath()
        case .search: searchPath = NavigationPath()
        case .cleanup: cleanupPath = NavigationPath()
        case .settings: settingsPath = NavigationPath()
        }
    }
}
