import Foundation
import GRDB

struct ScreenshotRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "screenshot"

    var id: String
    var photosLocalIdentifier: String?
    var createdAt: Date?
    var importedAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var width: Int?
    var height: Int?
    var analysisStatus: String
    var isRemovedFromApp: Bool
    var removedAt: Date?
    var previewSymbol: String
    var ocrText: String?
    var summary: String?
    var facetKeysJSON: String
    var entityLabelsJSON: String
    var visualLabelsJSON: String
    var semanticKeywordsJSON: String
    var source: String
    var accessState: String
    var ocrStatus: String
    var ocrVersion: Int
    var ocrLanguage: String?
    var ocrAttemptCount: Int
    var ocrClaimedAt: Date?
    var ocrLastAttemptAt: Date?
    var ocrNextRetryAt: Date?
    var ocrLastError: String?
    var organizeStatus: String
    var organizeResolverVersion: Int?
    var organizeLocked: Bool
    var organizeContentFingerprint: String?
    var aiSummary: String?

    enum CodingKeys: String, CodingKey {
        case id, photosLocalIdentifier = "photos_local_identifier", createdAt = "created_at"
        case importedAt = "imported_at", updatedAt = "updated_at", isFavorite = "is_favorite"
        case width, height, analysisStatus = "analysis_status", isRemovedFromApp = "is_removed_from_app"
        case removedAt = "removed_at", previewSymbol = "preview_symbol", ocrText = "ocr_text"
        case summary, facetKeysJSON = "facet_keys_json", entityLabelsJSON = "entity_labels_json"
        case visualLabelsJSON = "visual_labels_json", semanticKeywordsJSON = "semantic_keywords_json"
        case source, accessState = "access_state"
        case ocrStatus = "ocr_status", ocrVersion = "ocr_version", ocrLanguage = "ocr_language"
        case ocrAttemptCount = "ocr_attempt_count", ocrClaimedAt = "ocr_claimed_at"
        case ocrLastAttemptAt = "ocr_last_attempt_at", ocrNextRetryAt = "ocr_next_retry_at"
        case ocrLastError = "ocr_last_error"
        case organizeStatus = "organize_status"
        case organizeResolverVersion = "organize_resolver_version"
        case organizeLocked = "organize_locked"
        case organizeContentFingerprint = "organize_content_fingerprint"
        case aiSummary = "ai_summary"
    }

    init(memory: ScreenshotMemory, now: Date = Date()) {
        id = memory.id.rawValue.uuidString
        photosLocalIdentifier = memory.photosLocalIdentifier
        createdAt = memory.createdAt
        importedAt = now
        updatedAt = now
        isFavorite = memory.isFavorite
        width = nil
        height = nil
        analysisStatus = "ready"
        isRemovedFromApp = false
        removedAt = nil
        previewSymbol = memory.previewSymbol
        ocrText = memory.ocrText
        summary = memory.summary
        facetKeysJSON = Self.json(memory.facetKeys)
        entityLabelsJSON = Self.json(memory.entityLabels)
        visualLabelsJSON = Self.json(memory.visualLabels)
        semanticKeywordsJSON = Self.json(memory.semanticKeywords)
        source = memory.source.rawValue
        accessState = memory.accessState.rawValue
        ocrStatus = memory.ocrStatus.rawValue
        ocrVersion = memory.ocrVersion
        ocrLanguage = nil
        ocrAttemptCount = memory.ocrAttemptCount
        ocrClaimedAt = nil
        ocrLastAttemptAt = memory.ocrLastAttemptAt
        ocrNextRetryAt = nil
        ocrLastError = memory.ocrLastError
        organizeStatus = OrganizeStatus.idle.rawValue
        organizeResolverVersion = nil
        organizeLocked = false
        organizeContentFingerprint = nil
        aiSummary = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        photosLocalIdentifier = try container.decodeIfPresent(String.self, forKey: .photosLocalIdentifier)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        analysisStatus = try container.decode(String.self, forKey: .analysisStatus)
        isRemovedFromApp = try container.decode(Bool.self, forKey: .isRemovedFromApp)
        removedAt = try container.decodeIfPresent(Date.self, forKey: .removedAt)
        previewSymbol = try container.decode(String.self, forKey: .previewSymbol)
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        facetKeysJSON = try container.decode(String.self, forKey: .facetKeysJSON)
        entityLabelsJSON = try container.decode(String.self, forKey: .entityLabelsJSON)
        visualLabelsJSON = try container.decode(String.self, forKey: .visualLabelsJSON)
        semanticKeywordsJSON = try container.decode(String.self, forKey: .semanticKeywordsJSON)
        source = try container.decode(String.self, forKey: .source)
        accessState = try container.decode(String.self, forKey: .accessState)
        ocrStatus = try container.decode(String.self, forKey: .ocrStatus)
        ocrVersion = try container.decode(Int.self, forKey: .ocrVersion)
        ocrLanguage = try container.decodeIfPresent(String.self, forKey: .ocrLanguage)
        ocrAttemptCount = try container.decode(Int.self, forKey: .ocrAttemptCount)
        ocrClaimedAt = try container.decodeIfPresent(Date.self, forKey: .ocrClaimedAt)
        ocrLastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .ocrLastAttemptAt)
        ocrNextRetryAt = try container.decodeIfPresent(Date.self, forKey: .ocrNextRetryAt)
        ocrLastError = try container.decodeIfPresent(String.self, forKey: .ocrLastError)
        organizeStatus = try container.decodeIfPresent(String.self, forKey: .organizeStatus) ?? OrganizeStatus.idle.rawValue
        organizeResolverVersion = try container.decodeIfPresent(Int.self, forKey: .organizeResolverVersion)
        organizeLocked = try container.decodeIfPresent(Bool.self, forKey: .organizeLocked) ?? false
        organizeContentFingerprint = try container.decodeIfPresent(String.self, forKey: .organizeContentFingerprint)
        aiSummary = try container.decodeIfPresent(String.self, forKey: .aiSummary)
    }

    func memory() -> ScreenshotMemory? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return ScreenshotMemory(
            id: ScreenshotMemoryID(uuid),
            createdAt: createdAt,
            isFavorite: isFavorite,
            ocrText: ocrText,
            summary: summary,
            facetKeys: Self.array(facetKeysJSON),
            entityLabels: Self.array(entityLabelsJSON),
            previewSymbol: previewSymbol,
            visualLabels: Self.array(visualLabelsJSON),
            semanticKeywords: Self.array(semanticKeywordsJSON),
            photosLocalIdentifier: photosLocalIdentifier,
            source: ScreenshotSource(rawValue: source) ?? .fixture,
            accessState: ScreenshotAccessState(rawValue: accessState) ?? .available,
            ocrStatus: ScreenshotOCRStatus(rawValue: ocrStatus) ?? .completed,
            ocrVersion: ocrVersion,
            ocrAttemptCount: ocrAttemptCount,
            ocrLastAttemptAt: ocrLastAttemptAt,
            ocrLastError: ocrLastError
        )
    }
}

struct CollectionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "context_collection"

    var id: String
    var kind: String
    var title: String
    var normalizedTitle: String
    var badgeEmoji: String?
    var badgeColor: String?
    var isPinned: Bool
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var createdBy: String
    var insight: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, normalizedTitle = "normalized_title", badgeEmoji = "badge_emoji"
        case badgeColor = "badge_color"
        case isPinned = "is_pinned", isArchived = "is_archived", sortOrder = "sort_order"
        case createdAt = "created_at", updatedAt = "updated_at", createdBy = "created_by", insight
    }

    init(
        id: String,
        kind: String,
        title: String,
        normalizedTitle: String,
        badgeEmoji: String?,
        badgeColor: String?,
        isPinned: Bool,
        isArchived: Bool,
        sortOrder: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        createdBy: String,
        insight: String?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.normalizedTitle = normalizedTitle
        self.badgeEmoji = badgeEmoji
        self.badgeColor = badgeColor
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.insight = insight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        normalizedTitle = try container.decode(String.self, forKey: .normalizedTitle)
        badgeEmoji = try container.decodeIfPresent(String.self, forKey: .badgeEmoji)
        badgeColor = try container.decodeIfPresent(String.self, forKey: .badgeColor)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        insight = try container.decodeIfPresent(String.self, forKey: .insight)
    }
}

struct MembershipRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "screenshot_context"

    var screenshotID: String
    var collectionID: String
    var source: String
    var confidence: Double?
    var createdAt: Date
    var position: Int

    enum CodingKeys: String, CodingKey {
        case screenshotID = "screenshot_id", collectionID = "collection_id"
        case source, confidence, createdAt = "created_at", position
    }
}

struct DuplicateGroupRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "duplicate_group"

    var id: String
    var screenshotIDsJSON: String
    var recommendedKeepID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case screenshotIDsJSON = "screenshot_ids_json"
        case recommendedKeepID = "recommended_keep_id"
    }
}

struct AppMetaRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "app_meta"

    var key: String
    var value: String
}

extension ScreenshotRecord {
    static func json(_ values: [String]) -> String {
        (try? String(data: JSONEncoder().encode(values), encoding: .utf8)) ?? "[]"
    }

    static func array(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return values
    }
}
