import Foundation

/// Local pre-clustering for Needs Review backlog (ceiling = ResolverPolicy.maxBatchSize).
enum OrganizationBatchPlanner {
    struct Member: Sendable {
        var id: ScreenshotMemoryID
        var createdAt: Date?
        var ocrNormalized: String
    }

    /// Builds a natural group around `seed` using time proximity + token overlap.
    static func cluster(
        around seed: Member,
        candidates: [Member],
        maxSize: Int
    ) -> [ScreenshotMemoryID] {
        let limit = max(1, min(maxSize, 8))
        var selected: [Member] = [seed]
        let seedTokens = tokens(seed.ocrNormalized)

        let ranked = candidates
            .filter { $0.id != seed.id }
            .map { member -> (Member, Double) in
                (member, score(seed: seed, other: member, seedTokens: seedTokens))
            }
            .filter { $0.1 >= 0.35 }
            .sorted { $0.1 > $1.1 }

        for (member, _) in ranked {
            guard selected.count < limit else { break }
            selected.append(member)
        }

        // Prefer smaller natural groups — if only weak pairs, keep singleton.
        if selected.count == 2, let only = ranked.first, only.1 < 0.45 {
            return [seed.id]
        }
        return selected.map(\.id)
    }

    private static func score(seed: Member, other: Member, seedTokens: Set<String>) -> Double {
        var score = 0.0
        if let a = seed.createdAt, let b = other.createdAt {
            let hours = abs(a.timeIntervalSince(b)) / 3_600
            if hours <= 2 { score += 0.45 }
            else if hours <= 12 { score += 0.25 }
            else if hours <= 48 { score += 0.10 }
        }
        let otherTokens = tokens(other.ocrNormalized)
        if !seedTokens.isEmpty, !otherTokens.isEmpty {
            let inter = Double(seedTokens.intersection(otherTokens).count)
            let union = Double(seedTokens.union(otherTokens).count)
            if union > 0 {
                score += 0.55 * (inter / union)
            }
        }
        return min(1, score)
    }

    private static func tokens(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 3 }
        )
    }
}
