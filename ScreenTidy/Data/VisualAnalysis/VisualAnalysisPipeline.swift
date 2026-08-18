import CoreGraphics
import Foundation

/// P1 visual analysis pipeline (classify + feature print). Bump versions when
/// filter/revision/settings change — stale rows requeue without mass relaunch storms.
enum VisualAnalysisPipeline {
    /// Classification filter + persistence contract version.
    static let classifyVersion = 1
    /// Feature-print encode/revision contract version.
    static let featurePrintVersion = 1

    /// Combined pipeline version used for claim/stale gates.
    static let currentVersion = 1

    static let imageLongEdge: CGFloat = 1_024
    static let maxConcurrency = 1
    /// Abandoned `processing` rows recover after this (kick/launch). Keep short so a dropped worker cannot stall for minutes.
    static let staleClaimInterval: TimeInterval = 90
    static let maxAttempts = 8

    /// Persist at most this many filtered labels.
    static let maxPersistedLabels = 8
    /// Persist top raw (pre-filter) labels for DEBUG raw-vs-filtered evaluation.
    static let maxRawPersistedLabels = 20

    /// DEBUG Visual Intelligence list page size (lightweight rows only).
    static let debugListPageSize = 40

    /// Absolute confidence floor after precision gate.
    static let confidenceFloor: Float = 0.28

    /// Apple precision/recall helper gate (conservative).
    static let minimumPrecision: Float = 0.30
    static let recallForPrecision: Float = 0.50

    /// Feature-print distance below this counts as a strong visual neighbor (DEBUG-tuned).
    static let strongNeighborDistance: Float = 0.65
    static let weakNeighborDistance: Float = 0.90

    /// OCR uses a separate long-edge (`OCRPipeline.imageLongEdge`). Visual analysis uses `imageLongEdge`.
    static var analysisInputLongEdgeNote: String {
        "Visual classify/FP long-edge \(Int(imageLongEdge)) · OCR long-edge \(Int(OCRPipeline.imageLongEdge)) (separate PhotoKit requests)"
    }

    static func neighborBand(distance: Float) -> VisualNeighborBand {
        if distance <= strongNeighborDistance { return .strong }
        if distance <= weakNeighborDistance { return .weak }
        return .far
    }

    static func retryDelay(afterAttempt attempt: Int) -> TimeInterval {
        let base: TimeInterval = 30
        let delay = base * pow(2.0, Double(max(0, attempt - 1)))
        return min(delay, 3_600)
    }
}

/// DEBUG Visual Eval copy — persisted vs live RAW/FILTERED messaging (Sprint 8.1).
enum VisualEvalDebugMessaging {
    /// When persisted RAW is empty, explain why the RAW section must not look “blank.”
    static func persistedRawEmptyExplanation(rawCount: Int, filteredCount: Int) -> String? {
        guard rawCount == 0 else { return nil }
        if filteredCount > 0 {
            return """
            RAW labels were not persisted for this analysis. \
            Run Live classify (DEBUG) to compare RAW vs FILTERED.
            """
        }
        return """
        No RAW or FILTERED labels persisted. \
        Run Live classify (DEBUG) to evaluate Vision on device.
        """
    }
}

/// Machine-readable visual failure / stage codes persisted in `visual_last_error`.
enum VisualAnalysisErrorCode {
    static let photokitTimeout = "photokit_timeout"
    static let photokitMissingAsset = "photokit_missing_asset"
    static let photokitNoCGImage = "photokit_no_cgimage"
    static let visionClassifyFailed = "vision_classify_failed"
    static let visionFeaturePrintFailed = "vision_feature_print_failed"
    static let visionPerformFailed = "vision_perform_failed"
    static let featurePrintArchiveFailed = "feature_print_archive_failed"
    static let unknown = "unknown"
    /// Legacy coarse code from Sprint 8.0 pre-remediation builds.
    static let visionFailedLegacy = "vision_failed"

    /// Bounded, sanitized note for DEBUG runtime only — never dump raw payloads into SQLite.
    static func sanitizeDebugNote(_ message: String, maxLength: Int = 96) -> String {
        let trimmed = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength))
    }
}

struct VisualAnalysisResult: Sendable, Equatable {
    var labels: [VisualLabelObservation]
    /// Top raw Vision labels before filtering (DEBUG / persistence).
    var rawLabels: [VisualLabelObservation]
    var featurePrintData: Data?
    var classifyRevision: Int
    var featurePrintRevision: Int
    var facets: [String]
    /// `generated` | `failed` | `missing`
    var featurePrintStatus: String
    /// Set when classify succeeded but feature-print did not (partial success).
    var featurePrintErrorCode: String? = nil
    /// Pixel long-edge of the CGImage analyzed (for DEBUG resolution audit).
    var analysisLongEdge: Int = 0

    init(
        labels: [VisualLabelObservation],
        rawLabels: [VisualLabelObservation] = [],
        featurePrintData: Data?,
        classifyRevision: Int,
        featurePrintRevision: Int,
        facets: [String],
        featurePrintStatus: String? = nil,
        featurePrintErrorCode: String? = nil,
        analysisLongEdge: Int = 0
    ) {
        self.labels = labels
        self.rawLabels = rawLabels
        self.featurePrintData = featurePrintData
        self.classifyRevision = classifyRevision
        self.featurePrintRevision = featurePrintRevision
        self.facets = facets
        if let featurePrintStatus {
            self.featurePrintStatus = featurePrintStatus
        } else if featurePrintData != nil {
            self.featurePrintStatus = "generated"
        } else {
            self.featurePrintStatus = "failed"
        }
        self.featurePrintErrorCode = featurePrintErrorCode
        self.analysisLongEdge = analysisLongEdge
    }
}

enum VisualAnalysisJobError: Error, Sendable {
    case photokitTimeout
    case photokitMissingAsset
    case photokitNoCGImage
    case visionClassifyFailed
    case visionFeaturePrintFailed
    case visionPerformFailed
    case featurePrintArchiveFailed
    case unsupported
    case unknown

    var persistedCode: String {
        switch self {
        case .photokitTimeout: return VisualAnalysisErrorCode.photokitTimeout
        case .photokitMissingAsset: return VisualAnalysisErrorCode.photokitMissingAsset
        case .photokitNoCGImage: return VisualAnalysisErrorCode.photokitNoCGImage
        case .visionClassifyFailed: return VisualAnalysisErrorCode.visionClassifyFailed
        case .visionFeaturePrintFailed: return VisualAnalysisErrorCode.visionFeaturePrintFailed
        case .visionPerformFailed: return VisualAnalysisErrorCode.visionPerformFailed
        case .featurePrintArchiveFailed: return VisualAnalysisErrorCode.featurePrintArchiveFailed
        case .unsupported: return "unsupported"
        case .unknown: return VisualAnalysisErrorCode.unknown
        }
    }

    /// Missing asset is terminal; timeouts / decode / Vision classify are retryable.
    var isTerminalInaccessible: Bool {
        switch self {
        case .photokitMissingAsset: return true
        default: return false
        }
    }
}

struct VisualAnalysisClaim: Sendable, Equatable {
    let id: ScreenshotMemoryID
    let photosLocalIdentifier: String
}

struct VisualAnalysisStatusCounts: Equatable, Sendable {
    var pending: Int
    var processing: Int
    var completed: Int
    var failed: Int
    var inaccessible: Int
    /// Completed classify with `feature_print_status = failed` (honest partial success).
    var completedFeaturePrintFailed: Int = 0
}

/// DEBUG breakdown of why pending rows are not claimable.
struct VisualClaimabilityBreakdown: Equatable, Sendable {
    var pendingTotal: Int
    var claimable: Int
    var missingLocalID: Int
    var removedFromApp: Int
    var inaccessibleAccess: Int
}

struct VisualFailureReasonCount: Equatable, Sendable, Identifiable {
    var id: String { code }
    var code: String
    var count: Int
}

struct VisualFailureAttemptBucket: Equatable, Sendable, Identifiable {
    var id: String { label }
    var label: String
    var count: Int
}

/// Aggregated from persisted `visual_status = failed` rows only.
struct VisualFailureSummary: Equatable, Sendable {
    var totalFailed: Int
    var byErrorCode: [VisualFailureReasonCount]
    var attemptBuckets: [VisualFailureAttemptBucket]
}

struct VisualNeighbor: Sendable, Equatable, Identifiable {
    var id: ScreenshotMemoryID { screenshotID }
    var screenshotID: ScreenshotMemoryID
    var photosLocalIdentifier: String?
    var distance: Float
    var similarity: Float
    var band: VisualNeighborBand
}

enum VisualNeighborBand: String, Sendable, Equatable {
    case strong
    case weak
    case far
}

struct VisualClusterMemberDebug: Sendable, Equatable, Identifiable {
    var id: ScreenshotMemoryID
    var photosLocalIdentifier: String?
    /// Per-member support vs rest of candidate group (DEBUG).
    var support: Double?
    var topSignals: [String: Double]
    var strongFacets: [String]
    var pruned: Bool
    var pruneReason: String?
    /// R2a: seed-pair total at admission (`nil` for seed / list-light).
    var admissionTotalScore: Double?
    var admissionSignalParts: [String: Double]
    var admissionHasContextualSupport: Bool?
    var admissionContextualFamilies: [String]
    var admissionReason: String?
    var bridgeInvolved: Bool
    var outlierValidationPassed: Bool?
    var correlatedSemanticChannels: [String]

    init(
        id: ScreenshotMemoryID,
        photosLocalIdentifier: String?,
        support: Double? = nil,
        topSignals: [String: Double] = [:],
        strongFacets: [String] = [],
        pruned: Bool = false,
        pruneReason: String? = nil,
        admissionTotalScore: Double? = nil,
        admissionSignalParts: [String: Double] = [:],
        admissionHasContextualSupport: Bool? = nil,
        admissionContextualFamilies: [String] = [],
        admissionReason: String? = nil,
        bridgeInvolved: Bool = false,
        outlierValidationPassed: Bool? = nil,
        correlatedSemanticChannels: [String] = []
    ) {
        self.id = id
        self.photosLocalIdentifier = photosLocalIdentifier
        self.support = support
        self.topSignals = topSignals
        self.strongFacets = strongFacets
        self.pruned = pruned
        self.pruneReason = pruneReason
        self.admissionTotalScore = admissionTotalScore
        self.admissionSignalParts = admissionSignalParts
        self.admissionHasContextualSupport = admissionHasContextualSupport
        self.admissionContextualFamilies = admissionContextualFamilies
        self.admissionReason = admissionReason
        self.bridgeInvolved = bridgeInvolved
        self.outlierValidationPassed = outlierValidationPassed
        self.correlatedSemanticChannels = correlatedSemanticChannels
    }
}

/// DEBUG: peer scored against seed but not in the final candidate group.
struct VisualRejectedCandidateDebug: Sendable, Equatable, Identifiable {
    var id: ScreenshotMemoryID
    var photosLocalIdentifier: String?
    var totalScore: Double
    var hasContextualSupport: Bool
    var contextualFamilies: [String]
    var signalParts: [String: Double]
    var rejectionReason: String
    var sourcePlatform: String
    var contentType: String
    var contentFamily: String
    var correlatedSemanticChannels: [String]
}

/// R2a DEBUG: one layered evidence field for Visual Eval.
struct VisualSourceFieldDebug: Sendable, Equatable {
    var value: String
    var confidence: Float
    var evidence: [String]
    var trace: [String]
}

struct VisualEmbeddedHintDebug: Sendable, Equatable, Identifiable {
    var value: String
    var kind: String
    var confidence: Float
    var evidence: [String]

    var id: String { "\(kind):\(value)" }
    var debugLabel: String { "\(value)_\(kind)" }
}

struct VisualAnalysisDebugSnapshot: Sendable, Equatable, Identifiable {
    var id: ScreenshotMemoryID
    var createdAt: Date?
    var updatedAt: Date?
    var photosLocalIdentifier: String?
    var previewSymbol: String
    var ocrText: String?
    var ocrStatus: ScreenshotOCRStatus
    var visualStatus: ScreenshotVisualStatus
    var visualVersion: Int
    var visualAttemptCount: Int
    var visualLastError: String?
    /// Persisted filtered labels.
    var labels: [VisualLabelObservation]
    /// Persisted or live raw labels (may be empty for pre-8.1 completions until refresh).
    var rawLabels: [VisualLabelObservation]
    /// Dropped from raw→filtered when a live/DEBUG explain pass is available.
    var droppedLabels: [VisualLabelFilter.DroppedLabel]
    var facets: [String]
    /// Level 2 facet evidence with confidence / strength / provenance (DEBUG).
    var facetEvidence: [FacetEvidence]
    var featurePrintPresent: Bool
    var featurePrintVersion: Int
    var featurePrintStatus: String
    var clusterID: String?
    var clusterMemberIDs: [ScreenshotMemoryID]
    var clusterMembers: [VisualClusterMemberDebug]
    var clusterCohesion: Double?
    var clusterWeakestMemberSupport: Double?
    var clusterWeakestPairSupport: Double?
    var clusterSupportedEdgeCount: Int?
    var clusterFlags: [String]
    var clusterSignalBreakdown: [String: Double]
    /// DEBUG: singleton reason (`nil` when multi-member or list-light row).
    var clusterSingletonReason: String?
    /// DEBUG: top rejected peers for physical evaluation.
    var clusterRejectedCandidates: [VisualRejectedCandidateDebug]
    /// DEBUG: peers available to the clusterer (excludes seed).
    var clusterInputPeerCount: Int
    /// 8.2B-R1 flat accessors (still set for compatibility).
    var sourcePlatform: String
    var contentType: String
    var contentFamily: String
    var sourceEvidenceConfidence: Float
    /// 8.2B-R2a layered DEBUG evidence.
    var sourcePlatformField: VisualSourceFieldDebug
    var contentTypeField: VisualSourceFieldDebug
    var contentFamilyField: VisualSourceFieldDebug
    var surfaceField: VisualSourceFieldDebug
    var embeddedHints: [VisualEmbeddedHintDebug]
    var collectionProfileTitles: [String]
    var neighbors: [VisualNeighbor]
    /// True when OCR is empty/weak (DEBUG sparse-OCR hint — not a Level 2 semantic facet).
    var isImageOnlyEvidence: Bool
    var analysisInputNote: String
}

protocol VisualAnalysisProviding: Sendable {
    func analyze(cgImage: CGImage) async throws -> VisualAnalysisResult
}

protocol VisualAnalysisScheduling: AnyObject, Sendable {
    func kick()
    func reprocess(id: ScreenshotMemoryID) async
    func reprocessAll() async
}

protocol VisualAnalysisPersisting: Sendable {
    func recoverStaleVisualClaims(olderThan: Date) async throws -> Int
    func enqueueStaleVersionVisual(currentVersion: Int) async throws -> Int
    func claimNextVisualJob(currentVersion: Int, now: Date) async throws -> VisualAnalysisClaim?
    func completeVisualSuccess(
        id: ScreenshotMemoryID,
        result: VisualAnalysisResult,
        version: Int
    ) async throws
    func completeVisualFailure(id: ScreenshotMemoryID, errorCode: String) async throws
    /// Photos asset permanently missing / denied — terminal, not retried as failed.
    func completeVisualInaccessible(id: ScreenshotMemoryID, errorCode: String) async throws
    func fetchVisualStatusCounts() async throws -> VisualAnalysisStatusCounts
    func fetchVisualClaimabilityBreakdown() async throws -> VisualClaimabilityBreakdown
    func fetchVisualFailureSummary() async throws -> VisualFailureSummary
    /// Lightweight DEBUG list page (no neighbors / cluster). `offset`/`limit` pagination.
    func fetchVisualDebugListPage(offset: Int, limit: Int) async throws -> [VisualAnalysisDebugSnapshot]
    /// Full DEBUG detail for one shot (neighbors + cluster diagnostics).
    func fetchVisualDebugDetailSnapshot(id: ScreenshotMemoryID) async throws -> VisualAnalysisDebugSnapshot?
    /// Convenience: first page of lightweight list (tests / callers that only need a small window).
    func fetchVisualDebugSnapshots(limit: Int) async throws -> [VisualAnalysisDebugSnapshot]
    /// Failed-only list for DEBUG remediation (no cluster mutation).
    func fetchVisualFailedDebugSnapshots(limit: Int) async throws -> [VisualAnalysisDebugSnapshot]
    func fetchFeaturePrintData(id: ScreenshotMemoryID) async throws -> Data?
    func requestVisualReprocess(id: ScreenshotMemoryID) async throws
    func requestVisualReprocessAll(currentVersion: Int) async throws
    /// Marks organize pending only when OCR + visual terminal states allow it.
    func tryMarkReadyForOrganize(id: ScreenshotMemoryID) async throws
}
