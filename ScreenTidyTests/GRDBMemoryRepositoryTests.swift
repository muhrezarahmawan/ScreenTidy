import XCTest
import GRDB
@testable import ScreenTidy

final class GRDBMemoryRepositoryTests: XCTestCase {
    private var database: AppDatabase!
    private var repository: GRDBMemoryRepository!

    override func setUp() async throws {
        try await super.setUp()
        database = try AppDatabase.makeEmptyInMemory()
        try DatabaseSeeder.seedIfNeeded(database)
        repository = GRDBMemoryRepository(database: database)
    }

    override func tearDown() async throws {
        repository = nil
        database = nil
        try await super.tearDown()
    }

    func testMigrationsInitializeSchema() async throws {
        let tables = try await database.dbPool.read { db -> [String] in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type IN ('table', 'view')
                    ORDER BY name
                    """
            )
        }
        XCTAssertTrue(tables.contains("screenshot"))
        XCTAssertTrue(tables.contains("context_collection"))
        XCTAssertTrue(tables.contains("screenshot_context"))
        XCTAssertTrue(tables.contains("screenshot_fts"))
        XCTAssertTrue(tables.contains("app_meta"))
    }

    func testSeedCreatesFixtureCollections() async throws {
        let promoted = try await repository.fetchPromotedContexts()
        let titles = Set(promoted.map(\.title))
        XCTAssertTrue(titles.contains("Japan Trip"))
        XCTAssertTrue(titles.contains("Apartment Setup"))
        XCTAssertTrue(titles.contains("Qatar Airways"))
        XCTAssertTrue(titles.contains("Visa Application"))

        let needsReview = try await repository.fetchUnassignedContext()
        XCTAssertEqual(needsReview?.title, "Needs Review")
        XCTAssertGreaterThan(needsReview?.memberCount ?? 0, 0)
    }

    func testReorderContextsPersistsAcrossReload() async throws {
        let before = try await repository.fetchPromotedContexts()
        XCTAssertGreaterThanOrEqual(before.count, 2)
        let reversedIDs = before.map(\.id).reversed()
        try await repository.reorderContexts(orderedIDs: Array(reversedIDs))

        let reloaded = GRDBMemoryRepository(database: database)
        let after = try await reloaded.fetchPromotedContexts()
        XCTAssertEqual(after.map(\.id), Array(reversedIDs))
        XCTAssertEqual(after.map(\.sortOrder), Array(0..<after.count))
    }

    func testCreateRenameEmojiPersistAcrossReload() async throws {
        let created = try await repository.createContext(title: "Restaurants", badgeEmoji: "🍜", badgeColor: "#E8D9C8")
        try await repository.updateContext(id: created.id, title: "Dinner Plans", badgeEmoji: "🍽", badgeColor: "#F0C49A")

        let reloaded = GRDBMemoryRepository(database: database)
        let fetched = try await reloaded.fetchContext(id: created.id)
        XCTAssertEqual(fetched?.title, "Dinner Plans")
        XCTAssertEqual(fetched?.badgeEmoji, "🍽")
        XCTAssertEqual(fetched?.badgeColor, "#F0C49A")
        XCTAssertEqual(fetched?.kind, .userContext)

        let promoted = try await reloaded.fetchPromotedContexts()
        XCTAssertTrue(promoted.contains(where: { $0.id == created.id }))
    }

    func testMoveScreenshotPersists() async throws {
        let japan = MockData.japanTripID
        let apartment = MockData.apartmentID
        let shot = MockData.shotA

        let beforeJapan = try await repository.fetchScreenshots(in: japan)
        XCTAssertTrue(beforeJapan.contains(where: { $0.id == shot }))

        _ = try await repository.moveScreenshots(ids: [shot], to: apartment)

        let reloaded = GRDBMemoryRepository(database: database)
        let afterJapan = try await reloaded.fetchScreenshots(in: japan)
        let afterApartment = try await reloaded.fetchScreenshots(in: apartment)
        XCTAssertFalse(afterJapan.contains(where: { $0.id == shot }))
        XCTAssertTrue(afterApartment.contains(where: { $0.id == shot }))
    }

    func testDeleteCollectionOnlyMovesOrphansToNeedsReview() async throws {
        let created = try await repository.createContext(title: "Temp Bucket", badgeEmoji: "📦", badgeColor: nil)
        let shot = MockData.shotE
        _ = try await repository.moveScreenshots(ids: [shot], to: created.id)

        _ = try await repository.deleteContext(id: created.id, deleteScreenshots: false)

        let reloaded = GRDBMemoryRepository(database: database)
        let deleted = try await reloaded.fetchContext(id: created.id)
        XCTAssertNil(deleted)
        let needsReview = try await reloaded.fetchUnassignedContext()
        XCTAssertNotNil(needsReview)
        let members = try await reloaded.fetchScreenshots(in: needsReview!.id)
        XCTAssertTrue(members.contains(where: { $0.id == shot }))
    }

    func testUndoRestoresMovedScreenshots() async throws {
        let japan = MockData.japanTripID
        let apartment = MockData.apartmentID
        let shot = MockData.shotC

        let token = try await repository.moveScreenshots(ids: [shot], to: japan)
        let restored = await repository.undo(token: token)
        XCTAssertTrue(restored)

        let members = try await repository.fetchScreenshots(in: apartment)
        XCTAssertTrue(members.contains(where: { $0.id == shot }))
    }

    func testSeedDoesNotRepeatAfterMutation() async throws {
        let created = try await repository.createContext(title: "One Off", badgeEmoji: nil, badgeColor: nil)
        try DatabaseSeeder.seedIfNeeded(database)
        let again = try await repository.fetchContext(id: created.id)
        XCTAssertEqual(again?.title, "One Off")

        let count = try await database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM context_collection WHERE title = 'Japan Trip'")
        }
        XCTAssertEqual(count, 1)
    }

    func testResetAndReseedRestoresFixtures() async throws {
        _ = try await repository.createContext(title: "Ephemeral", badgeEmoji: nil, badgeColor: nil)
        try await DatabaseMaintenance.resetAndReseed(database)
        let reloaded = GRDBMemoryRepository(database: database)
        let ephemeralGone = try await database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM context_collection WHERE title = 'Ephemeral'")
        }
        XCTAssertEqual(ephemeralGone, 0)
        let japan = try await reloaded.fetchContext(id: MockData.japanTripID)
        XCTAssertEqual(japan?.title, "Japan Trip")
    }

    func testFixtureClearRemovesSeedDemoCollectionsAndFixtureScreenshots() async throws {
        try await repository.clearFixtureScreenshots()
        let fixtureCount = try await database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM screenshot WHERE source = 'fixture'")
        }
        XCTAssertEqual(fixtureCount, 0)
        let japan = try await repository.fetchContext(id: MockData.japanTripID)
        let apartment = try await repository.fetchContext(id: MockData.apartmentID)
        let qatar = try await repository.fetchContext(id: MockData.qatarID)
        let visa = try await repository.fetchContext(id: MockData.visaID)
        let weekend = try await repository.fetchContext(id: MockData.weekendID)
        XCTAssertNil(japan)
        XCTAssertNil(apartment)
        XCTAssertNil(qatar)
        XCTAssertNil(visa)
        XCTAssertNil(weekend)
        let needsReview = try await repository.fetchUnassignedContext()
        XCTAssertNotNil(needsReview)
        XCTAssertEqual(needsReview?.title, "Needs Review")
    }

    func testPhotoUpsertPersistsLocalIdentifierAndNeedsReviewPeekLimit() async throws {
        try await repository.clearFixtureScreenshots()
        let assets = (0..<5).map { index in
            PhotoAssetMetadata(
                localIdentifier: "photos-id-\(index)",
                createdAt: Date().addingTimeInterval(TimeInterval(-index)),
                width: 1170,
                height: 2532
            )
        }
        let inserted = try await repository.upsertPhotoScreenshots(assets)
        XCTAssertEqual(inserted, 5)
        let stored = try await database.dbPool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT photos_local_identifier FROM screenshot WHERE source = 'photos' ORDER BY photos_local_identifier"
            )
        }
        XCTAssertEqual(stored, assets.map(\.localIdentifier).sorted())
        let needsReviewCount = try await repository.fetchNeedsReviewCount()
        XCTAssertEqual(needsReviewCount, 5)
        let previewCount = try await repository.fetchNeedsReviewPreview(limit: 3).count
        XCTAssertEqual(previewCount, 3)

        let needsReviewOptional = try await repository.fetchUnassignedContext()
        let needsReview = try XCTUnwrap(needsReviewOptional)
        let peeks = try await repository.fetchScreenshots(in: needsReview.id, limit: 3, offset: 0)
        XCTAssertEqual(peeks.count, 3)
        XCTAssertEqual(needsReview.memberCount, 5)
    }

    func testPhotoUpsertAndLimitedInaccessibleKeepsMembership() async throws {
        try await repository.clearFixtureScreenshots()
        let asset = PhotoAssetMetadata(
            localIdentifier: "photos-id-1",
            createdAt: Date(),
            width: 1170,
            height: 2532
        )
        let inserted = try await repository.upsertPhotoScreenshots([asset])
        XCTAssertEqual(inserted, 1)
        let needsReviewOptional = try await repository.fetchUnassignedContext()
        let needsReview = try XCTUnwrap(needsReviewOptional)
        let before = try await repository.fetchScreenshots(in: needsReview.id)
        XCTAssertEqual(before.count, 1)

        try await repository.markPhotoScreenshotsInaccessible(identifiers: [asset.localIdentifier])
        let after = try await repository.fetchScreenshots(in: needsReview.id)
        XCTAssertTrue(after.isEmpty)
        let membershipCount = try await database.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM screenshot_context
                    JOIN screenshot ON screenshot.id = screenshot_context.screenshot_id
                    WHERE screenshot.photos_local_identifier = ?
                    """,
                arguments: [asset.localIdentifier]
            )
        }
        XCTAssertEqual(membershipCount, 1)
        let accessState = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT access_state FROM screenshot WHERE photos_local_identifier = ?",
                arguments: [asset.localIdentifier]
            )
        }
        XCTAssertEqual(accessState, "inaccessible")
    }

    func testFixtureClearIsIdempotent() async throws {
        try await repository.clearFixtureScreenshots()
        try await repository.clearFixtureScreenshots()
        let cleared = try await database.dbPool.read { db in
            try AppMetaRecord.fetchOne(db, key: "fixtureScreenshotsCleared")?.value
        }
        XCTAssertEqual(cleared, "1")
        let fixtureCount = try await database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM screenshot WHERE source = 'fixture'")
        }
        XCTAssertEqual(fixtureCount, 0)
    }

    func testRemovePhotoScreenshotsDeletesLocalMetadataOnly() async throws {
        try await repository.clearFixtureScreenshots()
        let asset = PhotoAssetMetadata(
            localIdentifier: "photos-id-remove",
            createdAt: Date(),
            width: 1170,
            height: 2532
        )
        _ = try await repository.upsertPhotoScreenshots([asset])
        let identifiers = try await repository.photoScreenshotIdentifiers()
        XCTAssertTrue(identifiers.contains(asset.localIdentifier))

        try await repository.removePhotoScreenshots(identifiers: [asset.localIdentifier])
        let after = try await repository.photoScreenshotIdentifiers()
        XCTAssertFalse(after.contains(asset.localIdentifier))
        let rowCount = try await database.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM screenshot WHERE photos_local_identifier = ?",
                arguments: [asset.localIdentifier]
            )
        }
        XCTAssertEqual(rowCount, 0)
    }

    func testOCRClaimCompletesWithEmptyTextAndPopulatesFTS() async throws {
        try await repository.clearFixtureScreenshots()
        let asset = PhotoAssetMetadata(
            localIdentifier: "photos-ocr-empty",
            createdAt: Date(),
            width: 1170,
            height: 2532
        )
        _ = try await repository.upsertPhotoScreenshots([asset])
        let claim = try await repository.claimNextOCRJob(currentVersion: OCRPipeline.currentVersion, now: Date())
        let unwrapped = try XCTUnwrap(claim)
        try await repository.completeOCRSuccess(
            id: unwrapped.id,
            text: "",
            language: nil,
            version: OCRPipeline.currentVersion
        )
        let status = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT ocr_status FROM screenshot WHERE photos_local_identifier = ?",
                arguments: [asset.localIdentifier]
            )
        }
        XCTAssertEqual(status, "completed")
        let text = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT ocr_text FROM screenshot WHERE photos_local_identifier = ?",
                arguments: [asset.localIdentifier]
            )
        }
        XCTAssertEqual(text, "")
        let fts = try await database.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM screenshot_fts WHERE screenshot_id = ?",
                arguments: [unwrapped.id.rawValue.uuidString]
            )
        }
        XCTAssertEqual(fts, 1)
    }

    func testOCRStaleProcessingClaimRecovered() async throws {
        try await repository.clearFixtureScreenshots()
        let asset = PhotoAssetMetadata(
            localIdentifier: "photos-ocr-stale",
            createdAt: Date(),
            width: 1170,
            height: 2532
        )
        _ = try await repository.upsertPhotoScreenshots([asset])
        let claim = try await repository.claimNextOCRJob(currentVersion: OCRPipeline.currentVersion, now: Date())
        XCTAssertNotNil(claim)
        let recovered = try await repository.recoverStaleOCRClaims(
            olderThan: Date().addingTimeInterval(60)
        )
        XCTAssertEqual(recovered, 1)
        let status = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT ocr_status FROM screenshot WHERE photos_local_identifier = ?",
                arguments: [asset.localIdentifier]
            )
        }
        XCTAssertEqual(status, "pending")
    }

    func testOCRNewestClaimedFirst() async throws {
        try await repository.clearFixtureScreenshots()
        let older = PhotoAssetMetadata(
            localIdentifier: "photos-ocr-old",
            createdAt: Date().addingTimeInterval(-3_600),
            width: 1170,
            height: 2532
        )
        let newer = PhotoAssetMetadata(
            localIdentifier: "photos-ocr-new",
            createdAt: Date(),
            width: 1170,
            height: 2532
        )
        _ = try await repository.upsertPhotoScreenshots([older, newer])
        let claim = try await repository.claimNextOCRJob(currentVersion: OCRPipeline.currentVersion, now: Date())
        XCTAssertEqual(claim?.photosLocalIdentifier, newer.localIdentifier)
    }

    func testOCRCompleteDoesNotChangeMemberships() async throws {
        try await repository.clearFixtureScreenshots()
        let asset = PhotoAssetMetadata(
            localIdentifier: "photos-ocr-membership",
            createdAt: Date(),
            width: 1170,
            height: 2532
        )
        _ = try await repository.upsertPhotoScreenshots([asset])
        let before = try await database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM screenshot_context")
        }
        let claim = try await repository.claimNextOCRJob(currentVersion: OCRPipeline.currentVersion, now: Date())
        let unwrapped = try XCTUnwrap(claim)
        try await repository.completeOCRSuccess(
            id: unwrapped.id,
            text: "hello",
            language: "en",
            version: OCRPipeline.currentVersion
        )
        let after = try await database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM screenshot_context")
        }
        XCTAssertEqual(before, after)
        let needsReview = try await repository.fetchNeedsReviewCount()
        XCTAssertEqual(needsReview, 1)
    }

    // MARK: - Sprint 6 Search (FTS)

    func testSearchFTSQueryEscapesAndTokenizes() {
        XCTAssertEqual(SearchFTSQuery.tokens(from: "  Hello, WORLD!! "), ["hello", "world"])
        XCTAssertEqual(SearchFTSQuery.matchExpression(from: "Hello WORLD"), "\"hello\"* AND \"world\"*")
        XCTAssertNil(SearchFTSQuery.matchExpression(from: "   !!!  "))
        XCTAssertEqual(SearchFTSQuery.matchExpression(from: "a"), "\"a\"")
        // Quotes in input become doubled inside FTS quotes after alphanumeric filter — no crash path.
        XCTAssertNotNil(SearchFTSQuery.matchExpression(from: #"board"ing"#))
    }

    func testSearchUsesFTSAndRespectsAccessAndEmptyOCR() async throws {
        try await repository.clearFixtureScreenshots()

        let visible = PhotoAssetMetadata(
            localIdentifier: "photos-search-visible",
            createdAt: Date(),
            width: 1170,
            height: 2532
        )
        let emptyOCR = PhotoAssetMetadata(
            localIdentifier: "photos-search-empty",
            createdAt: Date().addingTimeInterval(-10),
            width: 1170,
            height: 2532
        )
        let inaccessible = PhotoAssetMetadata(
            localIdentifier: "photos-search-inaccessible",
            createdAt: Date().addingTimeInterval(-20),
            width: 1170,
            height: 2532
        )

        _ = try await repository.upsertPhotoScreenshots([visible, emptyOCR, inaccessible])

        // Mark inaccessible before OCR so it stays out of Search.
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshot SET access_state = 'inaccessible'
                    WHERE photos_local_identifier = ?
                    """,
                arguments: [inaccessible.localIdentifier]
            )
        }

        func completeOCR(localID: String, text: String) async throws -> ScreenshotMemoryID {
            let claim = try await repository.claimNextOCRJob(
                currentVersion: OCRPipeline.currentVersion,
                now: Date()
            )
            let unwrapped = try XCTUnwrap(claim)
            XCTAssertEqual(unwrapped.photosLocalIdentifier, localID)
            try await repository.completeOCRSuccess(
                id: unwrapped.id,
                text: text,
                language: "en",
                version: OCRPipeline.currentVersion
            )
            return unwrapped.id
        }

        let visibleID = try await completeOCR(localID: visible.localIdentifier, text: "Boarding Pass Qatar Airways")
        _ = try await completeOCR(localID: emptyOCR.localIdentifier, text: "")

        // Inaccessible should never be claimed while unavailable — ensure no pending claim left for it.
        let leftover = try await repository.claimNextOCRJob(
            currentVersion: OCRPipeline.currentVersion,
            now: Date()
        )
        XCTAssertNil(leftover)

        let single = try await repository.search(query: "boarding")
        XCTAssertEqual(single.hits.count, 1)
        XCTAssertEqual(single.hits.first?.screenshot.id, visibleID)
        XCTAssertTrue(single.hits.first?.matchedSignals.contains(.ocr) == true)

        let multi = try await repository.search(query: "Qatar BOARDING")
        XCTAssertEqual(multi.hits.map(\.screenshot.id), [visibleID])

        let punct = try await repository.search(query: "boarding!!!")
        XCTAssertEqual(punct.hits.count, 1)

        let none = try await repository.search(query: "zzzznotfoundxyz")
        XCTAssertTrue(none.hits.isEmpty)

        // Empty OCR completed shot must not match arbitrary text and must not crash Search.
        let emptyQuery = try await repository.search(query: "boarding")
        XCTAssertFalse(emptyQuery.hits.contains { $0.screenshot.photosLocalIdentifier == emptyOCR.localIdentifier })

        // Soft-remove excludes from Search.
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshot SET is_removed_from_app = 1
                    WHERE photos_local_identifier = ?
                    """,
                arguments: [visible.localIdentifier]
            )
        }
        let removed = try await repository.search(query: "boarding")
        XCTAssertTrue(removed.hits.isEmpty)
    }

    func testSearchFindsNewOCRWithoutRestart() async throws {
        try await repository.clearFixtureScreenshots()
        let asset = PhotoAssetMetadata(
            localIdentifier: "photos-search-live",
            createdAt: Date(),
            width: 1170,
            height: 2532
        )
        _ = try await repository.upsertPhotoScreenshots([asset])

        let beforeOCR = try await repository.search(query: "UniqueZebraToken99")
        XCTAssertTrue(beforeOCR.hits.isEmpty)

        let claim = try await repository.claimNextOCRJob(currentVersion: OCRPipeline.currentVersion, now: Date())
        let unwrapped = try XCTUnwrap(claim)
        try await repository.completeOCRSuccess(
            id: unwrapped.id,
            text: "UniqueZebraToken99 appears mid screenshot",
            language: "en",
            version: OCRPipeline.currentVersion
        )

        let afterOCR = try await repository.search(query: "UniqueZebraToken99")
        XCTAssertEqual(afterOCR.hits.count, 1)
        XCTAssertEqual(afterOCR.hits.first?.screenshot.id, unwrapped.id)
    }

    func testSearchDoesNotMutateMemberships() async throws {
        try await repository.clearFixtureScreenshots()
        let asset = PhotoAssetMetadata(
            localIdentifier: "photos-search-nomutate",
            createdAt: Date(),
            width: 1170,
            height: 2532
        )
        _ = try await repository.upsertPhotoScreenshots([asset])
        let claim = try await repository.claimNextOCRJob(currentVersion: OCRPipeline.currentVersion, now: Date())
        let unwrapped = try XCTUnwrap(claim)
        try await repository.completeOCRSuccess(
            id: unwrapped.id,
            text: "membership guard",
            language: nil,
            version: OCRPipeline.currentVersion
        )
        let before = try await database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM screenshot_context")
        }
        _ = try await repository.search(query: "membership")
        let after = try await database.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM screenshot_context")
        }
        XCTAssertEqual(before, after)
    }

    // MARK: - Sprint 7 membership graph

    func testMoveIsExclusiveAndLeavesNeedsReview() async throws {
        try await repository.clearFixtureScreenshots()
        let asset = PhotoAssetMetadata(
            localIdentifier: "photos-s7-move-exclusive",
            createdAt: Date(),
            width: 100,
            height: 200
        )
        _ = try await repository.upsertPhotoScreenshots([asset])
        let inboxOptional = try await repository.fetchUnassignedContext()
        let inbox = try XCTUnwrap(inboxOptional)
        let inboxShots = try await repository.fetchScreenshots(in: inbox.id)
        let shot = try XCTUnwrap(inboxShots.first)
        let trip = try await repository.createContext(title: "Manual Trip", badgeEmoji: "✈️", badgeColor: nil)

        _ = try await repository.moveScreenshots(ids: [shot.id], to: trip.id)

        let inTrip = try await repository.fetchScreenshots(in: trip.id)
        let inInbox = try await repository.fetchScreenshots(in: inbox.id)
        XCTAssertTrue(inTrip.contains(where: { $0.id == shot.id }))
        XCTAssertFalse(inInbox.contains(where: { $0.id == shot.id }))

        let sources = try await membershipSources(for: shot.id)
        XCTAssertEqual(sources[trip.id.rawValue.uuidString], "user")
        XCTAssertEqual(sources.count, 1)
    }

    func testAddKeepsMultiContextAndLeavesNeedsReview() async throws {
        let japan = MockData.japanTripID
        let qatar = MockData.qatarID
        let shot = MockData.shotA

        _ = try await repository.moveScreenshots(ids: [shot], to: japan)
        _ = try await repository.addScreenshots(ids: [shot], to: qatar)

        let inJapan = try await repository.fetchScreenshots(in: japan)
        let inQatar = try await repository.fetchScreenshots(in: qatar)
        XCTAssertTrue(inJapan.contains(where: { $0.id == shot }))
        XCTAssertTrue(inQatar.contains(where: { $0.id == shot }))

        if let inbox = try await repository.fetchUnassignedContext() {
            let inInbox = try await repository.fetchScreenshots(in: inbox.id)
            XCTAssertFalse(inInbox.contains(where: { $0.id == shot }))
        }

        let sources = try await membershipSources(for: shot)
        XCTAssertEqual(sources[japan.rawValue.uuidString], "user")
        XCTAssertEqual(sources[qatar.rawValue.uuidString], "user")
    }

    func testRemoveFromOneCollectionKeepsOthers() async throws {
        let japan = MockData.japanTripID
        let qatar = MockData.qatarID
        let shot = MockData.shotB // Fixture: Japan + Qatar

        _ = try await repository.removeScreenshots(ids: [shot], from: japan)

        let inJapan = try await repository.fetchScreenshots(in: japan)
        let inQatar = try await repository.fetchScreenshots(in: qatar)
        XCTAssertFalse(inJapan.contains(where: { $0.id == shot }))
        XCTAssertTrue(inQatar.contains(where: { $0.id == shot }))
    }

    func testRemoveFinalMembershipReturnsToNeedsReview() async throws {
        let japan = MockData.japanTripID
        let shot = MockData.shotA
        _ = try await repository.moveScreenshots(ids: [shot], to: japan)
        _ = try await repository.removeScreenshots(ids: [shot], from: japan)

        let inboxOptional = try await repository.fetchUnassignedContext()
        let inbox = try XCTUnwrap(inboxOptional)
        let inInbox = try await repository.fetchScreenshots(in: inbox.id)
        let inJapan = try await repository.fetchScreenshots(in: japan)
        XCTAssertTrue(inInbox.contains(where: { $0.id == shot }))
        XCTAssertFalse(inJapan.contains(where: { $0.id == shot }))

        let sources = try await membershipSources(for: shot)
        XCTAssertEqual(sources[inbox.id.rawValue.uuidString], "user")
        XCTAssertEqual(sources.count, 1)
    }

    func testUndoRestoresExactMultiMembershipGraph() async throws {
        let japan = MockData.japanTripID
        let qatar = MockData.qatarID
        let apartment = MockData.apartmentID
        let shot = MockData.shotB // starts in Japan + Qatar

        let token = try await repository.moveScreenshots(ids: [shot], to: apartment)
        let inApartment = try await repository.fetchScreenshots(in: apartment)
        let inJapanAfterMove = try await repository.fetchScreenshots(in: japan)
        let inQatarAfterMove = try await repository.fetchScreenshots(in: qatar)
        XCTAssertTrue(inApartment.contains(where: { $0.id == shot }))
        XCTAssertFalse(inJapanAfterMove.contains(where: { $0.id == shot }))
        XCTAssertFalse(inQatarAfterMove.contains(where: { $0.id == shot }))

        let restored = await repository.undo(token: token)
        XCTAssertTrue(restored)

        let inJapan = try await repository.fetchScreenshots(in: japan)
        let inQatar = try await repository.fetchScreenshots(in: qatar)
        let inApartmentAfterUndo = try await repository.fetchScreenshots(in: apartment)
        XCTAssertTrue(inJapan.contains(where: { $0.id == shot }))
        XCTAssertTrue(inQatar.contains(where: { $0.id == shot }))
        XCTAssertFalse(inApartmentAfterUndo.contains(where: { $0.id == shot }))
    }

    func testMultiSelectMoveUndoRestoresPerScreenshotGraphs() async throws {
        let japan = MockData.japanTripID
        let qatar = MockData.qatarID
        let apartment = MockData.apartmentID
        let shotOnlyJapan = MockData.shotA
        let shotBoth = MockData.shotB

        _ = try await repository.moveScreenshots(ids: [shotOnlyJapan], to: japan)
        // shotBoth already Japan+Qatar from fixtures

        let token = try await repository.moveScreenshots(
            ids: [shotOnlyJapan, shotBoth],
            to: apartment
        )
        let restored = await repository.undo(token: token)
        XCTAssertTrue(restored)

        let japanMembers = try await repository.fetchScreenshots(in: japan)
        let qatarMembers = try await repository.fetchScreenshots(in: qatar)
        let apartmentMembers = try await repository.fetchScreenshots(in: apartment)

        XCTAssertTrue(japanMembers.contains(where: { $0.id == shotOnlyJapan }))
        XCTAssertFalse(qatarMembers.contains(where: { $0.id == shotOnlyJapan }))

        XCTAssertTrue(japanMembers.contains(where: { $0.id == shotBoth }))
        XCTAssertTrue(qatarMembers.contains(where: { $0.id == shotBoth }))
        XCTAssertFalse(apartmentMembers.contains(where: { $0.id == shotBoth }))
    }

    func testMovePreservesOCRAndFTSSearch() async throws {
        try await repository.clearFixtureScreenshots()
        let asset = PhotoAssetMetadata(
            localIdentifier: "photos-s7-ocr-survive",
            createdAt: Date(),
            width: 100,
            height: 200
        )
        _ = try await repository.upsertPhotoScreenshots([asset])
        let claimOptional = try await repository.claimNextOCRJob(
            currentVersion: OCRPipeline.currentVersion,
            now: Date()
        )
        let claim = try XCTUnwrap(claimOptional)
        try await repository.completeOCRSuccess(
            id: claim.id,
            text: "SprintSevenUniqueToken42",
            language: "en",
            version: OCRPipeline.currentVersion
        )

        let trip = try await repository.createContext(title: "OCR Trip", badgeEmoji: "📷", badgeColor: nil)
        let bookings = try await repository.createContext(title: "Bookings", badgeEmoji: "🎫", badgeColor: nil)
        _ = try await repository.moveScreenshots(ids: [claim.id], to: trip.id)
        _ = try await repository.addScreenshots(ids: [claim.id], to: bookings.id)

        let hit = try await repository.search(query: "SprintSevenUniqueToken42")
        XCTAssertEqual(hit.hits.count, 1)
        XCTAssertEqual(hit.hits.first?.screenshot.id, claim.id)

        let ocr = try await repository.fetchScreenshot(id: claim.id)
        XCTAssertEqual(ocr?.ocrStatus, .completed)
        XCTAssertEqual(ocr?.ocrText, "SprintSevenUniqueToken42")
        XCTAssertEqual(ocr?.photosLocalIdentifier, "photos-s7-ocr-survive")
    }

    func testAddPickerExcludesCollectionsContainingAllSelected() async throws {
        let shot = MockData.shotB // Japan + Qatar
        let destinations = try await repository.fetchContextsForAddPicker(
            screenshotIDs: [shot],
            excluding: nil
        )
        let ids = Set(destinations.map(\.id))
        XCTAssertFalse(ids.contains(MockData.japanTripID))
        XCTAssertFalse(ids.contains(MockData.qatarID))
        XCTAssertFalse(destinations.contains(where: { $0.kind == .unassigned }))
        XCTAssertTrue(ids.contains(MockData.apartmentID))
    }

    private func membershipSources(for id: ScreenshotMemoryID) async throws -> [String: String] {
        try await database.dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT collection_id, source FROM screenshot_context WHERE screenshot_id = ?",
                arguments: [id.rawValue.uuidString]
            )
            var map: [String: String] = [:]
            for row in rows {
                let collectionID: String = row["collection_id"]
                let source: String = row["source"]
                map[collectionID] = source
            }
            return map
        }
    }
}
