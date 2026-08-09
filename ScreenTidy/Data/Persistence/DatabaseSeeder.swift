import Foundation
import GRDB

enum DatabaseSeeder {
    static func seedIfNeeded(_ database: AppDatabase) throws {
        try database.dbPool.writeWithoutTransaction { db in
            // Prefer a single write transaction for seed.
            try db.inTransaction {
                let seeded = try AppMetaRecord.fetchOne(db, key: "fixtureSeeded")?.value == "1"
                let collectionCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM context_collection") ?? 0
                guard !seeded, collectionCount == 0 else { return .commit }
                try seed(db)
                return .commit
            }
        }
    }

    static func seed(_ db: Database) throws {
        let now = Date()
        for context in MockData.contexts {
            try CollectionRecord(
                id: context.id.rawValue.uuidString,
                kind: context.kind.rawValue,
                title: context.title,
                normalizedTitle: CollectionResolver.normalizeTitle(context.title),
                badgeEmoji: context.badgeEmoji,
                badgeColor: context.badgeColor,
                isPinned: context.isPinned,
                isArchived: context.isArchived,
                sortOrder: context.sortOrder,
                createdAt: now,
                updatedAt: now,
                createdBy: context.kind == .userContext ? "user" : "ai",
                insight: context.insight
            ).insert(db)
        }
        for shot in MockData.allScreenshots {
            try ScreenshotRecord(memory: shot, now: now).insert(db)
        }
        for (collectionID, screenshotIDs) in MockData.memberships {
            for (position, screenshotID) in screenshotIDs.enumerated() {
                try MembershipRecord(
                    screenshotID: screenshotID.rawValue.uuidString,
                    collectionID: collectionID.rawValue.uuidString,
                    source: "ai",
                    confidence: nil,
                    createdAt: now,
                    position: position
                ).insert(db)
            }
        }
        for group in MockData.duplicateGroups {
            try DuplicateGroupRecord(
                id: group.id.uuidString,
                screenshotIDsJSON: ScreenshotRecord.json(group.screenshotIDs.map { $0.rawValue.uuidString }),
                recommendedKeepID: group.recommendedKeepID?.rawValue.uuidString
            ).insert(db)
        }
        try AppMetaRecord(key: "fixtureSeeded", value: "1").insert(db)
        try AppMetaRecord(key: "seedVersion", value: "1").insert(db)
    }

    /// One-way fixture → Photos handoff.
    /// Removes demo fixture screenshots and seed AI demo collections.
    /// Keeps Needs Review and any user-created collections.
    static func clearFixtureScreenshotsIfNeeded(_ database: AppDatabase) async throws {
        try await database.dbPool.write { db in
            let cleared = try AppMetaRecord.fetchOne(db, key: "fixtureScreenshotsCleared")?.value == "1"
            if !cleared {
                try db.execute(sql: """
                    DELETE FROM screenshot_context
                    WHERE screenshot_id IN (SELECT id FROM screenshot WHERE source = 'fixture')
                    """)
                try db.execute(sql: "DELETE FROM screenshot WHERE source = 'fixture'")
                try db.execute(
                    sql: "INSERT OR REPLACE INTO app_meta (key, value) VALUES ('fixtureScreenshotsCleared', '1')"
                )
            }

            // Separate flag so devices that already cleared fixtures still drop empty demo folders.
            let seedCollectionsCleared =
                try AppMetaRecord.fetchOne(db, key: "seedDemoCollectionsCleared")?.value == "1"
            if !seedCollectionsCleared {
                let ids = MockData.seedDemoCollectionIDs.map(\.rawValue.uuidString)
                guard !ids.isEmpty else { return }
                let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
                try db.execute(
                    sql: """
                        DELETE FROM screenshot_context
                        WHERE collection_id IN (\(placeholders))
                        """,
                    arguments: StatementArguments(ids)
                )
                try db.execute(
                    sql: """
                        DELETE FROM context_collection
                        WHERE id IN (\(placeholders)) AND kind = 'aiContext'
                        """,
                    arguments: StatementArguments(ids)
                )
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO app_meta (key, value)
                        VALUES ('seedDemoCollectionsCleared', '1')
                        """
                )
            }
        }
    }
}

enum DatabaseMaintenance {
    static func resetAndReseed(_ db: AppDatabase) async throws {
        try await db.dbPool.write { database in
            for table in ["screenshot_context", "duplicate_group", "screenshot_fts", "screenshot", "context_collection", "app_meta"] {
                try database.execute(sql: "DELETE FROM \(table)")
            }
            try DatabaseSeeder.seed(database)
        }
    }
}
