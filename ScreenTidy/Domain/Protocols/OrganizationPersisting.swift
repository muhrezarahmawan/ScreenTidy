import Foundation
import GRDB

/// Persistence surface for Sprint 8 organization (separate from Organizing orchestration).
protocol OrganizationPersisting: Sendable {
    func markPendingOrganize(id: ScreenshotMemoryID) async throws
    func claimNextOrganizeJob(resolverVersion: Int, now: Date) async throws -> ScreenshotMemoryID?
    func fetchOrganizationEligibleCollections() async throws -> [CollectionResolver.EligibleCollection]
    func applyResolverDecision(
        screenshotID: ScreenshotMemoryID,
        decision: ResolverDecision,
        understanding: ScreenshotUnderstanding,
        policy: ResolverPolicy,
        fingerprint: String
    ) async throws
    func recordOrganizationRun(
        screenshotID: ScreenshotMemoryID,
        status: OrganizationRunStatus,
        decision: ResolverDecision?,
        understanding: ScreenshotUnderstanding?,
        policy: ResolverPolicy,
        errorCode: String?,
        fingerprint: String?
    ) async throws
    func setOrganizeStatus(_ status: OrganizeStatus, id: ScreenshotMemoryID, errorCode: String?) async throws
    func lockOrganization(ids: Set<ScreenshotMemoryID>) async throws
    func fetchOrganizationDebugSnapshots(limit: Int) async throws -> [OrganizationDebugSnapshot]
    func fetchOrganizationMetrics() async throws -> OrganizationMetrics
    func requeueSkippedConsentJobs() async throws
    /// DEBUG/smoke: force one screenshot back to `pending` immediately (bypasses pendingNetwork backoff).
    func requeueSingleOrganize(id: ScreenshotMemoryID) async throws

    func fetchOrganizeStatus(id: ScreenshotMemoryID) async throws -> OrganizeStatus?
    func fetchOrganizeResolverVersion(id: ScreenshotMemoryID) async throws -> Int?
    func fetchPendingOrganizeMembers(limit: Int) async throws -> [OrganizationClusterMemberSnapshot]
    func fetchFeaturePrintData(id: ScreenshotMemoryID) async throws -> Data?
    func cacheUnderstanding(fingerprint: String, understanding: ScreenshotUnderstanding) async throws
    func fetchCachedUnderstanding(fingerprint: String) async throws -> ScreenshotUnderstanding?
    func refreshCollectionProfile(for collectionID: ContextCollectionID?, createdTitle: String?) async throws
    func requeueNeedsReviewForResolver(version: Int) async throws -> Int
    func setOrganizationEvalLabel(screenshotID: ScreenshotMemoryID, label: OrganizationEvalLabel?) async throws
    func fetchOrganizationEvalStats() async throws -> OrganizationEvalStats
    func fetchCloudRequestCount() async throws -> Int
    func incrementCloudRequestCount() async throws
}

struct OrganizationMetrics: Sendable, Equatable {
    var pending: Int
    var pendingNetwork: Int
    var ready: Int
    var failed: Int
    var locked: Int
    var skippedNoConsent: Int
}
