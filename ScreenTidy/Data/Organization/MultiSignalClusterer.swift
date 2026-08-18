import Foundation

/// Sprint 8.2B — precision-first candidate grouping.
/// Strategy D: seed expansion → contextual 1-hop bridge → group validation → outlier prune.
/// Groups are evidence bundles only — never Collection titles or taxonomy.
enum MultiSignalClusterer {
    /// Final group size bound (organize / multimodal payload safety — not semantic truth).
    static let maxGroupSize = 8
    /// DEBUG / expand retrieval pool (consider more peers than final size).
    static let retrievalPoolSize = 24
    static let admitFloor = 0.32
    static let bridgeAdmitFloor = 0.26
    static let bridgePeerFloor = 0.38
    static let outlierFloor = 0.20
    static let distinctiveOCRJaccardFloor = 0.12

    struct Member: Sendable, Equatable {
        var id: ScreenshotMemoryID
        var createdAt: Date?
        var ocrNormalized: String
        var visualLabels: [String]
        /// Strong Level 2A facet IDs (from `visualFacets`).
        var facets: [String]
        /// Weak facets (optional DEBUG); never sole admit.
        var weakFacets: [String]
        var featurePrintData: Data?
        var profileMatchScore: Double
        var profileTitles: [String]
        /// 8.2B-R1 parallel evidence (never Collection identity).
        var sourcePlatform: String
        var contentType: String
        var contentFamily: String

        init(
            id: ScreenshotMemoryID,
            createdAt: Date?,
            ocrNormalized: String,
            visualLabels: [String],
            facets: [String],
            weakFacets: [String] = [],
            featurePrintData: Data?,
            profileMatchScore: Double,
            profileTitles: [String],
            sourcePlatform: String = ScreenshotSourceEvidence.unknown,
            contentType: String = ScreenshotSourceEvidence.unknown,
            contentFamily: String = ScreenshotSourceEvidence.unknown
        ) {
            self.id = id
            self.createdAt = createdAt
            self.ocrNormalized = ocrNormalized
            self.visualLabels = visualLabels
            self.facets = facets
            self.weakFacets = weakFacets
            self.featurePrintData = featurePrintData
            self.profileMatchScore = profileMatchScore
            self.profileTitles = profileTitles
            self.sourcePlatform = sourcePlatform
            self.contentType = contentType
            self.contentFamily = contentFamily
        }

        /// Convenience: derive source/type/family from OCR + strong facets.
        static func withDerivedSource(
            id: ScreenshotMemoryID,
            createdAt: Date?,
            ocrNormalized: String,
            visualLabels: [String],
            facets: [String],
            weakFacets: [String] = [],
            featurePrintData: Data?,
            profileMatchScore: Double,
            profileTitles: [String],
            rawOCR: String? = nil
        ) -> Member {
            let evidence = ScreenshotSourceDeriver.derive(
                ocrText: rawOCR ?? ocrNormalized,
                labels: [],
                strongFacets: facets
            )
            return Member(
                id: id,
                createdAt: createdAt,
                ocrNormalized: ocrNormalized,
                visualLabels: visualLabels,
                facets: facets,
                weakFacets: weakFacets,
                featurePrintData: featurePrintData,
                profileMatchScore: profileMatchScore,
                profileTitles: profileTitles,
                sourcePlatform: evidence.sourcePlatform,
                contentType: evidence.contentType,
                contentFamily: evidence.contentFamily
            )
        }
    }

    struct MemberSupport: Sendable, Equatable, Identifiable {
        var id: ScreenshotMemoryID
        var support: Double
        var topSignals: [String: Double]
        var strongFacets: [String]
        var pruned: Bool
        var pruneReason: String?
    }

    /// DEBUG: a peer scored against the seed but not present in the final candidate group.
    struct RejectedCandidate: Sendable, Equatable, Identifiable {
        var id: ScreenshotMemoryID
        var totalScore: Double
        var hasContextualSupport: Bool
        var contextualFamilies: [String]
        var signalParts: [String: Double]
        /// Exact gate/path reason (e.g. `below_admit_threshold`, `no_contextual_support`).
        var rejectionReason: String
        var sourcePlatform: String
        var contentType: String
        var contentFamily: String
        /// R2a DEBUG: facet/type/family describing the same fact (no score change).
        var correlatedSemanticChannels: [String]
    }

    /// R2a DEBUG: why an accepted member was admitted (scoring unchanged).
    struct AdmittedMemberAudit: Sendable, Equatable, Identifiable {
        var id: ScreenshotMemoryID
        var totalScore: Double
        var signalParts: [String: Double]
        var hasContextualSupport: Bool
        var contextualFamilies: [String]
        /// `seed` | `seed_expand` | `bridge_admit` | `fp_attach`
        var admissionReason: String
        var bridgeInvolved: Bool
        var outlierValidationPassed: Bool
        var correlatedSemanticChannels: [String]
    }

    struct ClusterResult: Sendable, Equatable {
        var memberIDs: [ScreenshotMemoryID]
        /// Backward-compatible alias for meanCohesion.
        var cohesion: Double { meanCohesion }
        var meanCohesion: Double
        var weakestMemberSupport: Double
        var weakestPairSupport: Double
        var supportedEdgeCount: Int
        var clusterID: String
        var profileTitlesConsidered: [String]
        var signalBreakdown: [String: Double]
        var memberSupport: [MemberSupport]
        var flags: [String]
        /// DEBUG: why the result is a singleton (`nil` when multi-member).
        var singletonReason: String?
        /// DEBUG: top rejected peers with score / contextual / reason breakdown.
        var rejectedCandidates: [RejectedCandidate]
        /// R2a DEBUG: admission audits for non-seed accepted members (+ seed row).
        var admittedMemberAudits: [AdmittedMemberAudit]
        /// DEBUG: peers available to score (excludes seed).
        var inputPeerCount: Int
    }

    private struct PairScore: Sendable {
        var total: Double
        var parts: [String: Double]
        var hasContextualSupport: Bool
        var contextualFamilies: [String]
        var correlatedSemanticChannels: [String]
    }

    private struct PendingAdmit: Sendable {
        var member: Member
        var pair: PairScore
        var admissionReason: String
        var bridgeInvolved: Bool
    }

    // MARK: - Public API

    static func cluster(
        around seed: Member,
        candidates: [Member],
        maxSize: Int = maxGroupSize
    ) -> ClusterResult {
        let limit = max(1, min(maxSize, maxGroupSize))
        var flags: [String] = ["precision_first", "strategy_d_seed_expand_bridge_validate"]
        var prunedRecords: [MemberSupport] = []

        let peers = candidates.filter { $0.id != seed.id }
        if peers.isEmpty {
            flags.append("singleton")
            return singletonResult(
                seed: seed,
                flags: flags,
                singletonReason: "no_peers_in_pool",
                rejected: [],
                pruned: [],
                admitted: [seedAudit(seed: seed)],
                inputPeerCount: 0
            )
        }

        let scored = peers
            .map { member -> (Member, PairScore) in
                (member, scorePair(seed, member))
            }
            .sorted { $0.1.total > $1.1.total }

        let pool = Array(scored.prefix(retrievalPoolSize))
        let poolIDs = Set(pool.map(\.0.id))

        // Seed expansion — require contextual support
        var selected: [Member] = [seed]
        var admitParts: [String: Double] = [:]
        var pendingAdmits: [PendingAdmit] = []
        var bridgeAttemptedIDs = Set<ScreenshotMemoryID>()
        var bridgeFailedIDs = Set<ScreenshotMemoryID>()
        var fpAttemptedIDs = Set<ScreenshotMemoryID>()
        var fpFailedIDs = Set<ScreenshotMemoryID>()

        for (member, pair) in pool {
            guard selected.count < limit else { break }
            if pair.total >= admitFloor, pair.hasContextualSupport {
                selected.append(member)
                merge(&admitParts, pair.parts)
                pendingAdmits.append(
                    PendingAdmit(
                        member: member,
                        pair: pair,
                        admissionReason: "seed_expand",
                        bridgeInvolved: false
                    )
                )
            }
        }

        // One-hop bridge to already-admitted non-seed members
        if selected.count < limit {
            for (member, seedPair) in pool {
                guard selected.count < limit else { break }
                guard !selected.contains(where: { $0.id == member.id }) else { continue }
                guard selected.contains(where: { $0.id != seed.id }) else { continue }

                bridgeAttemptedIDs.insert(member.id)
                var bestBridge: PairScore?
                for m in selected where m.id != seed.id {
                    let bridge = scorePair(member, m)
                    if bridge.hasContextualSupport, bridge.total >= bridgePeerFloor {
                        if bestBridge == nil || bridge.total > bestBridge!.total {
                            bestBridge = bridge
                        }
                    }
                }
                if let bridge = bestBridge, seedPair.total >= bridgeAdmitFloor {
                    selected.append(member)
                    merge(&admitParts, seedPair.parts)
                    merge(&admitParts, bridge.parts)
                    flags.append("bridge_admit")
                    pendingAdmits.append(
                        PendingAdmit(
                            member: member,
                            pair: seedPair,
                            admissionReason: "bridge_admit",
                            bridgeInvolved: true
                        )
                    )
                } else if seedPair.total >= bridgeAdmitFloor {
                    bridgeFailedIDs.insert(member.id)
                }
            }
        }

        // Sparse-OCR attach via FP only when contextual corroboration exists
        if selected.count < limit, selected.count >= 2 {
            for (member, seedPair) in pool {
                guard selected.count < limit else { break }
                guard !selected.contains(where: { $0.id == member.id }) else { continue }
                let sparse = member.ocrNormalized.trimmingCharacters(in: .whitespacesAndNewlines).count < 12
                guard sparse else { continue }
                let fp = seedPair.parts["feature_print", default: 0]
                guard fp >= 0.12 else { continue }
                fpAttemptedIDs.insert(member.id)
                let softContextual = seedPair.hasContextualSupport
                    || selected.contains { other in
                        let p = scorePair(member, other)
                        return p.hasContextualSupport && p.total >= bridgePeerFloor
                    }
                if softContextual, seedPair.total >= bridgeAdmitFloor {
                    selected.append(member)
                    merge(&admitParts, seedPair.parts)
                    flags.append("fp_attach")
                    pendingAdmits.append(
                        PendingAdmit(
                            member: member,
                            pair: seedPair,
                            admissionReason: "fp_attach",
                            bridgeInvolved: false
                        )
                    )
                } else {
                    fpFailedIDs.insert(member.id)
                }
            }
        }

        let prePruneCount = selected.count

        // Group validation — prune outliers (not seed)
        if selected.count > 1 {
            let supportMap = computeMemberSupports(selected)
            var kept: [Member] = [seed]
            for member in selected where member.id != seed.id {
                let support = supportMap[member.id.rawValue] ?? 0
                if support < outlierFloor {
                    flags.append("pruned_outlier")
                    prunedRecords.append(
                        MemberSupport(
                            id: member.id,
                            support: support,
                            topSignals: [:],
                            strongFacets: member.facets,
                            pruned: true,
                            pruneReason: String(
                                format: "memberSupport %.3f < outlierFloor %.3f",
                                support,
                                outlierFloor
                            )
                        )
                    )
                } else {
                    kept.append(member)
                }
            }
            selected = kept
        }

        let prunedIDs = Set(prunedRecords.map(\.id))
        let finalIDs = Set(selected.map(\.id))
        let rejected = buildRejectedCandidates(
            scored: scored,
            poolIDs: poolIDs,
            finalIDs: finalIDs,
            prunedIDs: prunedIDs,
            bridgeFailedIDs: bridgeFailedIDs,
            fpFailedIDs: fpFailedIDs,
            bridgeAttemptedIDs: bridgeAttemptedIDs,
            fpAttemptedIDs: fpAttemptedIDs
        )
        let admitted = buildAdmittedAudits(
            seed: seed,
            pending: pendingAdmits,
            finalIDs: finalIDs,
            prunedIDs: prunedIDs
        )

        if selected.count == 1 {
            flags.append("singleton")
            let reason: String
            if prePruneCount > 1, !prunedRecords.isEmpty {
                reason = "collapsed_after_prune"
            } else {
                reason = "peers_scored_none_admitted"
            }
            return singletonResult(
                seed: seed,
                flags: flags,
                singletonReason: reason,
                rejected: rejected,
                pruned: prunedRecords,
                admitted: admitted,
                inputPeerCount: peers.count
            )
        }

        if contextualEdges(in: selected) == 0 {
            flags.append("singleton")
            flags.append("no_contextual_edge_collapsed")
            return singletonResult(
                seed: seed,
                flags: flags,
                singletonReason: "no_contextual_edge_collapsed",
                rejected: rejected,
                pruned: prunedRecords,
                admitted: admitted,
                inputPeerCount: peers.count
            )
        }

        return buildResult(
            members: selected,
            admitParts: admitParts,
            flags: flags,
            pruned: prunedRecords,
            rejected: rejected,
            admitted: admitted,
            inputPeerCount: peers.count
        )
    }

    /// Pairwise multi-signal score (DEBUG / tests).
    static func score(seed: Member, other: Member) -> (total: Double, parts: [String: Double]) {
        let pair = scorePair(seed, other)
        return (pair.total, pair.parts)
    }

    static func cohesionScore(members: [Member]) -> Double {
        guard members.count >= 2 else { return 1 }
        var sum = 0.0
        var pairs = 0
        for i in 0..<members.count {
            for j in (i + 1)..<members.count {
                sum += scorePair(members[i], members[j]).total
                pairs += 1
            }
        }
        return pairs == 0 ? 0 : sum / Double(pairs)
    }

    // MARK: - Pair scoring

    private static func scorePair(_ a: Member, _ b: Member) -> PairScore {
        var parts: [String: Double] = [:]
        var families: [String] = []

        if let ta = a.createdAt, let tb = b.createdAt {
            let hours = abs(ta.timeIntervalSince(tb)) / 3_600
            if hours <= 2 { parts["time"] = 0.10 }
            else if hours <= 12 { parts["time"] = 0.06 }
            else if hours <= 48 { parts["time"] = 0.03 }
            else if hours <= 168 { parts["time"] = 0.01 }
        }

        let tokensA = distinctiveTokens(a.ocrNormalized)
        let tokensB = distinctiveTokens(b.ocrNormalized)
        if !tokensA.isEmpty, !tokensB.isEmpty {
            let inter = Double(tokensA.intersection(tokensB).count)
            let union = Double(tokensA.union(tokensB).count)
            if union > 0 {
                let jaccard = inter / union
                parts["ocr_tokens"] = 0.24 * jaccard
                if jaccard >= distinctiveOCRJaccardFloor, inter >= 2 {
                    families.append("ocr_tokens")
                } else if inter >= 1 {
                    let rare = tokensA.intersection(tokensB).filter { $0.count >= 6 }
                    if !rare.isEmpty, jaccard >= 0.08 {
                        families.append("ocr_tokens")
                    }
                }
            }
        }

        let entity = entityOverlap(a.ocrNormalized, b.ocrNormalized)
        if entity.high > 0 {
            parts["ocr_entities"] = min(0.28, 0.16 * Double(entity.high) + 0.08 * Double(entity.medium))
            families.append("ocr_entities_h")
        } else if entity.medium > 0 {
            parts["ocr_entities"] = min(0.14, 0.08 * Double(entity.medium))
        }

        let labelsA = distinctiveVisionLabels(a.visualLabels)
        let labelsB = distinctiveVisionLabels(b.visualLabels)
        let labelInter = labelsA.intersection(labelsB)
        if !labelInter.isEmpty {
            let denom = Double(max(1, labelsA.union(labelsB).count))
            parts["vision"] = min(0.10, 0.08 * (Double(labelInter.count) / denom))
        }

        if let pa = a.featurePrintData, let pb = b.featurePrintData,
           let distance = VisionVisualAnalysisService.distance(between: pa, and: pb) {
            if distance <= VisualAnalysisPipeline.strongNeighborDistance {
                parts["feature_print"] = 0.14
            } else if distance <= VisualAnalysisPipeline.weakNeighborDistance {
                parts["feature_print"] = 0.08
            } else if distance <= 1.2 {
                parts["feature_print"] = 0.03
            }
        }

        let strongA = Set(a.facets).subtracting(["image_only"])
        let strongB = Set(b.facets).subtracting(["image_only"])
        let same = strongA.intersection(strongB)
        if !same.isEmpty {
            parts["facets"] = min(0.14, 0.08 * Double(same.count))
            // Same facet alone is NOT contextual support
        } else {
            let travel: Set<String> = [
                "boarding_pass", "flight_booking", "hotel_booking", "map", "reservation", "travel_imagery"
            ]
            let home: Set<String> = ["product_page", "interior_reference"]
            if !strongA.isDisjoint(with: travel), !strongB.isDisjoint(with: travel) {
                parts["facets"] = 0.14
                families.append("facet_bridge_travel")
            } else if !strongA.isDisjoint(with: home), !strongB.isDisjoint(with: home) {
                parts["facets"] = 0.12
                families.append("facet_bridge_home")
            }
        }

        let weakInter = Set(a.weakFacets).intersection(Set(b.weakFacets))
        if !weakInter.isEmpty {
            parts["weak_facets"] = min(0.04, 0.02 * Double(weakInter.count))
        }

        // 8.2B-R1 — source / type / family (modest; alone ≠ contextual support).
        let known: (String) -> Bool = { $0 != ScreenshotSourceEvidence.unknown && !$0.isEmpty }
        var matchedSource = false
        var matchedType = false
        var matchedFamily = false
        if known(a.sourcePlatform), a.sourcePlatform == b.sourcePlatform {
            parts["source_platform"] = 0.04
            matchedSource = true
        }
        if known(a.contentType), a.contentType == b.contentType {
            parts["content_type"] = 0.05
            matchedType = true
        }
        if known(a.contentFamily), a.contentFamily == b.contentFamily {
            parts["content_family"] = 0.04
            matchedFamily = true
        }

        let sharedTitles = Set(a.profileTitles).intersection(Set(b.profileTitles))
        var profileHit = false
        if !sharedTitles.isEmpty {
            parts["profile"] = 0.10
            profileHit = true
        } else {
            let mutual = min(a.profileMatchScore, b.profileMatchScore)
            if mutual >= 0.4 {
                parts["profile"] = min(0.08, mutual * 0.08)
                profileHit = true
            }
        }

        if profileHit, !families.isEmpty {
            families.append("profile_with_context")
        }
        if entity.medium > 0, entity.high == 0, !families.isEmpty {
            families.append("ocr_entities_m")
        }
        // Source/type/family become contextual only with independent corroboration.
        if !families.isEmpty {
            if matchedSource { families.append("source_with_context") }
            if matchedType { families.append("type_with_context") }
            if matchedFamily { families.append("family_with_context") }
        }

        let hasContextual = !families.isEmpty
        let total = min(1, parts.values.reduce(0, +))
        let sharedFacets = Array(Set(a.facets).intersection(Set(b.facets)))
        let sharedType = (a.contentType == b.contentType) ? a.contentType : ScreenshotSourceEvidence.unknown
        let sharedFamily = (a.contentFamily == b.contentFamily) ? a.contentFamily : ScreenshotSourceEvidence.unknown
        let correlated = SemanticCorrelationDiagnostics.correlatedChannelsForPair(
            sharedFacets: sharedFacets,
            sharedContentType: sharedType,
            sharedContentFamily: sharedFamily,
            signalParts: parts
        )
        return PairScore(
            total: total,
            parts: parts,
            hasContextualSupport: hasContextual,
            contextualFamilies: families,
            correlatedSemanticChannels: correlated
        )
    }

    // MARK: - Group assembly helpers

    private static func singletonResult(
        seed: Member,
        flags: [String],
        singletonReason: String,
        rejected: [RejectedCandidate],
        pruned: [MemberSupport],
        admitted: [AdmittedMemberAudit],
        inputPeerCount: Int
    ) -> ClusterResult {
        var supports: [MemberSupport] = [
            MemberSupport(
                id: seed.id,
                support: 1,
                topSignals: [:],
                strongFacets: seed.facets,
                pruned: false,
                pruneReason: nil
            )
        ]
        supports.append(contentsOf: pruned)
        return ClusterResult(
            memberIDs: [seed.id],
            meanCohesion: 1,
            weakestMemberSupport: 1,
            weakestPairSupport: 1,
            supportedEdgeCount: 0,
            clusterID: "singleton_\(seed.id.rawValue.uuidString.prefix(8))",
            profileTitlesConsidered: seed.profileTitles.sorted(),
            signalBreakdown: [:],
            memberSupport: supports.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString },
            flags: Array(Set(flags)).sorted(),
            singletonReason: singletonReason,
            rejectedCandidates: rejected,
            admittedMemberAudits: admitted,
            inputPeerCount: inputPeerCount
        )
    }

    private static func seedAudit(seed: Member) -> AdmittedMemberAudit {
        AdmittedMemberAudit(
            id: seed.id,
            totalScore: 1,
            signalParts: [:],
            hasContextualSupport: true,
            contextualFamilies: [],
            admissionReason: "seed",
            bridgeInvolved: false,
            outlierValidationPassed: true,
            correlatedSemanticChannels: []
        )
    }

    private static func buildAdmittedAudits(
        seed: Member,
        pending: [PendingAdmit],
        finalIDs: Set<ScreenshotMemoryID>,
        prunedIDs: Set<ScreenshotMemoryID>
    ) -> [AdmittedMemberAudit] {
        var audits: [AdmittedMemberAudit] = [seedAudit(seed: seed)]
        for item in pending {
            let kept = finalIDs.contains(item.member.id)
            let pruned = prunedIDs.contains(item.member.id)
            // Include kept members; also surface pruned-after-admit in audit with outlier fail.
            guard kept || pruned else { continue }
            audits.append(
                AdmittedMemberAudit(
                    id: item.member.id,
                    totalScore: item.pair.total,
                    signalParts: item.pair.parts,
                    hasContextualSupport: item.pair.hasContextualSupport,
                    contextualFamilies: item.pair.contextualFamilies.sorted(),
                    admissionReason: item.admissionReason,
                    bridgeInvolved: item.bridgeInvolved,
                    outlierValidationPassed: kept && !pruned,
                    correlatedSemanticChannels: item.pair.correlatedSemanticChannels
                )
            )
        }
        return audits
    }

    private static func buildRejectedCandidates(
        scored: [(Member, PairScore)],
        poolIDs: Set<ScreenshotMemoryID>,
        finalIDs: Set<ScreenshotMemoryID>,
        prunedIDs: Set<ScreenshotMemoryID>,
        bridgeFailedIDs: Set<ScreenshotMemoryID>,
        fpFailedIDs: Set<ScreenshotMemoryID>,
        bridgeAttemptedIDs: Set<ScreenshotMemoryID>,
        fpAttemptedIDs: Set<ScreenshotMemoryID>
    ) -> [RejectedCandidate] {
        scored
            .filter { !finalIDs.contains($0.0.id) }
            .prefix(5)
            .map { member, pair in
                let reason = rejectionReason(
                    id: member.id,
                    pair: pair,
                    inPool: poolIDs.contains(member.id),
                    prunedIDs: prunedIDs,
                    bridgeFailedIDs: bridgeFailedIDs,
                    fpFailedIDs: fpFailedIDs,
                    bridgeAttemptedIDs: bridgeAttemptedIDs,
                    fpAttemptedIDs: fpAttemptedIDs
                )
                return RejectedCandidate(
                    id: member.id,
                    totalScore: pair.total,
                    hasContextualSupport: pair.hasContextualSupport,
                    contextualFamilies: pair.contextualFamilies.sorted(),
                    signalParts: pair.parts,
                    rejectionReason: reason,
                    sourcePlatform: member.sourcePlatform,
                    contentType: member.contentType,
                    contentFamily: member.contentFamily,
                    correlatedSemanticChannels: pair.correlatedSemanticChannels
                )
            }
    }

    private static func rejectionReason(
        id: ScreenshotMemoryID,
        pair: PairScore,
        inPool: Bool,
        prunedIDs: Set<ScreenshotMemoryID>,
        bridgeFailedIDs: Set<ScreenshotMemoryID>,
        fpFailedIDs: Set<ScreenshotMemoryID>,
        bridgeAttemptedIDs: Set<ScreenshotMemoryID>,
        fpAttemptedIDs: Set<ScreenshotMemoryID>
    ) -> String {
        if prunedIDs.contains(id) {
            return "pruned_outlier"
        }
        if !inPool {
            return "outside_retrieval_pool"
        }
        // Seed-pair gate reasons take priority (matches physical DEBUG examples).
        if !pair.hasContextualSupport {
            // Bridge/FP path labels only when seed-pair contextual is absent and that path ran.
            if fpAttemptedIDs.contains(id), fpFailedIDs.contains(id) {
                return "fp_attach_failed"
            }
            if bridgeAttemptedIDs.contains(id), bridgeFailedIDs.contains(id) {
                return "bridge_failed"
            }
            if let alone = sourceTypeFamilyAloneReason(pair) {
                return alone
            }
            return "no_contextual_support"
        }
        if pair.total < admitFloor {
            return "below_admit_threshold"
        }
        // Passed seed-admit gates but was not kept (capacity / later prune already handled).
        if fpAttemptedIDs.contains(id), fpFailedIDs.contains(id) {
            return "fp_attach_failed"
        }
        if bridgeAttemptedIDs.contains(id), bridgeFailedIDs.contains(id) {
            return "bridge_failed"
        }
        return "below_admit_threshold"
    }

    /// When contextual support failed but source/type/family matched, surface a precise reason.
    private static func sourceTypeFamilyAloneReason(_ pair: PairScore) -> String? {
        let typeHit = (pair.parts["content_type"] ?? 0) > 0
        let sourceHit = (pair.parts["source_platform"] ?? 0) > 0
        let familyHit = (pair.parts["content_family"] ?? 0) > 0
        guard typeHit || sourceHit || familyHit else { return nil }
        // Prefer most specific label.
        if typeHit { return "type_alone_insufficient" }
        if sourceHit { return "source_alone_insufficient" }
        return "family_alone_insufficient"
    }

    private static func buildResult(
        members: [Member],
        admitParts: [String: Double],
        flags: [String],
        pruned: [MemberSupport],
        rejected: [RejectedCandidate],
        admitted: [AdmittedMemberAudit],
        inputPeerCount: Int
    ) -> ClusterResult {
        var pairSum = 0.0
        var pairCount = 0
        var minPair = 1.0
        var supported = 0
        var byMember: [UUID: (sum: Double, count: Int, parts: [String: Double])] = [:]

        for i in 0..<members.count {
            for j in (i + 1)..<members.count {
                let pair = scorePair(members[i], members[j])
                pairSum += pair.total
                pairCount += 1
                minPair = min(minPair, pair.total)
                if pair.hasContextualSupport { supported += 1 }
                accumulate(&byMember, members[i].id.rawValue, pair)
                accumulate(&byMember, members[j].id.rawValue, pair)
            }
        }

        let mean = pairCount == 0 ? 1 : pairSum / Double(pairCount)
        var supports: [MemberSupport] = members.map { member in
            let agg = byMember[member.id.rawValue]
            let support = (agg == nil || agg!.count == 0) ? 1 : agg!.sum / Double(agg!.count)
            let top = Dictionary(
                uniqueKeysWithValues: (agg?.parts ?? [:])
                    .sorted { $0.value > $1.value }
                    .prefix(5)
                    .map { ($0.key, $0.value) }
            )
            return MemberSupport(
                id: member.id,
                support: support,
                topSignals: top,
                strongFacets: member.facets,
                pruned: false,
                pruneReason: nil
            )
        }
        supports.append(contentsOf: pruned)
        let weakestMember = supports.filter { !$0.pruned }.map(\.support).min() ?? 1

        let titles = Array(Set(members.flatMap(\.profileTitles))).sorted()
        let clusterID = members
            .map(\.id.rawValue.uuidString)
            .sorted()
            .prefix(3)
            .joined(separator: "_")

        return ClusterResult(
            memberIDs: members.map(\.id),
            meanCohesion: mean,
            weakestMemberSupport: weakestMember,
            weakestPairSupport: pairCount == 0 ? 1 : minPair,
            supportedEdgeCount: supported,
            clusterID: "c_\(clusterID)",
            profileTitlesConsidered: titles,
            signalBreakdown: admitParts,
            memberSupport: supports.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString },
            flags: Array(Set(flags)).sorted(),
            singletonReason: nil,
            rejectedCandidates: rejected,
            admittedMemberAudits: admitted,
            inputPeerCount: inputPeerCount
        )
    }

    private static func computeMemberSupports(_ members: [Member]) -> [UUID: Double] {
        var byMember: [UUID: (sum: Double, count: Int)] = [:]
        for i in 0..<members.count {
            for j in (i + 1)..<members.count {
                let total = scorePair(members[i], members[j]).total
                let ia = members[i].id.rawValue
                let ib = members[j].id.rawValue
                var a = byMember[ia] ?? (0, 0)
                a.sum += total
                a.count += 1
                byMember[ia] = a
                var b = byMember[ib] ?? (0, 0)
                b.sum += total
                b.count += 1
                byMember[ib] = b
            }
        }
        return byMember.mapValues { $0.count == 0 ? 0 : $0.sum / Double($0.count) }
    }

    private static func contextualEdges(in members: [Member]) -> Int {
        var count = 0
        for i in 0..<members.count {
            for j in (i + 1)..<members.count {
                if scorePair(members[i], members[j]).hasContextualSupport { count += 1 }
            }
        }
        return count
    }

    private static func merge(_ into: inout [String: Double], _ parts: [String: Double]) {
        for (k, v) in parts {
            into[k, default: 0] += v
        }
    }

    private static func accumulate(
        _ into: inout [UUID: (sum: Double, count: Int, parts: [String: Double])],
        _ id: UUID,
        _ pair: PairScore
    ) {
        var cur = into[id] ?? (0, 0, [:])
        cur.sum += pair.total
        cur.count += 1
        for (k, v) in pair.parts {
            cur.parts[k, default: 0] += v
        }
        into[id] = cur
    }

    // MARK: - OCR / entity / vision helpers

    private static let ocrStopwords: Set<String> = [
        "settings", "done", "back", "share", "continue", "cancel", "search", "today", "home",
        "ok", "open", "close", "edit", "delete", "more", "next", "skip", "save", "send",
        "yes", "no", "the", "and", "for", "you", "are", "but", "not", "all", "can", "had",
        "her", "was", "one", "our", "out", "get", "has", "him", "his", "how", "man", "new",
        "now", "old", "see", "way", "who", "did", "let", "put", "say", "she", "too", "use",
        "from", "with", "this", "that", "your", "have", "will", "just", "like", "what",
        "when", "where", "which", "while", "about", "after", "before", "into", "over",
        "only", "also", "than", "then", "them", "they", "been", "were", "said", "each",
        "make", "most", "some", "time", "very", "message", "messages", "notification",
        "notifications", "photo", "photos", "camera", "gallery",
        // Platform chrome must not create OCR contextual glue by itself (8.2B-R1).
        "instagram", "linkedin", "facebook", "whatsapp", "imessage", "messenger",
        "gmail", "twitter", "tiktok", "inbox", "subject", "safari"
    ]

    private static let visionDenylist: Set<String> = [
        "document", "adult", "person", "people", "human", "text", "screenshot", "screen",
        "display", "clothing", "structure", "man", "woman", "child", "face", "body",
        "indoor", "outdoors"
    ]

    private static let genericGeoAlone: Set<String> = [
        "hotel", "airport", "city", "country", "travel", "trip", "flight", "room", "guest"
    ]

    private static let domainDenylist: Set<String> = [
        "apple.com", "google.com", "icloud.com", "microsoft.com", "facebook.com", "instagram.com"
    ]

    private static func distinctiveTokens(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 4 && !ocrStopwords.contains($0) && !genericGeoAlone.contains($0) }
        )
    }

    private static func distinctiveVisionLabels(_ labels: [String]) -> Set<String> {
        Set(labels.map { $0.lowercased() }.filter { !visionDenylist.contains($0) })
    }

    private struct EntityHit {
        var high: Int
        var medium: Int
    }

    private static func entityOverlap(_ a: String, _ b: String) -> EntityHit {
        let al = a.lowercased()
        let bl = b.lowercased()
        var high = 0
        var medium = 0

        let refPatterns = [
            #"\b(?:confirmation|booking)\s*(?:#|no\.?|number|ref(?:erence)?\.?)?\s*[a-z0-9-]{5,}\b"#,
            #"\b(?:ref|pnr)\s*[:#]?\s*[a-z0-9]{5,}\b"#,
            #"#[a-z0-9]{5,}\b"#
        ]
        for pattern in refPatterns {
            let ra = matches(pattern, in: al)
            let rb = matches(pattern, in: bl)
            if !ra.isEmpty, !ra.isDisjoint(with: rb) { high += 1 }
        }

        let flightsA = flightNumbers(in: al)
        let flightsB = flightNumbers(in: bl)
        if !flightsA.isEmpty, !flightsA.isDisjoint(with: flightsB) { high += 1 }

        let iataA = iataCodes(in: a)
        let iataB = iataCodes(in: b)
        let sharedIata = iataA.intersection(iataB)
        if sharedIata.count >= 2 { high += 1 }
        else if sharedIata.count == 1 { medium += 1 }

        let sharedDomains = domains(in: al).intersection(domains(in: bl)).subtracting(domainDenylist)
        if !sharedDomains.isEmpty { high += 1 }

        let sharedPhrases = multiWordPhrases(al).intersection(multiWordPhrases(bl))
        if !sharedPhrases.isEmpty { high += 1 }

        let sharedCodes = alnumCodes(al).intersection(alnumCodes(bl))
        if !sharedCodes.isEmpty { medium += sharedCodes.count }

        let longA = Set(
            al.split(whereSeparator: { !$0.isLetter }).map(String.init)
                .filter { $0.count >= 6 && !ocrStopwords.contains($0) }
        )
        let longB = Set(
            bl.split(whereSeparator: { !$0.isLetter }).map(String.init)
                .filter { $0.count >= 6 && !ocrStopwords.contains($0) }
        )
        if !longA.intersection(longB).isEmpty { medium += 1 }

        return EntityHit(high: high, medium: medium)
    }

    private static func matches(_ pattern: String, in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]).lowercased() }
        })
    }

    private static func flightNumbers(in text: String) -> Set<String> {
        var hits = Set<String>()
        let patterns = [
            #"\b(?:flight|flt)\s*#?\s*\d{1,4}\b"#,
            #"\b[a-z]{2}\s?\d{3,4}\b"#
        ]
        let block: Set<String> = [
            "to", "at", "on", "in", "by", "of", "or", "if", "is", "it", "be", "as", "an", "am", "pm", "no", "ok"
        ]
        for (idx, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let swift = Range(match.range, in: text) else { continue }
                let token = String(text[swift])
                if idx == 1 {
                    let letters = String(token.prefix(while: { $0.isLetter }))
                    if block.contains(letters) { continue }
                }
                hits.insert(token.replacingOccurrences(of: " ", with: ""))
            }
        }
        return hits
    }

    private static func iataCodes(in text: String) -> Set<String> {
        let denylist: Set<String> = [
            "THE", "AND", "FOR", "YOU", "ARE", "BUT", "NOT", "ALL", "CAN", "HAD", "HER", "WAS", "ONE",
            "OUR", "OUT", "DAY", "GET", "HAS", "HIM", "HIS", "HOW", "MAN", "NEW", "NOW", "OLD", "SEE",
            "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN", "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
            "JUL", "AUG", "SEP", "OCT", "NOV", "DEC", "PDF", "SMS", "OTP", "APP", "IOS", "USD", "EUR"
        ]
        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Z]{3}\b"#) else { return [] }
        let upper = text.uppercased()
        let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
        var codes = Set<String>()
        for match in regex.matches(in: upper, range: range) {
            guard let swift = Range(match.range, in: upper) else { continue }
            let code = String(upper[swift])
            if !denylist.contains(code) { codes.insert(code) }
        }
        return codes
    }

    private static func domains(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:https?://)?([a-z0-9-]+(?:\.[a-z0-9-]+)+)\b"#)
        else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = Set<String>()
        for match in regex.matches(in: text, range: range) {
            if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) {
                result.insert(String(text[r]).lowercased())
            }
        }
        return result
    }

    private static func multiWordPhrases(_ text: String) -> Set<String> {
        let tokens = text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0).lowercased() }
            .filter { $0.count >= 3 && !ocrStopwords.contains($0) }
        var phrases = Set<String>()
        guard tokens.count >= 2 else { return phrases }
        for i in 0..<(tokens.count - 1) where tokens[i].count >= 4 && tokens[i + 1].count >= 4 {
            phrases.insert(tokens[i] + " " + tokens[i + 1])
        }
        return phrases
    }

    private static func alnumCodes(_ text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?=[a-z]*\d)(?=\d*[a-z])[a-z0-9]{6,}\b"#)
        else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        })
    }
}
