import Foundation

/// DEBUG/runtime telemetry for the visual analysis worker (P1).
/// Not used for product decisions.
enum VisualAnalysisWorkerState: String, Sendable {
    case idle
    case running
    case stopped
}

struct VisualAnalysisQueueDiagnostics: Sendable, Equatable {
    var workerState: VisualAnalysisWorkerState = .idle
    var lastWakeAt: Date?
    var lastClaimAttemptAt: Date?
    var lastClaimedID: String?
    var lastCompletedID: String?
    var lastError: String?
    var processedThisSession: Int = 0
    var lastClaimResult: String = "never"
    /// Pending rows that match claim SQL (available + local identifier).
    var claimablePending: Int = 0
    var pendingTotal: Int = 0
    /// Pending but not claimable — breakdown for DEBUG.
    var pendingMissingLocalID: Int = 0
    var pendingRemovedFromApp: Int = 0
    var pendingInaccessibleAccess: Int = 0
}

#if DEBUG
enum VisualAnalysisDebugRuntime: Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var snapshot = VisualAnalysisQueueDiagnostics()
    /// When true, `overrideSettings` is used for new Vision classify passes (DEBUG only).
    nonisolated(unsafe) private static var useOverrideFilter = false
    nonisolated(unsafe) private static var overrideSettings = VisualLabelFilter.Settings.production

    static func current() -> VisualAnalysisQueueDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    static func update(_ mutate: (inout VisualAnalysisQueueDiagnostics) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        mutate(&snapshot)
    }

    /// Production defaults unless DEBUG override is explicitly enabled.
    static func filterSettings() -> VisualLabelFilter.Settings {
        lock.lock()
        defer { lock.unlock() }
        return useOverrideFilter ? overrideSettings : .production
    }

    static func isFilterOverrideEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return useOverrideFilter
    }

    static func currentOverrideSettings() -> VisualLabelFilter.Settings {
        lock.lock()
        defer { lock.unlock() }
        return overrideSettings
    }

    static func setFilterOverride(enabled: Bool, settings: VisualLabelFilter.Settings = .production) {
        lock.lock()
        defer { lock.unlock() }
        useOverrideFilter = enabled
        overrideSettings = settings
    }
}
#else
enum VisualAnalysisDebugRuntime: Sendable {
    static func current() -> VisualAnalysisQueueDiagnostics { VisualAnalysisQueueDiagnostics() }
    static func update(_ mutate: (inout VisualAnalysisQueueDiagnostics) -> Void) {}
    static func filterSettings() -> VisualLabelFilter.Settings { .production }
    static func isFilterOverrideEnabled() -> Bool { false }
    static func currentOverrideSettings() -> VisualLabelFilter.Settings { .production }
    static func setFilterOverride(enabled: Bool, settings: VisualLabelFilter.Settings = .production) {}
}
#endif
