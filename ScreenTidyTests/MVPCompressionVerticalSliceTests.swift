import XCTest
import GRDB
@testable import ScreenTidy

final class MVPCompressionVerticalSliceTests: XCTestCase {

    // MARK: - SharedContext coding (memberLocalIds wire key)

    func testSharedBatchContextDecodesGatewayMemberLocalIds() throws {
        let json = """
        {
          "title": "Trip to Abu Dhabi",
          "confidence": 0.91,
          "memberLocalIds": ["A", "B", "C"],
          "evidence": ["flight", "hotel"]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SharedBatchContext.self, from: json)
        XCTAssertEqual(decoded.title, "Trip to Abu Dhabi")
        XCTAssertEqual(decoded.confidence, 0.91, accuracy: 0.001)
        XCTAssertEqual(decoded.memberLocalIDs, ["A", "B", "C"])
        XCTAssertEqual(decoded.evidence, ["flight", "hotel"])

        let encoded = try JSONEncoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual(object?["memberLocalIds"] as? [String], ["A", "B", "C"])
        XCTAssertNil(object?["memberLocalIDs"])
    }

    func testResolverDoesNotChangeThresholdsWithSharedContext() {
        XCTAssertEqual(ResolverPolicy.current.assignThreshold, 0.70, accuracy: 0.001)
        XCTAssertEqual(ResolverPolicy.current.createThreshold, 0.85, accuracy: 0.001)
        XCTAssertEqual(ResolverPolicy.current.maxBatchSize, 8)

        let resolver = CollectionResolver(policy: .current)
        let understanding = ScreenshotUnderstanding(
            summary: "Hotel + flight",
            entities: [UnderstandingEntity(type: "city", value: "Abu Dhabi", confidence: 0.9)],
            candidateCollections: [
                UnderstandingCandidate(title: "Abu Dhabi Trip", confidence: 0.72, reasonSignals: ["hotel"])
            ],
            proposedNewCollection: ProposedNewCollection(
                title: "Abu Dhabi Trip",
                emoji: "✈️",
                confidence: 0.88
            ),
            provider: "test",
            sharedContext: SharedBatchContext(
                title: "Trip to Abu Dhabi",
                confidence: 0.91,
                memberLocalIDs: ["a", "b"],
                evidence: ["hotel", "flight"]
            )
        )
        let decision = resolver.resolve(
            understanding: understanding,
            eligible: [],
            batchSize: 4
        )
        // Shared context may corroborate CREATE/NR path, but thresholds stay locked.
        XCTAssertTrue(
            decision.kind == .create || decision.kind == .needsReview,
            "Unexpected decision \(decision.kind)"
        )
        if decision.kind == .create {
            XCTAssertEqual(decision.applicableThreshold, 0.85, accuracy: 0.001)
        }
    }

    // MARK: - Failure → Needs Review (not stuck failed)

    func testCloudMalformedFailureRoutesToNeedsReviewNotFailed() async throws {
        CloudUnderstandingPreferences.consent = .accepted
        let database = try AppDatabase.makeEmptyInMemory()
        try DatabaseSeeder.seedIfNeeded(database)
        let memory = GRDBMemoryRepository(database: database)

        let id = ScreenshotMemoryID()
        try await database.dbPool.write { db in
            var record = ScreenshotRecord(
                memory: ScreenshotMemory(
                    id: id,
                    createdAt: Date(),
                    isFavorite: false,
                    ocrText: "noise",
                    summary: nil,
                    facetKeys: [],
                    entityLabels: [],
                    previewSymbol: "photo",
                    ocrStatus: .completed
                )
            )
            record.organizeStatus = OrganizeStatus.pending.rawValue
            try record.insert(db)
            let inbox = try CollectionRecord.fetchOne(
                db,
                sql: "SELECT * FROM context_collection WHERE kind = 'unassigned'"
            )!
            try MembershipRecord(
                screenshotID: id.rawValue.uuidString,
                collectionID: inbox.id,
                source: "photos",
                confidence: nil,
                createdAt: Date(),
                position: 0
            ).insert(db)
        }

        struct FailingUnderstanding: UnderstandingProviding {
            func understand(_ input: UnderstandingInput) async throws -> ScreenshotUnderstanding {
                throw UnderstandingError.malformed
            }
        }

        let service = OrganizationService(
            store: memory,
            understanding: FailingUnderstanding(),
            memory: memory
        )
        try await service.organizeIfNeeded(screenshotID: id)

        let status = try await memory.fetchOrganizeStatus(id: id)
        XCTAssertEqual(status, .ready, "Must not remain permanently failed")
        XCTAssertNotEqual(status, .failed)

        let kind = try await database.dbPool.read { db -> String? in
            try String.fetchOne(
                db,
                sql: """
                    SELECT c.kind FROM screenshot_context sc
                    JOIN context_collection c ON c.id = sc.collection_id
                    WHERE sc.screenshot_id = ?
                    LIMIT 1
                    """,
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertEqual(kind, "unassigned", "Cloud failure must land in Needs Review inbox")
    }

    func testBatchMemberPayloadCeilingMatchesPolicy() {
        XCTAssertEqual(ResolverPolicy.current.maxBatchSize, 8)
        XCTAssertLessThanOrEqual(ResolverPolicy.current.maxBatchSize, 8)
        XCTAssertGreaterThanOrEqual(ResolverPolicy.current.maxBatchSize, 5)
    }
}
