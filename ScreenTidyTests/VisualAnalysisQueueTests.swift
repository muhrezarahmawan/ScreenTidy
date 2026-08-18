import CoreGraphics
import XCTest
@testable import ScreenTidy

/// Sprint 8.0 — Visual Analysis queue foundation health.
final class VisualAnalysisQueueTests: XCTestCase {
    private var database: AppDatabase!
    private var repository: GRDBMemoryRepository!

    override func setUp() async throws {
        try await super.setUp()
        database = try AppDatabase.makeEmptyInMemory()
        try DatabaseSeeder.seedIfNeeded(database)
        try await repositoryClearPhotos()
        repository = GRDBMemoryRepository(database: database)
        VisualAnalysisDebugRuntime.update { $0 = VisualAnalysisQueueDiagnostics() }
    }

    override func tearDown() async throws {
        repository = nil
        database = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func repositoryClearPhotos() async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: "DELETE FROM screenshot WHERE source = 'photos'")
            try db.execute(sql: "DELETE FROM screenshot")
        }
    }

    @discardableResult
    private func insertClaimable(
        localID: String,
        createdAt: Date = Date()
    ) async throws -> ScreenshotMemoryID {
        _ = try await repository.upsertPhotoScreenshots([
            PhotoAssetMetadata(
                localIdentifier: localID,
                createdAt: createdAt,
                width: 100,
                height: 200
            )
        ])
        let idString = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT id FROM screenshot WHERE photos_local_identifier = ?",
                arguments: [localID]
            )
        }
        let uuid = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(idString)))
        return ScreenshotMemoryID(uuid)
    }

    private func setVisual(
        id: ScreenshotMemoryID,
        status: ScreenshotVisualStatus,
        access: ScreenshotAccessState = .available,
        removed: Bool = false,
        labelsJSON: String = "[]",
        featurePrint: Data? = nil,
        claimedAt: Date? = nil,
        clearLocalID: Bool = false
    ) async throws {
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshot
                    SET visual_status = ?,
                        access_state = ?,
                        is_removed_from_app = ?,
                        visual_labels_json = ?,
                        feature_print = ?,
                        feature_print_status = ?,
                        visual_claimed_at = ?,
                        photos_local_identifier = CASE WHEN ? THEN NULL ELSE photos_local_identifier END,
                        updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    status.rawValue,
                    access.rawValue,
                    removed,
                    labelsJSON,
                    featurePrint,
                    featurePrint == nil ? "missing" : "generated",
                    claimedAt,
                    clearLocalID,
                    Date(),
                    id.rawValue.uuidString
                ]
            )
        }
    }

    private func status(of id: ScreenshotMemoryID) async throws -> String {
        try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT visual_status FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            ) ?? ""
        }
    }

    private func labelsJSON(of id: ScreenshotMemoryID) async throws -> String {
        try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT visual_labels_json FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            ) ?? "[]"
        }
    }

    private func makeCGImage() -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    // MARK: - Claimability

    func testClaimableVsNonClaimablePending() async throws {
        let claimable = try await insertClaimable(localID: "A")
        let missingID = try await insertClaimable(localID: "missing-id-row")
        try await setVisual(id: missingID, status: .pending, clearLocalID: true)
        let inaccessible = try await insertClaimable(localID: "B")
        try await setVisual(id: inaccessible, status: .pending, access: .inaccessible)
        let removed = try await insertClaimable(localID: "C")
        try await setVisual(id: removed, status: .pending, removed: true)

        let breakdown = try await repository.fetchVisualClaimabilityBreakdown()
        XCTAssertEqual(breakdown.pendingTotal, 4)
        XCTAssertEqual(breakdown.claimable, 1)
        XCTAssertEqual(breakdown.missingLocalID, 1)
        XCTAssertEqual(breakdown.inaccessibleAccess, 1)
        XCTAssertEqual(breakdown.removedFromApp, 1)

        let claim = try await repository.claimNextVisualJob(
            currentVersion: VisualAnalysisPipeline.currentVersion,
            now: Date()
        )
        XCTAssertEqual(claim?.id, claimable)
        XCTAssertEqual(claim?.photosLocalIdentifier, "A")
    }

    func testClaimTransitionsPendingToProcessing() async throws {
        let id = try await insertClaimable(localID: "shot-1")
        let claim = try await repository.claimNextVisualJob(
            currentVersion: VisualAnalysisPipeline.currentVersion,
            now: Date()
        )
        XCTAssertEqual(claim?.id, id)
        let __s_id = try await status(of: id)
        XCTAssertEqual(__s_id, "processing")
    }

    // MARK: - Complete / fail / inaccessible

    func testCompletePersistsLabelsAndFeaturePrint() async throws {
        let id = try await insertClaimable(localID: "shot-2")
        _ = try await repository.claimNextVisualJob(
            currentVersion: VisualAnalysisPipeline.currentVersion,
            now: Date()
        )
        let printData = Data([0x01, 0x02, 0x03])
        try await repository.completeVisualSuccess(
            id: id,
            result: VisualAnalysisResult(
                labels: [VisualLabelObservation(identifier: "sofa", confidence: 0.9)],
                featurePrintData: printData,
                classifyRevision: 2,
                featurePrintRevision: 2,
                facets: ["image_only"]
            ),
            version: VisualAnalysisPipeline.currentVersion
        )
        let __s_id = try await status(of: id)
        XCTAssertEqual(__s_id, "completed")
        let json = try await labelsJSON(of: id)
        XCTAssertTrue(json.contains("sofa"))
        let stored = try await repository.fetchFeaturePrintData(id: id)
        XCTAssertEqual(stored, printData)
        let counts = try await repository.fetchVisualStatusCounts()
        XCTAssertEqual(counts.completed, 1)
        XCTAssertEqual(counts.pending, 0)
        let rawJSON = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT visual_labels_raw_json FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        // Older helpers may omit rawLabels — still valid empty array.
        XCTAssertNotNil(rawJSON)
    }

    func testCompletePersistsRawAndFilteredLabels() async throws {
        let id = try await insertClaimable(localID: "raw-labels")
        _ = try await repository.claimNextVisualJob(
            currentVersion: VisualAnalysisPipeline.currentVersion,
            now: Date()
        )
        try await repository.completeVisualSuccess(
            id: id,
            result: VisualAnalysisResult(
                labels: [VisualLabelObservation(identifier: "sofa", confidence: 0.9)],
                rawLabels: [
                    VisualLabelObservation(identifier: "sofa", confidence: 0.9),
                    VisualLabelObservation(identifier: "indoor", confidence: 0.8)
                ],
                featurePrintData: Data([1]),
                classifyRevision: 2,
                featurePrintRevision: 2,
                facets: ["image_only"],
                featurePrintStatus: "generated",
                analysisLongEdge: 1_024
            ),
            version: VisualAnalysisPipeline.currentVersion
        )
        let snapshots = try await repository.fetchVisualDebugSnapshots(limit: 5)
        let row = try XCTUnwrap(snapshots.first { $0.id == id })
        XCTAssertTrue(row.labels.contains { $0.identifier == "sofa" })
        XCTAssertTrue(row.rawLabels.contains { $0.identifier == "indoor" })
        XCTAssertTrue(row.isImageOnlyEvidence)
        XCTAssertTrue(row.analysisInputNote.contains("1024"))
    }

    func testCompletePersistsFacetEvidenceWithStrength() async throws {
        let id = try await insertClaimable(localID: "facet-evidence")
        try await database.dbPool.write { db in
            try db.execute(
                sql: "UPDATE screenshot SET ocr_text = ?, ocr_status = 'completed' WHERE id = ?",
                arguments: [
                    "Flight details AUH CGK Terminal 3 Check-in opens Passenger Manage trip",
                    id.rawValue.uuidString
                ]
            )
        }
        _ = try await repository.claimNextVisualJob(
            currentVersion: VisualAnalysisPipeline.currentVersion,
            now: Date()
        )
        try await repository.completeVisualSuccess(
            id: id,
            result: VisualAnalysisResult(
                labels: [VisualLabelObservation(identifier: "document", confidence: 0.9)],
                rawLabels: [VisualLabelObservation(identifier: "document", confidence: 0.9)],
                featurePrintData: Data([1]),
                classifyRevision: 2,
                featurePrintRevision: 2,
                facets: [],
                featurePrintStatus: "generated",
                analysisLongEdge: 1_024
            ),
            version: VisualAnalysisPipeline.currentVersion
        )
        let evidenceJSON = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT visual_facets_evidence_json FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        let evidence = ScreenshotRecord.decodeFacetEvidence(try XCTUnwrap(evidenceJSON))
        XCTAssertFalse(evidence.isEmpty)
        XCTAssertFalse(evidence.contains { $0.id == "hotel_booking" })
        let facetsJSON = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT visual_facets_json FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        let strong = ScreenshotRecord.array(try XCTUnwrap(facetsJSON))
        XCTAssertTrue(strong.contains("flight_booking") || strong.contains("boarding_pass"))
        XCTAssertFalse(strong.contains("hotel_booking"))
    }

    func testImageUnavailableBecomesInaccessible() async throws {
        let id = try await insertClaimable(localID: "missing")
        _ = try await repository.claimNextVisualJob(
            currentVersion: VisualAnalysisPipeline.currentVersion,
            now: Date()
        )
        try await repository.completeVisualInaccessible(id: id, errorCode: "image_unavailable")
        let __s_id = try await status(of: id)
        XCTAssertEqual(__s_id, "inaccessible")
        let counts = try await repository.fetchVisualStatusCounts()
        XCTAssertEqual(counts.inaccessible, 1)
    }

    func testFailureIncrementsAttemptsAndRetries() async throws {
        let id = try await insertClaimable(localID: "fail-1")
        _ = try await repository.claimNextVisualJob(
            currentVersion: VisualAnalysisPipeline.currentVersion,
            now: Date()
        )
        try await repository.completeVisualFailure(id: id, errorCode: "vision_failed")
        let __s_id = try await status(of: id)
        XCTAssertEqual(__s_id, "failed")
        let attempt = try await database.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT visual_attempt_count FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertEqual(attempt, 1)
        let next = try await database.dbPool.read { db in
            try Date.fetchOne(
                db,
                sql: "SELECT visual_next_retry_at FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertNotNil(next)
    }

    // MARK: - Stale recovery + reprocess

    func testStaleProcessingClaimRecovered() async throws {
        let id = try await insertClaimable(localID: "stale")
        try await setVisual(
            id: id,
            status: .processing,
            claimedAt: Date().addingTimeInterval(-120)
        )
        let recovered = try await repository.recoverStaleVisualClaims(
            olderThan: Date().addingTimeInterval(-VisualAnalysisPipeline.staleClaimInterval)
        )
        XCTAssertEqual(recovered, 1)
        let __s_id = try await status(of: id)
        XCTAssertEqual(__s_id, "pending")
    }

    func testReprocessClearsStaleVisualOutputs() async throws {
        let id = try await insertClaimable(localID: "repro")
        try await setVisual(
            id: id,
            status: .completed,
            labelsJSON: #"[{"identifier":"document","confidence":0.95}]"#,
            featurePrint: Data([9, 9, 9])
        )
        try await repository.requestVisualReprocess(id: id)
        let __s_id = try await status(of: id)
        XCTAssertEqual(__s_id, "pending")
        let labels = try await labelsJSON(of: id)
        XCTAssertEqual(labels, "[]")
        let print = try await repository.fetchFeaturePrintData(id: id)
        XCTAssertNil(print)
        let featureStatus = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT feature_print_status FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertEqual(featureStatus, "missing")
    }

    // MARK: - Worker drain across multiple screenshots

    func testQueueDrainsMultipleScreenshotsWithoutPerItemKick() async throws {
        let ids = [
            try await insertClaimable(localID: "q1", createdAt: Date().addingTimeInterval(-3)),
            try await insertClaimable(localID: "q2", createdAt: Date().addingTimeInterval(-2)),
            try await insertClaimable(localID: "q3", createdAt: Date().addingTimeInterval(-1))
        ]

        let analyzer = MockVisualAnalysisService(
            result: VisualAnalysisResult(
                labels: [VisualLabelObservation(identifier: "sofa", confidence: 0.88)],
                featurePrintData: Data([1, 2, 3, 4]),
                classifyRevision: 2,
                featurePrintRevision: 2,
                facets: ["image_only"]
            )
        )
        let images = StubVisualImageLoader(image: makeCGImage())
        let queue = VisualAnalysisProcessingQueue(
            repository: repository,
            analyzer: analyzer,
            images: images
        )

        queue.kick()

        let deadline = Date().addingTimeInterval(5)
        var completed = 0
        while Date() < deadline {
            let counts = try await repository.fetchVisualStatusCounts()
            completed = counts.completed
            if completed == 3 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(completed, 3, "Queue should drain all claimable pending after one kick")
        for id in ids {
            let statusValue = try await status(of: id)
            XCTAssertEqual(statusValue, "completed")
            let json = try await labelsJSON(of: id)
            XCTAssertTrue(json.contains("sofa"))
        }
        let diagnostics = VisualAnalysisDebugRuntime.current()
        XCTAssertGreaterThanOrEqual(diagnostics.processedThisSession, 3)
        XCTAssertNotNil(diagnostics.lastWakeAt)
    }

    func testKickDoesNotClaimNonClaimableRows() async throws {
        let id = try await insertClaimable(localID: "non-claim")
        try await setVisual(id: id, status: .pending, clearLocalID: true)
        let analyzer = MockVisualAnalysisService()
        let images = StubVisualImageLoader(image: makeCGImage())
        let queue = VisualAnalysisProcessingQueue(
            repository: repository,
            analyzer: analyzer,
            images: images
        )
        queue.kick()
        try await Task.sleep(nanoseconds: 250_000_000)
        let counts = try await repository.fetchVisualStatusCounts()
        XCTAssertEqual(counts.completed, 0)
        XCTAssertEqual(counts.pending, 1)
        XCTAssertEqual(VisualAnalysisDebugRuntime.current().lastClaimResult, "empty")
    }

    func testQueueMapsImageUnavailableToInaccessibleAndContinues() async throws {
        let bad = try await insertClaimable(localID: "bad-asset", createdAt: Date().addingTimeInterval(-2))
        let good = try await insertClaimable(localID: "good-asset", createdAt: Date().addingTimeInterval(-1))

        let analyzer = MockVisualAnalysisService(
            result: VisualAnalysisResult(
                labels: [VisualLabelObservation(identifier: "sofa", confidence: 0.9)],
                featurePrintData: Data([7]),
                classifyRevision: 2,
                featurePrintRevision: 2,
                facets: [],
                featurePrintStatus: "generated"
            )
        )
        let images = FailingThenSucceedingImageLoader(
            failLocalID: "bad-asset",
            failError: .photokitMissingAsset,
            image: makeCGImage()
        )
        let queue = VisualAnalysisProcessingQueue(
            repository: repository,
            analyzer: analyzer,
            images: images
        )
        queue.kick()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let counts = try await repository.fetchVisualStatusCounts()
            if counts.completed == 1 && counts.inaccessible == 1 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let __s_bad = try await status(of: bad)
        XCTAssertEqual(__s_bad, "inaccessible")
        let __s_good = try await status(of: good)
        XCTAssertEqual(__s_good, "completed")
    }

    // MARK: - Sprint 8.0 failure remediation

    func testFailureAggregationByPersistedErrorCode() async throws {
        let a = try await insertClaimable(localID: "agg-a")
        let b = try await insertClaimable(localID: "agg-b")
        let c = try await insertClaimable(localID: "agg-c")
        for _ in [a, b, c] {
            _ = try await repository.claimNextVisualJob(
                currentVersion: VisualAnalysisPipeline.currentVersion,
                now: Date()
            )
        }
        try await repository.completeVisualFailure(id: a, errorCode: VisualAnalysisErrorCode.visionFailedLegacy)
        try await repository.completeVisualFailure(id: b, errorCode: VisualAnalysisErrorCode.visionFailedLegacy)
        try await repository.completeVisualFailure(id: c, errorCode: VisualAnalysisErrorCode.photokitTimeout)

        let summary = try await repository.fetchVisualFailureSummary()
        XCTAssertEqual(summary.totalFailed, 3)
        let map = Dictionary(uniqueKeysWithValues: summary.byErrorCode.map { ($0.code, $0.count) })
        XCTAssertEqual(map[VisualAnalysisErrorCode.visionFailedLegacy], 2)
        XCTAssertEqual(map[VisualAnalysisErrorCode.photokitTimeout], 1)
        XCTAssertFalse(summary.attemptBuckets.isEmpty)

        let failed = try await repository.fetchVisualFailedDebugSnapshots(limit: 10)
        XCTAssertEqual(failed.count, 3)
        XCTAssertTrue(failed.allSatisfy { $0.visualStatus == .failed })
        XCTAssertTrue(failed.allSatisfy { ($0.visualLastError?.isEmpty == false) })
    }

    func testClassifySuccessFeaturePrintSuccess() async throws {
        let id = try await insertClaimable(localID: "both-ok")
        _ = try await repository.claimNextVisualJob(
            currentVersion: VisualAnalysisPipeline.currentVersion,
            now: Date()
        )
        let printData = Data([4, 5, 6])
        try await repository.completeVisualSuccess(
            id: id,
            result: VisualAnalysisResult(
                labels: [VisualLabelObservation(identifier: "sofa", confidence: 0.91)],
                featurePrintData: printData,
                classifyRevision: 2,
                featurePrintRevision: 2,
                facets: ["image_only"],
                featurePrintStatus: "generated"
            ),
            version: VisualAnalysisPipeline.currentVersion
        )
        let statusValue = try await status(of: id)
        XCTAssertEqual(statusValue, "completed")
        let fpStatus = try await featurePrintStatus(of: id)
        XCTAssertEqual(fpStatus, "generated")
        let storedPrint = try await repository.fetchFeaturePrintData(id: id)
        XCTAssertEqual(storedPrint, printData)
        let labelsValue = try await labelsJSON(of: id)
        XCTAssertTrue(labelsValue.contains("sofa"))
    }

    func testClassifySuccessFeaturePrintFailureKeepsLabels() async throws {
        let id = try await insertClaimable(localID: "partial-fp")
        _ = try await repository.claimNextVisualJob(
            currentVersion: VisualAnalysisPipeline.currentVersion,
            now: Date()
        )
        try await repository.completeVisualSuccess(
            id: id,
            result: VisualAnalysisResult(
                labels: [VisualLabelObservation(identifier: "sofa", confidence: 0.88)],
                featurePrintData: nil,
                classifyRevision: 2,
                featurePrintRevision: 2,
                facets: ["image_only"],
                featurePrintStatus: "failed",
                featurePrintErrorCode: VisualAnalysisErrorCode.visionFeaturePrintFailed
            ),
            version: VisualAnalysisPipeline.currentVersion
        )
        let statusValue = try await status(of: id)
        XCTAssertEqual(statusValue, "completed")
        let fpStatus = try await featurePrintStatus(of: id)
        XCTAssertEqual(fpStatus, "failed")
        let missingPrint = try await repository.fetchFeaturePrintData(id: id)
        XCTAssertNil(missingPrint)
        let labelsValue = try await labelsJSON(of: id)
        XCTAssertTrue(labelsValue.contains("sofa"))
        let lastError = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT visual_last_error FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertNil(lastError)
        let counts = try await repository.fetchVisualStatusCounts()
        XCTAssertEqual(counts.completedFeaturePrintFailed, 1)
    }

    func testClassifyFailureIsRetryableFailed() async throws {
        let id = try await insertClaimable(localID: "classify-fail")
        let analyzer = MockVisualAnalysisService(behavior: .classifyFail)
        let queue = VisualAnalysisProcessingQueue(
            repository: repository,
            analyzer: analyzer,
            images: StubVisualImageLoader(image: makeCGImage())
        )
        queue.kick()
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if try await status(of: id) == "failed" { break }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        let statusValue = try await status(of: id)
        XCTAssertEqual(statusValue, "failed")
        let err = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT visual_last_error FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertEqual(err, VisualAnalysisErrorCode.visionClassifyFailed)
        let next = try await database.dbPool.read { db in
            try Date.fetchOne(
                db,
                sql: "SELECT visual_next_retry_at FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertNotNil(next)
    }

    func testPhotoKitTimeoutIsTransientFailedNotInaccessible() async throws {
        let id = try await insertClaimable(localID: "timeout-asset")
        let analyzer = MockVisualAnalysisService()
        let images = FailingThenSucceedingImageLoader(
            failLocalID: "timeout-asset",
            failError: .photokitTimeout,
            image: makeCGImage()
        )
        let queue = VisualAnalysisProcessingQueue(
            repository: repository,
            analyzer: analyzer,
            images: images
        )
        queue.kick()
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if try await status(of: id) == "failed" { break }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        let statusValue = try await status(of: id)
        XCTAssertEqual(statusValue, "failed")
        let counts = try await repository.fetchVisualStatusCounts()
        XCTAssertEqual(counts.inaccessible, 0)
        let err = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT visual_last_error FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertEqual(err, VisualAnalysisErrorCode.photokitTimeout)
    }

    func testMissingPHAssetIsInaccessible() async throws {
        let id = try await insertClaimable(localID: "gone-asset")
        let analyzer = MockVisualAnalysisService()
        let images = FailingThenSucceedingImageLoader(
            failLocalID: "gone-asset",
            failError: .photokitMissingAsset,
            image: makeCGImage()
        )
        let queue = VisualAnalysisProcessingQueue(
            repository: repository,
            analyzer: analyzer,
            images: images
        )
        queue.kick()
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if try await status(of: id) == "inaccessible" { break }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        let statusValue = try await status(of: id)
        XCTAssertEqual(statusValue, "inaccessible")
        let err = try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT visual_last_error FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertEqual(err, VisualAnalysisErrorCode.photokitMissingAsset)
    }

    func testBoundedRetriesExhaustEventually() async throws {
        let id = try await insertClaimable(localID: "retry-bound")
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshot
                    SET visual_status = 'processing',
                        visual_attempt_count = ?
                    WHERE id = ?
                    """,
                arguments: [VisualAnalysisPipeline.maxAttempts - 1, id.rawValue.uuidString]
            )
        }
        try await repository.completeVisualFailure(
            id: id,
            errorCode: VisualAnalysisErrorCode.visionClassifyFailed
        )
        let attempt = try await database.dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT visual_attempt_count FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertEqual(attempt, VisualAnalysisPipeline.maxAttempts)
        let next = try await database.dbPool.read { db in
            try Date.fetchOne(
                db,
                sql: "SELECT visual_next_retry_at FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            )
        }
        XCTAssertNil(next)
    }

    func testTargetedReprocessThenPartialSuccessPersistsAcrossReload() async throws {
        let id = try await insertClaimable(localID: "repro-target")
        _ = try await repository.claimNextVisualJob(
            currentVersion: VisualAnalysisPipeline.currentVersion,
            now: Date()
        )
        try await repository.completeVisualFailure(
            id: id,
            errorCode: VisualAnalysisErrorCode.visionFailedLegacy
        )
        try await repository.requestVisualReprocess(id: id)
        _ = try await repository.claimNextVisualJob(
            currentVersion: VisualAnalysisPipeline.currentVersion,
            now: Date()
        )
        try await repository.completeVisualSuccess(
            id: id,
            result: VisualAnalysisResult(
                labels: [VisualLabelObservation(identifier: "chair", confidence: 0.8)],
                featurePrintData: nil,
                classifyRevision: 2,
                featurePrintRevision: 2,
                facets: [],
                featurePrintStatus: "failed",
                featurePrintErrorCode: VisualAnalysisErrorCode.featurePrintArchiveFailed
            ),
            version: VisualAnalysisPipeline.currentVersion
        )

        let reloaded = GRDBMemoryRepository(database: database)
        let snapshots = try await reloaded.fetchVisualDebugSnapshots(limit: 5)
        let row = try XCTUnwrap(snapshots.first { $0.id == id })
        XCTAssertEqual(row.visualStatus, .completed)
        XCTAssertEqual(row.featurePrintStatus, "failed")
        XCTAssertTrue(row.labels.contains { $0.identifier == "chair" })
        XCTAssertNil(row.visualLastError)
    }

    func testQueuePartialFeaturePrintFailureCompletesWithLabels() async throws {
        let id = try await insertClaimable(localID: "queue-partial")
        let analyzer = MockVisualAnalysisService(
            result: VisualAnalysisResult(
                labels: [VisualLabelObservation(identifier: "table", confidence: 0.77)],
                featurePrintData: nil,
                classifyRevision: 2,
                featurePrintRevision: 2,
                facets: ["image_only"],
                featurePrintStatus: "failed",
                featurePrintErrorCode: VisualAnalysisErrorCode.visionFeaturePrintFailed
            )
        )
        let queue = VisualAnalysisProcessingQueue(
            repository: repository,
            analyzer: analyzer,
            images: StubVisualImageLoader(image: makeCGImage())
        )
        queue.kick()
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if try await status(of: id) == "completed" { break }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        let statusValue = try await status(of: id)
        XCTAssertEqual(statusValue, "completed")
        let labelsValue = try await labelsJSON(of: id)
        XCTAssertTrue(labelsValue.contains("table"))
        let fpStatus = try await featurePrintStatus(of: id)
        XCTAssertEqual(fpStatus, "failed")
    }

    // MARK: - DEBUG list pagination (Sprint 8.1 browse-all)

    func testVisualDebugListPagePaginationNoDuplicatesAndStableOrder() async throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var ids: [ScreenshotMemoryID] = []
        for index in 0..<7 {
            let id = try await insertClaimable(
                localID: "page-\(index)",
                createdAt: base.addingTimeInterval(TimeInterval(index))
            )
            try await setVisual(
                id: id,
                status: .completed,
                labelsJSON: "[{\"identifier\":\"lamp\",\"confidence\":0.9}]",
                featurePrint: Data([UInt8(index)])
            )
            ids.append(id)
        }
        // Newest created_at first: index 6 … 0
        let expectedOrder = Array(ids.reversed())

        let pageSize = 3
        let page0 = try await repository.fetchVisualDebugListPage(offset: 0, limit: pageSize)
        let page1 = try await repository.fetchVisualDebugListPage(offset: pageSize, limit: pageSize)
        let page2 = try await repository.fetchVisualDebugListPage(offset: pageSize * 2, limit: pageSize)

        XCTAssertEqual(page0.map(\.id), Array(expectedOrder.prefix(3)))
        XCTAssertEqual(page1.map(\.id), Array(expectedOrder.dropFirst(3).prefix(3)))
        XCTAssertEqual(page2.map(\.id), Array(expectedOrder.dropFirst(6).prefix(3)))
        XCTAssertEqual(page2.count, 1, "final page is partial")

        let allIDs = (page0 + page1 + page2).map(\.id)
        XCTAssertEqual(Set(allIDs).count, allIDs.count, "no duplicates across pages")
        XCTAssertEqual(allIDs, expectedOrder)

        // List rows stay lightweight — neighbors/cluster deferred to detail.
        XCTAssertTrue(page0.allSatisfy { $0.neighbors.isEmpty && $0.clusterMembers.isEmpty })
    }

    func testVisualDebugListPageEmptyAndExcludesNonCompleted() async throws {
        let empty = try await repository.fetchVisualDebugListPage(offset: 0, limit: 40)
        XCTAssertTrue(empty.isEmpty)

        let pending = try await insertClaimable(localID: "still-pending")
        let completed = try await insertClaimable(
            localID: "done-only",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try await setVisual(id: completed, status: .completed, labelsJSON: "[]")
        _ = pending

        let page = try await repository.fetchVisualDebugListPage(offset: 0, limit: 40)
        XCTAssertEqual(page.map(\.id), [completed])
    }

    func testVisualDebugDetailLoadsNeighborsSeparatelyFromList() async throws {
        let a = try await insertClaimable(localID: "detail-a", createdAt: Date(timeIntervalSince1970: 10))
        let b = try await insertClaimable(localID: "detail-b", createdAt: Date(timeIntervalSince1970: 20))
        // Identical prints → detail should surface a neighbor; list must not.
        let printData = Data(repeating: 7, count: 16)
        try await setVisual(id: a, status: .completed, featurePrint: printData)
        try await setVisual(id: b, status: .completed, featurePrint: printData)

        let list = try await repository.fetchVisualDebugListPage(offset: 0, limit: 10)
        XCTAssertEqual(list.count, 2)
        XCTAssertTrue(list.allSatisfy { $0.neighbors.isEmpty })

        let detail = try await repository.fetchVisualDebugDetailSnapshot(id: b)
        let detailRow = try XCTUnwrap(detail)
        XCTAssertEqual(detailRow.id, b)
        // Neighbor computation requires Vision distance; may be empty if prints aren't valid VNFeaturePrintObservation archives.
        // Detail path must at least run includeNeighbors build without dropping the row.
        XCTAssertEqual(detailRow.visualStatus, .completed)
    }

    func testVisualDebugDetailPassesPeersToCandidateGrouping() async throws {
        let collectionsBefore = try await repository.contexts().count

        let seed = try await insertClaimable(localID: "cluster-seed", createdAt: Date(timeIntervalSince1970: 100))
        let peerA = try await insertClaimable(localID: "cluster-peer-a", createdAt: Date(timeIntervalSince1970: 90))
        let peerB = try await insertClaimable(localID: "cluster-peer-b", createdAt: Date(timeIntervalSince1970: 80))
        try await setVisual(id: seed, status: .completed)
        try await setVisual(id: peerA, status: .completed)
        try await setVisual(id: peerB, status: .completed)
        try await database.dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshot SET ocr_text = ?, ocr_status = 'completed',
                      visual_facets_json = ?
                    WHERE id = ?
                    """,
                arguments: ["park hyatt tokyo reservation", "[\"hotel_booking\"]", seed.rawValue.uuidString]
            )
            try db.execute(
                sql: """
                    UPDATE screenshot SET ocr_text = ?, ocr_status = 'completed',
                      visual_facets_json = ?
                    WHERE id = ?
                    """,
                arguments: ["boarding pass seat 12a", "[\"boarding_pass\"]", peerA.rawValue.uuidString]
            )
            try db.execute(
                sql: """
                    UPDATE screenshot SET ocr_text = ?, ocr_status = 'completed',
                      visual_facets_json = ?
                    WHERE id = ?
                    """,
                arguments: ["grocery list milk eggs", "[]", peerB.rawValue.uuidString]
            )
        }

        let list = try await repository.fetchVisualDebugListPage(offset: 0, limit: 10)
        XCTAssertTrue(list.allSatisfy { $0.clusterInputPeerCount == 0 })
        XCTAssertTrue(list.allSatisfy { $0.clusterRejectedCandidates.isEmpty })

        let detailOptional = try await repository.fetchVisualDebugDetailSnapshot(id: seed)
        let detail = try XCTUnwrap(detailOptional)
        XCTAssertEqual(detail.clusterInputPeerCount, 2, "detail must score peers, not seed-only")
        XCTAssertNotEqual(detail.clusterSingletonReason, "no_peers_in_pool")
        // Unrelated / below-threshold peers should surface as rejected diagnostics.
        XCTAssertFalse(detail.clusterRejectedCandidates.isEmpty)
        XCTAssertTrue(
            detail.clusterRejectedCandidates.contains { $0.rejectionReason == "below_admit_threshold" }
                || detail.clusterRejectedCandidates.contains { $0.rejectionReason == "no_contextual_support" }
        )

        let collectionsAfter = try await repository.contexts().count
        XCTAssertEqual(collectionsBefore, collectionsAfter, "DEBUG detail must not mutate Collections")
    }

    func testVisualDebugDetailSeedOnlyLibraryReportsNoPeersInPool() async throws {
        let only = try await insertClaimable(localID: "lonely-seed")
        try await setVisual(id: only, status: .completed)
        let detailOptional = try await repository.fetchVisualDebugDetailSnapshot(id: only)
        let detail = try XCTUnwrap(detailOptional)
        XCTAssertEqual(detail.clusterInputPeerCount, 0)
        XCTAssertEqual(detail.clusterSingletonReason, "no_peers_in_pool")
        XCTAssertTrue(detail.clusterRejectedCandidates.isEmpty)
    }

    func testVisualDebugListPageZeroLimitAndBeyondEnd() async throws {
        let id = try await insertClaimable(localID: "one-done")
        try await setVisual(id: id, status: .completed)
        let zeroLimit = try await repository.fetchVisualDebugListPage(offset: 0, limit: 0)
        XCTAssertTrue(zeroLimit.isEmpty)
        let beyondEnd = try await repository.fetchVisualDebugListPage(offset: 50, limit: 10)
        XCTAssertTrue(beyondEnd.isEmpty)
    }

    private func featurePrintStatus(of id: ScreenshotMemoryID) async throws -> String {
        try await database.dbPool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT feature_print_status FROM screenshot WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            ) ?? ""
        }
    }
}

// MARK: - Stubs

private final class StubVisualImageLoader: OCRImageLoading, @unchecked Sendable {
    let image: CGImage
    init(image: CGImage) { self.image = image }
    func loadCGImage(localIdentifier: String) async throws -> CGImage { image }
}

private final class FailingThenSucceedingImageLoader: OCRImageLoading, @unchecked Sendable {
    let failLocalID: String
    let failError: OCRJobError
    let image: CGImage
    init(failLocalID: String, failError: OCRJobError, image: CGImage) {
        self.failLocalID = failLocalID
        self.failError = failError
        self.image = image
    }

    func loadCGImage(localIdentifier: String) async throws -> CGImage {
        if localIdentifier == failLocalID {
            throw failError
        }
        return image
    }
}
