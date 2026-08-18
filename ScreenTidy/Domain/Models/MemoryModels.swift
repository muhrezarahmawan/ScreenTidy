import Foundation

/// Typed identifiers keep Domain free of UIKit/Photos types.
struct ScreenshotMemoryID: Hashable, Codable, Sendable, Identifiable {
    let rawValue: UUID
    var id: UUID { rawValue }

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct ContextCollectionID: Hashable, Codable, Sendable, Identifiable {
    let rawValue: UUID
    var id: UUID { rawValue }

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

enum ContextCollectionKind: String, Codable, Sendable {
    case aiContext
    case userContext
    case unassigned
}

enum ScreenshotSource: String, Codable, Sendable {
    case fixture
    case photos
}

enum ScreenshotAccessState: String, Codable, Sendable {
    case available
    case inaccessible
}

/// Explicit OCR pipeline state (Sprint 5). Independent of Collection organization.
enum ScreenshotOCRStatus: String, Codable, Sendable {
    case pending
    case processing
    case completed
    case failed
    case inaccessible
}

/// Vision classification + feature-print pipeline state (P1).
enum ScreenshotVisualStatus: String, Codable, Sendable {
    case pending
    case processing
    case completed
    case failed
    case inaccessible
}

/// Filtered Apple Vision classification — evidence only, never a Collection title.
struct VisualLabelObservation: Codable, Sendable, Equatable, Hashable {
    var identifier: String
    var confidence: Float
}

/// PhotoKit metadata kept locally; never contains image bytes.
struct PhotoAssetMetadata: Hashable, Sendable {
    let localIdentifier: String
    let createdAt: Date?
    let width: Int
    let height: Int
}

/// A Photos-backed memory (metadata only in later sprints).
struct ScreenshotMemory: Identifiable, Hashable, Sendable {
    let id: ScreenshotMemoryID
    var createdAt: Date?
    var isFavorite: Bool
    /// Raw extracted OCR text (may be empty string when completed with no text).
    var ocrText: String?
    var summary: String?
    var facetKeys: [String]
    var entityLabels: [String]
    /// Placeholder asset name or color token for mocks/previews.
    var previewSymbol: String
    /// Identifier-only visual labels for search / lightweight consumers.
    var visualLabels: [String] = []
    /// Filtered Vision classifications with confidence (P1).
    var visualLabelObservations: [VisualLabelObservation] = []
    /// Internal facets (boarding_pass, map, …) — never Collection titles.
    /// Strong Level 2 identifiers for consumers / clustering (Sprint 8.2A).
    var visualFacets: [String] = []
    /// Full Level 2 facet evidence (strong + weak) for DEBUG / provenance.
    var visualFacetEvidence: [FacetEvidence] = []
    /// Internal semantic / organization keywords — Sprint 2 mock search; not shown in UI.
    var semanticKeywords: [String] = []
    /// Stable Photos identity when this record originated in PhotoKit.
    var photosLocalIdentifier: String? = nil
    var source: ScreenshotSource = .fixture
    var accessState: ScreenshotAccessState = .available
    var ocrStatus: ScreenshotOCRStatus = .completed
    var ocrVersion: Int = 0
    var ocrAttemptCount: Int = 0
    var ocrLastAttemptAt: Date? = nil
    var ocrLastError: String? = nil
    var visualStatus: ScreenshotVisualStatus = .completed
    var visualVersion: Int = 0
    var visualAttemptCount: Int = 0
    var visualLastAttemptAt: Date? = nil
    var visualLastError: String? = nil
    var featurePrintStatus: String = "missing"
    var featurePrintVersion: Int = 0
    var candidateClusterID: String? = nil
    var candidateClusterCohesion: Double? = nil
}

/// Primary Home unit — living context (not a type folder).
struct ContextCollection: Identifiable, Hashable, Sendable {
    let id: ContextCollectionID
    var kind: ContextCollectionKind
    var title: String
    var isPinned: Bool
    var isArchived: Bool
    /// Home grid order (lower = earlier). User drag-reorder updates this.
    var sortOrder: Int = 0
    var memberCount: Int
    /// Up to 3 `MockShotKind` raw values for peek previews (Photos thumbs later).
    var memberPreviewSymbols: [String]
    /// Up to three available PhotoKit identifiers for real peeks.
    var memberPreviewLocalIdentifiers: [String] = []
    /// AI context hint — single emoji only (e.g. "✈️"). Nil for Needs Review (`kind = unassigned`).
    var badgeEmoji: String?
    /// Hex background for the badge circle (e.g. "#E8D9C8"). Nil uses design-system default.
    var badgeColor: String? = nil
    var insight: String?
}

struct CleanupSuggestion: Identifiable, Hashable, Sendable {
    enum Category: String, Sendable {
        case duplicate
        case old
    }

    let id: UUID
    var screenshotID: ScreenshotMemoryID
    var category: Category
    var reason: String
}

// MARK: - Cleanup MVP (Duplicates + Old only)

/// Home summary for Cleanup tab — MVP exposes only Duplicates + Old Screenshots.
struct CleanupOverview: Hashable, Sendable {
    var duplicateScreenshotCount: Int
    var duplicateGroupCount: Int
    var oldScreenshotCount: Int
    /// Months threshold for Old Screenshots (UI shows 6 for now; configurable later).
    var oldThresholdMonths: Int
}

/// A set of visually duplicate screenshots. `recommendedKeepID` reserved for later “keep one” UX.
struct DuplicateGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    var screenshotIDs: [ScreenshotMemoryID]
    var recommendedKeepID: ScreenshotMemoryID?

    var count: Int { screenshotIDs.count }
}

// MARK: - Mock undo

/// Opaque handle for a reversible **metadata** mutation.
///
/// Sprint 3: restores a SQLite snapshot (not PhotoKit). Production PhotoKit deletes must **not**
/// expose Undo unless ScreenTidy can reliably restore those Photos assets.
struct MockUndoToken: Equatable, Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

// MARK: - Search

/// Internal match channels. Never exposed as UI chrome on results.
enum SearchSignal: String, Hashable, Sendable, CaseIterable {
    case ocr
    case visual
    case collection
    case semantic
    case date
}

/// One ranked screenshot hit from unified search.
struct SearchHit: Identifiable, Hashable, Sendable {
    var id: ScreenshotMemoryID { screenshot.id }
    let screenshot: ScreenshotMemory
    let relevanceScore: Double
    let matchedSignals: Set<SearchSignal>
}

/// Combined search payload — Collections (strong name matches) + ranked screenshots.
struct SearchResponse: Equatable, Sendable {
    var collections: [ContextCollection]
    var hits: [SearchHit]

    static let empty = SearchResponse(collections: [], hits: [])

    var isEmpty: Bool { collections.isEmpty && hits.isEmpty }
    var screenshotIDs: [ScreenshotMemoryID] { hits.map(\.screenshot.id) }
}
