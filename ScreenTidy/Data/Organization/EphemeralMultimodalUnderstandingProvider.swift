import Foundation

/// Calls the ScreenTidy-owned stateless gateway. Never embeds provider API keys.
struct EphemeralMultimodalUnderstandingProvider: UnderstandingProviding {
    var baseURL: URL
    var session: URLSession
    var schemaVersion: String
    var requestTimeout: TimeInterval
    /// MVP/TestFlight shared secret — never the OpenAI API key.
    var bearerToken: String?

    init(
        baseURL: URL,
        schemaVersion: String = UnderstandingGatewayConfiguration.schemaVersion,
        requestTimeout: TimeInterval = 60,
        session: URLSession = UnderstandingGatewayURLSession.shared,
        bearerToken: String? = UnderstandingGatewayConfiguration.gatewayBearerToken
    ) {
        self.baseURL = baseURL
        self.schemaVersion = schemaVersion
        self.requestTimeout = requestTimeout
        self.session = session
        self.bearerToken = bearerToken
    }

    func understand(_ input: UnderstandingInput) async throws -> ScreenshotUnderstanding {
        if input.batchMembers.count > 1 {
            return try await understandBatch(input)
        }
        return try await understandSingle(input)
    }

    // MARK: - Single

    private func understandSingle(_ input: UnderstandingInput) async throws -> ScreenshotUnderstanding {
        let normalized = OrganizationOCRNormalizer.normalize(input.ocrText)
        let ocrEmpty = normalized.isEmpty
        if ocrEmpty, input.allowMultimodal, input.imageJPEGData == nil {
            OrganizationPipelineDebugStore.update(
                screenshotID: input.screenshotID,
                stage: .failed,
                detail: "Image required for image-only multimodal request",
                failureCategory: .malformedResponse,
                imageAttached: false,
                ocrAttached: false
            )
            throw UnderstandingError.malformed
        }

        let body = GatewayUnderstandRequest(
            correlationId: input.screenshotID.rawValue.uuidString,
            schemaVersion: schemaVersion,
            ocrNormalized: normalized.isEmpty ? nil : normalized,
            createdAt: input.createdAt.map { ISO8601DateFormatter().string(from: $0) },
            imageBase64: input.imageJPEGData?.base64EncodedString(),
            imageMimeType: input.imageJPEGData == nil ? nil : "image/jpeg",
            eligibleCollections: input.eligibleCollectionContexts.map {
                GatewayEligibleCollection(from: $0)
            },
            allowVisual: input.allowMultimodal
        )

        let data = try await postJSON(
            path: "v1/understand",
            body: body,
            screenshotID: input.screenshotID,
            imageAttached: body.imageBase64 != nil,
            ocrAttached: body.ocrNormalized != nil,
            collectionContextAttached: !body.eligibleCollections.isEmpty,
            batchContext: false
        )

        let decoded: GatewayUnderstandingResponse
        do {
            decoded = try JSONDecoder().decode(GatewayUnderstandingResponse.self, from: data)
        } catch {
            OrganizationPipelineDebugStore.update(
                screenshotID: input.screenshotID,
                stage: .failed,
                detail: "Structured understanding decode failed",
                failureCategory: .malformedResponse,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.malformed
        }

        let understanding = decoded.asScreenshotUnderstanding(
            sharedContext: nil,
            normalizedOCRPreview: OrganizationOCRNormalizer.preview(input.ocrText)
        )
        OrganizationPipelineDebugStore.update(
            screenshotID: input.screenshotID,
            stage: .structuredCandidateDecoded,
            detail: "Candidates \(understanding.candidateCollections.count); proposed=\(understanding.proposedNewCollection != nil)",
            gatewayHost: baseURL.host,
            provider: understanding.provider
        )
        return understanding
    }

    // MARK: - Batch (production MVP path)

    private func understandBatch(_ input: UnderstandingInput) async throws -> ScreenshotUnderstanding {
        let seedID = input.screenshotID.rawValue.uuidString
        let iso = ISO8601DateFormatter()
        let members = input.batchMembers.prefix(8).map { member -> GatewayBatchMemberRequest in
            let normalized = OrganizationOCRNormalizer.normalize(member.ocrText)
            return GatewayBatchMemberRequest(
                localId: member.localID,
                ocrNormalized: normalized.isEmpty ? nil : normalized,
                createdAt: member.createdAt.map { iso.string(from: $0) },
                imageBase64: member.imageJPEGData?.base64EncodedString(),
                imageMimeType: member.imageJPEGData == nil ? nil : "image/jpeg",
                visualFacets: member.visualFacets.isEmpty ? nil : member.visualFacets,
                sourcePlatform: member.sourcePlatform,
                contentType: member.contentType,
                contentFamily: member.contentFamily
            )
        }

        guard members.count > 1 else {
            return try await understandSingle(input)
        }

        let anyImage = members.contains { $0.imageBase64 != nil }
        let anyOCR = members.contains { $0.ocrNormalized != nil }
        if input.allowMultimodal, !anyOCR, !anyImage {
            OrganizationPipelineDebugStore.update(
                screenshotID: input.screenshotID,
                stage: .failed,
                detail: "Batch multimodal requires OCR or image on at least one member",
                failureCategory: .malformedResponse,
                imageAttached: false,
                ocrAttached: false
            )
            throw UnderstandingError.malformed
        }

        let body = GatewayUnderstandBatchRequest(
            correlationId: seedID,
            schemaVersion: schemaVersion,
            allowVisual: input.allowMultimodal,
            eligibleCollections: input.eligibleCollectionContexts.map {
                GatewayEligibleCollection(from: $0)
            },
            members: Array(members)
        )

        let data = try await postJSON(
            path: "v1/understand-batch",
            body: body,
            screenshotID: input.screenshotID,
            imageAttached: anyImage,
            ocrAttached: anyOCR,
            collectionContextAttached: !body.eligibleCollections.isEmpty,
            batchContext: true
        )

        let decoded: GatewayBatchUnderstandingResponse
        do {
            decoded = try JSONDecoder().decode(GatewayBatchUnderstandingResponse.self, from: data)
        } catch {
            OrganizationPipelineDebugStore.update(
                screenshotID: input.screenshotID,
                stage: .failed,
                detail: "Structured batch understanding decode failed",
                failureCategory: .malformedResponse,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.malformed
        }

        guard let seedMember = decoded.members.first(where: { $0.localId == seedID })
            ?? decoded.members.first
        else {
            OrganizationPipelineDebugStore.update(
                screenshotID: input.screenshotID,
                stage: .failed,
                detail: "Batch response missing seed member",
                failureCategory: .malformedResponse,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.malformed
        }

        let shared = decoded.sharedContextForSeed(seedID)
        let unresolved = Set(decoded.unresolvedIds ?? [])
        var understanding = seedMember.asScreenshotUnderstanding(
            sharedContext: shared,
            normalizedOCRPreview: OrganizationOCRNormalizer.preview(input.ocrText),
            provider: decoded.provider,
            promptVersion: decoded.promptVersion,
            schemaVersion: decoded.schemaVersion
        )
        if unresolved.contains(seedID) {
            understanding.sharedContext = nil
            if !understanding.reasonSignals.contains("unresolved_in_batch") {
                understanding.reasonSignals.append("unresolved_in_batch")
            }
        }
        if let evidence = shared?.evidence, !evidence.isEmpty {
            for tag in evidence where !understanding.reasonSignals.contains(tag) {
                understanding.reasonSignals.append(tag)
            }
        }

        OrganizationPipelineDebugStore.update(
            screenshotID: input.screenshotID,
            stage: .structuredCandidateDecoded,
            detail: "Batch members=\(decoded.members.count); shared=\(shared != nil); unresolved=\(unresolved.count); candidates=\(understanding.candidateCollections.count)",
            gatewayHost: baseURL.host,
            batchContext: true,
            provider: understanding.provider
        )
        return understanding
    }

    // MARK: - HTTP

    private func postJSON<Body: Encodable>(
        path: String,
        body: Body,
        screenshotID: ScreenshotMemoryID,
        imageAttached: Bool,
        ocrAttached: Bool,
        collectionContextAttached: Bool,
        batchContext: Bool
    ) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = requestTimeout
        request.httpBody = try JSONEncoder().encode(body)

        OrganizationPipelineDebugStore.update(
            screenshotID: screenshotID,
            stage: .requestStarted,
            detail: "POST /\(path) → \(baseURL.host ?? baseURL.absoluteString)",
            gatewayHost: baseURL.host,
            imageAttached: imageAttached,
            ocrAttached: ocrAttached,
            collectionContextAttached: collectionContextAttached,
            batchContext: batchContext
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let category = OrganizationNetworkFailureCategory.classify(error)
            OrganizationPipelineDebugStore.update(
                screenshotID: screenshotID,
                stage: .failed,
                detail: "URLSession failed before HTTP response",
                failureCategory: category,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.pendingNetwork
        }

        OrganizationPipelineDebugStore.update(
            screenshotID: screenshotID,
            stage: .gatewayReached,
            detail: "HTTP response received",
            gatewayHost: baseURL.host
        )

        guard let http = response as? HTTPURLResponse else {
            OrganizationPipelineDebugStore.update(
                screenshotID: screenshotID,
                stage: .failed,
                detail: "Non-HTTP response",
                failureCategory: .unknownNetwork,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.pendingNetwork
        }
        if http.statusCode == 401 {
            OrganizationPipelineDebugStore.update(
                screenshotID: screenshotID,
                stage: .failed,
                detail: "Gateway rejected bearer token (401)",
                failureCategory: .gatewayHTTP,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.malformed
        }
        if http.statusCode == 408 || http.statusCode == 429 || (500...599).contains(http.statusCode) {
            let category: OrganizationNetworkFailureCategory =
                (500...599).contains(http.statusCode) ? .providerError : .gatewayHTTP
            OrganizationPipelineDebugStore.update(
                screenshotID: screenshotID,
                stage: .failed,
                detail: "Gateway HTTP \(http.statusCode) (retryable)",
                failureCategory: category,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.pendingNetwork
        }
        guard (200...299).contains(http.statusCode) else {
            OrganizationPipelineDebugStore.update(
                screenshotID: screenshotID,
                stage: .failed,
                detail: "Gateway HTTP \(http.statusCode)",
                failureCategory: .gatewayHTTP,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.malformed
        }

        OrganizationPipelineDebugStore.update(
            screenshotID: screenshotID,
            stage: .providerResponseReceived,
            detail: "Gateway returned \(http.statusCode)",
            gatewayHost: baseURL.host
        )
        return data
    }
}

// MARK: - Wire models (gateway JSON)

private struct GatewayUnderstandRequest: Encodable {
    var correlationId: String
    var schemaVersion: String?
    var ocrNormalized: String?
    var createdAt: String?
    var imageBase64: String?
    var imageMimeType: String?
    var eligibleCollections: [GatewayEligibleCollection]
    var allowVisual: Bool
}

private struct GatewayUnderstandBatchRequest: Encodable {
    var correlationId: String
    var schemaVersion: String?
    var allowVisual: Bool
    var eligibleCollections: [GatewayEligibleCollection]
    var members: [GatewayBatchMemberRequest]
}

private struct GatewayBatchMemberRequest: Encodable {
    var localId: String
    var ocrNormalized: String?
    var createdAt: String?
    var imageBase64: String?
    var imageMimeType: String?
    var visualFacets: [String]?
    var sourcePlatform: String?
    var contentType: String?
    var contentFamily: String?
}

private struct GatewayEligibleCollection: Encodable {
    var title: String
    var aliases: [String]?
    var keyEntities: [String]?
    var keyTerms: [String]?
    var visualDescriptors: [String]?
    var dateRangeStart: String?
    var dateRangeEnd: String?

    init(from context: EligibleCollectionContext) {
        let iso = ISO8601DateFormatter()
        title = context.title
        aliases = context.aliases.isEmpty ? nil : context.aliases
        keyEntities = context.keyEntities.isEmpty ? nil : context.keyEntities
        keyTerms = context.keyTerms.isEmpty ? nil : context.keyTerms
        visualDescriptors = context.visualDescriptors.isEmpty ? nil : context.visualDescriptors
        dateRangeStart = context.dateRangeStart.map { iso.string(from: $0) }
        dateRangeEnd = context.dateRangeEnd.map { iso.string(from: $0) }
    }
}

private struct GatewayUnderstandingResponse: Decodable {
    var summary: String?
    var typeFacets: [String]?
    var entities: [UnderstandingEntity]?
    var locations: [String]?
    var dates: [String]?
    var visualDescriptors: [String]?
    var candidateCollections: [UnderstandingCandidate]?
    var proposedNewCollection: GatewayProposed?
    var reasonSignals: [String]?
    var provider: String
    var promptVersion: String?
    var schemaVersion: String?

    struct GatewayProposed: Decodable {
        var title: String
        var emoji: String?
        var confidence: Double
    }

    func asScreenshotUnderstanding(
        sharedContext: SharedBatchContext?,
        normalizedOCRPreview: String?
    ) -> ScreenshotUnderstanding {
        let proposed: ProposedNewCollection?
        if let proposedNewCollection {
            proposed = ProposedNewCollection(
                title: proposedNewCollection.title,
                emoji: proposedNewCollection.emoji.flatMap { $0.isEmpty ? nil : $0 },
                confidence: proposedNewCollection.confidence
            )
        } else {
            proposed = nil
        }
        return ScreenshotUnderstanding(
            summary: summary,
            typeFacets: typeFacets ?? [],
            entities: entities ?? [],
            locations: locations ?? [],
            dates: dates ?? [],
            visualDescriptors: visualDescriptors ?? [],
            candidateCollections: candidateCollections ?? [],
            proposedNewCollection: proposed,
            reasonSignals: reasonSignals ?? [],
            provider: provider,
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
            sharedContext: sharedContext,
            normalizedOCRPreview: normalizedOCRPreview
        )
    }
}

private struct GatewayBatchUnderstandingResponse: Decodable {
    var members: [GatewayBatchMemberResponse]
    var sharedContext: GatewaySharedContext?
    var unresolvedIds: [String]?
    var provider: String
    var promptVersion: String?
    var schemaVersion: String?

    func sharedContextForSeed(_ seedID: String) -> SharedBatchContext? {
        guard let sharedContext else { return nil }
        guard sharedContext.memberLocalIds.contains(seedID) else { return nil }
        return SharedBatchContext(
            title: sharedContext.title,
            confidence: sharedContext.confidence,
            memberLocalIDs: sharedContext.memberLocalIds,
            evidence: sharedContext.evidence ?? []
        )
    }
}

private struct GatewaySharedContext: Decodable {
    var title: String
    var confidence: Double
    var memberLocalIds: [String]
    var evidence: [String]?
}

private struct GatewayBatchMemberResponse: Decodable {
    var localId: String
    var summary: String?
    var typeFacets: [String]?
    var entities: [UnderstandingEntity]?
    var locations: [String]?
    var dates: [String]?
    var visualDescriptors: [String]?
    var candidateCollections: [UnderstandingCandidate]?
    var proposedNewCollection: GatewayUnderstandingResponse.GatewayProposed?
    var reasonSignals: [String]?

    func asScreenshotUnderstanding(
        sharedContext: SharedBatchContext?,
        normalizedOCRPreview: String?,
        provider: String,
        promptVersion: String?,
        schemaVersion: String?
    ) -> ScreenshotUnderstanding {
        let proposed: ProposedNewCollection?
        if let proposedNewCollection {
            proposed = ProposedNewCollection(
                title: proposedNewCollection.title,
                emoji: proposedNewCollection.emoji.flatMap { $0.isEmpty ? nil : $0 },
                confidence: proposedNewCollection.confidence
            )
        } else {
            proposed = nil
        }
        return ScreenshotUnderstanding(
            summary: summary,
            typeFacets: typeFacets ?? [],
            entities: entities ?? [],
            locations: locations ?? [],
            dates: dates ?? [],
            visualDescriptors: visualDescriptors ?? [],
            candidateCollections: candidateCollections ?? [],
            proposedNewCollection: proposed,
            reasonSignals: reasonSignals ?? [],
            provider: provider,
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
            sharedContext: sharedContext,
            normalizedOCRPreview: normalizedOCRPreview
        )
    }
}
