import Foundation

// MARK: - Resolver policy (tunable — not permanent schema constants)

struct ResolverPolicy: Sendable, Equatable {
    /// Minimum confidence to attach to an existing eligible Collection.
    var assignThreshold: Double
    /// Minimum confidence to mint a new Collection when no reuse candidate.
    var createThreshold: Double
    /// Never auto-add into user-created Collections (Sprint 8 locked OFF).
    var userCollectionAutoAdd: Bool
    /// Bump intentionally when resolver behavior changes; do not mass-reprocess on launch.
    var resolverVersion: Int
    /// Ceiling for contextual batches (prefer smaller natural groups).
    var maxBatchSize: Int

    static let current = ResolverPolicy(
        assignThreshold: 0.70,
        createThreshold: 0.85,
        userCollectionAutoAdd: false,
        resolverVersion: 2,
        maxBatchSize: 8
    )

    static let genericTitleDenylist: Set<String> = [
        "travel", "shopping", "work", "receipts", "receipt", "chats", "chat",
        "social", "misc", "other", "screenshots", "screenshot", "photos", "general",
        "image", "website", "miscellaneous", "hotels", "hotel", "maps", "map",
        "restaurants", "restaurant", "boarding pass", "furniture", "chair", "sofa",
        "information", "document", "documents"
    ]
}

// MARK: - Multimodal image policy (tunable)

struct MultimodalImagePolicy: Sendable, Equatable {
    var longEdge: Double
    var jpegQuality: Double

    static let current = MultimodalImagePolicy(longEdge: 1_024, jpegQuality: 0.75)
}

// MARK: - Understanding contract (structured only)

struct UnderstandingEntity: Sendable, Equatable, Codable {
    var type: String
    var value: String
    var confidence: Double
}

struct UnderstandingCandidate: Sendable, Equatable, Codable {
    var title: String
    var confidence: Double
    var reasonSignals: [String]
}

struct ProposedNewCollection: Sendable, Equatable, Codable {
    var title: String
    var emoji: String?
    var confidence: Double
}

struct EligibleCollectionContext: Sendable, Equatable, Codable {
    var title: String
    var aliases: [String]
    var keyEntities: [String]
    var keyTerms: [String]
    var visualDescriptors: [String]
    var dateRangeStart: Date?
    var dateRangeEnd: Date?
}

struct SharedBatchContext: Sendable, Equatable, Codable {
    var title: String
    var confidence: Double
    var memberLocalIDs: [String]
}

struct ScreenshotUnderstanding: Sendable, Equatable, Codable {
    var summary: String?
    var typeFacets: [String]
    var entities: [UnderstandingEntity]
    var locations: [String]
    var dates: [String]
    var visualDescriptors: [String]
    var candidateCollections: [UnderstandingCandidate]
    var proposedNewCollection: ProposedNewCollection?
    var reasonSignals: [String]
    var provider: String
    var promptVersion: String?
    var schemaVersion: String?
    var sharedContext: SharedBatchContext?
    /// Organization-normalized OCR preview (DEBUG; not Search substrate).
    var normalizedOCRPreview: String?

    enum CodingKeys: String, CodingKey {
        case summary, typeFacets, entities, locations, dates, visualDescriptors
        case candidateCollections, proposedNewCollection, reasonSignals
        case provider, promptVersion, schemaVersion, sharedContext, normalizedOCRPreview
    }

    init(
        summary: String? = nil,
        typeFacets: [String] = [],
        entities: [UnderstandingEntity] = [],
        locations: [String] = [],
        dates: [String] = [],
        visualDescriptors: [String] = [],
        candidateCollections: [UnderstandingCandidate] = [],
        proposedNewCollection: ProposedNewCollection? = nil,
        reasonSignals: [String] = [],
        provider: String,
        promptVersion: String? = nil,
        schemaVersion: String? = nil,
        sharedContext: SharedBatchContext? = nil,
        normalizedOCRPreview: String? = nil
    ) {
        self.summary = summary
        self.typeFacets = typeFacets
        self.entities = entities
        self.locations = locations
        self.dates = dates
        self.visualDescriptors = visualDescriptors
        self.candidateCollections = candidateCollections
        self.proposedNewCollection = proposedNewCollection
        self.reasonSignals = reasonSignals
        self.provider = provider
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.sharedContext = sharedContext
        self.normalizedOCRPreview = normalizedOCRPreview
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        typeFacets = try c.decodeIfPresent([String].self, forKey: .typeFacets) ?? []
        entities = try c.decodeIfPresent([UnderstandingEntity].self, forKey: .entities) ?? []
        locations = try c.decodeIfPresent([String].self, forKey: .locations) ?? []
        dates = try c.decodeIfPresent([String].self, forKey: .dates) ?? []
        visualDescriptors = try c.decodeIfPresent([String].self, forKey: .visualDescriptors) ?? []
        candidateCollections = try c.decodeIfPresent([UnderstandingCandidate].self, forKey: .candidateCollections) ?? []
        proposedNewCollection = try c.decodeIfPresent(ProposedNewCollection.self, forKey: .proposedNewCollection)
        reasonSignals = try c.decodeIfPresent([String].self, forKey: .reasonSignals) ?? []
        provider = try c.decode(String.self, forKey: .provider)
        promptVersion = try c.decodeIfPresent(String.self, forKey: .promptVersion)
        schemaVersion = try c.decodeIfPresent(String.self, forKey: .schemaVersion)
        sharedContext = try c.decodeIfPresent(SharedBatchContext.self, forKey: .sharedContext)
        normalizedOCRPreview = try c.decodeIfPresent(String.self, forKey: .normalizedOCRPreview)
    }
}

struct UnderstandingInput: Sendable {
    var screenshotID: ScreenshotMemoryID
    var ocrText: String?
    var createdAt: Date?
    var photosLocalIdentifier: String?
    var eligibleCollectionTitles: [String]
    var eligibleCollectionContexts: [EligibleCollectionContext]
    var allowMultimodal: Bool
    var batchMemberIDs: [ScreenshotMemoryID]
    var imageJPEGData: Data?
}

enum UnderstandingError: Error, Sendable {
    case unavailable
    case pendingNetwork
    case malformed
    case cancelled
}

protocol UnderstandingProviding: Sendable {
    func understand(_ input: UnderstandingInput) async throws -> ScreenshotUnderstanding
}

// MARK: - Confidence breakdown (DEBUG-visible)

struct ResolverConfidenceComponents: Sendable, Equatable, Codable {
    var provider: Double
    var profileMatch: Double
    var aliasMatch: Double
    var entityOverlap: Double
    var temporalOverlap: Double
    var textVisualAgreement: Double
    var batchCorroboration: Double
    var conflictPenalty: Double
    var final: Double
    var createCorroborated: Bool
    var notes: [String]
}

// MARK: - Resolver decision

enum ResolverDecisionKind: String, Sendable, Codable {
    case reuse
    case create
    case needsReview
    case skipped
}

struct ResolverDecision: Sendable, Equatable {
    var kind: ResolverDecisionKind
    var collectionID: ContextCollectionID?
    var title: String?
    var emoji: String?
    var confidence: Double?
    var applicableThreshold: Double?
    var reason: String
    var candidates: [UnderstandingCandidate]
    var confidenceComponents: ResolverConfidenceComponents?
    var batchID: String?
}

enum OrganizeStatus: String, Sendable, Codable {
    case idle
    case pending
    case pendingNetwork
    case ready
    case failed
    case skippedNoConsent
    case locked
}

enum OrganizationRunStatus: String, Sendable, Codable {
    case success
    case failure
    case skippedOffline
    case skippedNoConsent
    case pendingNetwork
    case skippedLocked
    case skippedFresh
}

enum OrganizationEvalLabel: String, Sendable, Codable, CaseIterable {
    case correct
    case wrongCollection
    case shouldBeNeedsReview
    case wrongCollectionName
}

struct OrganizationEvalStats: Sendable, Equatable {
    var totalEvaluated: Int
    var autoFiled: Int
    var correct: Int
    var wrongFile: Int
    var shouldBeNeedsReview: Int
    var wrongName: Int
    var needsReviewDecisions: Int
    var reuseCorrect: Int
    var createCorrect: Int

    var autoFileCoverage: Double {
        guard totalEvaluated > 0 else { return 0 }
        return Double(autoFiled) / Double(totalEvaluated)
    }

    var correctRate: Double {
        guard totalEvaluated > 0 else { return 0 }
        return Double(correct) / Double(totalEvaluated)
    }

    var wrongFileRate: Double {
        guard totalEvaluated > 0 else { return 0 }
        return Double(wrongFile) / Double(totalEvaluated)
    }

    var needsReviewRate: Double {
        guard totalEvaluated > 0 else { return 0 }
        return Double(needsReviewDecisions) / Double(totalEvaluated)
    }
}

struct OrganizationDebugSnapshot: Sendable, Identifiable, Equatable {
    var id: ScreenshotMemoryID
    var titleHint: String
    var previewSymbol: String?
    var photosLocalIdentifier: String?
    var ocrAvailable: Bool
    var ocrPreview: String?
    var normalizedOCRPreview: String?
    var organizeStatus: OrganizeStatus
    var resolverVersion: Int?
    var locked: Bool
    var decisionKind: ResolverDecisionKind?
    var decisionTitle: String?
    var decisionCollectionID: ContextCollectionID?
    var maxConfidence: Double?
    var assignThreshold: Double?
    var createThreshold: Double?
    var reason: String?
    var candidates: [UnderstandingCandidate]
    var memberships: [(title: String, source: String)]
    var lastError: String?
    var provider: String?
    var typeFacets: [String]
    var entities: [UnderstandingEntity]
    var visualDescriptors: [String]
    var confidenceComponents: ResolverConfidenceComponents?
    var batchID: String?
    var batchMemberCount: Int?
    var profilesConsidered: [String]
    var proposedEmoji: String?
    var evalLabel: OrganizationEvalLabel?
    var promptVersion: String?
    var schemaVersion: String?
}

extension OrganizationDebugSnapshot {
    static func == (lhs: OrganizationDebugSnapshot, rhs: OrganizationDebugSnapshot) -> Bool {
        lhs.id == rhs.id
            && lhs.organizeStatus == rhs.organizeStatus
            && lhs.decisionKind == rhs.decisionKind
            && lhs.maxConfidence == rhs.maxConfidence
            && lhs.evalLabel == rhs.evalLabel
    }
}
