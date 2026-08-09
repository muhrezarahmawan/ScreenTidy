import Foundation

/// On-device Collection Resolver — sole authority for reuse / create / Needs Review.
/// Cloud/understanding output is advisory only.
struct CollectionResolver: Sendable {
    var policy: ResolverPolicy

    init(policy: ResolverPolicy = .current) {
        self.policy = policy
    }

    struct EligibleCollection: Sendable {
        var id: ContextCollectionID
        var title: String
        var normalizedTitle: String
        var kind: ContextCollectionKind
        var createdBy: String
        var aliases: [String]
        var keyEntities: [String]
        var keyTerms: [String]
        var visualDescriptors: [String]
        var dateRangeStart: Date?
        var dateRangeEnd: Date?
    }

    func resolve(
        understanding: ScreenshotUnderstanding,
        eligible: [EligibleCollection],
        batchSize: Int = 1,
        screenshotCreatedAt: Date? = nil
    ) -> ResolverDecision {
        let autoEligible = eligible.filter { collection in
            if collection.kind == .unassigned { return false }
            if collection.kind == .userContext || collection.createdBy == "user" {
                return policy.userCollectionAutoAdd
            }
            return true
        }

        let scored = scoreCandidates(
            understanding: understanding,
            eligible: autoEligible,
            batchSize: batchSize,
            screenshotCreatedAt: screenshotCreatedAt
        )

        guard let best = scored.first else {
            return needsReview(
                candidates: understanding.candidateCollections,
                reason: "No candidates above noise floor",
                threshold: policy.assignThreshold,
                components: nil
            )
        }

        if best.components.final < policy.assignThreshold {
            return needsReview(
                candidates: scored.map(\.asCandidate),
                reason: "Best confidence \(fmt(best.components.final)) < assign \(fmt(policy.assignThreshold))",
                threshold: policy.assignThreshold,
                components: best.components
            )
        }

        if let match = best.matched {
            return ResolverDecision(
                kind: .reuse,
                collectionID: match.id,
                title: match.title,
                emoji: nil,
                confidence: best.components.final,
                applicableThreshold: policy.assignThreshold,
                reason: "Reuse \(match.title) (final \(fmt(best.components.final)) ≥ \(fmt(policy.assignThreshold)))",
                candidates: scored.map(\.asCandidate),
                confidenceComponents: best.components
            )
        }

        if let proposed = understanding.proposedNewCollection {
            let createConfidence = clamp(proposed.confidence)
            if let proposal = validatedCreateProposal(understanding: understanding, title: proposed.title) {
                if let existing = bestMatch(for: proposal.title, in: autoEligible) {
                    let reuseComponents = composeConfidence(
                        provider: createConfidence,
                        understanding: understanding,
                        matched: existing,
                        batchSize: batchSize,
                        screenshotCreatedAt: screenshotCreatedAt,
                        forCreate: false
                    )
                    if reuseComponents.final >= policy.assignThreshold {
                        return ResolverDecision(
                            kind: .reuse,
                            collectionID: existing.id,
                            title: existing.title,
                            emoji: nil,
                            confidence: reuseComponents.final,
                            applicableThreshold: policy.assignThreshold,
                            reason: "Reuse \(existing.title) for proposed title (final \(fmt(reuseComponents.final)))",
                            candidates: scored.map(\.asCandidate),
                            confidenceComponents: reuseComponents
                        )
                    }
                }

                let createComponents = composeConfidence(
                    provider: createConfidence,
                    understanding: understanding,
                    matched: nil,
                    batchSize: batchSize,
                    screenshotCreatedAt: screenshotCreatedAt,
                    forCreate: true
                )

                if createComponents.final >= policy.createThreshold,
                   bestMatch(for: proposal.title, in: autoEligible) == nil,
                   createComponents.createCorroborated {
                    let clashesWithUser = eligible.contains {
                        ($0.kind == .userContext || $0.createdBy == "user")
                            && ($0.normalizedTitle == CollectionResolver.normalizeTitle(proposal.title)
                                || $0.aliases.contains(CollectionResolver.normalizeTitle(proposal.title)))
                    }
                    if !clashesWithUser {
                        return ResolverDecision(
                            kind: .create,
                            collectionID: nil,
                            title: proposal.title,
                            emoji: proposal.emoji,
                            confidence: createComponents.final,
                            applicableThreshold: policy.createThreshold,
                            reason: "Create \(proposal.title) (final \(fmt(createComponents.final)) ≥ \(fmt(policy.createThreshold)); corroborated)",
                            candidates: scored.map(\.asCandidate),
                            confidenceComponents: createComponents
                        )
                    }
                }

                if createComponents.final >= policy.createThreshold, !createComponents.createCorroborated {
                    return needsReview(
                        candidates: scored.map(\.asCandidate),
                        reason: "Create confidence met but corroboration failed (object/type-only or weak context)",
                        threshold: policy.createThreshold,
                        components: createComponents
                    )
                }

                if createComponents.final >= policy.assignThreshold, createComponents.final < policy.createThreshold {
                    return needsReview(
                        candidates: scored.map(\.asCandidate),
                        reason: "Mid-band \(fmt(createComponents.final)): below create \(fmt(policy.createThreshold)), no reusable match",
                        threshold: policy.createThreshold,
                        components: createComponents
                    )
                }
            }
        }

        if best.components.final >= policy.assignThreshold, best.matched == nil {
            return needsReview(
                candidates: scored.map(\.asCandidate),
                reason: "High confidence but no eligible automatic Collection to reuse",
                threshold: policy.assignThreshold,
                components: best.components
            )
        }

        return needsReview(
            candidates: scored.map(\.asCandidate),
            reason: "No safe reuse or create",
            threshold: policy.assignThreshold,
            components: best.components
        )
    }

    // MARK: - Scoring

    private struct Scored {
        var title: String
        var matched: EligibleCollection?
        var reasonSignals: [String]
        var components: ResolverConfidenceComponents

        var asCandidate: UnderstandingCandidate {
            UnderstandingCandidate(
                title: title,
                confidence: components.final,
                reasonSignals: reasonSignals + components.notes
            )
        }
    }

    private func scoreCandidates(
        understanding: ScreenshotUnderstanding,
        eligible: [EligibleCollection],
        batchSize: Int,
        screenshotCreatedAt: Date?
    ) -> [Scored] {
        var scored: [Scored] = []

        for candidate in understanding.candidateCollections {
            let match = bestMatch(for: candidate.title, in: eligible)
            let components = composeConfidence(
                provider: clamp(candidate.confidence),
                understanding: understanding,
                matched: match,
                batchSize: batchSize,
                screenshotCreatedAt: screenshotCreatedAt,
                forCreate: false
            )
            scored.append(
                Scored(
                    title: candidate.title,
                    matched: match,
                    reasonSignals: candidate.reasonSignals,
                    components: components
                )
            )
        }

        if let proposed = understanding.proposedNewCollection {
            let match = bestMatch(for: proposed.title, in: eligible)
            let components = composeConfidence(
                provider: clamp(proposed.confidence),
                understanding: understanding,
                matched: match,
                batchSize: batchSize,
                screenshotCreatedAt: screenshotCreatedAt,
                forCreate: match == nil
            )
            scored.append(
                Scored(
                    title: proposed.title,
                    matched: match,
                    reasonSignals: ["proposed_new"],
                    components: components
                )
            )
        }

        let tokens = understandingTokens(understanding)
        for collection in eligible {
            let overlap = titleOverlapScore(collection: collection, tokens: tokens)
            guard overlap >= 0.55 else { continue }
            let components = composeConfidence(
                provider: min(0.95, overlap),
                understanding: understanding,
                matched: collection,
                batchSize: batchSize,
                screenshotCreatedAt: screenshotCreatedAt,
                forCreate: false
            )
            scored.append(
                Scored(
                    title: collection.title,
                    matched: collection,
                    reasonSignals: ["local_title_overlap"],
                    components: components
                )
            )
        }

        // Profile entity overlap even without provider title hit
        for collection in eligible {
            let entityScore = entityOverlap(understanding: understanding, collection: collection)
            guard entityScore >= 0.45 else { continue }
            let components = composeConfidence(
                provider: entityScore,
                understanding: understanding,
                matched: collection,
                batchSize: batchSize,
                screenshotCreatedAt: screenshotCreatedAt,
                forCreate: false
            )
            scored.append(
                Scored(
                    title: collection.title,
                    matched: collection,
                    reasonSignals: ["profile_entity_overlap"],
                    components: components
                )
            )
        }

        return scored.sorted { $0.components.final > $1.components.final }
    }

    private func composeConfidence(
        provider: Double,
        understanding: ScreenshotUnderstanding,
        matched: EligibleCollection?,
        batchSize: Int,
        screenshotCreatedAt: Date?,
        forCreate: Bool
    ) -> ResolverConfidenceComponents {
        var notes: [String] = []
        let providerClamped = clamp(provider)

        var profileMatch = 0.0
        var aliasMatch = 0.0
        var entity = 0.0
        var temporal = 0.0

        if let matched {
            entity = entityOverlap(understanding: understanding, collection: matched)
            if entity > 0 { notes.append("entity_overlap=\(fmt(entity))") }

            let proposedTitle = understanding.proposedNewCollection?.title
                ?? understanding.candidateCollections.first?.title
            if let proposedTitle {
                let normalized = Self.normalizeTitle(proposedTitle)
                if matched.aliases.contains(normalized) {
                    aliasMatch = 0.12
                    notes.append("alias_match")
                }
                if Self.similarity(normalized, matched.normalizedTitle) >= 0.90 {
                    profileMatch = max(profileMatch, 0.10)
                }
            }
            profileMatch = max(profileMatch, min(0.15, entity * 0.2))

            if let created = screenshotCreatedAt,
               let start = matched.dateRangeStart,
               let end = matched.dateRangeEnd {
                if created >= start.addingTimeInterval(-3 * 86_400),
                   created <= end.addingTimeInterval(3 * 86_400) {
                    temporal = 0.08
                    notes.append("temporal_overlap")
                }
            }
        }

        let textVisual = textVisualAgreement(understanding)
        if textVisual > 0 { notes.append("text_visual=\(fmt(textVisual))") }

        var batch = 0.0
        if batchSize > 1 {
            batch = min(0.12, 0.04 * Double(batchSize - 1))
            notes.append("batch_size=\(batchSize)")
        }
        if let shared = understanding.sharedContext, shared.confidence >= 0.7 {
            batch = max(batch, 0.10)
            notes.append("shared_context")
        }

        var conflict = 0.0
        if let matched {
            // Prefer trip/context profile when type-facet airline conflicts with stronger trip entities.
            let typeLooksAirline = understanding.typeFacets.contains {
                $0.lowercased().contains("airline") || $0.lowercased().contains("boarding")
            }
            let profileLooksTrip = matched.keyTerms.contains { $0.lowercased().contains("trip") }
                || matched.keyEntities.contains { ["tokyo", "japan", "osaka"].contains($0.lowercased()) }
            let titleLooksAirline = matched.normalizedTitle.contains("airways")
                || matched.normalizedTitle.contains("airline")
            if typeLooksAirline, profileLooksTrip, titleLooksAirline == false {
                // Good — boarding pass into Japan Trip; slight boost already via entity
            } else if typeLooksAirline, titleLooksAirline, profileLooksTrip == false,
                      understanding.locations.contains(where: { $0.lowercased().contains("tokyo") || $0.lowercased().contains("japan") }) {
                conflict = 0.08
                notes.append("airline_vs_trip_ambiguity")
            }
        }

        var final = providerClamped
            + profileMatch
            + aliasMatch
            + min(0.12, entity * 0.15)
            + temporal
            + textVisual
            + batch
            - conflict
        final = clamp(final)

        let corroborated = createCorroboration(
            understanding: understanding,
            provider: providerClamped,
            batchSize: batchSize,
            textVisual: textVisual,
            forCreate: forCreate
        )
        if forCreate {
            notes.append(corroborated ? "create_corroborated" : "create_not_corroborated")
        }

        return ResolverConfidenceComponents(
            provider: providerClamped,
            profileMatch: profileMatch,
            aliasMatch: aliasMatch,
            entityOverlap: entity,
            temporalOverlap: temporal,
            textVisualAgreement: textVisual,
            batchCorroboration: batch,
            conflictPenalty: conflict,
            final: final,
            createCorroborated: corroborated,
            notes: notes
        )
    }

    private func createCorroboration(
        understanding: ScreenshotUnderstanding,
        provider: Double,
        batchSize: Int,
        textVisual: Double,
        forCreate: Bool
    ) -> Bool {
        guard forCreate else { return true }
        guard provider >= policy.createThreshold else { return false }

        // Reject bare object / type labels as Collection titles.
        let title = CollectionResolver.normalizeTitle(understanding.proposedNewCollection?.title ?? "")
        if ResolverPolicy.genericTitleDenylist.contains(title) { return false }
        if understanding.typeFacets.map({ CollectionResolver.normalizeTitle($0) }).contains(title) {
            return false
        }

        let strongEntity = understanding.entities.contains {
            $0.confidence >= 0.75 && ["city", "place", "project", "event", "airline", "hotel", "merchant", "topic"].contains($0.type)
                && $0.value.split(separator: " ").count >= 1
        }
        let namedLocation = !understanding.locations.isEmpty
        let batchSupport = batchSize >= 2 || (understanding.sharedContext?.confidence ?? 0) >= 0.75
        let agreement = textVisual >= 0.08
        let specificTitle = title.split(separator: " ").count >= 2

        return batchSupport || (strongEntity && (namedLocation || agreement || specificTitle)) || (agreement && specificTitle && strongEntity)
    }

    private func textVisualAgreement(_ understanding: ScreenshotUnderstanding) -> Double {
        let hasOCRSignal = !(understanding.normalizedOCRPreview ?? "").isEmpty
            || understanding.entities.contains { $0.type != "visual" }
        let hasVisual = !understanding.visualDescriptors.isEmpty
            && !understanding.visualDescriptors.allSatisfy { $0 == "image_only" || $0 == "image_unavailable" }
        if hasOCRSignal, hasVisual { return 0.08 }
        if hasVisual, understanding.entities.isEmpty == false { return 0.05 }
        return 0
    }

    private func entityOverlap(understanding: ScreenshotUnderstanding, collection: EligibleCollection) -> Double {
        let values = Set(
            (understanding.entities.map { $0.value.lowercased() }
                + understanding.locations.map { $0.lowercased() }
                + understanding.visualDescriptors.map { $0.lowercased() })
                .flatMap { $0.split(separator: " ").map(String.init) }
                .filter { $0.count >= 3 }
        )
        let profile = Set(
            (collection.keyEntities + collection.keyTerms + collection.visualDescriptors + collection.aliases)
                .map { $0.lowercased() }
                .flatMap { $0.split(separator: " ").map(String.init) }
                .filter { $0.count >= 3 }
        )
        guard !values.isEmpty, !profile.isEmpty else { return 0 }
        let inter = Double(values.intersection(profile).count)
        return min(1, inter / Double(min(6, profile.count)))
    }

    private func bestMatch(for title: String, in eligible: [EligibleCollection]) -> EligibleCollection? {
        let normalized = Self.normalizeTitle(title)
        guard !normalized.isEmpty else { return nil }

        if let exact = eligible.first(where: { $0.normalizedTitle == normalized }) {
            return exact
        }
        if let alias = eligible.first(where: { $0.aliases.contains(normalized) }) {
            return alias
        }

        var best: (EligibleCollection, Double)?
        for collection in eligible {
            let score = Self.similarity(normalized, collection.normalizedTitle)
            let aliasBest = collection.aliases.map { Self.similarity(normalized, $0) }.max() ?? 0
            let combined = max(score, aliasBest)
            if combined >= 0.90 {
                if best == nil || combined > best!.1 {
                    best = (collection, combined)
                }
            }
        }
        return best?.0
    }

    private func validatedCreateProposal(
        understanding: ScreenshotUnderstanding,
        title: String
    ) -> ProposedNewCollection? {
        let cleaned = Self.sanitizeTitle(title)
        guard Self.isAcceptableAutomaticTitle(cleaned) else { return nil }
        let emoji = understanding.proposedNewCollection?.emoji.flatMap(Self.sanitizeEmoji)
        let confidence = understanding.proposedNewCollection?.confidence
            ?? understanding.candidateCollections.first(where: { $0.title == title })?.confidence
            ?? 0
        return ProposedNewCollection(title: cleaned, emoji: emoji, confidence: clamp(confidence))
    }

    private func needsReview(
        candidates: [UnderstandingCandidate],
        reason: String,
        threshold: Double,
        components: ResolverConfidenceComponents?
    ) -> ResolverDecision {
        ResolverDecision(
            kind: .needsReview,
            collectionID: nil,
            title: nil,
            emoji: nil,
            confidence: components?.final ?? candidates.map(\.confidence).max(),
            applicableThreshold: threshold,
            reason: reason,
            candidates: candidates,
            confidenceComponents: components
        )
    }

    private func understandingTokens(_ understanding: ScreenshotUnderstanding) -> Set<String> {
        var tokens = Set<String>()
        for entity in understanding.entities {
            for part in entity.value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                if part.count >= 3 { tokens.insert(String(part)) }
            }
        }
        for location in understanding.locations {
            for part in location.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                if part.count >= 3 { tokens.insert(String(part)) }
            }
        }
        for descriptor in understanding.visualDescriptors {
            for part in descriptor.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                if part.count >= 3 { tokens.insert(String(part)) }
            }
        }
        if let summary = understanding.summary {
            for part in summary.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                if part.count >= 3 { tokens.insert(String(part)) }
            }
        }
        return tokens
    }

    private func titleOverlapScore(collection: EligibleCollection, tokens: Set<String>) -> Double {
        let titleTokens = Set(
            collection.normalizedTitle.split(separator: " ").map(String.init).filter { $0.count >= 3 }
        )
        guard !titleTokens.isEmpty, !tokens.isEmpty else { return 0 }
        let inter = titleTokens.intersection(tokens).count
        return Double(inter) / Double(titleTokens.count)
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - Title helpers

    static func sanitizeTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: \.isWhitespace).prefix(4)
        return parts.joined(separator: " ")
    }

    static func isAcceptableAutomaticTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 40 else { return false }
        guard !trimmed.contains(".") else { return false }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard (1...4).contains(words.count) else { return false }
        let normalized = Self.normalizeTitle(trimmed)
        if ResolverPolicy.genericTitleDenylist.contains(normalized) { return false }
        if normalized.hasPrefix("screenshot") { return false }
        return true
    }

    static func normalizeTitle(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != " " })
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitizeEmoji(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let first = trimmed.first else { return nil }
        let grapheme = String(first)
        if grapheme.unicodeScalars.allSatisfy({ $0.isASCII }) { return nil }
        return grapheme
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let aTokens = Set(a.split(separator: " ").map(String.init))
        let bTokens = Set(b.split(separator: " ").map(String.init))
        if !aTokens.isEmpty, !bTokens.isEmpty {
            let inter = Double(aTokens.intersection(bTokens).count)
            let union = Double(aTokens.union(bTokens).count)
            let jaccard = union == 0 ? 0 : inter / union
            if jaccard >= 0.5 { return jaccard }
        }
        let distance = editDistance(a, b)
        let maxLen = Double(max(a.count, b.count))
        return max(0, 1 - (Double(distance) / maxLen))
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var prev = Array(0...bChars.count)
        for i in 1...aChars.count {
            var cur = [i] + Array(repeating: 0, count: bChars.count)
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = cur
        }
        return prev[bChars.count]
    }
}
