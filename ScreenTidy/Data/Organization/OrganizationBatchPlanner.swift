import Foundation

/// Local candidate grouping for organize batch context (ceiling = ResolverPolicy.maxBatchSize).
/// Sprint 8.2B: precision-first multi-signal groups — never Collection names.
enum OrganizationBatchPlanner {
    typealias Member = MultiSignalClusterer.Member

    /// Builds a candidate group around `seed` (member IDs only).
    static func cluster(
        around seed: Member,
        candidates: [Member],
        maxSize: Int
    ) -> [ScreenshotMemoryID] {
        MultiSignalClusterer.cluster(around: seed, candidates: candidates, maxSize: maxSize).memberIDs
    }

    static func clusterDetailed(
        around seed: Member,
        candidates: [Member],
        maxSize: Int
    ) -> MultiSignalClusterer.ClusterResult {
        MultiSignalClusterer.cluster(around: seed, candidates: candidates, maxSize: maxSize)
    }
}
