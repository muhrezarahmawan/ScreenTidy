import Foundation
import GRDB

/// Owns ScreenTidy's SQLite connection pool and schema migrations.
final class AppDatabase: @unchecked Sendable {
    let dbPool: any DatabaseWriter

    init(path: String) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: path, configuration: config)
        try Self.migrator.migrate(pool)
        dbPool = pool
    }

    private init(writer: any DatabaseWriter) throws {
        try Self.migrator.migrate(writer)
        dbPool = writer
    }

    static func open(path: String) throws -> AppDatabase {
        try AppDatabase(path: path)
    }

    /// In-memory DB for unit tests. Foreign keys enabled.
    static func makeEmptyInMemory() throws -> AppDatabase {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(configuration: config)
        return try AppDatabase(writer: queue)
    }

    static var defaultPath: String {
        get throws {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return support
                .appendingPathComponent("ScreenTidy", isDirectory: true)
                .appendingPathComponent("screentidy.sqlite")
                .path
        }
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = false
        #endif

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE screenshot (
                    id TEXT PRIMARY KEY NOT NULL,
                    photos_local_identifier TEXT UNIQUE,
                    created_at DATETIME,
                    imported_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL,
                    is_favorite INTEGER NOT NULL DEFAULT 0,
                    width INTEGER,
                    height INTEGER,
                    analysis_status TEXT NOT NULL DEFAULT 'ready'
                        CHECK (analysis_status IN ('pendingOCR', 'pendingOrganize', 'ready', 'failed', 'excluded')),
                    is_removed_from_app INTEGER NOT NULL DEFAULT 0,
                    removed_at DATETIME,
                    preview_symbol TEXT NOT NULL DEFAULT 'photo',
                    ocr_text TEXT,
                    summary TEXT,
                    facet_keys_json TEXT NOT NULL DEFAULT '[]',
                    entity_labels_json TEXT NOT NULL DEFAULT '[]',
                    visual_labels_json TEXT NOT NULL DEFAULT '[]',
                    semantic_keywords_json TEXT NOT NULL DEFAULT '[]'
                );
                CREATE INDEX screenshot_created_at ON screenshot(created_at);

                CREATE TABLE context_collection (
                    id TEXT PRIMARY KEY NOT NULL,
                    kind TEXT NOT NULL CHECK (kind IN ('aiContext', 'userContext', 'unassigned')),
                    title TEXT NOT NULL,
                    normalized_title TEXT NOT NULL,
                    badge_emoji TEXT,
                    is_pinned INTEGER NOT NULL DEFAULT 0,
                    is_archived INTEGER NOT NULL DEFAULT 0,
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL,
                    created_by TEXT NOT NULL DEFAULT 'ai' CHECK (created_by IN ('ai', 'user')),
                    insight TEXT
                );
                CREATE UNIQUE INDEX one_unassigned_context
                    ON context_collection(kind) WHERE kind = 'unassigned';
                CREATE INDEX context_collection_kind ON context_collection(kind);

                CREATE TABLE screenshot_context (
                    screenshot_id TEXT NOT NULL REFERENCES screenshot(id) ON DELETE CASCADE,
                    collection_id TEXT NOT NULL REFERENCES context_collection(id) ON DELETE CASCADE,
                    source TEXT NOT NULL DEFAULT 'ai',
                    confidence REAL,
                    created_at DATETIME NOT NULL,
                    position INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (screenshot_id, collection_id)
                );
                CREATE INDEX screenshot_context_collection_id ON screenshot_context(collection_id);

                CREATE TABLE duplicate_group (
                    id TEXT PRIMARY KEY NOT NULL,
                    screenshot_ids_json TEXT NOT NULL,
                    recommended_keep_id TEXT
                );

                CREATE TABLE app_meta (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                );

                -- Foundation only. Sprint 5/6 will populate this from OCR and title changes.
                CREATE VIRTUAL TABLE screenshot_fts USING fts5(
                    screenshot_id UNINDEXED,
                    ocr_text,
                    title_blob,
                    tokenize='porter unicode61'
                );
                """)
        }
        migrator.registerMigration("v2_photos") { db in
            try db.execute(sql: """
                ALTER TABLE screenshot ADD COLUMN source TEXT NOT NULL DEFAULT 'fixture'
                    CHECK (source IN ('fixture', 'photos'));
                ALTER TABLE screenshot ADD COLUMN access_state TEXT NOT NULL DEFAULT 'available'
                    CHECK (access_state IN ('available', 'inaccessible'));
                CREATE UNIQUE INDEX screenshot_photos_local_identifier_unique
                    ON screenshot(photos_local_identifier)
                    WHERE photos_local_identifier IS NOT NULL;
                CREATE INDEX screenshot_available_created_at
                    ON screenshot(access_state, created_at);
                """)
        }

        migrator.registerMigration("v3_ocr") { db in
            try db.execute(sql: """
                ALTER TABLE screenshot ADD COLUMN ocr_status TEXT NOT NULL DEFAULT 'completed'
                    CHECK (ocr_status IN ('pending', 'processing', 'completed', 'failed', 'inaccessible'));
                ALTER TABLE screenshot ADD COLUMN ocr_version INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE screenshot ADD COLUMN ocr_language TEXT;
                ALTER TABLE screenshot ADD COLUMN ocr_attempt_count INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE screenshot ADD COLUMN ocr_claimed_at DATETIME;
                ALTER TABLE screenshot ADD COLUMN ocr_last_attempt_at DATETIME;
                ALTER TABLE screenshot ADD COLUMN ocr_next_retry_at DATETIME;
                ALTER TABLE screenshot ADD COLUMN ocr_last_error TEXT;
                CREATE INDEX screenshot_ocr_status_created_at
                    ON screenshot(ocr_status, created_at DESC);
                CREATE INDEX screenshot_ocr_status_next_retry
                    ON screenshot(ocr_status, ocr_next_retry_at);
                CREATE INDEX screenshot_ocr_status_claimed_at
                    ON screenshot(ocr_status, ocr_claimed_at);
                """)
            // Existing photos rows without current-version OCR need processing.
            try db.execute(sql: """
                UPDATE screenshot
                SET ocr_status = 'pending', ocr_version = 0
                WHERE source = 'photos'
                  AND access_state = 'available'
                  AND (ocr_text IS NULL OR ocr_version = 0)
                """)
            try db.execute(sql: """
                UPDATE screenshot
                SET ocr_status = 'inaccessible'
                WHERE source = 'photos' AND access_state = 'inaccessible'
                """)
        }

        migrator.registerMigration("v4_badge_color") { db in
            let columns = try db.columns(in: "context_collection").map(\.name)
            if !columns.contains("badge_color") {
                try db.execute(sql: """
                    ALTER TABLE context_collection ADD COLUMN badge_color TEXT
                    """)
            }
        }

        migrator.registerMigration("v5_collection_sort_order") { db in
            let columns = try db.columns(in: "context_collection").map(\.name)
            if !columns.contains("sort_order") {
                try db.execute(sql: """
                    ALTER TABLE context_collection ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0
                    """)
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id FROM context_collection
                    WHERE kind != 'unassigned'
                    ORDER BY title COLLATE NOCASE ASC, id ASC
                    """
            )
            for (index, row) in rows.enumerated() {
                try db.execute(
                    sql: "UPDATE context_collection SET sort_order = ? WHERE id = ?",
                    arguments: [index, row["id"]]
                )
            }
        }

        migrator.registerMigration("v6_organization_resolver") { db in
            let shotColumns = try db.columns(in: "screenshot").map(\.name)
            if !shotColumns.contains("organize_status") {
                try db.execute(sql: """
                    ALTER TABLE screenshot ADD COLUMN organize_status TEXT NOT NULL DEFAULT 'idle'
                    """)
            }
            if !shotColumns.contains("organize_resolver_version") {
                try db.execute(sql: """
                    ALTER TABLE screenshot ADD COLUMN organize_resolver_version INTEGER
                    """)
            }
            if !shotColumns.contains("organize_locked") {
                try db.execute(sql: """
                    ALTER TABLE screenshot ADD COLUMN organize_locked INTEGER NOT NULL DEFAULT 0
                    """)
            }
            if !shotColumns.contains("organize_content_fingerprint") {
                try db.execute(sql: """
                    ALTER TABLE screenshot ADD COLUMN organize_content_fingerprint TEXT
                    """)
            }
            if !shotColumns.contains("ai_summary") {
                try db.execute(sql: """
                    ALTER TABLE screenshot ADD COLUMN ai_summary TEXT
                    """)
            }

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS context_alias (
                    id TEXT PRIMARY KEY NOT NULL,
                    collection_id TEXT NOT NULL REFERENCES context_collection(id) ON DELETE CASCADE,
                    alias_title TEXT NOT NULL,
                    normalized_alias TEXT NOT NULL,
                    created_at DATETIME NOT NULL
                );
                CREATE INDEX IF NOT EXISTS context_alias_collection_id ON context_alias(collection_id);
                CREATE INDEX IF NOT EXISTS context_alias_normalized ON context_alias(normalized_alias);
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS organization_run (
                    id TEXT PRIMARY KEY NOT NULL,
                    screenshot_id TEXT NOT NULL REFERENCES screenshot(id) ON DELETE CASCADE,
                    started_at DATETIME NOT NULL,
                    finished_at DATETIME,
                    provider TEXT,
                    status TEXT NOT NULL,
                    resolver_version INTEGER,
                    decision TEXT,
                    decision_collection_id TEXT,
                    decision_title TEXT,
                    assign_threshold REAL,
                    create_threshold REAL,
                    max_candidate_confidence REAL,
                    reason TEXT,
                    candidates_json TEXT,
                    error_code TEXT,
                    request_fingerprint TEXT
                );
                CREATE INDEX IF NOT EXISTS organization_run_screenshot_id ON organization_run(screenshot_id);
                CREATE INDEX IF NOT EXISTS organization_run_started_at ON organization_run(started_at);
                """)
        }

        // Collapse AI/user title twins minted by concurrent organize, then enforce uniqueness.
        migrator.registerMigration("v7_dedupe_collections") { db in
            let collections = try Row.fetchAll(
                db,
                sql: "SELECT id, title FROM context_collection WHERE kind != 'unassigned'"
            )
            for row in collections {
                let id: String = row["id"]
                let title: String = row["title"]
                let normalized = CollectionResolver.normalizeTitle(title)
                try db.execute(
                    sql: "UPDATE context_collection SET normalized_title = ? WHERE id = ?",
                    arguments: [normalized, id]
                )
            }

            let duplicateTitles = try String.fetchAll(
                db,
                sql: """
                    SELECT normalized_title FROM context_collection
                    WHERE kind != 'unassigned'
                    GROUP BY normalized_title
                    HAVING COUNT(*) > 1
                    """
            )

            for normalized in duplicateTitles {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT c.id,
                               (
                                   SELECT COUNT(*) FROM screenshot_context sc
                                   WHERE sc.collection_id = c.id
                               ) AS member_count,
                               c.created_at AS created_at
                        FROM context_collection c
                        WHERE c.kind != 'unassigned'
                          AND c.normalized_title = ?
                        ORDER BY member_count DESC, c.created_at ASC, c.id ASC
                        """,
                    arguments: [normalized]
                )
                guard let winnerRow = rows.first else { continue }
                let winnerID: String = winnerRow["id"]
                var affectedScreenshotIDs = Set<String>()

                for loser in rows.dropFirst() {
                    let loserID: String = loser["id"]
                    let shotIDs = try String.fetchAll(
                        db,
                        sql: "SELECT screenshot_id FROM screenshot_context WHERE collection_id = ?",
                        arguments: [loserID]
                    )
                    for shotID in shotIDs {
                        affectedScreenshotIDs.insert(shotID)
                        let existsOnWinner = try Int.fetchOne(
                            db,
                            sql: """
                                SELECT COUNT(*) FROM screenshot_context
                                WHERE screenshot_id = ? AND collection_id = ?
                                """,
                            arguments: [shotID, winnerID]
                        ) ?? 0
                        if existsOnWinner == 0 {
                            try db.execute(
                                sql: """
                                    INSERT INTO screenshot_context
                                    (screenshot_id, collection_id, source, confidence, created_at, position)
                                    SELECT screenshot_id, ?, source, confidence, created_at,
                                           (
                                               SELECT COALESCE(MAX(position), -1) + 1
                                               FROM screenshot_context
                                               WHERE collection_id = ?
                                           )
                                    FROM screenshot_context
                                    WHERE screenshot_id = ? AND collection_id = ?
                                    """,
                                arguments: [winnerID, winnerID, shotID, loserID]
                            )
                        } else {
                            let loserIsUser = try Int.fetchOne(
                                db,
                                sql: """
                                    SELECT COUNT(*) FROM screenshot_context
                                    WHERE screenshot_id = ? AND collection_id = ? AND source = 'user'
                                    """,
                                arguments: [shotID, loserID]
                            ) ?? 0
                            if loserIsUser > 0 {
                                try db.execute(
                                    sql: """
                                        UPDATE screenshot_context
                                        SET source = 'user'
                                        WHERE screenshot_id = ? AND collection_id = ?
                                        """,
                                    arguments: [shotID, winnerID]
                                )
                            }
                        }
                        try db.execute(
                            sql: """
                                DELETE FROM screenshot_context
                                WHERE screenshot_id = ? AND collection_id = ?
                                """,
                            arguments: [shotID, loserID]
                        )
                    }

                    if try db.tableExists("context_alias") {
                        let leftoverAliases = try Row.fetchAll(
                            db,
                            sql: "SELECT * FROM context_alias WHERE collection_id = ?",
                            arguments: [loserID]
                        )
                        let winnerNormalized = try String.fetchOne(
                            db,
                            sql: "SELECT normalized_title FROM context_collection WHERE id = ?",
                            arguments: [winnerID]
                        )
                        for alias in leftoverAliases {
                            let normalizedAlias: String = alias["normalized_alias"]
                            let already = try Int.fetchOne(
                                db,
                                sql: """
                                    SELECT COUNT(*) FROM context_alias
                                    WHERE collection_id = ? AND normalized_alias = ?
                                    """,
                                arguments: [winnerID, normalizedAlias]
                            ) ?? 0
                            if already == 0, normalizedAlias != winnerNormalized {
                                try db.execute(
                                    sql: """
                                        INSERT INTO context_alias
                                        (id, collection_id, alias_title, normalized_alias, created_at)
                                        VALUES (?, ?, ?, ?, ?)
                                        """,
                                    arguments: [
                                        UUID().uuidString,
                                        winnerID,
                                        alias["alias_title"] as String,
                                        normalizedAlias,
                                        alias["created_at"] as Date
                                    ]
                                )
                            }
                        }
                        try db.execute(
                            sql: "DELETE FROM context_alias WHERE collection_id = ?",
                            arguments: [loserID]
                        )
                    }

                    if try db.tableExists("organization_run") {
                        try db.execute(
                            sql: """
                                UPDATE organization_run
                                SET decision_collection_id = ?
                                WHERE decision_collection_id = ?
                                """,
                            arguments: [winnerID, loserID]
                        )
                    }

                    try db.execute(
                        sql: "DELETE FROM context_collection WHERE id = ?",
                        arguments: [loserID]
                    )
                }

                try GRDBMemoryRepository.applyNeedsReviewInvariant(
                    forScreenshotIDs: Array(affectedScreenshotIDs),
                    db: db
                )
            }

            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS context_collection_normalized_title_uq
                ON context_collection(normalized_title)
                WHERE kind != 'unassigned'
                """)
        }

        migrator.registerMigration("v8_accuracy_remediation") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS collection_context_profile (
                    collection_id TEXT PRIMARY KEY NOT NULL REFERENCES context_collection(id) ON DELETE CASCADE,
                    key_entities_json TEXT NOT NULL DEFAULT '[]',
                    key_terms_json TEXT NOT NULL DEFAULT '[]',
                    visual_descriptors_json TEXT NOT NULL DEFAULT '[]',
                    date_range_start DATETIME,
                    date_range_end DATETIME,
                    profile_version INTEGER NOT NULL DEFAULT 1,
                    updated_at DATETIME NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS understanding_cache (
                    fingerprint TEXT PRIMARY KEY NOT NULL,
                    understanding_json TEXT NOT NULL,
                    created_at DATETIME NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS organization_eval (
                    screenshot_id TEXT PRIMARY KEY NOT NULL REFERENCES screenshot(id) ON DELETE CASCADE,
                    label TEXT NOT NULL,
                    updated_at DATETIME NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS organization_gateway_stats (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    request_count INTEGER NOT NULL DEFAULT 0
                );
                INSERT OR IGNORE INTO organization_gateway_stats (id, request_count) VALUES (1, 0);
                """)

            let runColumns = try db.columns(in: "organization_run").map(\.name)
            if !runColumns.contains("understanding_json") {
                try db.execute(sql: "ALTER TABLE organization_run ADD COLUMN understanding_json TEXT")
            }
            if !runColumns.contains("score_components_json") {
                try db.execute(sql: "ALTER TABLE organization_run ADD COLUMN score_components_json TEXT")
            }
            if !runColumns.contains("batch_id") {
                try db.execute(sql: "ALTER TABLE organization_run ADD COLUMN batch_id TEXT")
            }
            if !runColumns.contains("normalized_ocr_preview") {
                try db.execute(sql: "ALTER TABLE organization_run ADD COLUMN normalized_ocr_preview TEXT")
            }
        }

        return migrator
    }
}
