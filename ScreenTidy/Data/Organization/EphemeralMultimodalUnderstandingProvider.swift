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

        let url = baseURL.appendingPathComponent("v1/understand")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = requestTimeout
        request.httpBody = try JSONEncoder().encode(body)

        OrganizationPipelineDebugStore.update(
            screenshotID: input.screenshotID,
            stage: .requestStarted,
            detail: "POST /v1/understand → \(baseURL.host ?? baseURL.absoluteString)",
            gatewayHost: baseURL.host,
            imageAttached: body.imageBase64 != nil,
            ocrAttached: body.ocrNormalized != nil,
            collectionContextAttached: !body.eligibleCollections.isEmpty,
            batchContext: input.batchMemberIDs.count > 1
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let category = OrganizationNetworkFailureCategory.classify(error)
            OrganizationPipelineDebugStore.update(
                screenshotID: input.screenshotID,
                stage: .failed,
                detail: "URLSession failed before HTTP response",
                failureCategory: category,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.pendingNetwork
        }

        OrganizationPipelineDebugStore.update(
            screenshotID: input.screenshotID,
            stage: .gatewayReached,
            detail: "HTTP response received",
            gatewayHost: baseURL.host
        )

        guard let http = response as? HTTPURLResponse else {
            OrganizationPipelineDebugStore.update(
                screenshotID: input.screenshotID,
                stage: .failed,
                detail: "Non-HTTP response",
                failureCategory: .unknownNetwork,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.pendingNetwork
        }
        if http.statusCode == 401 {
            OrganizationPipelineDebugStore.update(
                screenshotID: input.screenshotID,
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
                screenshotID: input.screenshotID,
                stage: .failed,
                detail: "Gateway HTTP \(http.statusCode) (retryable)",
                failureCategory: category,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.pendingNetwork
        }
        guard (200...299).contains(http.statusCode) else {
            OrganizationPipelineDebugStore.update(
                screenshotID: input.screenshotID,
                stage: .failed,
                detail: "Gateway HTTP \(http.statusCode)",
                failureCategory: .gatewayHTTP,
                gatewayHost: baseURL.host
            )
            throw UnderstandingError.malformed
        }

        OrganizationPipelineDebugStore.update(
            screenshotID: input.screenshotID,
            stage: .providerResponseReceived,
            detail: "Gateway returned \(http.statusCode)",
            gatewayHost: baseURL.host
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

    func asScreenshotUnderstanding(normalizedOCRPreview: String?) -> ScreenshotUnderstanding {
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
            sharedContext: nil,
            normalizedOCRPreview: normalizedOCRPreview
        )
    }
}
