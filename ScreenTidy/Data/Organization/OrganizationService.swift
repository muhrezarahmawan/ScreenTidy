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

        // Local batch context (inspectable via batchMemberIDs on input / DEBUG).
        let pendingPeers = try await store.fetchPendingOrganizeMembers(limit: 40)
        let seed = OrganizationBatchPlanner.Member(
            id: screenshotID,
            createdAt: shot.createdAt,
            ocrNormalized: OrganizationOCRNormalizer.normalize(shot.ocrText)
        )
        let peerMembers = pendingPeers.map {
            OrganizationBatchPlanner.Member(
                id: $0.id,
                createdAt: $0.createdAt,
                ocrNormalized: OrganizationOCRNormalizer.normalize($0.ocrText)
            )
        }
        let batchIDs = OrganizationBatchPlanner.cluster(
            around: seed,
            candidates: peerMembers,
            maxSize: policy.maxBatchSize
        )

        let input = UnderstandingInput(
            screenshotID: screenshotID,
            ocrText: shot.ocrText,
            createdAt: shot.createdAt,
            photosLocalIdentifier: shot.photosLocalIdentifier,
            eligibleCollectionTitles: titles,
            eligibleCollectionContexts: contexts,
            allowMultimodal: allowMultimodal,
            batchMemberIDs: batchIDs,
            imageJPEGData: nil
        )

        let fingerprint = Self.fingerprint(
            ocr: OrganizationOCRNormalizer.normalize(shot.ocrText),
            createdAt: shot.createdAt,
            resolverVersion: policy.resolverVersion
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
                batchID: batchIDs.count > 1 ? batchIDs.map(\.rawValue.uuidString).sorted().joined(separator: ",") : nil
            )
            return
        }

        let understandingResult: ScreenshotUnderstanding
        do {
            understandingResult = try await understanding.understand(input)
        } catch UnderstandingError.pendingNetwork {
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
            let category = OrganizationPipelineDebugStore.trace(for: screenshotID)?.failureCategory
            let code = category?.rawValue ?? "understand_failed"
            OrganizationPipelineDebugStore.update(
                screenshotID: screenshotID,
                stage: .failed,
                detail: "Understanding failed",
                failureCategory: category ?? .malformedResponse
            )
            try await store.setOrganizeStatus(.failed, id: screenshotID, errorCode: code)
            try await store.recordOrganizationRun(
                screenshotID: screenshotID,
                status: .failure,
                decision: nil,
                understanding: nil,
                policy: policy,
                errorCode: code,
                fingerprint: fingerprint
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
            batchID: batchIDs.count > 1 ? batchIDs.map(\.rawValue.uuidString).sorted().joined(separator: ",") : nil
        )
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

    private static func fingerprint(ocr: String, createdAt: Date?, resolverVersion: Int) -> String {
        let datePart = createdAt.map { String(Int($0.timeIntervalSince1970)) } ?? ""
        return "v\(resolverVersion):\(ocr.count):\(ocr.hashValue):\(datePart)"
    }
}
