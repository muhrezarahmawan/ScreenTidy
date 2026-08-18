import Foundation
import GRDB

extension GRDBMemoryRepository: OrganizationPersisting {
    func markPendingOrganize(id: ScreenshotMemoryID) async throws {
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshot
                    SET organize_status = ?,
                        analysis_status = 'pendingOrganize',
                        updated_at = ?
                    WHERE id = ?
                      AND is_removed_from_app = 0
                      AND organize_locked = 0
                      AND organize_status NOT IN ('ready', 'locked')
                    """,
                arguments: [OrganizeStatus.pending.rawValue, Date(), id.rawValue.uuidString]
            )
        }
    }

    func claimNextOrganizeJob(resolverVersion: Int, now: Date) async throws -> ScreenshotMemoryID? {
        _ = resolverVersion
        // Soft backoff so pendingNetwork does not hot-loop at 60s timeouts when LAN is down.
        let pendingNetworkEligibleBefore = now.addingTimeInterval(-15)
        return try await database.dbPool.write { db -> ScreenshotMemoryID? in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id FROM screenshot
                    WHERE is_removed_from_app = 0
                      AND access_state = 'available'
                      AND organize_locked = 0
                      AND organize_status IN ('pending', 'pendingNetwork', 'failed', 'idle')
                      AND (
                            organize_status IN ('pending', 'failed')
                         OR (organize_status = 'pendingNetwork' AND updated_at <= ?)
                         OR (
                                organize_status = 'idle'
                            AND ocr_status IN ('completed', 'failed')
                            AND visual_status IN ('completed', 'failed', 'inaccessible')
                         )
                      )
                    ORDER BY
                        CASE organize_status
                            WHEN 'pending' THEN 0
                            WHEN 'pendingNetwork' THEN 1
                            WHEN 'failed' THEN 2
                            ELSE 3
                        END,
                        created_at DESC,
                        imported_at DESC,
                        id DESC
                    LIMIT 1
                    """,
                arguments: [pendingNetworkEligibleBefore]
            )
            guard let idString = row?["id"] as String?,
                  let uuid = UUID(uuidString: idString)
            else {
                return nil
            }
            try db.execute(
                sql: """
                    UPDATE screenshot
                    SET organize_status = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [OrganizeStatus.pending.rawValue, now, idString]
            )
            return ScreenshotMemoryID(uuid)
        }
    }

    func fetchOrganizationEligibleCollections() async throws -> [CollectionResolver.EligibleCollection] {
        try await database.dbPool.read { db in
            let collections = try CollectionRecord.fetchAll(
                db,
                sql: "SELECT * FROM context_collection WHERE is_archived = 0"
            )
            let aliases = try Row.fetchAll(db, sql: "SELECT collection_id, normalized_alias FROM context_alias")
            var aliasMap: [String: [String]] = [:]
            for row in aliases {
                let collectionID: String = row["collection_id"]
                let alias: String = row["normalized_alias"]
                aliasMap[collectionID, default: []].append(alias)
            }
            let profiles = try Row.fetchAll(db, sql: "SELECT * FROM collection_context_profile")
            var profileMap: [String: Row] = [:]
            for row in profiles {
                profileMap[row["collection_id"]] = row
            }
            return collections.compactMap { record in
                guard let uuid = UUID(uuidString: record.id),
                      let kind = ContextCollectionKind(rawValue: record.kind)
                else { return nil }
                let profile = profileMap[record.id]
                return CollectionResolver.EligibleCollection(
                    id: ContextCollectionID(uuid),
                    title: record.title,
                    normalizedTitle: record.normalizedTitle,
                    kind: kind,
                    createdBy: record.createdBy,
                    aliases: aliasMap[record.id] ?? [],
                    keyEntities: Self.decodeStringArray(profile?["key_entities_json"]),
                    keyTerms: Self.decodeStringArray(profile?["key_terms_json"]),
                    visualDescriptors: Self.decodeStringArray(profile?["visual_descriptors_json"]),
                    dateRangeStart: profile?["date_range_start"],
                    dateRangeEnd: profile?["date_range_end"]
                )
            }
        }
    }

    func applyResolverDecision(
        screenshotID: ScreenshotMemoryID,
        decision: ResolverDecision,
        understanding: ScreenshotUnderstanding,
        policy: ResolverPolicy,
        fingerprint: String
    ) async throws {
        try await database.dbPool.write { db in
            let id = screenshotID.rawValue.uuidString
            guard let record = try ScreenshotRecord.fetchOne(db, key: id) else { return }
            if record.organizeLocked {
                try db.execute(
                    sql: "UPDATE screenshot SET organize_status = ? WHERE id = ?",
                    arguments: [OrganizeStatus.locked.rawValue, id]
                )
                return
            }

            // Never alter graph if any source=user membership exists.
            let userMembership = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM screenshot_context
                    WHERE screenshot_id = ? AND source = 'user'
                    """,
                arguments: [id]
            ) ?? 0
            if userMembership > 0 {
                try db.execute(
                    sql: """
                        UPDATE screenshot
                        SET organize_status = ?,
                            organize_locked = 1,
                            organize_resolver_version = ?,
                            organize_content_fingerprint = ?,
                            ai_summary = ?,
                            updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        OrganizeStatus.locked.rawValue,
                        policy.resolverVersion,
                        fingerprint,
                        understanding.summary,
                        Date(),
                        id
                    ]
                )
                return
            }

            switch decision.kind {
            case .needsReview, .skipped:
                try OrganizationSQL.ensureNeedsReviewOnly(screenshotID: id, db: db)
                try db.execute(
                    sql: """
                        UPDATE screenshot
                        SET organize_status = ?,
                            organize_resolver_version = ?,
                            organize_content_fingerprint = ?,
                            ai_summary = ?,
                            analysis_status = 'ready',
                            updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        OrganizeStatus.ready.rawValue,
                        policy.resolverVersion,
                        fingerprint,
                        understanding.summary,
                        Date(),
                        id
                    ]
                )

            case .reuse:
                guard let collectionID = decision.collectionID else { return }
                try OrganizationSQL.attachAI(
                    screenshotID: id,
                    collectionID: collectionID.rawValue.uuidString,
                    confidence: decision.confidence,
                    db: db
                )
                try OrganizationSQL.maybeAddAlias(
                    collectionID: collectionID.rawValue.uuidString,
                    proposedTitle: decision.title,
                    db: db
                )
                try db.execute(
                    sql: """
                        UPDATE screenshot
                        SET organize_status = ?,
                            organize_resolver_version = ?,
                            organize_content_fingerprint = ?,
                            ai_summary = ?,
                            analysis_status = 'ready',
                            updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        OrganizeStatus.ready.rawValue,
                        policy.resolverVersion,
                        fingerprint,
                        understanding.summary,
                        Date(),
                        id
                    ]
                )

            case .create:
                guard let title = decision.title else { return }
                let now = Date()
                let normalized = CollectionResolver.normalizeTitle(title)
                // Find-or-create: never mint a second Collection with the same normalized title
                // (guards concurrent backlog organize races).
                let destinationID: String
                if let existing = try CollectionRecord.fetchOne(
                    db,
                    sql: """
                        SELECT * FROM context_collection
                        WHERE kind != 'unassigned'
                          AND normalized_title = ?
                        ORDER BY created_at ASC, id ASC
                        LIMIT 1
                        """,
                    arguments: [normalized]
                ) {
                    destinationID = existing.id
                    try OrganizationSQL.maybeAddAlias(
                        collectionID: existing.id,
                        proposedTitle: title,
                        db: db
                    )
                } else {
                    let newID = UUID().uuidString
                    do {
                        try CollectionRecord(
                            id: newID,
                            kind: ContextCollectionKind.aiContext.rawValue,
                            title: title,
                            normalizedTitle: normalized,
                            badgeEmoji: decision.emoji,
                            badgeColor: nil,
                            isPinned: false,
                            isArchived: false,
                            sortOrder: (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM context_collection") ?? 0),
                            createdAt: now,
                            updatedAt: now,
                            createdBy: "ai",
                            insight: nil
                        ).insert(db)
                        destinationID = newID
                    } catch {
                        // Concurrent organize may have created the same title first.
                        guard let raced = try CollectionRecord.fetchOne(
                            db,
                            sql: """
                                SELECT * FROM context_collection
                                WHERE kind != 'unassigned'
                                  AND normalized_title = ?
                                ORDER BY created_at ASC, id ASC
                                LIMIT 1
                                """,
                            arguments: [normalized]
                        ) else { throw error }
                        destinationID = raced.id
                        try OrganizationSQL.maybeAddAlias(
                            collectionID: raced.id,
                            proposedTitle: title,
                            db: db
                        )
                    }
                }
                try OrganizationSQL.attachAI(
                    screenshotID: id,
                    collectionID: destinationID,
                    confidence: decision.confidence,
                    db: db
                )
                try db.execute(
                    sql: """
                        UPDATE screenshot
                        SET organize_status = ?,
                            organize_resolver_version = ?,
                            organize_content_fingerprint = ?,
                            ai_summary = ?,
                            analysis_status = 'ready',
                            updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        OrganizeStatus.ready.rawValue,
                        policy.resolverVersion,
                        fingerprint,
                        understanding.summary,
                        now,
                        id
                    ]
                )
            }
        }
    }

    func recordOrganizationRun(
        screenshotID: ScreenshotMemoryID,
        status: OrganizationRunStatus,
        decision: ResolverDecision?,
        understanding: ScreenshotUnderstanding?,
        policy: ResolverPolicy,
        errorCode: String?,
        fingerprint: String?
    ) async throws {
        let candidatesJSON: String?
        if let candidates = decision?.candidates ?? understanding?.candidateCollections,
           let data = try? JSONEncoder().encode(candidates) {
            candidatesJSON = String(data: data, encoding: .utf8)
        } else {
            candidatesJSON = nil
        }
        let understandingJSON: String?
        if let understanding, let data = try? JSONEncoder().encode(understanding) {
            understandingJSON = String(data: data, encoding: .utf8)
        } else {
            understandingJSON = nil
        }
        let scoreJSON: String?
        if let components = decision?.confidenceComponents,
           let data = try? JSONEncoder().encode(components) {
            scoreJSON = String(data: data, encoding: .utf8)
        } else {
            scoreJSON = nil
        }
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO organization_run (
                        id, screenshot_id, started_at, finished_at, provider, status,
                        resolver_version, decision, decision_collection_id, decision_title,
                        assign_threshold, create_threshold, max_candidate_confidence,
                        reason, candidates_json, error_code, request_fingerprint,
                        understanding_json, score_components_json, batch_id, normalized_ocr_preview
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    UUID().uuidString,
                    screenshotID.rawValue.uuidString,
                    Date(),
                    Date(),
                    understanding?.provider,
                    status.rawValue,
                    policy.resolverVersion,
                    decision?.kind.rawValue,
                    decision?.collectionID?.rawValue.uuidString,
                    decision?.title,
                    policy.assignThreshold,
                    policy.createThreshold,
                    decision?.confidence ?? understanding?.candidateCollections.map(\.confidence).max(),
                    decision?.reason,
                    candidatesJSON,
                    errorCode,
                    fingerprint,
                    understandingJSON,
                    scoreJSON,
                    decision?.batchID,
                    understanding?.normalizedOCRPreview
                ]
            )
        }
    }

    func setOrganizeStatus(_ status: OrganizeStatus, id: ScreenshotMemoryID, errorCode: String?) async throws {
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshot
                    SET organize_status = ?,
                        ocr_last_error = COALESCE(?, ocr_last_error),
                        updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [status.rawValue, errorCode, Date(), id.rawValue.uuidString]
            )
        }
    }

    func lockOrganization(ids: Set<ScreenshotMemoryID>) async throws {
        guard !ids.isEmpty else { return }
        let strings = ids.map { $0.rawValue.uuidString }
        try await database.dbPool.write { db in
            for id in strings {
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
    }

    func fetchOrganizationDebugSnapshots(limit: Int) async throws -> [OrganizationDebugSnapshot] {
        try await database.dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM screenshot
                    WHERE is_removed_from_app = 0
                    ORDER BY updated_at DESC, imported_at DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            )
            var snapshots: [OrganizationDebugSnapshot] = []
            for row in rows {
                guard let record = try? ScreenshotRecord(row: row),
                      let memory = record.memory()
                else { continue }
                let latest = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT * FROM organization_run
                        WHERE screenshot_id = ?
                        ORDER BY started_at DESC
                        LIMIT 1
                        """,
                    arguments: [record.id]
                )
                let membershipRows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT c.title, sc.source
                        FROM screenshot_context sc
                        JOIN context_collection c ON c.id = sc.collection_id
                        WHERE sc.screenshot_id = ?
                        """,
                    arguments: [record.id]
                )
                let candidates: [UnderstandingCandidate]
                if let json: String = latest?["candidates_json"],
                   let data = json.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([UnderstandingCandidate].self, from: data) {
                    candidates = decoded
                } else {
                    candidates = []
                }
                var understanding: ScreenshotUnderstanding?
                if let json: String = latest?["understanding_json"],
                   let data = json.data(using: .utf8) {
                    understanding = try? JSONDecoder().decode(ScreenshotUnderstanding.self, from: data)
                }
                var components: ResolverConfidenceComponents?
                if let json: String = latest?["score_components_json"],
                   let data = json.data(using: .utf8) {
                    components = try? JSONDecoder().decode(ResolverConfidenceComponents.self, from: data)
                }
                let evalLabel = try String.fetchOne(
                    db,
                    sql: "SELECT label FROM organization_eval WHERE screenshot_id = ?",
                    arguments: [record.id]
                ).flatMap(OrganizationEvalLabel.init(rawValue:))
                let ocr = memory.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let batchID: String? = latest?["batch_id"]
                let batchCount = batchID.map { $0.split(separator: ",").count }
                snapshots.append(
                    OrganizationDebugSnapshot(
                        id: memory.id,
                        titleHint: String(ocr.prefix(48)).isEmpty ? memory.previewSymbol : String(ocr.prefix(48)),
                        previewSymbol: memory.previewSymbol,
                        photosLocalIdentifier: memory.photosLocalIdentifier,
                        ocrAvailable: !ocr.isEmpty,
                        ocrPreview: ocr.isEmpty ? nil : String(ocr.prefix(120)),
                        normalizedOCRPreview: latest?["normalized_ocr_preview"] ?? understanding?.normalizedOCRPreview,
                        organizeStatus: OrganizeStatus(rawValue: record.organizeStatus) ?? .idle,
                        resolverVersion: record.organizeResolverVersion ?? latest?["resolver_version"],
                        locked: record.organizeLocked,
                        decisionKind: (latest?["decision"] as String?).flatMap(ResolverDecisionKind.init(rawValue:)),
                        decisionTitle: latest?["decision_title"],
                        decisionCollectionID: (latest?["decision_collection_id"] as String?)
                            .flatMap(UUID.init(uuidString:))
                            .map(ContextCollectionID.init),
                        maxConfidence: latest?["max_candidate_confidence"],
                        assignThreshold: latest?["assign_threshold"],
                        createThreshold: latest?["create_threshold"],
                        reason: latest?["reason"],
                        candidates: candidates,
                        memberships: membershipRows.map { (title: $0["title"], source: $0["source"]) },
                        lastError: latest?["error_code"],
                        provider: latest?["provider"] ?? understanding?.provider,
                        typeFacets: understanding?.typeFacets ?? [],
                        entities: understanding?.entities ?? [],
                        visualDescriptors: understanding?.visualDescriptors ?? [],
                        confidenceComponents: components,
                        batchID: batchID,
                        batchMemberCount: batchCount,
                        profilesConsidered: candidates.map(\.title),
                        proposedEmoji: understanding?.proposedNewCollection?.emoji,
                        evalLabel: evalLabel,
                        promptVersion: understanding?.promptVersion,
                        schemaVersion: understanding?.schemaVersion
                    )
                )
            }
            return snapshots
        }
    }

    func fetchOrganizationMetrics() async throws -> OrganizationMetrics {
        try await database.dbPool.read { db in
            func count(_ status: String) throws -> Int {
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM screenshot WHERE is_removed_from_app = 0 AND organize_status = ?",
                    arguments: [status]
                ) ?? 0
            }
            return OrganizationMetrics(
                pending: try count(OrganizeStatus.pending.rawValue),
                pendingNetwork: try count(OrganizeStatus.pendingNetwork.rawValue),
                ready: try count(OrganizeStatus.ready.rawValue),
                failed: try count(OrganizeStatus.failed.rawValue),
                locked: try count(OrganizeStatus.locked.rawValue),
                skippedNoConsent: try count(OrganizeStatus.skippedNoConsent.rawValue)
            )
        }
    }

    func requeueSkippedConsentJobs() async throws {
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshot
                    SET organize_status = ?, updated_at = ?
                    WHERE organize_status = ?
                      AND organize_locked = 0
                      AND is_removed_from_app = 0
                    """,
                arguments: [
                    OrganizeStatus.pending.rawValue,
                    Date(),
                    OrganizeStatus.skippedNoConsent.rawValue
                ]
            )
        }
    }

    func requeueSingleOrganize(id: ScreenshotMemoryID) async throws {
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshot
                    SET organize_status = ?,
                        organize_content_fingerprint = NULL,
                        updated_at = ?
                    WHERE id = ?
                      AND is_removed_from_app = 0
                      AND organize_locked = 0
                    """,
                arguments: [
                    OrganizeStatus.pending.rawValue,
                    Date().addingTimeInterval(-60),
                    id.rawValue.uuidString
                ]
            )
        }
    }

    func fetchOrganizeStatus(id: ScreenshotMemoryID) async throws -> OrganizeStatus? {
        try await database.dbPool.read { db in
            let raw = try String.fetchOne(
                db,
                sql: "SELECT organize_status FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
            return raw.flatMap(OrganizeStatus.init(rawValue:))
        }
    }

    func fetchOrganizeResolverVersion(id: ScreenshotMemoryID) async throws -> Int? {
        try await database.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT organize_resolver_version FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
    }

    func fetchPendingOrganizeMembers(limit: Int) async throws -> [OrganizationClusterMemberSnapshot] {
        try await database.dbPool.read { db in
            let records = try ScreenshotRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM screenshot
                    WHERE is_removed_from_app = 0
                      AND organize_locked = 0
                      AND organize_status IN ('pending', 'pendingNetwork', 'failed', 'idle')
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            )
            return records.compactMap { record in
                guard let memory = record.memory() else { return nil }
                return OrganizationClusterMemberSnapshot(
                    id: memory.id,
                    createdAt: memory.createdAt,
                    ocrText: memory.ocrText,
                    visualLabels: memory.visualLabels,
                    visualFacets: memory.visualFacets,
                    featurePrintData: record.featurePrint,
                    photosLocalIdentifier: memory.photosLocalIdentifier
                )
            }
        }
    }

    func cacheUnderstanding(fingerprint: String, understanding: ScreenshotUnderstanding) async throws {
        guard let data = try? JSONEncoder().encode(understanding),
              let json = String(data: data, encoding: .utf8)
        else { return }
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO understanding_cache (fingerprint, understanding_json, created_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(fingerprint) DO UPDATE SET
                        understanding_json = excluded.understanding_json,
                        created_at = excluded.created_at
                    """,
                arguments: [fingerprint, json, Date()]
            )
        }
    }

    func fetchCachedUnderstanding(fingerprint: String) async throws -> ScreenshotUnderstanding? {
        try await database.dbPool.read { db in
            guard let json = try String.fetchOne(
                db,
                sql: "SELECT understanding_json FROM understanding_cache WHERE fingerprint = ?",
                arguments: [fingerprint]
            ),
            let data = json.data(using: .utf8)
            else { return nil }
            return try? JSONDecoder().decode(ScreenshotUnderstanding.self, from: data)
        }
    }

    func refreshCollectionProfile(for collectionID: ContextCollectionID?, createdTitle: String?) async throws {
        try await database.dbPool.write { db in
            let idString: String?
            if let collectionID {
                idString = collectionID.rawValue.uuidString
            } else if let createdTitle {
                idString = try String.fetchOne(
                    db,
                    sql: """
                        SELECT id FROM context_collection
                        WHERE normalized_title = ?
                        ORDER BY created_at DESC LIMIT 1
                        """,
                    arguments: [CollectionResolver.normalizeTitle(createdTitle)]
                )
            } else {
                idString = nil
            }
            guard let idString else { return }

            let memberOCR = try String.fetchAll(
                db,
                sql: """
                    SELECT screenshot.ocr_text FROM screenshot_context sc
                    JOIN screenshot ON screenshot.id = sc.screenshot_id
                    WHERE sc.collection_id = ?
                      AND screenshot.ocr_text IS NOT NULL
                    ORDER BY screenshot.created_at DESC
                    LIMIT 12
                    """,
                arguments: [idString]
            )
            var entityCounts: [String: Int] = [:]
            for ocr in memberOCR {
                for token in OrganizationOCRNormalizer.normalize(ocr)
                    .lowercased()
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map(String.init)
                    .filter({ $0.count >= 4 }) {
                    entityCounts[token, default: 0] += 1
                }
            }
            let keyTerms = entityCounts.sorted { $0.value > $1.value }.prefix(12).map(\.key)
            let dates = try Row.fetchOne(
                db,
                sql: """
                    SELECT MIN(screenshot.created_at) AS start_at, MAX(screenshot.created_at) AS end_at
                    FROM screenshot_context sc
                    JOIN screenshot ON screenshot.id = sc.screenshot_id
                    WHERE sc.collection_id = ?
                    """,
                arguments: [idString]
            )
            let entitiesJSON = String(data: (try? JSONEncoder().encode(Array(keyTerms.prefix(8)))) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
            let termsJSON = String(data: (try? JSONEncoder().encode(Array(keyTerms))) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
            try db.execute(
                sql: """
                    INSERT INTO collection_context_profile (
                        collection_id, key_entities_json, key_terms_json, visual_descriptors_json,
                        date_range_start, date_range_end, profile_version, updated_at
                    ) VALUES (?, ?, ?, '[]', ?, ?, 1, ?)
                    ON CONFLICT(collection_id) DO UPDATE SET
                        key_entities_json = excluded.key_entities_json,
                        key_terms_json = excluded.key_terms_json,
                        date_range_start = excluded.date_range_start,
                        date_range_end = excluded.date_range_end,
                        profile_version = collection_context_profile.profile_version + 1,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    idString,
                    entitiesJSON,
                    termsJSON,
                    dates?["start_at"] as Date?,
                    dates?["end_at"] as Date?,
                    Date()
                ]
            )
        }
    }

    func requeueNeedsReviewForResolver(version: Int) async throws -> Int {
        try await database.dbPool.write { db in
            let inbox = try CollectionRecord.fetchOne(
                db,
                sql: "SELECT * FROM context_collection WHERE kind = 'unassigned'"
            )
            guard let inbox else { return 0 }
            let ids = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT screenshot.id FROM screenshot
                    JOIN screenshot_context sc ON sc.screenshot_id = screenshot.id
                    WHERE screenshot.is_removed_from_app = 0
                      AND screenshot.organize_locked = 0
                      AND screenshot.access_state = 'available'
                      AND (
                            sc.collection_id = ?
                         OR screenshot.organize_status IN ('failed', 'pendingNetwork', 'skippedNoConsent')
                         OR screenshot.organize_resolver_version IS NULL
                         OR screenshot.organize_resolver_version < ?
                      )
                      AND NOT EXISTS (
                            SELECT 1 FROM screenshot_context sc2
                            WHERE sc2.screenshot_id = screenshot.id AND sc2.source = 'user'
                              AND sc2.collection_id != ?
                      )
                    """,
                arguments: [inbox.id, version, inbox.id]
            )
            for id in ids {
                try db.execute(
                    sql: """
                        UPDATE screenshot
                        SET organize_status = ?,
                            organize_resolver_version = NULL,
                            organize_content_fingerprint = NULL,
                            updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [OrganizeStatus.pending.rawValue, Date(), id]
                )
            }
            return ids.count
        }
    }

    func setOrganizationEvalLabel(screenshotID: ScreenshotMemoryID, label: OrganizationEvalLabel?) async throws {
        try await database.dbPool.write { db in
            if let label {
                try db.execute(
                    sql: """
                        INSERT INTO organization_eval (screenshot_id, label, updated_at)
                        VALUES (?, ?, ?)
                        ON CONFLICT(screenshot_id) DO UPDATE SET label = excluded.label, updated_at = excluded.updated_at
                        """,
                    arguments: [screenshotID.rawValue.uuidString, label.rawValue, Date()]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM organization_eval WHERE screenshot_id = ?",
                    arguments: [screenshotID.rawValue.uuidString]
                )
            }
        }
    }

    func fetchOrganizationEvalStats() async throws -> OrganizationEvalStats {
        try await database.dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT e.label, r.decision
                    FROM organization_eval e
                    LEFT JOIN (
                        SELECT screenshot_id, decision, MAX(started_at) AS started_at
                        FROM organization_run
                        GROUP BY screenshot_id
                    ) latest ON latest.screenshot_id = e.screenshot_id
                    LEFT JOIN organization_run r
                        ON r.screenshot_id = latest.screenshot_id AND r.started_at = latest.started_at
                    """
            )
            var stats = OrganizationEvalStats(
                totalEvaluated: 0, autoFiled: 0, correct: 0, wrongFile: 0,
                shouldBeNeedsReview: 0, wrongName: 0, needsReviewDecisions: 0,
                reuseCorrect: 0, createCorrect: 0
            )
            for row in rows {
                stats.totalEvaluated += 1
                let label = OrganizationEvalLabel(rawValue: row["label"] as String? ?? "") ?? .correct
                let decision = row["decision"] as String?
                if decision == ResolverDecisionKind.reuse.rawValue || decision == ResolverDecisionKind.create.rawValue {
                    stats.autoFiled += 1
                }
                if decision == ResolverDecisionKind.needsReview.rawValue {
                    stats.needsReviewDecisions += 1
                }
                switch label {
                case .correct:
                    stats.correct += 1
                    if decision == ResolverDecisionKind.reuse.rawValue { stats.reuseCorrect += 1 }
                    if decision == ResolverDecisionKind.create.rawValue { stats.createCorrect += 1 }
                case .wrongCollection:
                    stats.wrongFile += 1
                case .shouldBeNeedsReview:
                    stats.shouldBeNeedsReview += 1
                case .wrongCollectionName:
                    stats.wrongName += 1
                }
            }
            return stats
        }
    }

    func fetchCloudRequestCount() async throws -> Int {
        try await database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT request_count FROM organization_gateway_stats WHERE id = 1") ?? 0
        }
    }

    func incrementCloudRequestCount() async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: "UPDATE organization_gateway_stats SET request_count = request_count + 1 WHERE id = 1")
        }
    }

    private static func decodeStringArray(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }
}

enum OrganizationSQL {
    static func attachAI(
        screenshotID: String,
        collectionID: String,
        confidence: Double?,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                DELETE FROM screenshot_context
                WHERE screenshot_id = ?
                  AND collection_id IN (
                      SELECT id FROM context_collection WHERE kind = 'unassigned'
                  )
                """,
            arguments: [screenshotID]
        )
        let exists = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM screenshot_context
                WHERE screenshot_id = ? AND collection_id = ?
                """,
            arguments: [screenshotID, collectionID]
        ) ?? 0
        if exists == 0 {
            try MembershipRecord(
                screenshotID: screenshotID,
                collectionID: collectionID,
                source: "ai",
                confidence: confidence,
                createdAt: Date(),
                position: 0
            ).insert(db)
        } else {
            try db.execute(
                sql: """
                    UPDATE screenshot_context
                    SET source = 'ai', confidence = ?
                    WHERE screenshot_id = ? AND collection_id = ?
                    """,
                arguments: [confidence, screenshotID, collectionID]
            )
        }
    }

    static func ensureNeedsReviewOnly(screenshotID: String, db: Database) throws {
        try GRDBMemoryRepository.applyNeedsReviewInvariant(forScreenshotIDs: [screenshotID], db: db)
    }

    static func maybeAddAlias(collectionID: String, proposedTitle: String?, db: Database) throws {
        guard let proposedTitle else { return }
        let normalized = CollectionResolver.normalizeTitle(proposedTitle)
        guard !normalized.isEmpty else { return }
        guard let collection = try CollectionRecord.fetchOne(db, key: collectionID) else { return }
        guard normalized != collection.normalizedTitle else { return }
        let similarity = CollectionResolver.similarity(normalized, collection.normalizedTitle)
        guard similarity >= 0.90 else { return }
        let existing = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM context_alias
                WHERE collection_id = ? AND normalized_alias = ?
                """,
            arguments: [collectionID, normalized]
        ) ?? 0
        guard existing == 0 else { return }
        try db.execute(
            sql: """
                INSERT INTO context_alias (id, collection_id, alias_title, normalized_alias, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
            arguments: [UUID().uuidString, collectionID, proposedTitle, normalized, Date()]
        )
    }
}
