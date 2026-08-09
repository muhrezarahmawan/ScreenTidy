import XCTest
import GRDB
@testable import ScreenTidy

final class CollectionResolverTests: XCTestCase {
    private var policy: ResolverPolicy {
        ResolverPolicy.current
    }

    private func eligibleJapan() -> CollectionResolver.EligibleCollection {
        CollectionResolver.EligibleCollection(
            id: MockData.japanTripID,
            title: "Japan Trip",
            normalizedTitle: "japan trip",
            kind: .aiContext,
            createdBy: "ai",
            aliases: ["trip to japan"],
            keyEntities: ["tokyo", "japan"],
            keyTerms: ["hotel", "flight", "trip"],
            visualDescriptors: [],
            dateRangeStart: nil,
            dateRangeEnd: nil
        )
    }

    private func eligibleUser() -> CollectionResolver.EligibleCollection {
        CollectionResolver.EligibleCollection(
            id: ContextCollectionID(),
            title: "Personal Notes",
            normalizedTitle: "personal notes",
            kind: .userContext,
            createdBy: "user",
            aliases: [],
            keyEntities: [],
            keyTerms: [],
            visualDescriptors: [],
            dateRangeStart: nil,
            dateRangeEnd: nil
        )
    }

    func testReuseWhenConfidenceAboveAssignThreshold() {
        let resolver = CollectionResolver(policy: policy)
        let understanding = ScreenshotUnderstanding(
            summary: "Tokyo hotel",
            entities: [UnderstandingEntity(type: "city", value: "Tokyo", confidence: 0.9)],
            visualDescriptors: [],
            candidateCollections: [
                UnderstandingCandidate(title: "Japan Trip", confidence: 0.76, reasonSignals: ["tokyo"])
            ],
            proposedNewCollection: nil,
            provider: "test"
        )
        let decision = resolver.resolve(understanding: understanding, eligible: [eligibleJapan()])
        XCTAssertEqual(decision.kind, .reuse)
        XCTAssertEqual(decision.collectionID, MockData.japanTripID)
        XCTAssertEqual(decision.applicableThreshold, policy.assignThreshold)
    }

    func testNeedsReviewWhenBelowAssignThreshold() {
        let resolver = CollectionResolver(policy: policy)
        let understanding = ScreenshotUnderstanding(
            summary: nil,
            entities: [],
            visualDescriptors: [],
            candidateCollections: [
                UnderstandingCandidate(title: "Japan Trip", confidence: 0.55, reasonSignals: [])
            ],
            proposedNewCollection: nil,
            provider: "test"
        )
        let decision = resolver.resolve(understanding: understanding, eligible: [eligibleJapan()])
        XCTAssertEqual(decision.kind, .needsReview)
    }

    func testCreateRequiresCreateThreshold() {
        let resolver = CollectionResolver(policy: policy)
        let understanding = ScreenshotUnderstanding(
            summary: "Visa paperwork",
            entities: [],
            visualDescriptors: [],
            candidateCollections: [],
            proposedNewCollection: ProposedNewCollection(
                title: "Visa Application",
                emoji: "🛂",
                confidence: 0.79
            ),
            provider: "test"
        )
        let decision = resolver.resolve(understanding: understanding, eligible: [])
        XCTAssertEqual(decision.kind, .needsReview)
        XCTAssertEqual(decision.applicableThreshold, policy.createThreshold)
    }

    func testCreateRequiresCorroborationBeyondThreshold() {
        let resolver = CollectionResolver(policy: policy)
        // High confidence but object-like title should not create.
        let understanding = ScreenshotUnderstanding(
            summary: "A chair",
            typeFacets: ["product"],
            entities: [UnderstandingEntity(type: "object", value: "chair", confidence: 0.95)],
            locations: [],
            dates: [],
            visualDescriptors: ["chair"],
            candidateCollections: [],
            proposedNewCollection: ProposedNewCollection(title: "Chair", emoji: "🪑", confidence: 0.92),
            reasonSignals: [],
            provider: "test"
        )
        let decision = resolver.resolve(understanding: understanding, eligible: [])
        XCTAssertEqual(decision.kind, .needsReview)
    }

    func testCreateJapanTripWithCorroboration() {
        let resolver = CollectionResolver(policy: policy)
        let understanding = ScreenshotUnderstanding(
            summary: "Tokyo hotel + flight",
            typeFacets: ["boarding_pass"],
            entities: [
                UnderstandingEntity(type: "city", value: "Tokyo", confidence: 0.9),
                UnderstandingEntity(type: "hotel", value: "Park Hyatt", confidence: 0.88)
            ],
            locations: ["Tokyo", "Japan"],
            dates: ["2026-08-01"],
            visualDescriptors: ["boarding pass", "hotel confirmation"],
            candidateCollections: [],
            proposedNewCollection: ProposedNewCollection(title: "Japan Trip", emoji: "✈️", confidence: 0.91),
            reasonSignals: ["context"],
            provider: "test"
        )
        let decision = resolver.resolve(understanding: understanding, eligible: [], batchSize: 3)
        XCTAssertEqual(decision.kind, .create)
        XCTAssertEqual(decision.title, "Japan Trip")
        XCTAssertEqual(decision.confidenceComponents?.createCorroborated, true)
    }

    func testOrganizationOCRNormalizerStripsClock() {
        let raw = "18:29\n85%\nPark Hyatt Tokyo confirmation"
        let normalized = OrganizationOCRNormalizer.normalize(raw)
        XCTAssertFalse(normalized.contains("18:29"))
        XCTAssertTrue(normalized.contains("Park Hyatt"))
    }

    func testRejectsGenericCreateTitle() {
        let resolver = CollectionResolver(policy: policy)
        let understanding = ScreenshotUnderstanding(
            summary: nil,
            entities: [],
            visualDescriptors: [],
            candidateCollections: [],
            proposedNewCollection: ProposedNewCollection(
                title: "Travel",
                emoji: "✈️",
                confidence: 0.95
            ),
            provider: "test"
        )
        let decision = resolver.resolve(understanding: understanding, eligible: [])
        XCTAssertEqual(decision.kind, .needsReview)
    }

    func testUserCreatedCollectionNotAutoAdded() {
        let resolver = CollectionResolver(policy: policy)
        let understanding = ScreenshotUnderstanding(
            summary: "note",
            entities: [],
            visualDescriptors: [],
            candidateCollections: [
                UnderstandingCandidate(title: "Personal Notes", confidence: 0.95, reasonSignals: [])
            ],
            proposedNewCollection: nil,
            provider: "test"
        )
        let decision = resolver.resolve(understanding: understanding, eligible: [eligibleUser()])
        XCTAssertEqual(decision.kind, .needsReview)
    }

    func testAliasReuseTripToJapan() {
        let resolver = CollectionResolver(policy: policy)
        let understanding = ScreenshotUnderstanding(
            summary: "Tokyo",
            entities: [],
            visualDescriptors: [],
            candidateCollections: [
                UnderstandingCandidate(title: "Trip to Japan", confidence: 0.84, reasonSignals: [])
            ],
            proposedNewCollection: nil,
            provider: "test"
        )
        let decision = resolver.resolve(understanding: understanding, eligible: [eligibleJapan()])
        XCTAssertEqual(decision.kind, .reuse)
        XCTAssertEqual(decision.collectionID, MockData.japanTripID)
    }

    func testProposedCreateReusesExistingTitle() {
        let resolver = CollectionResolver(policy: policy)
        let understanding = ScreenshotUnderstanding(
            summary: "Tokyo hotel",
            entities: [],
            visualDescriptors: [],
            candidateCollections: [
                UnderstandingCandidate(title: "Unrelated Stuff", confidence: 0.72, reasonSignals: [])
            ],
            proposedNewCollection: ProposedNewCollection(
                title: "Japan Trip",
                emoji: "✈️",
                confidence: 0.92
            ),
            provider: "test"
        )
        let decision = resolver.resolve(understanding: understanding, eligible: [eligibleJapan()])
        XCTAssertEqual(decision.kind, .reuse)
        XCTAssertEqual(decision.collectionID, MockData.japanTripID)
        XCTAssertEqual(decision.title, "Japan Trip")
    }

    func testCreateDecisionIsFindOrCreateByNormalizedTitle() async throws {
        let database = try AppDatabase.makeEmptyInMemory()
        let memory = GRDBMemoryRepository(database: database)
        let now = Date()

        func insertPendingShot() async throws -> ScreenshotMemoryID {
            let id = ScreenshotMemoryID()
            try await database.dbPool.write { db in
                if try CollectionRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM context_collection WHERE kind = 'unassigned'"
                ) == nil {
                    try CollectionRecord(
                        id: UUID().uuidString,
                        kind: ContextCollectionKind.unassigned.rawValue,
                        title: "Needs Review",
                        normalizedTitle: "needs review",
                        badgeEmoji: "✨",
                        badgeColor: nil,
                        isPinned: false,
                        isArchived: false,
                        sortOrder: 0,
                        createdAt: now,
                        updatedAt: now,
                        createdBy: "ai",
                        insight: nil
                    ).insert(db)
                }
                var record = ScreenshotRecord(
                    memory: ScreenshotMemory(
                        id: id,
                        createdAt: now,
                        isFavorite: false,
                        ocrText: "ski pass",
                        summary: nil,
                        facetKeys: [],
                        entityLabels: [],
                        previewSymbol: "snow",
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
                    createdAt: now,
                    position: 0
                ).insert(db)
            }
            return id
        }

        let first = try await insertPendingShot()
        let second = try await insertPendingShot()
        let understanding = ScreenshotUnderstanding(
            summary: "Ski",
            entities: [],
            visualDescriptors: [],
            candidateCollections: [],
            proposedNewCollection: ProposedNewCollection(
                title: "Ski Weekend",
                emoji: "⛷️",
                confidence: 0.95
            ),
            provider: "test"
        )
        let decision = ResolverDecision(
            kind: .create,
            collectionID: nil,
            title: "Ski Weekend",
            emoji: "⛷️",
            confidence: 0.95,
            applicableThreshold: policy.createThreshold,
            reason: "test",
            candidates: []
        )

        try await memory.applyResolverDecision(
            screenshotID: first,
            decision: decision,
            understanding: understanding,
            policy: policy,
            fingerprint: "a"
        )
        try await memory.applyResolverDecision(
            screenshotID: second,
            decision: decision,
            understanding: understanding,
            policy: policy,
            fingerprint: "b"
        )

        let count = try await database.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM context_collection
                    WHERE normalized_title = ?
                    """,
                arguments: [CollectionResolver.normalizeTitle("Ski Weekend")]
            ) ?? 0
        }
        XCTAssertEqual(count, 1)

        let members = try await database.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM screenshot_context sc
                    JOIN context_collection c ON c.id = sc.collection_id
                    WHERE c.normalized_title = ?
                    """,
                arguments: [CollectionResolver.normalizeTitle("Ski Weekend")]
            ) ?? 0
        }
        XCTAssertEqual(members, 2)
    }

    func testOrganizationPipelineReusesJapanTrip() async throws {
        CloudUnderstandingPreferences.consent = .accepted
        let database = try AppDatabase.makeEmptyInMemory()
        try DatabaseSeeder.seedIfNeeded(database)
        let memory = GRDBMemoryRepository(database: database)

        let promoted = try await memory.fetchPromotedContexts()
        XCTAssertTrue(promoted.contains(where: { $0.title == "Japan Trip" }))

        let id = ScreenshotMemoryID()
        try await database.dbPool.write { db in
            var record = ScreenshotRecord(
                memory: ScreenshotMemory(
                    id: id,
                    createdAt: Date(),
                    isFavorite: false,
                    ocrText: "Park Hyatt Tokyo confirmation NRT",
                    summary: nil,
                    facetKeys: [],
                    entityLabels: [],
                    previewSymbol: "building.2",
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

        let service = OrganizationService(
            store: memory,
            understanding: OnDeviceStructuredUnderstandingProvider(),
            memory: memory
        )
        try await service.organizeIfNeeded(screenshotID: id)

        let memberships = try await database.dbPool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT c.title, sc.source FROM screenshot_context sc
                    JOIN context_collection c ON c.id = sc.collection_id
                    WHERE sc.screenshot_id = ?
                    """,
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertTrue(memberships.contains(where: { ($0["title"] as String) == "Japan Trip" }))
        XCTAssertTrue(memberships.contains(where: { ($0["source"] as String) == "ai" }))
        XCTAssertFalse(memberships.contains(where: { ($0["title"] as String) == "Needs Review" }))
    }
}
