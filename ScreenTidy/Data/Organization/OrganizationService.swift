import Foundation

/// Orchestrates understanding → local resolver → persistence.
/// Cloud/understanding never mutates Collections directly.
actor OrganizationService: Organizing {
    private let store: any OrganizationPersisting
    private let understanding: any UnderstandingProviding
    private let memory: any MemoryReading
    private let policy: ResolverPolicy
    private let onMutated: @Sendable () -> Void

    init(
        store: any OrganizationPersisting,
        understanding: any UnderstandingProviding,
        memory: any MemoryReading,
        policy: ResolverPolicy = .current,
        onMutated: @escaping @Sendable () -> Void = {}
    ) {
        self.store = store
        self.understanding = understanding
        self.memory = memory
        self.policy = policy
        self.onMutated = onMutated
    }

    func organizeIfNeeded(screenshotID: ScreenshotMemoryID) async throws {
        OrganizationPipelineDebugStore.reset(screenshotID: screenshotID)

        let consent = CloudUnderstandingPreferences.consent
        let allowMultimodal = (consent == .accepted)

        if consent == .notDetermined {
            OrganizationPipelineDebugStore.update(
                screenshotID: screenshotID,
                stage: .failed,
                detail: "Cloud consent not determined — multimodal blocked"
            )
            try await store.setOrganizeStatus(.skippedNoConsent, id: screenshotID, errorCode: nil)
            try await store.recordOrganizationRun(
                screenshotID: screenshotID,
                status: .skippedNoConsent,
                decision: nil,
                understanding: nil,
                policy: policy,
                errorCode: "consent_not_determined",
                fingerprint: nil
            )
            return
        }

        guard let shot = try await memory.fetchScreenshot(id: screenshotID) else { return }

        // Skip if already resolved at current resolver version (cost control).
        if let existingVersion = try await store.fetchOrganizeResolverVersion(id: screenshotID),
           existingVersion == policy.resolverVersion,
           try await store.fetchOrganizeStatus(id: screenshotID) == .ready {
            OrganizationPipelineDebugStore.update(
                screenshotID: screenshotID,
                stage: .completed,
                detail: "Already ready at resolver v\(policy.resolverVersion) — skipped"
            )
            return
        }

        let eligible = try await store.fetchOrganizationEligibleCollections()
        let contexts = eligible
            .filter { $0.kind != .unassigned && $0.kind != .userContext && $0.createdBy != "user" }
            .map {
                EligibleCollectionContext(
                    title: $0.title,
                    aliases: $0.aliases,
                    keyEntities: $0.keyEntities,
                    keyTerms: $0.keyTerms,
                    visualDescriptors: $0.visualDescriptors,
                    dateRangeStart: $0.dateRangeStart,
                    dateRangeEnd: $0.dateRangeEnd
                )
            }
        let titles = contexts.map(\.title)

        // Local multi-signal batch context (P2).
        let pendingPeers = try await store.fetchPendingOrganizeMembers(limit: 40)
        let eligibleTitles = contexts.map(\.title)
        func clusterMember(from snap: OrganizationClusterMemberSnapshot) -> MultiSignalClusterer.Member {
            let ocr = OrganizationOCRNormalizer.normalize(snap.ocrText)
            let profileTitles = eligibleTitles.filter { title in
                let t = title.lowercased()
                let o = ocr.lowercased()
                return t.split(separator: " ").contains(where: { o.contains($0) && $0.count >= 3 })
            }
            return MultiSignalClusterer.Member.withDerivedSource(
                id: snap.id,
                createdAt: snap.createdAt,
                ocrNormalized: ocr,
                visualLabels: snap.visualLabels,
                facets: snap.visualFacets,
                featurePrintData: snap.featurePrintData,
                profileMatchScore: profileTitles.isEmpty ? 0 : 0.7,
                profileTitles: profileTitles,
                rawOCR: snap.ocrText
            )
        }
        let seed = clusterMember(
            from: OrganizationClusterMemberSnapshot(
                id: screenshotID,
                createdAt: shot.createdAt,
                ocrText: shot.ocrText,
                visualLabels: shot.visualLabels,
                visualFacets: shot.visualFacets,
                featurePrintData: try? await store.fetchFeaturePrintData(id: screenshotID),
                photosLocalIdentifier: shot.photosLocalIdentifier
            )
        )
        // Prefer print from peer snapshots when seed print missing above.
        var seedWithPrint = seed
        if seedWithPrint.featurePrintData == nil,
           let peer = pendingPeers.first(where: { $0.id == screenshotID }) {
            seedWithPrint.featurePrintData = peer.featurePrintData
            seedWithPrint.visualLabels = peer.visualLabels
            seedWithPrint.facets = peer.visualFacets
            let refreshed = ScreenshotSourceDeriver.derive(
                ocrText: shot.ocrText,
                labels: [],
                strongFacets: peer.visualFacets
            )
            seedWithPrint.sourcePlatform = refreshed.sourcePlatform
            seedWithPrint.contentType = refreshed.contentType
            seedWithPrint.contentFamily = refreshed.contentFamily
        }
        let peerMembers = pendingPeers.map(clusterMember(from:))
        let cluster = OrganizationBatchPlanner.clusterDetailed(
            around: seedWithPrint,
            candidates: peerMembers,
            maxSize: policy.maxBatchSize
        )
        let batchIDs = cluster.memberIDs

        // Build multimodal batch payloads from local candidate group (ceiling 8).
        var batchMembers: [UnderstandingBatchMemberPayload] = []
        batchMembers.reserveCapacity(batchIDs.count)
        for memberID in batchIDs {
            let memoryShot: ScreenshotMemory?
            if memberID == screenshotID {
                memoryShot = shot
            } else {
                memoryShot = try? await memory.fetchScreenshot(id: memberID)
            }
            let peerSnap = pendingPeers.first(where: { $0.id == memberID })
            let ocr = memoryShot?.ocrText ?? peerSnap?.ocrText
            let facets = memoryShot?.visualFacets ?? peerSnap?.visualFacets ?? []
            let source = ScreenshotSourceDeriver.derive(
                ocrText: ocr,
                labels: [],
                strongFacets: facets
            )
            batchMembers.append(
                UnderstandingBatchMemberPayload(
                    localID: memberID.rawValue.uuidString,
                    ocrText: ocr,
                    createdAt: memoryShot?.createdAt ?? peerSnap?.createdAt,
                    photosLocalIdentifier: memoryShot?.photosLocalIdentifier
                        ?? peerSnap?.photosLocalIdentifier,
                    imageJPEGData: nil,
                    visualFacets: facets,
                    sourcePlatform: source.sourcePlatform == ScreenshotSourceEvidence.unknown
                        ? nil : source.sourcePlatform,
                    contentType: source.contentType == ScreenshotSourceEvidence.unknown
                        ? nil : source.contentType,
                    contentFamily: source.contentFamily == ScreenshotSourceEvidence.unknown
                        ? nil : source.contentFamily
                )
            )
        }

        let input = UnderstandingInput(
            screenshotID: screenshotID,
            ocrText: shot.ocrText,
            createdAt: shot.createdAt,
            photosLocalIdentifier: shot.photosLocalIdentifier,
            eligibleCollectionTitles: titles,
            eligibleCollectionContexts: contexts,
            allowMultimodal: allowMultimodal,
            batchMemberIDs: batchIDs,
            batchMembers: batchMembers,
            imageJPEGData: nil,
            visualLabels: shot.visualLabelObservations,
            visualFacets: shot.visualFacets
        )

        let batchSignature = batchIDs.count > 1
            ? batchIDs.map(\.rawValue.uuidString).sorted().joined(separator: ",")
            : nil
        let fingerprint = Self.fingerprint(
            ocr: OrganizationOCRNormalizer.normalize(shot.ocrText),
            createdAt: shot.createdAt,
            resolverVersion: policy.resolverVersion,
            batchSignature: batchSignature
        )

        if let cached = try await store.fetchCachedUnderstanding(fingerprint: fingerprint) {
            OrganizationPipelineDebugStore.update(
                screenshotID: screenshotID,
                stage: .structuredCandidateDecoded,
                detail: "Understanding cache hit (no new gateway call)",
                provider: cached.provider
            )
            try await apply(
                screenshotID: screenshotID,
                understandingResult: cached,
                eligible: eligible,
                batchSize: batchIDs.count,
                createdAt: shot.createdAt,
                fingerprint: fingerprint,
                batchID: batchSignature
            )
            return
        }

        let understandingResult: ScreenshotUnderstanding
        do {
            understandingResult = try await understanding.understand(input)
        } catch UnderstandingError.pendingNetwork {
            // Bounded retry path — keep pendingNetwork (OrganizationQueue backoff).
            let category = OrganizationPipelineDebugStore.trace(for: screenshotID)?.failureCategory
            let code = category?.rawValue ?? "pending_network"
            try await store.setOrganizeStatus(.pendingNetwork, id: screenshotID, errorCode: code)
            try await store.recordOrganizationRun(
                screenshotID: screenshotID,
                status: .pendingNetwork,
                decision: nil,
                understanding: nil,
                policy: policy,
                errorCode: code,
                fingerprint: fingerprint
            )
            return
        } catch {
            // Ordinary cloud-intelligence failures → Needs Review (never stuck in `failed`).
            let category = OrganizationPipelineDebugStore.trace(for: screenshotID)?.failureCategory
            let code = category?.rawValue ?? "understand_failed"
            OrganizationPipelineDebugStore.update(
                screenshotID: screenshotID,
                stage: .failed,
                detail: "Understanding failed → Needs Review fallback",
                failureCategory: category ?? .malformedResponse
            )
            try await applyCloudFailureNeedsReview(
                screenshotID: screenshotID,
                errorCode: code,
                fingerprint: fingerprint,
                batchID: batchSignature
            )
            return
        }

        try await store.cacheUnderstanding(fingerprint: fingerprint, understanding: understandingResult)
        if !understandingResult.provider.hasPrefix("ondevice") {
            try await store.incrementCloudRequestCount()
        }
        try await apply(
            screenshotID: screenshotID,
            understandingResult: understandingResult,
            eligible: eligible,
            batchSize: batchIDs.count,
            createdAt: shot.createdAt,
            fingerprint: fingerprint,
            batchID: batchSignature
        )
    }

    /// Cloud/schema/malformed failures must leave the screenshot usable in Needs Review.
    private func applyCloudFailureNeedsReview(
        screenshotID: ScreenshotMemoryID,
        errorCode: String,
        fingerprint: String,
        batchID: String?
    ) async throws {
        let understanding = ScreenshotUnderstanding(
            summary: nil,
            typeFacets: [],
            entities: [],
            locations: [],
            dates: [],
            visualDescriptors: [],
            candidateCollections: [],
            proposedNewCollection: nil,
            reasonSignals: ["cloud_intelligence_failed", errorCode],
            provider: "gateway-failed",
            sharedContext: nil,
            normalizedOCRPreview: nil
        )
        var decision = ResolverDecision(
            kind: .needsReview,
            collectionID: nil,
            title: nil,
            emoji: nil,
            confidence: nil,
            applicableThreshold: policy.assignThreshold,
            reason: "Cloud intelligence failed (\(errorCode)) — Needs Review",
            candidates: [],
            confidenceComponents: nil
        )
        decision.batchID = batchID

        try await store.applyResolverDecision(
            screenshotID: screenshotID,
            decision: decision,
            understanding: understanding,
            policy: policy,
            fingerprint: fingerprint
        )
        try await store.recordOrganizationRun(
            screenshotID: screenshotID,
            status: .success,
            decision: decision,
            understanding: understanding,
            policy: policy,
            errorCode: errorCode,
            fingerprint: fingerprint
        )
        OrganizationPipelineDebugStore.update(
            screenshotID: screenshotID,
            stage: .completed,
            detail: "Persisted needsReview after cloud failure",
            decisionKind: ResolverDecisionKind.needsReview.rawValue,
            provider: understanding.provider
        )
        onMutated()
    }

    private func apply(
        screenshotID: ScreenshotMemoryID,
        understandingResult: ScreenshotUnderstanding,
        eligible: [CollectionResolver.EligibleCollection],
        batchSize: Int,
        createdAt: Date?,
        fingerprint: String,
        batchID: String?
    ) async throws {
        let resolver = CollectionResolver(policy: policy)
        var decision = resolver.resolve(
            understanding: understandingResult,
            eligible: eligible,
            batchSize: batchSize,
            screenshotCreatedAt: createdAt
        )
        decision.batchID = batchID

        OrganizationPipelineDebugStore.update(
            screenshotID: screenshotID,
            stage: .resolverEvaluated,
            detail: "Resolver \(decision.kind.rawValue)",
            decisionKind: decision.kind.rawValue,
            provider: understandingResult.provider
        )

        try await store.applyResolverDecision(
            screenshotID: screenshotID,
            decision: decision,
            understanding: understandingResult,
            policy: policy,
            fingerprint: fingerprint
        )
        try await store.recordOrganizationRun(
            screenshotID: screenshotID,
            status: .success,
            decision: decision,
            understanding: understandingResult,
            policy: policy,
            errorCode: nil,
            fingerprint: fingerprint
        )
        if decision.kind == .create || decision.kind == .reuse {
            try await store.refreshCollectionProfile(for: decision.collectionID, createdTitle: decision.title)
        }
        OrganizationPipelineDebugStore.update(
            screenshotID: screenshotID,
            stage: .completed,
            detail: "Persisted \(decision.kind.rawValue)",
            decisionKind: decision.kind.rawValue,
            provider: understandingResult.provider
        )
        onMutated()
    }

    private static func fingerprint(
        ocr: String,
        createdAt: Date?,
        resolverVersion: Int,
        batchSignature: String?
    ) -> String {
        let datePart = createdAt.map { String(Int($0.timeIntervalSince1970)) } ?? ""
        let batchPart = batchSignature.map { ":\($0.hashValue)" } ?? ""
        return "v\(resolverVersion):\(ocr.count):\(ocr.hashValue):\(datePart)\(batchPart)"
    }
}
