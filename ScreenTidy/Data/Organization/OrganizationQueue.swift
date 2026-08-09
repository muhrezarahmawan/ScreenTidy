import Foundation

protocol OrganizationScheduling: Sendable {
    func kick()
}

/// Bounded organization drain. Newest-first via repository claim.
final class OrganizationQueue: OrganizationScheduling, @unchecked Sendable {
    static let maxConcurrency = 2

    private let store: any OrganizationPersisting
    private let organizer: any Organizing
    private let policy: ResolverPolicy
    private let onMutated: @Sendable () -> Void
    private let lock = NSLock()
    private var inFlight = 0
    private var isScheduling = false

    init(
        store: any OrganizationPersisting,
        organizer: any Organizing,
        policy: ResolverPolicy = .current,
        onMutated: @escaping @Sendable () -> Void = {}
    ) {
        self.store = store
        self.organizer = organizer
        self.policy = policy
        self.onMutated = onMutated
    }

    func kick() {
        Task { await schedule() }
    }

    private func schedule() async {
        lock.lock()
        if isScheduling {
            lock.unlock()
            return
        }
        isScheduling = true
        lock.unlock()

        defer {
            lock.lock()
            isScheduling = false
            lock.unlock()
        }

        while true {
            lock.lock()
            let canStart = inFlight < Self.maxConcurrency
            lock.unlock()
            guard canStart else { break }

            let id: ScreenshotMemoryID?
            do {
                id = try await store.claimNextOrganizeJob(
                    resolverVersion: policy.resolverVersion,
                    now: Date()
                )
            } catch {
                AppLog.general.error(
                    "Organize claim failed: \(error.localizedDescription, privacy: .public)"
                )
                break
            }
            guard let id else { break }

            lock.lock()
            inFlight += 1
            lock.unlock()

            Task {
                await self.run(id)
            }
        }
    }

    private func run(_ id: ScreenshotMemoryID) async {
        defer {
            lock.lock()
            inFlight = max(0, inFlight - 1)
            lock.unlock()
            kick()
        }
        do {
            try await organizer.organizeIfNeeded(screenshotID: id)
            onMutated()
            AppLog.general.info("Organize pass finished for one screenshot")
        } catch {
            AppLog.general.error(
                "Organize failed: \(error.localizedDescription, privacy: .public)"
            )
            try? await store.setOrganizeStatus(.failed, id: id, errorCode: "organize_failed")
        }
    }
}

struct NoOpOrganizationScheduler: OrganizationScheduling {
    func kick() {}
}
