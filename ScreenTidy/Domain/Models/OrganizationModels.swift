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

    static let genericTitleDenylist: Set<String> = {
        var set: Set<String> = [
            "travel", "shopping", "work", "receipts", "receipt", "chats", "chat",
            "social", "misc", "other", "screenshots", "screenshot", "photos", "general",
            "image", "website", "miscellaneous", "hotels", "hotel", "maps", "map",
            "restaurants", "restaurant", "boarding pass", "furniture", "chair", "sofa",
            "information", "document", "documents", "airplanes", "airplane", "airports",
            "airport", "cars", "car", "food", "cats", "cat", "dogs", "dog", "vehicles",
            "vehicle", "buildings", "building", "landmarks", "landmark", "city", "cities"
        ]
        set.formUnion(VisionEvidencePolicy.nounDenylist)
        return set
    }()
}

/// Vision evidence policy — labels/facets never become Collection titles.
enum VisionEvidencePolicy {
    static let nounDenylist: Set<String> = [
        "indoor", "outdoor", "person", "people", "human", "man", "woman",
        "screenshot", "text", "font", "electronics", "computer", "laptop",
        "monitor", "screen", "display", "smartphone", "mobile_phone", "phone",
        "pattern", "abstract", "design", "art", "drawing", "illustration",
        "room", "floor", "wall", "ceiling", "window", "door",
        "sky", "cloud", "clouds", "nature", "plant", "tree", "grass",
        "animal", "mammal", "object", "thing", "scene", "landscape",
        "photo", "photograph", "image", "picture",
        "airplane", "aeroplane", "aircraft", "airport", "vehicle", "car", "truck", "bus",
        "train", "boat", "ship", "bicycle", "motorcycle",
        "building", "skyscraper", "bridge", "tower", "landmark", "city", "town", "street",
        "furniture", "sofa", "couch", "chair", "table", "bed", "desk", "cabinet",
        "food", "meal", "dish", "fruit", "vegetable", "drink", "beverage",
        "document", "paper", "book", "magazine", "newspaper",
        "cat", "dog", "bird", "pet", "flower", "beach", "mountain", "ocean", "sea",
        "hotel", "restaurant", "shop", "store", "market", "office", "kitchen", "bathroom",
        "travel", "vacation", "trip", "holiday"
    ]
}

/// Snapshot used by multi-signal clustering during organize.
struct OrganizationClusterMemberSnapshot: Sendable, Equatable {
    var id: ScreenshotMemoryID
    var createdAt: Date?
    var ocrText: String?
    var visualLabels: [String]
    var visualFacets: [String]
    var featurePrintData: Data?
    var photosLocalIdentifier: String?
}

/// Compact peer payload for multimodal batch understand (5–8 members).
struct UnderstandingBatchMemberPayload: Sendable, Equatable {
    var localID: String
    var ocrText: String?
    var createdAt: Date?
    var photosLocalIdentifier: String?
    var imageJPEGData: Data?
    var visualFacets: [String]
    var sourcePlatform: String?
    var contentType: String?
    var contentFamily: String?
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
    /// When count > 1, production uses POST /v1/understand-batch.
    var batchMembers: [UnderstandingBatchMemberPayload] = []
    var imageJPEGData: Data?
    /// Cached on-device Vision labels (P1) — evidence only.
    var visualLabels: [VisualLabelObservation] = []
    /// Internal facets (P1/P2) — never Collection titles.
    var visualFacets: [String] = []
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
    var evidence: [String]

    enum CodingKeys: String, CodingKey {
        case title, confidence
        case memberLocalIDs = "memberLocalIds"
        case evidence
    }

    init(
        title: String,
        confidence: Double,
        memberLocalIDs: [String],
        evidence: [String] = []
    ) {
        self.title = title
        self.confidence = confidence
        self.memberLocalIDs = memberLocalIDs
        self.evidence = evidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        confidence = try c.decode(Double.self, forKey: .confidence)
        memberLocalIDs = try c.decode([String].self, forKey: .memberLocalIDs)
        evidence = try c.decodeIfPresent([String].self, forKey: .evidence) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(memberLocalIDs, forKey: .memberLocalIDs)
        try c.encode(evidence, forKey: .evidence)
    }
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
