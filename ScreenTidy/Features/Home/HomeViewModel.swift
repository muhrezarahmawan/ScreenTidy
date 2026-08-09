import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private let memory: any MemoryReading
    private let screenshotSync: any ScreenshotSyncing

    private(set) var state: LoadState<HomeContent> = .idle
    private(set) var greeting: String
    /// Stable for the current Home tab visit; rotates when leaving and returning.
    private(set) var subtitle: String
    private var isHomeVisitActive = false

    struct NeedsReviewTeaser: Equatable {
        var contextID: ContextCollectionID
        var count: Int
        var previews: [ScreenshotMemory]
    }

    struct HomeContent: Equatable {
        /// Present only when there is at least one screenshot needing review.
        var needsReview: NeedsReviewTeaser?
        var contexts: [ContextCollection]
    }

    init(memory: any MemoryReading, screenshotSync: any ScreenshotSyncing) {
        self.memory = memory
        self.screenshotSync = screenshotSync
        self.greeting = Self.makeGreeting()
        self.subtitle = STHomeCopy.nextSubtitle()
        self.isHomeVisitActive = true
    }

    /// Call when the Home tab becomes the selected tab.
    func noteHomeBecameActive() {
        guard !isHomeVisitActive else { return }
        isHomeVisitActive = true
        greeting = Self.makeGreeting()
        subtitle = STHomeCopy.nextSubtitle()
    }

    /// Call when the user leaves the Home tab (not when pushing Context Detail).
    func noteHomeBecameInactive() {
        isHomeVisitActive = false
    }

    /// Full reload (initial / hard refresh). Shows loading only when empty.
    func reload() async {
        let showLoading: Bool
        if case .loaded = state {
            showLoading = false
        } else {
            showLoading = true
        }
        if showLoading {
            state = .loading
        }
        await refreshContent()
    }

    /// Optimistic Home grid reorder while a drag is in progress / just committed.
    func replaceContexts(_ contexts: [ContextCollection]) {
        guard case .loaded(var content) = state else { return }
        content.contexts = contexts
        state = .loaded(content)
    }

    /// Always refresh from the shared store without blanking the grid.
    /// Does not rotate the greeting subtitle.
    func refreshContent() async {
        do {
            let contexts = try await memory.fetchPromotedContexts()
            let unassigned = try await memory.fetchUnassignedContext()
            let needsReview: NeedsReviewTeaser?
            if let unassigned, unassigned.memberCount > 0 {
                // Count comes from SQL; load at most 3 peeks — never the full Needs Review set.
                let peeks = try await memory.fetchScreenshots(in: unassigned.id, limit: 3, offset: 0)
                needsReview = NeedsReviewTeaser(
                    contextID: unassigned.id,
                    count: unassigned.memberCount,
                    previews: peeks
                )
            } else {
                needsReview = nil
            }
            state = .loaded(
                HomeContent(
                    needsReview: needsReview,
                    contexts: contexts
                )
            )
        } catch is CancellationError {
            // Tab switches / SwiftUI task teardown cancel in-flight reads — not a user-facing failure.
            return
        } catch {
            state = .failed(.underlying(message: error.localizedDescription))
            AppLog.ui.error("Home load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Manual pull-to-refresh: PhotoKit identifier reconcile, then reload Home.
    @discardableResult
    func refreshScreenshots() async -> ScreenshotSyncResult {
        do {
            let result = try await screenshotSync.syncIncremental()
            await refreshContent()
            return result
        } catch {
            AppLog.ui.error("Screenshot sync failed: \(error.localizedDescription, privacy: .public)")
            await refreshContent()
            return .failed
        }
    }

    private static func makeGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}
