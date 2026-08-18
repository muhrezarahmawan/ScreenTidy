import Foundation
import GRDB

actor GRDBMemoryRepository: MemoryRepository, ScreenshotIngesting, SearchProviding, CleanupProviding, Organizing, PhotoLibraryPersisting, OCRPersisting, VisualAnalysisPersisting {
    let database: AppDatabase
    private let oldThresholdMonths = 6
    private var pendingUndo: (MockUndoToken, String)?

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchPromotedContexts() async throws -> [ContextCollection] {
        try await contexts(where: "kind != 'unassigned' AND is_archived = 0")
            .filter { $0.isPinned || $0.kind == .userContext || $0.memberCount >= 3 }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    func fetchUnassignedCount() async throws -> Int {
        try await fetchUnassignedContext()?.memberCount ?? 0
    }

    func fetchUnassignedContext() async throws -> ContextCollection? {
        try await contexts(where: "kind = 'unassigned'").first
    }

    func fetchRecentScreenshots(limit: Int) async throws -> [ScreenshotMemory] {
        try await database.dbPool.read { db in
            try ScreenshotRecord
                .filter(Column("is_removed_from_app") == false && Column("access_state") == "available")
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
                .compactMap { $0.memory() }
        }
    }

    func fetchScreenshot(id: ScreenshotMemoryID) async throws -> ScreenshotMemory? {
        try await database.dbPool.read { db in
            try ScreenshotRecord.fetchOne(db, key: id.rawValue.uuidString)?.memory()
        }
    }

    func fetchContext(id: ContextCollectionID) async throws -> ContextCollection? {
        try await contexts(where: "id = ?", arguments: [id.rawValue.uuidString]).first
    }

    func fetchScreenshots(in contextID: ContextCollectionID) async throws -> [ScreenshotMemory] {
        try await fetchScreenshots(in: contextID, limit: Int.max, offset: 0)
    }

    func fetchScreenshots(in contextID: ContextCollectionID, limit: Int, offset: Int) async throws -> [ScreenshotMemory] {
        guard limit > 0, offset >= 0 else { return [] }
        return try await database.dbPool.read { db in
            try ScreenshotRecord.fetchAll(
                db,
                sql: """
                    SELECT screenshot.* FROM screenshot
                    JOIN screenshot_context ON screenshot_context.screenshot_id = screenshot.id
                    WHERE screenshot_context.collection_id = ?
                      AND screenshot.is_removed_from_app = 0
                      AND screenshot.access_state = 'available'
                    ORDER BY screenshot.created_at DESC, screenshot.imported_at DESC, screenshot.id DESC
                    LIMIT ? OFFSET ?
                    """,
                arguments: [contextID.rawValue.uuidString, limit, offset]
            ).compactMap { $0.memory() }
        }
    }

    func fetchContextsForPicker(excluding excludedID: ContextCollectionID?) async throws -> [ContextCollection] {
        try await contexts(where: "is_archived = 0")
            .filter { $0.id != excludedID }
            .sorted {
                if ($0.kind == .unassigned) != ($1.kind == .unassigned) {
                    return $0.kind != .unassigned
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    func fetchContextsForAddPicker(
        screenshotIDs: Set<ScreenshotMemoryID>,
        excluding excludedID: ContextCollectionID?
    ) async throws -> [ContextCollection] {
        let alreadyInAll = try await collectionsContainingAll(ids: screenshotIDs)
        return try await contexts(where: "is_archived = 0 AND kind != 'unassigned'")
            .filter { $0.id != excludedID }
            .filter { !alreadyInAll.contains($0.id) }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    /// Collections that already contain every selected screenshot (not useful Add targets).
    func collectionsContainingAll(ids: Set<ScreenshotMemoryID>) async throws -> Set<ContextCollectionID> {
        guard !ids.isEmpty else { return [] }
        let strings = ids.map { $0.rawValue.uuidString }
        let placeholders = strings.map { _ in "?" }.joined(separator: ",")
        return try await database.dbPool.read { db in
            var arguments = StatementArguments(strings)
            arguments += [strings.count]
            let rows = try Row.fetchAll(db, sql: """
                SELECT collection_id, COUNT(DISTINCT screenshot_id) AS hit_count
                FROM screenshot_context
                WHERE screenshot_id IN (\(placeholders))
                GROUP BY collection_id
                HAVING hit_count = ?
                """, arguments: arguments)
            return Set(rows.compactMap { row -> ContextCollectionID? in
                guard let raw: String = row["collection_id"], let uuid = UUID(uuidString: raw) else { return nil }
                return ContextCollectionID(uuid)
            })
        }
    }

    func createContext(title: String, badgeEmoji: String?, badgeColor: String?) async throws -> ContextCollection {
        pendingUndo = nil
        let title = try Self.validatedTitle(title)
        let emoji = badgeEmoji.flatMap { $0.isEmpty ? nil : $0 }
        let color = badgeColor.flatMap { $0.isEmpty ? nil : $0 }
        let normalized = CollectionResolver.normalizeTitle(title)

        if let existing = try await database.dbPool.read({ db -> ContextCollection? in
            guard let record = try CollectionRecord.fetchOne(
                db,
                sql: """
                    SELECT * FROM context_collection
                    WHERE kind != 'unassigned'
                      AND normalized_title = ?
                    ORDER BY created_at ASC, id ASC
                    LIMIT 1
                    """,
                arguments: [normalized]
            ),
            let uuid = UUID(uuidString: record.id)
            else { return nil }
            return try Self.makeContextCollection(from: record, id: ContextCollectionID(uuid), db: db)
        }) {
            return existing
        }

        let id = ContextCollectionID()
        let now = Date()
        let sortOrder = try await database.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM context_collection"
            ) ?? 0
        }
        let record = CollectionRecord(
            id: id.rawValue.uuidString,
            kind: ContextCollectionKind.userContext.rawValue,
            title: title,
            normalizedTitle: normalized,
            badgeEmoji: emoji,
            badgeColor: color,
            isPinned: false,
            isArchived: false,
            sortOrder: sortOrder,
            createdAt: now,
            updatedAt: now,
            createdBy: "user",
            insight: nil
        )
        do {
            try await database.dbPool.write { db in try record.insert(db) }
        } catch {
            if let raced = try await database.dbPool.read({ db -> ContextCollection? in
                guard let record = try CollectionRecord.fetchOne(
                    db,
                    sql: """
                        SELECT * FROM context_collection
                        WHERE kind != 'unassigned'
                          AND normalized_title = ?
                        ORDER BY created_at ASC, id ASC
                        LIMIT 1
                        """,
                    arguments: [normalized]
                ),
                let uuid = UUID(uuidString: record.id)
                else { return nil }
                return try Self.makeContextCollection(from: record, id: ContextCollectionID(uuid), db: db)
            }) {
                return raced
            }
            throw error
        }
        if let color {
            try await database.dbPool.write { db in
                try db.execute(
                    sql: "UPDATE context_collection SET badge_color = ? WHERE id = ?",
                    arguments: [color, id.rawValue.uuidString]
                )
            }
        }
        return ContextCollection(
            id: id,
            kind: .userContext,
            title: title,
            isPinned: false,
            isArchived: false,
            sortOrder: sortOrder,
            memberCount: 0,
            memberPreviewSymbols: [],
            badgeEmoji: emoji,
            badgeColor: color,
            insight: nil
        )
    }

    func reorderContexts(orderedIDs: [ContextCollectionID]) async throws {
        pendingUndo = nil
        guard !orderedIDs.isEmpty else { return }
        let now = Date()
        try await database.dbPool.write { db in
            for (index, id) in orderedIDs.enumerated() {
                try db.execute(
                    sql: """
                        UPDATE context_collection
                        SET sort_order = ?, updated_at = ?
                        WHERE id = ? AND kind != 'unassigned'
                        """,
                    arguments: [index, now, id.rawValue.uuidString]
                )
            }
        }
    }

    func remapPhotosLocalIdentifiers(_ mapping: [String: String]) async throws {
        guard !mapping.isEmpty else { return }
        try await database.dbPool.write { db in
            for (previous, next) in mapping {
                guard previous != next, !previous.isEmpty, !next.isEmpty else { continue }
                try db.execute(
                    sql: """
                        UPDATE screenshot
                        SET photos_local_identifier = ?
                        WHERE photos_local_identifier = ?
                        """,
                    arguments: [next, previous]
                )
            }
        }
    }

    func updateContext(id: ContextCollectionID, title: String?, badgeEmoji: String?, badgeColor: String?) async throws {
        pendingUndo = nil
        try await database.dbPool.write { db in
            guard var record = try CollectionRecord.fetchOne(db, key: id.rawValue.uuidString) else {
                throw AppError.underlying(message: "Collection not found")
            }
            guard record.kind != ContextCollectionKind.unassigned.rawValue else {
                throw AppError.underlying(message: "Needs Review can’t be renamed")
            }
            if let title {
                let validated = try Self.validatedTitle(title)
                let normalized = CollectionResolver.normalizeTitle(validated)
                let clash = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM context_collection
                        WHERE kind != 'unassigned'
                          AND normalized_title = ?
                          AND id != ?
                        """,
                    arguments: [normalized, id.rawValue.uuidString]
                ) ?? 0
                if clash > 0 {
                    throw AppError.underlying(message: "A Collection named “\(validated)” already exists")
                }
                record.title = validated
                record.normalizedTitle = normalized
            }
            if let badgeEmoji {
                record.badgeEmoji = badgeEmoji.isEmpty ? nil : badgeEmoji
            }
            if let badgeColor {
                record.badgeColor = badgeColor.isEmpty ? nil : badgeColor
            }
            record.updatedAt = Date()
            try record.update(db)
            // Explicit write so badge color can’t be dropped by encode edge cases.
            if let badgeColor {
                try db.execute(
                    sql: "UPDATE context_collection SET badge_color = ? WHERE id = ?",
                    arguments: [badgeColor.isEmpty ? nil : badgeColor, id.rawValue.uuidString]
                )
            }
        }
    }

    func deleteContext(id: ContextCollectionID, deleteScreenshots: Bool) async throws -> MockUndoToken {
        let existing = try await database.dbPool.read { db in
            try CollectionRecord.fetchOne(db, key: id.rawValue.uuidString)
        }
        guard let existing else { return MockUndoToken() }
        guard existing.kind != ContextCollectionKind.unassigned.rawValue else {
            throw AppError.underlying(message: "Needs Review can’t be deleted")
        }

        let token = try await beginUndoableMutation()
        try await database.dbPool.write { db in
            guard let context = try CollectionRecord.fetchOne(db, key: id.rawValue.uuidString) else { return }
            let ids = try String.fetchAll(
                db,
                sql: "SELECT screenshot_id FROM screenshot_context WHERE collection_id = ?",
                arguments: [context.id]
            )
            if deleteScreenshots {
                try Self.removeScreenshots(ids, db: db)
            } else if let inbox = try CollectionRecord.fetchOne(
                db,
                sql: "SELECT * FROM context_collection WHERE kind = 'unassigned'"
            ) {
                let base = try Int.fetchOne(
                    db,
                    sql: "SELECT COALESCE(MAX(position), -1) FROM screenshot_context WHERE collection_id = ?",
                    arguments: [inbox.id]
                ) ?? -1
                for (offset, shotID) in ids.enumerated() {
                    let elsewhere = try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM screenshot_context
                        WHERE screenshot_id = ? AND collection_id NOT IN (?, ?)
                        """, arguments: [shotID, context.id, inbox.id]) ?? 0
                    if elsewhere == 0 {
                        try db.execute(sql: """
                            INSERT OR IGNORE INTO screenshot_context
                            (screenshot_id, collection_id, source, created_at, position)
                            VALUES (?, ?, 'user', ?, ?)
                            """, arguments: [shotID, inbox.id, Date(), base + 1 + offset])
                    }
                }
            }
            try context.delete(db)
        }
        return token
    }

    func moveScreenshots(ids: Set<ScreenshotMemoryID>, to destinationID: ContextCollectionID) async throws -> MockUndoToken {
        try await database.dbPool.read { db in
            guard try CollectionRecord.fetchOne(db, key: destinationID.rawValue.uuidString) != nil else {
                throw AppError.underlying(message: "Destination not found")
            }
        }
        let token = try await beginUndoableMutation()
        let strings = Array(ids).map { $0.rawValue.uuidString }
        guard !strings.isEmpty else { return token }
        try await database.dbPool.write { db in
            let dest = destinationID.rawValue.uuidString
            for id in strings {
                try db.execute(sql: "DELETE FROM screenshot_context WHERE screenshot_id = ?", arguments: [id])
            }
            let base = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(position), -1) FROM screenshot_context WHERE collection_id = ?",
                arguments: [dest]
            ) ?? -1
            for (offset, id) in strings.enumerated() {
                try db.execute(sql: """
                    INSERT INTO screenshot_context (screenshot_id, collection_id, source, created_at, position)
                    VALUES (?, ?, 'user', ?, ?)
                    """, arguments: [id, dest, Date(), base + 1 + offset])
            }
            try Self.applyNeedsReviewInvariant(forScreenshotIDs: strings, db: db)
            try Self.lockOrganization(ids: strings, db: db)
        }
        return token
    }

    func addScreenshots(ids: Set<ScreenshotMemoryID>, to destinationID: ContextCollectionID) async throws -> MockUndoToken {
        let destKind: String = try await database.dbPool.read { db in
            guard let record = try CollectionRecord.fetchOne(db, key: destinationID.rawValue.uuidString) else {
                throw AppError.underlying(message: "Destination not found")
            }
            return record.kind
        }
        guard destKind != ContextCollectionKind.unassigned.rawValue else {
            throw AppError.underlying(message: "Use Move to send screenshots to Needs Review")
        }
        let token = try await beginUndoableMutation()
        let strings = Array(ids).map { $0.rawValue.uuidString }
        guard !strings.isEmpty else { return token }
        try await database.dbPool.write { db in
            let dest = destinationID.rawValue.uuidString
            let base = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(position), -1) FROM screenshot_context WHERE collection_id = ?",
                arguments: [dest]
            ) ?? -1
            var nextPosition = base + 1
            for id in strings {
                let exists = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM screenshot_context
                        WHERE screenshot_id = ? AND collection_id = ?
                        """,
                    arguments: [id, dest]
                ) ?? 0
                if exists == 0 {
                    try db.execute(sql: """
                        INSERT INTO screenshot_context (screenshot_id, collection_id, source, created_at, position)
                        VALUES (?, ?, 'user', ?, ?)
                        """, arguments: [id, dest, Date(), nextPosition])
                    nextPosition += 1
                } else {
                    try db.execute(sql: """
                        UPDATE screenshot_context SET source = 'user'
                        WHERE screenshot_id = ? AND collection_id = ?
                        """, arguments: [id, dest])
                }
            }
            try Self.applyNeedsReviewInvariant(forScreenshotIDs: strings, db: db)
            try Self.lockOrganization(ids: strings, db: db)
        }
        return token
    }

    func removeScreenshots(ids: Set<ScreenshotMemoryID>, from collectionID: ContextCollectionID) async throws -> MockUndoToken {
        try await database.dbPool.read { db in
            guard let record = try CollectionRecord.fetchOne(db, key: collectionID.rawValue.uuidString) else {
                throw AppError.underlying(message: "Collection not found")
            }
            guard record.kind != ContextCollectionKind.unassigned.rawValue else {
                throw AppError.underlying(message: "Remove from Collection isn’t available in Needs Review")
            }
        }
        let token = try await beginUndoableMutation()
        let strings = Array(ids).map { $0.rawValue.uuidString }
        guard !strings.isEmpty else { return token }
        try await database.dbPool.write { db in
            let collection = collectionID.rawValue.uuidString
            for id in strings {
                try db.execute(sql: """
                    DELETE FROM screenshot_context
                    WHERE screenshot_id = ? AND collection_id = ?
                    """, arguments: [id, collection])
            }
            try Self.applyNeedsReviewInvariant(forScreenshotIDs: strings, db: db)
            try Self.lockOrganization(ids: strings, db: db)
        }
        return token
    }

    func mockRemoveScreenshots(ids: Set<ScreenshotMemoryID>) async throws -> MockUndoToken {
        let token = try await beginUndoableMutation()
        try await database.dbPool.write { db in
            try Self.removeScreenshots(ids.map { $0.rawValue.uuidString }, db: db)
        }
        return token
    }

    func undo(token: MockUndoToken) async -> Bool {
        guard let pending = pendingUndo, pending.0 == token else { return false }
        do {
            try await database.dbPool.write { db in try Self.restore(snapshot: pending.1, db: db) }
            pendingUndo = nil
            return true
        } catch {
            return false
        }
    }

    func discardUndo(token: MockUndoToken) async {
        if pendingUndo?.0 == token { pendingUndo = nil }
    }

    func search(query: String) async throws -> SearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let matchExpression = SearchFTSQuery.matchExpression(from: trimmed) else {
            return .empty
        }
        let tokens = SearchFTSQuery.tokens(from: trimmed)

        let allContexts = try await contexts()
        let collections = allContexts.filter { $0.kind != .unassigned && !$0.isArchived }
        let matchedCollections = collections.compactMap { context -> (ContextCollection, Double)? in
            let count = tokens.filter { Self.contains(context.title, $0) }.count
            return count == 0 ? nil : (context, Double(count) / Double(tokens.count))
        }.sorted { $0.1 > $1.1 }.prefix(4).map(\.0)

        let hits: [SearchHit] = try await database.dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT screenshot.*,
                       bm25(screenshot_fts) AS fts_rank
                FROM screenshot_fts
                JOIN screenshot ON screenshot.id = screenshot_fts.screenshot_id
                WHERE screenshot_fts MATCH ?
                  AND screenshot.is_removed_from_app = 0
                  AND screenshot.access_state = 'available'
                ORDER BY fts_rank ASC,
                         screenshot.is_favorite DESC,
                         screenshot.created_at DESC,
                         screenshot.id DESC
                LIMIT 100
                """, arguments: [matchExpression])

            let now = Date()
            return rows.compactMap { row -> SearchHit? in
                guard let record = try? ScreenshotRecord(row: row),
                      let shot = record.memory()
                else { return nil }
                let bm25: Double = (row["fts_rank"] as Double?) ?? 0
                // Lower bm25 = better FTS match. Invert for SearchHit (higher = better).
                var score = -bm25
                if shot.isFavorite { score += 2.0 }
                if let created = shot.createdAt {
                    let days = max(0, now.timeIntervalSince(created) / 86_400)
                    score += max(0, 1.0 - min(days, 365) / 365.0) * 0.25
                }
                return SearchHit(screenshot: shot, relevanceScore: score, matchedSignals: [.ocr])
            }
        }

        // Annotate .collection when the hit is a member of a title-matched collection.
        let membershipTitles: [ScreenshotMemoryID: [ContextCollectionID]] = try await database.dbPool.read { db in
            let memberships = try MembershipRecord.fetchAll(db)
            var map: [ScreenshotMemoryID: [ContextCollectionID]] = [:]
            for membership in memberships {
                guard let sid = UUID(uuidString: membership.screenshotID),
                      let cid = UUID(uuidString: membership.collectionID)
                else { continue }
                map[ScreenshotMemoryID(sid), default: []].append(ContextCollectionID(cid))
            }
            return map
        }
        let matchedIDs = Set(matchedCollections.map(\.id))
        let annotatedHits = hits.map { hit -> SearchHit in
            var signals = hit.matchedSignals
            if let ids = membershipTitles[hit.screenshot.id], ids.contains(where: { matchedIDs.contains($0) }) {
                signals.insert(.collection)
            }
            return SearchHit(
                screenshot: hit.screenshot,
                relevanceScore: hit.relevanceScore,
                matchedSignals: signals
            )
        }

        return SearchResponse(collections: Array(matchedCollections), hits: annotatedHits)
    }

    func fetchCleanupOverview() async throws -> CleanupOverview {
        let groups = try await fetchDuplicateGroups()
        let old = try await fetchOldScreenshots()
        return CleanupOverview(
            duplicateScreenshotCount: groups.reduce(0) { $0 + $1.count },
            duplicateGroupCount: groups.count,
            oldScreenshotCount: old.count,
            oldThresholdMonths: oldThresholdMonths
        )
    }

    func fetchDuplicateGroups() async throws -> [DuplicateGroup] {
        try await database.dbPool.read { db in
            try DuplicateGroupRecord.fetchAll(db).compactMap { record in
                guard let id = UUID(uuidString: record.id) else { return nil }
                let strings = ScreenshotRecord.array(record.screenshotIDsJSON)
                let shots = strings.compactMap(UUID.init(uuidString:)).map(ScreenshotMemoryID.init)
                guard shots.count >= 2 else { return nil }
                return DuplicateGroup(
                    id: id,
                    screenshotIDs: shots,
                    recommendedKeepID: record.recommendedKeepID
                        .flatMap(UUID.init(uuidString:))
                        .map(ScreenshotMemoryID.init)
                )
            }
        }
    }

    func fetchOldScreenshots() async throws -> [ScreenshotMemory] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -oldThresholdMonths, to: Date()) ?? .distantPast
        return try await database.dbPool.read { db in
            try ScreenshotRecord
                .filter(
                    Column("created_at") < cutoff
                        && Column("is_removed_from_app") == false
                        && Column("access_state") == "available"
                )
                .order(Column("created_at"))
                .fetchAll(db)
                .compactMap { $0.memory() }
        }
    }

    func mockIngestNewScreenshots(count: Int) async throws -> Int {
        pendingUndo = nil
        guard count > 0 else { return 0 }
        let kinds = [
            ("airplane", "flight"), ("building.2", "hotel"), ("doc.text", "document"),
            ("fork.knife", "restaurant"), ("map", "map"), ("photo", "photo")
        ]
        let created = (0..<count).map { index -> ScreenshotMemory in
            let kind = kinds[index % kinds.count]
            return ScreenshotMemory(
                id: ScreenshotMemoryID(),
                createdAt: Date(),
                isFavorite: false,
                ocrText: "Synced screenshot \(index + 1)",
                summary: nil,
                facetKeys: [kind.1],
                entityLabels: [],
                previewSymbol: kind.0
            )
        }
        try await database.dbPool.write { db in
            for shot in created { try ScreenshotRecord(memory: shot).insert(db) }
            let destination = try CollectionRecord.fetchOne(db, key: MockData.japanTripID.rawValue.uuidString)
                ?? CollectionRecord.fetchOne(db, sql: "SELECT * FROM context_collection WHERE kind = 'unassigned'")
            guard let destination else { return }
            let base = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(position), -1) FROM screenshot_context WHERE collection_id = ?",
                arguments: [destination.id]
            ) ?? -1
            for (offset, shot) in created.enumerated() {
                try MembershipRecord(
                    screenshotID: shot.id.rawValue.uuidString,
                    collectionID: destination.id,
                    source: "ai",
                    confidence: nil,
                    createdAt: Date(),
                    position: base + 1 + offset
                ).insert(db)
            }
        }
        return created.count
    }

    func organizeIfNeeded(screenshotID: ScreenshotMemoryID) async throws {
        // Orchestration lives in OrganizationService (AppDependencies.organizer).
        throw AppError.unavailable(feature: "Organization")
    }

    func upsertPhotoScreenshots(_ assets: [PhotoAssetMetadata]) async throws -> Int {
        guard !assets.isEmpty else { return 0 }
        return try await database.dbPool.write { db in
            guard let inbox = try CollectionRecord.fetchOne(
                db,
                sql: "SELECT * FROM context_collection WHERE kind = 'unassigned'"
            ) else { return 0 }
            let base = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(position), -1) FROM screenshot_context WHERE collection_id = ?",
                arguments: [inbox.id]
            ) ?? -1
            var inserted = 0
            for (offset, asset) in assets.enumerated() {
                if var record = try ScreenshotRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM screenshot WHERE photos_local_identifier = ?",
                    arguments: [asset.localIdentifier]
                ) {
                    let wasInaccessible = record.accessState == ScreenshotAccessState.inaccessible.rawValue
                    record.createdAt = asset.createdAt
                    record.width = asset.width
                    record.height = asset.height
                    record.source = ScreenshotSource.photos.rawValue
                    record.accessState = ScreenshotAccessState.available.rawValue
                    record.updatedAt = Date()
                    if wasInaccessible {
                        if record.ocrStatus == ScreenshotOCRStatus.inaccessible.rawValue {
                            record.ocrStatus = ScreenshotOCRStatus.pending.rawValue
                            record.ocrClaimedAt = nil
                            record.ocrNextRetryAt = nil
                            record.ocrLastError = nil
                        } else if record.ocrStatus == ScreenshotOCRStatus.completed.rawValue,
                                  record.ocrVersion < OCRPipeline.currentVersion {
                            record.ocrStatus = ScreenshotOCRStatus.pending.rawValue
                        }
                        if record.visualStatus == ScreenshotVisualStatus.inaccessible.rawValue {
                            record.visualStatus = ScreenshotVisualStatus.pending.rawValue
                            record.visualClaimedAt = nil
                            record.visualNextRetryAt = nil
                            record.visualLastError = nil
                        } else if record.visualStatus == ScreenshotVisualStatus.completed.rawValue,
                                  record.visualVersion < VisualAnalysisPipeline.currentVersion {
                            record.visualStatus = ScreenshotVisualStatus.pending.rawValue
                        }
                    }
                    try record.update(db)
                } else {
                    let memory = ScreenshotMemory(
                        id: ScreenshotMemoryID(),
                        createdAt: asset.createdAt,
                        isFavorite: false,
                        ocrText: nil,
                        summary: nil,
                        facetKeys: [],
                        entityLabels: [],
                        previewSymbol: "photo",
                        photosLocalIdentifier: asset.localIdentifier,
                        source: .photos,
                        accessState: .available,
                        ocrStatus: .pending,
                        ocrVersion: 0,
                        visualStatus: .pending,
                        visualVersion: 0
                    )
                    var record = ScreenshotRecord(memory: memory)
                    record.width = asset.width
                    record.height = asset.height
                    record.ocrStatus = ScreenshotOCRStatus.pending.rawValue
                    record.ocrVersion = 0
                    record.visualStatus = ScreenshotVisualStatus.pending.rawValue
                    record.visualVersion = 0
                    try record.insert(db)
                    try MembershipRecord(
                        screenshotID: record.id,
                        collectionID: inbox.id,
                        source: "photos",
                        confidence: nil,
                        createdAt: Date(),
                        position: base + offset + 1
                    ).insert(db)
                    inserted += 1
                }
            }
            return inserted
        }
    }

    func markPhotoScreenshotsInaccessible(identifiers: Set<String>) async throws {
        guard !identifiers.isEmpty else { return }
        try await database.dbPool.write { db in
            for identifier in identifiers {
                try db.execute(sql: """
                    UPDATE screenshot
                    SET access_state = 'inaccessible',
                        updated_at = ?,
                        ocr_status = CASE
                            WHEN ocr_status IN ('pending', 'processing') THEN 'inaccessible'
                            ELSE ocr_status
                        END,
                        ocr_claimed_at = CASE
                            WHEN ocr_status IN ('pending', 'processing') THEN NULL
                            ELSE ocr_claimed_at
                        END,
                        visual_status = CASE
                            WHEN visual_status IN ('pending', 'processing') THEN 'inaccessible'
                            ELSE visual_status
                        END,
                        visual_claimed_at = CASE
                            WHEN visual_status IN ('pending', 'processing') THEN NULL
                            ELSE visual_claimed_at
                        END
                    WHERE photos_local_identifier = ? AND source = 'photos'
                    """, arguments: [Date(), identifier])
            }
        }
    }

    func removePhotoScreenshots(identifiers: Set<String>) async throws {
        guard !identifiers.isEmpty else { return }
        try await database.dbPool.write { db in
            for identifier in identifiers {
                try db.execute(
                    sql: "DELETE FROM screenshot WHERE photos_local_identifier = ? AND source = 'photos'",
                    arguments: [identifier]
                )
            }
        }
    }

    func clearFixtureScreenshots() async throws {
        try await DatabaseSeeder.clearFixtureScreenshotsIfNeeded(database)
    }

    func photoScreenshotIdentifiers() async throws -> Set<String> {
        try await database.dbPool.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT photos_local_identifier FROM screenshot WHERE source = 'photos' AND photos_local_identifier IS NOT NULL"
            ))
        }
    }

    func fetchNeedsReviewCount() async throws -> Int {
        try await database.dbPool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM screenshot_context
                JOIN screenshot ON screenshot.id = screenshot_context.screenshot_id
                JOIN context_collection ON context_collection.id = screenshot_context.collection_id
                WHERE context_collection.kind = 'unassigned'
                  AND screenshot.is_removed_from_app = 0
                  AND screenshot.access_state = 'available'
                """) ?? 0
        }
    }

    func fetchNeedsReviewPreview(limit: Int) async throws -> [ScreenshotMemory] {
        guard limit > 0 else { return [] }
        return try await database.dbPool.read { db in
            try ScreenshotRecord.fetchAll(db, sql: """
                SELECT screenshot.* FROM screenshot
                JOIN screenshot_context ON screenshot.id = screenshot_context.screenshot_id
                JOIN context_collection ON context_collection.id = screenshot_context.collection_id
                WHERE context_collection.kind = 'unassigned'
                  AND screenshot.is_removed_from_app = 0
                  AND screenshot.access_state = 'available'
                ORDER BY screenshot.created_at DESC, screenshot.imported_at DESC, screenshot.id DESC
                LIMIT ?
                """, arguments: [limit]).compactMap { $0.memory() }
        }
    }

    func fetchScreenshots(page: Int, pageSize: Int) async throws -> [ScreenshotMemory] {
        guard page >= 0, pageSize > 0 else { return [] }
        return try await database.dbPool.read { db in
            try ScreenshotRecord.fetchAll(db, sql: """
                SELECT * FROM screenshot
                WHERE is_removed_from_app = 0 AND access_state = 'available'
                ORDER BY created_at DESC LIMIT ? OFFSET ?
                """, arguments: [pageSize, page * pageSize]).compactMap { $0.memory() }
        }
    }

    func setPhotosSyncCheckpoint(_ date: Date) async throws {
        try await database.dbPool.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO app_meta (key, value) VALUES ('lastPhotosSyncAt', ?)",
                arguments: [ISO8601DateFormatter().string(from: date)]
            )
        }
    }

    // MARK: - OCR (Sprint 5)

    func recoverStaleOCRClaims(olderThan date: Date) async throws -> Int {
        try await database.dbPool.write { db in
            try db.execute(sql: """
                UPDATE screenshot
                SET ocr_status = 'pending',
                    ocr_claimed_at = NULL,
                    updated_at = ?
                WHERE ocr_status = 'processing'
                  AND (ocr_claimed_at IS NULL OR ocr_claimed_at < ?)
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                """, arguments: [Date(), date])
            return db.changesCount
        }
    }

    func enqueueStaleVersionOCR(currentVersion: Int) async throws -> Int {
        try await database.dbPool.write { db in
            try db.execute(sql: """
                UPDATE screenshot
                SET ocr_status = 'pending',
                    ocr_claimed_at = NULL,
                    ocr_next_retry_at = NULL,
                    updated_at = ?
                WHERE source = 'photos'
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                  AND (
                    ocr_status = 'completed' AND ocr_version < ?
                    OR ocr_status = 'failed' AND ocr_next_retry_at IS NOT NULL AND ocr_next_retry_at <= ?
                  )
                """, arguments: [Date(), currentVersion, Date()])
            return db.changesCount
        }
    }

    func claimNextOCRJob(currentVersion: Int, now: Date) async throws -> OCRClaim? {
        try await database.dbPool.write { db in
            // Also promote due failed retries into pending for claiming.
            try db.execute(sql: """
                UPDATE screenshot
                SET ocr_status = 'pending', ocr_next_retry_at = NULL, updated_at = ?
                WHERE ocr_status = 'failed'
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                  AND ocr_next_retry_at IS NOT NULL
                  AND ocr_next_retry_at <= ?
                """, arguments: [now, now])

            guard let row = try Row.fetchOne(db, sql: """
                SELECT id, photos_local_identifier FROM screenshot
                WHERE ocr_status = 'pending'
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                  AND source = 'photos'
                  AND photos_local_identifier IS NOT NULL
                ORDER BY created_at DESC
                LIMIT 1
                """)
            else { return nil }

            let idString: String = row["id"]
            let localID: String = row["photos_local_identifier"]
            try db.execute(sql: """
                UPDATE screenshot
                SET ocr_status = 'processing',
                    ocr_claimed_at = ?,
                    ocr_last_attempt_at = ?,
                    updated_at = ?
                WHERE id = ? AND ocr_status = 'pending'
                """, arguments: [now, now, now, idString])
            guard db.changesCount == 1, let uuid = UUID(uuidString: idString) else { return nil }
            return OCRClaim(id: ScreenshotMemoryID(uuid), photosLocalIdentifier: localID)
        }
    }

    func completeOCRSuccess(
        id: ScreenshotMemoryID,
        text: String,
        language: String?,
        version: Int
    ) async throws {
        let normalized = OCRPipeline.normalizedForSearch(text)
        try await database.dbPool.write { db in
            try db.execute(sql: """
                UPDATE screenshot
                SET ocr_text = ?,
                    ocr_language = ?,
                    ocr_status = 'completed',
                    ocr_version = ?,
                    ocr_claimed_at = NULL,
                    ocr_next_retry_at = NULL,
                    ocr_last_error = NULL,
                    updated_at = ?
                WHERE id = ?
                """, arguments: [text, language, version, Date(), id.rawValue.uuidString])
            try db.execute(
                sql: "DELETE FROM screenshot_fts WHERE screenshot_id = ?",
                arguments: [id.rawValue.uuidString]
            )
            try db.execute(sql: """
                INSERT INTO screenshot_fts(screenshot_id, ocr_text, title_blob)
                VALUES (?, ?, '')
                """, arguments: [id.rawValue.uuidString, normalized])
        }
    }

    func completeOCRFailure(id: ScreenshotMemoryID, errorCode: String) async throws {
        try await database.dbPool.write { db in
            let attempt = (try Int.fetchOne(
                db,
                sql: "SELECT ocr_attempt_count FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            ) ?? 0) + 1
            let next: Date? = attempt >= OCRPipeline.maxAttempts
                ? nil
                : Date().addingTimeInterval(OCRPipeline.retryDelay(afterAttempt: attempt))
            try db.execute(sql: """
                UPDATE screenshot
                SET ocr_status = 'failed',
                    ocr_attempt_count = ?,
                    ocr_claimed_at = NULL,
                    ocr_last_attempt_at = ?,
                    ocr_next_retry_at = ?,
                    ocr_last_error = ?,
                    updated_at = ?
                WHERE id = ?
                """, arguments: [attempt, Date(), next, errorCode, Date(), id.rawValue.uuidString])
        }
    }

    func fetchOCRStatusCounts() async throws -> OCRStatusCounts {
        try await database.dbPool.read { db in
            func count(_ status: String) throws -> Int {
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM screenshot WHERE source = 'photos' AND ocr_status = ?",
                    arguments: [status]
                ) ?? 0
            }
            return OCRStatusCounts(
                pending: try count("pending"),
                processing: try count("processing"),
                completed: try count("completed"),
                failed: try count("failed"),
                inaccessible: try count("inaccessible")
            )
        }
    }

    func fetchOCRDebugRows(limit: Int) async throws -> [ScreenshotMemory] {
        try await database.dbPool.read { db in
            try ScreenshotRecord.fetchAll(db, sql: """
                SELECT * FROM screenshot
                WHERE source = 'photos'
                ORDER BY updated_at DESC
                LIMIT ?
                """, arguments: [limit]).compactMap { $0.memory() }
        }
    }

    func requestOCRReprocess(id: ScreenshotMemoryID) async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: """
                UPDATE screenshot
                SET ocr_status = 'pending',
                    ocr_version = 0,
                    ocr_attempt_count = 0,
                    ocr_claimed_at = NULL,
                    ocr_next_retry_at = NULL,
                    ocr_last_error = NULL,
                    updated_at = ?
                WHERE id = ?
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                """, arguments: [Date(), id.rawValue.uuidString])
        }
    }

    func requestOCRReprocessAll(currentVersion: Int) async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: """
                UPDATE screenshot
                SET ocr_status = 'pending',
                    ocr_version = 0,
                    ocr_attempt_count = 0,
                    ocr_claimed_at = NULL,
                    ocr_next_retry_at = NULL,
                    ocr_last_error = NULL,
                    updated_at = ?
                WHERE source = 'photos'
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                """, arguments: [Date()])
        }
    }

    // MARK: - Visual analysis (P1)

    func recoverStaleVisualClaims(olderThan date: Date) async throws -> Int {
        try await database.dbPool.write { db in
            try db.execute(sql: """
                UPDATE screenshot
                SET visual_status = 'pending',
                    visual_claimed_at = NULL,
                    updated_at = ?
                WHERE visual_status = 'processing'
                  AND (visual_claimed_at IS NULL OR visual_claimed_at < ?)
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                """, arguments: [Date(), date])
            return db.changesCount
        }
    }

    func enqueueStaleVersionVisual(currentVersion: Int) async throws -> Int {
        try await database.dbPool.write { db in
            try db.execute(sql: """
                UPDATE screenshot
                SET visual_status = 'pending',
                    visual_claimed_at = NULL,
                    visual_next_retry_at = NULL,
                    updated_at = ?
                WHERE source = 'photos'
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                  AND (
                    visual_status = 'completed' AND visual_version < ?
                    OR visual_status = 'failed' AND visual_next_retry_at IS NOT NULL AND visual_next_retry_at <= ?
                  )
                """, arguments: [Date(), currentVersion, Date()])
            return db.changesCount
        }
    }

    func claimNextVisualJob(currentVersion: Int, now: Date) async throws -> VisualAnalysisClaim? {
        try await database.dbPool.write { db in
            try db.execute(sql: """
                UPDATE screenshot
                SET visual_status = 'pending', visual_next_retry_at = NULL, updated_at = ?
                WHERE visual_status = 'failed'
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                  AND visual_next_retry_at IS NOT NULL
                  AND visual_next_retry_at <= ?
                """, arguments: [now, now])

            guard let row = try Row.fetchOne(db, sql: """
                SELECT id, photos_local_identifier FROM screenshot
                WHERE visual_status = 'pending'
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                  AND source = 'photos'
                  AND photos_local_identifier IS NOT NULL
                  AND length(photos_local_identifier) > 0
                ORDER BY created_at DESC
                LIMIT 1
                """)
            else { return nil }

            let idString: String = row["id"]
            let localID: String = row["photos_local_identifier"]
            try db.execute(sql: """
                UPDATE screenshot
                SET visual_status = 'processing',
                    visual_claimed_at = ?,
                    visual_last_attempt_at = ?,
                    updated_at = ?
                WHERE id = ? AND visual_status = 'pending'
                """, arguments: [now, now, now, idString])
            guard db.changesCount == 1, let uuid = UUID(uuidString: idString) else { return nil }
            return VisualAnalysisClaim(id: ScreenshotMemoryID(uuid), photosLocalIdentifier: localID)
        }
    }

    func completeVisualSuccess(
        id: ScreenshotMemoryID,
        result: VisualAnalysisResult,
        version: Int
    ) async throws {
        try await database.dbPool.write { db in
            let ocrText = try String.fetchOne(
                db,
                sql: "SELECT ocr_text FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
            let evidence = ScreenshotFacetDeriver.evaluate(ocrText: ocrText, labels: result.labels)
            // Strong semantic facets only — never persist legacy `image_only` as a type.
            let facets = evidence
                .filter { $0.strength == .strong && $0.id != "image_only" }
                .map(\.id)
                .sorted()
            let evidenceForPersist = evidence.filter { $0.id != "image_only" }
            let labelsJSON = ScreenshotRecord.labelsJSON(result.labels)
            let rawLabelsJSON = ScreenshotRecord.labelsJSON(result.rawLabels)
            let facetsJSON = ScreenshotRecord.json(facets)
            let evidenceJSON = ScreenshotRecord.facetEvidenceJSON(evidenceForPersist)
            let printStatus: String = {
                switch result.featurePrintStatus {
                case "generated", "failed", "missing":
                    return result.featurePrintStatus
                default:
                    return result.featurePrintData == nil ? "failed" : "generated"
                }
            }()
            // Partial success keeps labels; clear job-level error. FP stage is in feature_print_status.
            try db.execute(sql: """
                UPDATE screenshot
                SET visual_labels_json = ?,
                    visual_labels_raw_json = ?,
                    visual_facets_json = ?,
                    visual_facets_evidence_json = ?,
                    visual_status = 'completed',
                    visual_version = ?,
                    visual_classify_revision = ?,
                    feature_print = ?,
                    feature_print_version = ?,
                    feature_print_status = ?,
                    visual_claimed_at = NULL,
                    visual_next_retry_at = NULL,
                    visual_last_error = NULL,
                    updated_at = ?
                WHERE id = ?
                """, arguments: [
                labelsJSON,
                rawLabelsJSON,
                facetsJSON,
                evidenceJSON,
                version,
                result.classifyRevision,
                result.featurePrintData,
                result.featurePrintRevision,
                printStatus,
                Date(),
                id.rawValue.uuidString
            ])
        }
    }

    func completeVisualFailure(id: ScreenshotMemoryID, errorCode: String) async throws {
        try await database.dbPool.write { db in
            let attempt = (try Int.fetchOne(
                db,
                sql: "SELECT visual_attempt_count FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            ) ?? 0) + 1
            let next: Date? = attempt >= VisualAnalysisPipeline.maxAttempts
                ? nil
                : Date().addingTimeInterval(VisualAnalysisPipeline.retryDelay(afterAttempt: attempt))
            // Bound persisted codes — never store huge Vision dumps.
            let bounded = VisualAnalysisErrorCode.sanitizeDebugNote(errorCode, maxLength: 64)
            try db.execute(sql: """
                UPDATE screenshot
                SET visual_status = 'failed',
                    visual_attempt_count = ?,
                    visual_claimed_at = NULL,
                    visual_last_attempt_at = ?,
                    visual_next_retry_at = ?,
                    visual_last_error = ?,
                    feature_print_status = 'failed',
                    updated_at = ?
                WHERE id = ?
                """, arguments: [attempt, Date(), next, bounded, Date(), id.rawValue.uuidString])
        }
    }

    func completeVisualInaccessible(id: ScreenshotMemoryID, errorCode: String) async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: """
                UPDATE screenshot
                SET visual_status = 'inaccessible',
                    access_state = 'inaccessible',
                    visual_claimed_at = NULL,
                    visual_next_retry_at = NULL,
                    visual_last_error = ?,
                    feature_print_status = 'failed',
                    updated_at = ?
                WHERE id = ?
                """, arguments: [errorCode, Date(), id.rawValue.uuidString])
        }
    }

    func fetchVisualClaimabilityBreakdown() async throws -> VisualClaimabilityBreakdown {
        try await database.dbPool.read { db in
            let pendingTotal = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM screenshot WHERE source = 'photos' AND visual_status = 'pending'",
                arguments: []
            ) ?? 0
            let claimable = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM screenshot
                    WHERE source = 'photos'
                      AND visual_status = 'pending'
                      AND access_state = 'available'
                      AND is_removed_from_app = 0
                      AND photos_local_identifier IS NOT NULL
                      AND length(photos_local_identifier) > 0
                    """
            ) ?? 0
            let missingLocalID = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM screenshot
                    WHERE source = 'photos'
                      AND visual_status = 'pending'
                      AND is_removed_from_app = 0
                      AND (photos_local_identifier IS NULL OR length(photos_local_identifier) = 0)
                    """
            ) ?? 0
            let removedFromApp = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM screenshot
                    WHERE source = 'photos'
                      AND visual_status = 'pending'
                      AND is_removed_from_app = 1
                    """
            ) ?? 0
            let inaccessibleAccess = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM screenshot
                    WHERE source = 'photos'
                      AND visual_status = 'pending'
                      AND access_state = 'inaccessible'
                      AND is_removed_from_app = 0
                    """
            ) ?? 0
            let breakdown = VisualClaimabilityBreakdown(
                pendingTotal: pendingTotal,
                claimable: claimable,
                missingLocalID: missingLocalID,
                removedFromApp: removedFromApp,
                inaccessibleAccess: inaccessibleAccess
            )
            VisualAnalysisDebugRuntime.update {
                $0.pendingTotal = pendingTotal
                $0.claimablePending = claimable
                $0.pendingMissingLocalID = missingLocalID
                $0.pendingRemovedFromApp = removedFromApp
                $0.pendingInaccessibleAccess = inaccessibleAccess
            }
            return breakdown
        }
    }

    func fetchVisualStatusCounts() async throws -> VisualAnalysisStatusCounts {
        _ = try? await fetchVisualClaimabilityBreakdown()
        return try await database.dbPool.read { db in
            func count(_ status: String) throws -> Int {
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM screenshot WHERE source = 'photos' AND visual_status = ?",
                    arguments: [status]
                ) ?? 0
            }
            let completedFPFailed = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM screenshot
                    WHERE source = 'photos'
                      AND visual_status = 'completed'
                      AND feature_print_status = 'failed'
                    """
            ) ?? 0
            return VisualAnalysisStatusCounts(
                pending: try count("pending"),
                processing: try count("processing"),
                completed: try count("completed"),
                failed: try count("failed"),
                inaccessible: try count("inaccessible"),
                completedFeaturePrintFailed: completedFPFailed
            )
        }
    }

    func fetchVisualFailureSummary() async throws -> VisualFailureSummary {
        try await database.dbPool.read { db in
            let totalFailed = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM screenshot WHERE source = 'photos' AND visual_status = 'failed'"
            ) ?? 0

            let reasonRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT COALESCE(visual_last_error, '(nil)') AS code, COUNT(*) AS cnt
                    FROM screenshot
                    WHERE source = 'photos' AND visual_status = 'failed'
                    GROUP BY COALESCE(visual_last_error, '(nil)')
                    ORDER BY cnt DESC, code ASC
                    """
            )
            let byErrorCode = reasonRows.map { row in
                VisualFailureReasonCount(code: row["code"], count: row["cnt"])
            }

            let attemptRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT visual_attempt_count AS attempts, COUNT(*) AS cnt
                    FROM screenshot
                    WHERE source = 'photos' AND visual_status = 'failed'
                    GROUP BY visual_attempt_count
                    ORDER BY visual_attempt_count ASC
                    """
            )
            let attemptBuckets = attemptRows.map { row -> VisualFailureAttemptBucket in
                let attempts: Int = row["attempts"]
                let count: Int = row["cnt"]
                return VisualFailureAttemptBucket(label: "attempts=\(attempts)", count: count)
            }

            return VisualFailureSummary(
                totalFailed: totalFailed,
                byErrorCode: byErrorCode,
                attemptBuckets: attemptBuckets
            )
        }
    }

    func fetchFeaturePrintData(id: ScreenshotMemoryID) async throws -> Data? {
        try await database.dbPool.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT feature_print FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
    }

    func requestVisualReprocess(id: ScreenshotMemoryID) async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: """
                UPDATE screenshot
                SET visual_status = 'pending',
                    visual_version = 0,
                    visual_attempt_count = 0,
                    visual_claimed_at = NULL,
                    visual_next_retry_at = NULL,
                    visual_last_error = NULL,
                    visual_labels_json = '[]',
                    visual_labels_raw_json = '[]',
                    visual_facets_json = '[]',
                    visual_facets_evidence_json = '[]',
                    feature_print = NULL,
                    feature_print_status = 'missing',
                    feature_print_version = 0,
                    updated_at = ?
                WHERE id = ?
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                """, arguments: [Date(), id.rawValue.uuidString])
        }
    }

    func requestVisualReprocessAll(currentVersion: Int) async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: """
                UPDATE screenshot
                SET visual_status = 'pending',
                    visual_version = 0,
                    visual_attempt_count = 0,
                    visual_claimed_at = NULL,
                    visual_next_retry_at = NULL,
                    visual_last_error = NULL,
                    visual_labels_json = '[]',
                    visual_labels_raw_json = '[]',
                    visual_facets_json = '[]',
                    visual_facets_evidence_json = '[]',
                    feature_print = NULL,
                    feature_print_status = 'missing',
                    feature_print_version = 0,
                    updated_at = ?
                WHERE source = 'photos'
                  AND access_state = 'available'
                  AND is_removed_from_app = 0
                """, arguments: [Date()])
        }
    }

    func tryMarkReadyForOrganize(id: ScreenshotMemoryID) async throws {
        try await database.dbPool.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT ocr_status, visual_status, organize_status, organize_locked
                    FROM screenshot WHERE id = ?
                    """,
                arguments: [id.rawValue.uuidString]
            ) else { return }

            let ocr: String = row["ocr_status"]
            let visual: String = row["visual_status"]
            let organize: String = row["organize_status"]
            let locked: Bool = row["organize_locked"]
            guard !locked else { return }

            let ocrReady = ["completed", "failed", "inaccessible"].contains(ocr)
            let visualReady = ["completed", "failed", "inaccessible"].contains(visual)
            guard ocrReady, visualReady else { return }

            // Don't interrupt active organize / already ready unless idle/pendingNetwork/failed.
            let resumable = ["idle", "pendingNetwork", "failed", "skippedNoConsent"].contains(organize)
            guard resumable else { return }

            try db.execute(sql: """
                UPDATE screenshot
                SET organize_status = 'pending',
                    analysis_status = 'pendingOrganize',
                    updated_at = ?
                WHERE id = ?
                """, arguments: [Date(), id.rawValue.uuidString])
        }
    }

    func fetchVisualDebugListPage(offset: Int, limit: Int) async throws -> [VisualAnalysisDebugSnapshot] {
        let safeOffset = max(0, offset)
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else { return [] }

        let rows: [(ScreenshotMemory, Data?, Date, String)] = try await database.dbPool.read { db in
            let records = try ScreenshotRecord.fetchAll(db, sql: """
                SELECT * FROM screenshot
                WHERE source = 'photos'
                  AND is_removed_from_app = 0
                  AND visual_status = 'completed'
                ORDER BY created_at DESC, id DESC
                LIMIT ? OFFSET ?
                """, arguments: [safeLimit, safeOffset])
            return records.compactMap { record in
                guard let memory = record.memory() else { return nil }
                return (memory, record.featurePrint, record.updatedAt, record.visualLabelsRawJSON)
            }
        }
        // Lightweight list: persisted metadata only — no neighbor / cluster work.
        return try await buildVisualDebugSnapshots(rows: rows, includeNeighbors: false)
    }

    func fetchVisualDebugDetailSnapshot(id: ScreenshotMemoryID) async throws -> VisualAnalysisDebugSnapshot? {
        let rows: [(ScreenshotMemory, Data?, Date, String)] = try await database.dbPool.read { db in
            let records = try ScreenshotRecord.fetchAll(db, sql: """
                SELECT * FROM screenshot
                WHERE id = ?
                LIMIT 1
                """, arguments: [id.rawValue.uuidString])
            return records.compactMap { record in
                guard let memory = record.memory() else { return nil }
                return (memory, record.featurePrint, record.updatedAt, record.visualLabelsRawJSON)
            }
        }
        guard !rows.isEmpty else { return nil }
        return try await buildVisualDebugSnapshots(rows: rows, includeNeighbors: true).first
    }

    func fetchVisualDebugSnapshots(limit: Int) async throws -> [VisualAnalysisDebugSnapshot] {
        try await fetchVisualDebugListPage(offset: 0, limit: limit)
    }

    func fetchVisualFailedDebugSnapshots(limit: Int) async throws -> [VisualAnalysisDebugSnapshot] {
        let rows: [(ScreenshotMemory, Data?, Date, String)] = try await database.dbPool.read { db in
            let records = try ScreenshotRecord.fetchAll(db, sql: """
                SELECT * FROM screenshot
                WHERE source = 'photos'
                  AND visual_status = 'failed'
                ORDER BY updated_at DESC
                LIMIT ?
                """, arguments: [limit])
            return records.compactMap { record in
                guard let memory = record.memory() else { return nil }
                return (memory, record.featurePrint, record.updatedAt, record.visualLabelsRawJSON)
            }
        }
        return try await buildVisualDebugSnapshots(rows: rows, includeNeighbors: false)
    }

    /// DEBUG-only peer pool for candidate grouping (independent of FP neighbors / list page).
    private static let visualDebugClusterPeerLimit = 200

    private func buildVisualDebugSnapshots(
        rows: [(ScreenshotMemory, Data?, Date, String)],
        includeNeighbors: Bool
    ) async throws -> [VisualAnalysisDebugSnapshot] {
        let eligible = includeNeighbors ? ((try? await fetchOrganizationEligibleCollections()) ?? []) : []
        let profileTitles = eligible
            .filter { $0.kind != .unassigned }
            .map(\.title)

        // Broader neighbor pool for feature-print similarity (visual only — not grouping candidates).
        let neighborPool: [(ScreenshotMemoryID, String?, Data)] = includeNeighbors
            ? (try await database.dbPool.read { db in
                let records = try ScreenshotRecord.fetchAll(db, sql: """
                    SELECT * FROM screenshot
                    WHERE source = 'photos'
                      AND is_removed_from_app = 0
                      AND visual_status = 'completed'
                      AND feature_print IS NOT NULL
                      AND feature_print_status = 'generated'
                    ORDER BY created_at DESC
                    LIMIT 200
                    """)
                return records.compactMap { record in
                    guard let uuid = UUID(uuidString: record.id), let print = record.featurePrint else { return nil }
                    return (ScreenshotMemoryID(uuid), record.photosLocalIdentifier, print)
                }
            })
            : []

        // Candidate-grouping peer pool: eligible completed screenshots (not FP-neighbor list, not list page).
        let clusterPeerRows: [(ScreenshotMemory, Data?)] = includeNeighbors
            ? (try await database.dbPool.read { db in
                let records = try ScreenshotRecord.fetchAll(db, sql: """
                    SELECT * FROM screenshot
                    WHERE source = 'photos'
                      AND is_removed_from_app = 0
                      AND visual_status = 'completed'
                    ORDER BY created_at DESC, id DESC
                    LIMIT ?
                    """, arguments: [Self.visualDebugClusterPeerLimit])
                return records.compactMap { record in
                    guard let memory = record.memory() else { return nil }
                    return (memory, record.featurePrint)
                }
            })
            : []

        var localIDByScreenshot: [ScreenshotMemoryID: String?] = Dictionary(
            uniqueKeysWithValues: rows.map { ($0.0.id, $0.0.photosLocalIdentifier) }
        )
        for (memory, _) in clusterPeerRows {
            localIDByScreenshot[memory.id] = memory.photosLocalIdentifier
        }

        let members: [MultiSignalClusterer.Member] = includeNeighbors
            ? {
                var byID: [ScreenshotMemoryID: MultiSignalClusterer.Member] = [:]
                for (memory, printData) in clusterPeerRows {
                    byID[memory.id] = Self.clusterMember(
                        memory: memory,
                        printData: printData,
                        profileTitles: profileTitles,
                        profileMatch: profileMatchScore(for: memory, titles: profileTitles),
                        matchingTitles: matchingProfileTitles(for: memory, titles: profileTitles)
                    )
                }
                // Ensure the detail seed is present even if outside the recent peer window.
                for (memory, printData, _, _) in rows {
                    if byID[memory.id] == nil {
                        byID[memory.id] = Self.clusterMember(
                            memory: memory,
                            printData: printData,
                            profileTitles: profileTitles,
                            profileMatch: profileMatchScore(for: memory, titles: profileTitles),
                            matchingTitles: matchingProfileTitles(for: memory, titles: profileTitles)
                        )
                    }
                }
                return Array(byID.values)
            }()
            : []

        var snapshots: [VisualAnalysisDebugSnapshot] = []
        snapshots.reserveCapacity(rows.count)

        for quadruple in rows {
            let memory = quadruple.0
            let printData = quadruple.1
            let updatedAt = quadruple.2
            let rawJSON = quadruple.3
            let rawLabels = ScreenshotRecord.decodeLabels(rawJSON)

            var clusterID: String?
            var clusterMemberIDs: [ScreenshotMemoryID] = []
            var clusterMembers: [VisualClusterMemberDebug] = []
            var clusterCohesion: Double?
            var clusterWeakestMemberSupport: Double?
            var clusterWeakestPairSupport: Double?
            var clusterSupportedEdgeCount: Int?
            var clusterFlags: [String] = []
            var signalBreakdown: [String: Double] = [:]
            var singletonReason: String?
            var rejectedCandidates: [VisualRejectedCandidateDebug] = []
            var inputPeerCount = 0
            var collectionTitles: [String] = []
            var neighbors: [VisualNeighbor] = []

            if includeNeighbors, let seed = members.first(where: { $0.id == memory.id }) {
                let cluster = MultiSignalClusterer.cluster(around: seed, candidates: members, maxSize: 8)
                clusterID = cluster.clusterID
                clusterMemberIDs = cluster.memberIDs
                clusterCohesion = cluster.meanCohesion
                clusterWeakestMemberSupport = cluster.weakestMemberSupport
                clusterWeakestPairSupport = cluster.weakestPairSupport
                clusterSupportedEdgeCount = cluster.supportedEdgeCount
                clusterFlags = cluster.flags
                signalBreakdown = cluster.signalBreakdown
                singletonReason = cluster.singletonReason
                inputPeerCount = cluster.inputPeerCount
                collectionTitles = cluster.profileTitlesConsidered.isEmpty
                    ? matchingProfileTitles(for: memory, titles: profileTitles)
                    : cluster.profileTitlesConsidered
                let supportByID = Dictionary(
                    uniqueKeysWithValues: cluster.memberSupport.map { ($0.id, $0) }
                )
                let auditByID = Dictionary(
                    uniqueKeysWithValues: cluster.admittedMemberAudits.map { ($0.id, $0) }
                )
                clusterMembers = cluster.memberIDs.map { id in
                    let support = supportByID[id]
                    let audit = auditByID[id]
                    return VisualClusterMemberDebug(
                        id: id,
                        photosLocalIdentifier: localIDByScreenshot[id] ?? nil,
                        support: support?.support,
                        topSignals: support?.topSignals ?? [:],
                        strongFacets: support?.strongFacets ?? [],
                        pruned: support?.pruned ?? false,
                        pruneReason: support?.pruneReason,
                        admissionTotalScore: audit?.totalScore,
                        admissionSignalParts: audit?.signalParts ?? [:],
                        admissionHasContextualSupport: audit?.hasContextualSupport,
                        admissionContextualFamilies: audit?.contextualFamilies ?? [],
                        admissionReason: audit?.admissionReason,
                        bridgeInvolved: audit?.bridgeInvolved ?? false,
                        outlierValidationPassed: audit?.outlierValidationPassed,
                        correlatedSemanticChannels: audit?.correlatedSemanticChannels ?? []
                    )
                }
                // Surface pruned outliers in DEBUG even if not in final memberIDs
                for pruned in cluster.memberSupport where pruned.pruned {
                    if !clusterMembers.contains(where: { $0.id == pruned.id }) {
                        let audit = auditByID[pruned.id]
                        clusterMembers.append(
                            VisualClusterMemberDebug(
                                id: pruned.id,
                                photosLocalIdentifier: localIDByScreenshot[pruned.id] ?? nil,
                                support: pruned.support,
                                topSignals: pruned.topSignals,
                                strongFacets: pruned.strongFacets,
                                pruned: true,
                                pruneReason: pruned.pruneReason,
                                admissionTotalScore: audit?.totalScore,
                                admissionSignalParts: audit?.signalParts ?? [:],
                                admissionHasContextualSupport: audit?.hasContextualSupport,
                                admissionContextualFamilies: audit?.contextualFamilies ?? [],
                                admissionReason: audit?.admissionReason,
                                bridgeInvolved: audit?.bridgeInvolved ?? false,
                                outlierValidationPassed: false,
                                correlatedSemanticChannels: audit?.correlatedSemanticChannels ?? []
                            )
                        )
                    }
                }
                rejectedCandidates = cluster.rejectedCandidates.map { rejected in
                    VisualRejectedCandidateDebug(
                        id: rejected.id,
                        photosLocalIdentifier: localIDByScreenshot[rejected.id] ?? nil,
                        totalScore: rejected.totalScore,
                        hasContextualSupport: rejected.hasContextualSupport,
                        contextualFamilies: rejected.contextualFamilies,
                        signalParts: rejected.signalParts,
                        rejectionReason: rejected.rejectionReason,
                        sourcePlatform: rejected.sourcePlatform,
                        contentType: rejected.contentType,
                        contentFamily: rejected.contentFamily,
                        correlatedSemanticChannels: rejected.correlatedSemanticChannels
                    )
                }

                if let printData {
                    neighbors = neighborPool
                        .filter { $0.0 != memory.id }
                        .compactMap { otherID, otherLocalID, otherPrint -> VisualNeighbor? in
                            guard let distance = VisionVisualAnalysisService.distance(between: printData, and: otherPrint)
                            else { return nil }
                            return VisualNeighbor(
                                screenshotID: otherID,
                                photosLocalIdentifier: otherLocalID,
                                distance: distance,
                                similarity: VisionVisualAnalysisService.similarity(distance: distance),
                                band: VisualAnalysisPipeline.neighborBand(distance: distance)
                            )
                        }
                        .sorted { $0.distance < $1.distance }
                        .prefix(8)
                        .map { $0 }
                }
            }

            let ocrTrimmed = memory.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Sparse-OCR DEBUG flag — not a semantic Level 2 facet. Stale `image_only` facet ids ignored.
            let imageOnly = ocrTrimmed.count < 12
            let evidence: [FacetEvidence] = {
                if !memory.visualFacetEvidence.isEmpty {
                    return memory.visualFacetEvidence
                }
                // Pre-8.2A rows: re-derive for DEBUG without mutating DB.
                return ScreenshotFacetDeriver.evaluate(
                    ocrText: memory.ocrText,
                    labels: memory.visualLabelObservations
                )
            }()
            let sourceEvidence = ScreenshotSourceDeriver.derive(
                ocrText: memory.ocrText,
                labels: memory.visualLabelObservations,
                strongFacets: memory.visualFacets,
                facetEvidence: evidence
            )
            func fieldDebug(_ field: SourceEvidenceField) -> VisualSourceFieldDebug {
                VisualSourceFieldDebug(
                    value: field.value,
                    confidence: field.confidence,
                    evidence: field.evidence,
                    trace: field.trace
                )
            }

            snapshots.append(
                VisualAnalysisDebugSnapshot(
                    id: memory.id,
                    createdAt: memory.createdAt,
                    updatedAt: updatedAt,
                    photosLocalIdentifier: memory.photosLocalIdentifier,
                    previewSymbol: memory.previewSymbol,
                    ocrText: memory.ocrText,
                    ocrStatus: memory.ocrStatus,
                    visualStatus: memory.visualStatus,
                    visualVersion: memory.visualVersion,
                    visualAttemptCount: memory.visualAttemptCount,
                    visualLastError: memory.visualLastError,
                    labels: memory.visualLabelObservations,
                    rawLabels: rawLabels,
                    droppedLabels: [],
                    facets: memory.visualFacets,
                    facetEvidence: evidence,
                    featurePrintPresent: printData != nil,
                    featurePrintVersion: memory.featurePrintVersion,
                    featurePrintStatus: memory.featurePrintStatus,
                    clusterID: clusterID,
                    clusterMemberIDs: clusterMemberIDs,
                    clusterMembers: clusterMembers,
                    clusterCohesion: clusterCohesion,
                    clusterWeakestMemberSupport: clusterWeakestMemberSupport,
                    clusterWeakestPairSupport: clusterWeakestPairSupport,
                    clusterSupportedEdgeCount: clusterSupportedEdgeCount,
                    clusterFlags: clusterFlags,
                    clusterSignalBreakdown: signalBreakdown,
                    clusterSingletonReason: singletonReason,
                    clusterRejectedCandidates: rejectedCandidates,
                    clusterInputPeerCount: inputPeerCount,
                    sourcePlatform: sourceEvidence.sourcePlatform,
                    contentType: sourceEvidence.contentType,
                    contentFamily: sourceEvidence.contentFamily,
                    sourceEvidenceConfidence: sourceEvidence.confidence,
                    sourcePlatformField: fieldDebug(sourceEvidence.platform),
                    contentTypeField: fieldDebug(sourceEvidence.type),
                    contentFamilyField: fieldDebug(sourceEvidence.family),
                    surfaceField: fieldDebug(sourceEvidence.surface),
                    embeddedHints: sourceEvidence.embeddedHints.map {
                        VisualEmbeddedHintDebug(
                            value: $0.value,
                            kind: $0.kind,
                            confidence: $0.confidence,
                            evidence: $0.evidence
                        )
                    },
                    collectionProfileTitles: collectionTitles,
                    neighbors: neighbors,
                    isImageOnlyEvidence: imageOnly,
                    analysisInputNote: VisualAnalysisPipeline.analysisInputLongEdgeNote
                )
            )
        }
        return snapshots
    }

    private static func clusterMember(
        memory: ScreenshotMemory,
        printData: Data?,
        profileTitles: [String],
        profileMatch: Double,
        matchingTitles: [String]
    ) -> MultiSignalClusterer.Member {
        _ = profileTitles
        return MultiSignalClusterer.Member.withDerivedSource(
            id: memory.id,
            createdAt: memory.createdAt,
            ocrNormalized: OrganizationOCRNormalizer.normalize(memory.ocrText),
            visualLabels: memory.visualLabels,
            facets: memory.visualFacets,
            featurePrintData: printData,
            profileMatchScore: profileMatch,
            profileTitles: matchingTitles,
            rawOCR: memory.ocrText
        )
    }

    private func profileMatchScore(for memory: ScreenshotMemory, titles: [String]) -> Double {
        let ocr = OrganizationOCRNormalizer.normalize(memory.ocrText).lowercased()
        guard !ocr.isEmpty else { return 0 }
        var best = 0.0
        for title in titles {
            let tokens = title.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 3 }
            guard !tokens.isEmpty else { continue }
            let hits = tokens.filter { ocr.contains($0) }.count
            best = max(best, Double(hits) / Double(tokens.count))
        }
        return best
    }

    private func matchingProfileTitles(for memory: ScreenshotMemory, titles: [String]) -> [String] {
        let ocr = OrganizationOCRNormalizer.normalize(memory.ocrText).lowercased()
        let labels = Set(memory.visualLabels)
        return titles.filter { title in
            let t = title.lowercased()
            if !ocr.isEmpty, t.split(separator: " ").contains(where: { ocr.contains($0) && $0.count >= 3 }) {
                return true
            }
            // Soft visual assist — never invent titles from labels alone.
            if t.contains("japan"), labels.contains(where: { ["airplane", "airport", "city", "building", "landmark"].contains($0) }) {
                return true
            }
            if t.contains("apartment"), labels.contains(where: { ["sofa", "furniture", "chair", "table"].contains($0) }) {
                return true
            }
            return false
        }
    }
}

extension GRDBMemoryRepository {
    func contexts(where sql: String = "1", arguments: StatementArguments = []) async throws -> [ContextCollection] {
        try await database.dbPool.read { db in
            let records = try CollectionRecord.fetchAll(
                db,
                sql: "SELECT * FROM context_collection WHERE \(sql)",
                arguments: arguments
            )
            return try records.compactMap { record in
                guard let id = UUID(uuidString: record.id) else { return nil }
                return try Self.makeContextCollection(
                    from: record,
                    id: ContextCollectionID(id),
                    db: db
                )
            }
        }
    }

    static func makeContextCollection(
        from record: CollectionRecord,
        id: ContextCollectionID,
        db: Database
    ) throws -> ContextCollection? {
        guard let kind = ContextCollectionKind(rawValue: record.kind) else { return nil }
        let previews = try String.fetchAll(db, sql: """
            SELECT screenshot.preview_symbol FROM screenshot_context
            JOIN screenshot ON screenshot.id = screenshot_context.screenshot_id
            WHERE screenshot_context.collection_id = ?
              AND screenshot.is_removed_from_app = 0
              AND screenshot.access_state = 'available'
            ORDER BY screenshot.created_at DESC, screenshot.imported_at DESC, screenshot.id DESC
            LIMIT 3
            """, arguments: [record.id])
        let photoPreviews = try String.fetchAll(db, sql: """
            SELECT screenshot.photos_local_identifier FROM screenshot_context
            JOIN screenshot ON screenshot.id = screenshot_context.screenshot_id
            WHERE screenshot_context.collection_id = ?
              AND screenshot.access_state = 'available'
              AND screenshot.photos_local_identifier IS NOT NULL
            ORDER BY screenshot.created_at DESC, screenshot.imported_at DESC, screenshot.id DESC
            LIMIT 3
            """, arguments: [record.id])
        let count = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM screenshot_context
                JOIN screenshot ON screenshot.id = screenshot_context.screenshot_id
                WHERE screenshot_context.collection_id = ?
                  AND screenshot.is_removed_from_app = 0
                  AND screenshot.access_state = 'available'
                """,
            arguments: [record.id]
        ) ?? 0
        return ContextCollection(
            id: id,
            kind: kind,
            title: record.title,
            isPinned: record.isPinned,
            isArchived: record.isArchived,
            sortOrder: record.sortOrder,
            memberCount: count,
            memberPreviewSymbols: previews,
            memberPreviewLocalIdentifiers: photoPreviews,
            badgeEmoji: record.badgeEmoji,
            badgeColor: record.badgeColor,
            insight: record.insight
        )
    }

    func beginUndoableMutation() async throws -> MockUndoToken {
        pendingUndo = nil
        let snapshot = try await database.dbPool.read { db in try Self.snapshot(db: db) }
        let token = MockUndoToken()
        pendingUndo = (token, snapshot)
        return token
    }

    /// User corrections lock the screenshot against future automatic reassignment.
    static func lockOrganization(ids: [String], db: Database) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            try db.execute(
                sql: """
                    UPDATE screenshot
                    SET organize_locked = 1,
                        organize_status = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [OrganizeStatus.locked.rawValue, Date(), id]
            )
        }
    }

    /// Needs Review inbox invariant:
    /// - Any normal Collection membership → leave Needs Review
    /// - Zero normal memberships → ensure Needs Review (`source = user`)
    static func applyNeedsReviewInvariant(forScreenshotIDs ids: [String], db: Database) throws {
        guard !ids.isEmpty else { return }
        guard let inbox = try CollectionRecord.fetchOne(
            db,
            sql: "SELECT * FROM context_collection WHERE kind = 'unassigned'"
        ) else { return }

        let inboxBase = try Int.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(position), -1) FROM screenshot_context WHERE collection_id = ?",
            arguments: [inbox.id]
        ) ?? -1
        var nextInboxPosition = inboxBase + 1

        for shotID in ids {
            let normalCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM screenshot_context AS sc
                JOIN context_collection AS c ON c.id = sc.collection_id
                WHERE sc.screenshot_id = ? AND c.kind != 'unassigned'
                """, arguments: [shotID]) ?? 0

            if normalCount == 0 {
                let already = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM screenshot_context
                    WHERE screenshot_id = ? AND collection_id = ?
                    """, arguments: [shotID, inbox.id]) ?? 0
                if already == 0 {
                    try db.execute(sql: """
                        INSERT INTO screenshot_context
                        (screenshot_id, collection_id, source, created_at, position)
                        VALUES (?, ?, 'user', ?, ?)
                        """, arguments: [shotID, inbox.id, Date(), nextInboxPosition])
                    nextInboxPosition += 1
                } else {
                    try db.execute(sql: """
                        UPDATE screenshot_context SET source = 'user'
                        WHERE screenshot_id = ? AND collection_id = ?
                        """, arguments: [shotID, inbox.id])
                }
            } else {
                try db.execute(sql: """
                    DELETE FROM screenshot_context
                    WHERE screenshot_id = ? AND collection_id = ?
                    """, arguments: [shotID, inbox.id])
            }
        }
    }

    static func removeScreenshots(_ ids: [String], db: Database) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            try db.execute(sql: "DELETE FROM screenshot_fts WHERE screenshot_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM screenshot WHERE id = ?", arguments: [id])
        }
        for record in try DuplicateGroupRecord.fetchAll(db) {
            let remaining = ScreenshotRecord.array(record.screenshotIDsJSON).filter { !ids.contains($0) }
            if remaining.count < 2 {
                try record.delete(db)
            } else {
                var updated = record
                updated.screenshotIDsJSON = ScreenshotRecord.json(remaining)
                if let keep = updated.recommendedKeepID, ids.contains(keep) {
                    updated.recommendedKeepID = remaining.first
                }
                try updated.update(db)
            }
        }
    }

    struct Snapshot: Codable {
        var screenshots: [ScreenshotRecord]
        var collections: [CollectionRecord]
        var memberships: [MembershipRecord]
        var groups: [DuplicateGroupRecord]
        var meta: [AppMetaRecord]
        var ftsRows: [FTSSnapshotRow]

        init(
            screenshots: [ScreenshotRecord],
            collections: [CollectionRecord],
            memberships: [MembershipRecord],
            groups: [DuplicateGroupRecord],
            meta: [AppMetaRecord],
            ftsRows: [FTSSnapshotRow]
        ) {
            self.screenshots = screenshots
            self.collections = collections
            self.memberships = memberships
            self.groups = groups
            self.meta = meta
            self.ftsRows = ftsRows
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            screenshots = try container.decode([ScreenshotRecord].self, forKey: .screenshots)
            collections = try container.decode([CollectionRecord].self, forKey: .collections)
            memberships = try container.decode([MembershipRecord].self, forKey: .memberships)
            groups = try container.decode([DuplicateGroupRecord].self, forKey: .groups)
            meta = try container.decode([AppMetaRecord].self, forKey: .meta)
            ftsRows = try container.decodeIfPresent([FTSSnapshotRow].self, forKey: .ftsRows) ?? []
        }
    }

    struct FTSSnapshotRow: Codable {
        var screenshotID: String
        var ocrText: String
        var titleBlob: String
    }

    static func snapshot(db: Database) throws -> String {
        let ftsRows = try Row.fetchAll(db, sql: "SELECT screenshot_id, ocr_text, title_blob FROM screenshot_fts").map { row in
            FTSSnapshotRow(
                screenshotID: row["screenshot_id"],
                ocrText: row["ocr_text"] ?? "",
                titleBlob: row["title_blob"] ?? ""
            )
        }
        let value = Snapshot(
            screenshots: try ScreenshotRecord.fetchAll(db),
            collections: try CollectionRecord.fetchAll(db),
            memberships: try MembershipRecord.fetchAll(db),
            groups: try DuplicateGroupRecord.fetchAll(db),
            meta: try AppMetaRecord.fetchAll(db),
            ftsRows: ftsRows
        )
        return String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }

    static func restore(snapshot: String, db: Database) throws {
        let decoder = JSONDecoder()
        let value = try decoder.decode(Snapshot.self, from: Data(snapshot.utf8))
        for table in ["screenshot_context", "duplicate_group", "screenshot_fts", "screenshot", "context_collection", "app_meta"] {
            try db.execute(sql: "DELETE FROM \(table)")
        }
        for record in value.screenshots { try record.insert(db) }
        for record in value.collections { try record.insert(db) }
        for record in value.memberships { try record.insert(db) }
        for record in value.groups { try record.insert(db) }
        for record in value.meta { try record.insert(db) }
        for row in value.ftsRows {
            try db.execute(
                sql: """
                    INSERT INTO screenshot_fts(screenshot_id, ocr_text, title_blob)
                    VALUES (?, ?, ?)
                    """,
                arguments: [row.screenshotID, row.ocrText, row.titleBlob]
            )
        }
    }

    static func validatedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.underlying(message: "Name is required") }
        return trimmed
    }

    static func searchTokens(_ query: String) -> [String] {
        SearchFTSQuery.tokens(from: query)
    }

    static func contains(_ text: String, _ needle: String) -> Bool {
        text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

private extension String {
    var normalizedForSearch: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    }
}
