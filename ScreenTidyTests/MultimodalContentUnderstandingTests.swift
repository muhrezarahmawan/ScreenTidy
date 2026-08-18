import XCTest
@testable import ScreenTidy

final class MultimodalContentUnderstandingTests: XCTestCase {
    func testSchemaVersionConstant() {
        XCTAssertEqual(MultimodalContentUnderstanding.schemaVersion, "8.3a-content-v1")
    }

    func testDecodeContentUnderstandingPayload() throws {
        let json = """
        {
          "surface": { "id": "app_screen", "confidence": 0.95 },
          "platform": { "id": "whatsapp", "confidence": 0.96 },
          "contentType": { "id": "chat", "confidence": 0.98 },
          "contentFamily": { "id": "messaging", "confidence": 0.98 },
          "embeddedHints": [],
          "openDescriptors": ["conversation", "message_bubbles"],
          "evidenceNotes": ["WhatsApp-style conversation UI"],
          "disagreesWithLocal": true,
          "provider": "openai",
          "promptVersion": "screentidy-content-8.3a-v1",
          "schemaVersion": "8.3a-content-v1"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MultimodalContentUnderstanding.self, from: json)
        XCTAssertEqual(decoded.platform.id, "whatsapp")
        XCTAssertEqual(decoded.contentType.id, "chat")
        XCTAssertEqual(decoded.contentFamily.id, "messaging")
        XCTAssertEqual(decoded.surface.id, "app_screen")
        XCTAssertTrue(decoded.disagreesWithLocal)
        XCTAssertFalse(decoded.containsForbiddenCollectionFields)
    }

    func testDecodeLockScreenEmbeddedGmail() throws {
        let json = """
        {
          "surface": { "id": "lock_screen", "confidence": 0.97 },
          "platform": { "id": "unknown", "confidence": 0.9 },
          "contentType": { "id": "unknown", "confidence": 0.85 },
          "contentFamily": { "id": "unknown", "confidence": 0.85 },
          "embeddedHints": [
            { "id": "gmail", "kind": "notification", "confidence": 0.92 }
          ],
          "openDescriptors": ["lock_screen", "notification"],
          "evidenceNotes": ["Gmail notification on lock screen; not a Gmail app screen"],
          "disagreesWithLocal": false,
          "schemaVersion": "8.3a-content-v1"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MultimodalContentUnderstanding.self, from: json)
        XCTAssertEqual(decoded.surface.id, "lock_screen")
        XCTAssertEqual(decoded.platform.id, "unknown")
        XCTAssertEqual(decoded.contentType.id, "unknown")
        XCTAssertEqual(decoded.embeddedHints.first?.id, "gmail")
        XCTAssertEqual(decoded.embeddedHints.first?.kind, "notification")
    }

    func testForbiddenCollectionLeakageDetection() {
        let understanding = MultimodalContentUnderstanding(
            surface: .init(id: "app_screen", confidence: 1),
            platform: .init(id: "linkedin", confidence: 0.9),
            contentType: .init(id: "social_post", confidence: 0.9),
            contentFamily: .init(id: "social_media", confidence: 0.9),
            embeddedHints: [],
            openDescriptors: [],
            evidenceNotes: ["create collection called LinkedIn"],
            disagreesWithLocal: true
        )
        XCTAssertTrue(understanding.containsForbiddenCollectionFields)
    }

    func testLocalEvidenceEncodingOmitsCollections() throws {
        let evidence = MultimodalContentLocalEvidence(
            ocrText: "hello",
            visionLabels: ["document"],
            facets: ["chat"],
            platform: "unknown",
            contentType: "unknown",
            contentFamily: "unknown",
            surface: "app_screen",
            embeddedHints: [],
            createdAt: nil
        )
        let data = try JSONEncoder().encode(evidence)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(obj["eligibleCollections"])
        XCTAssertNil(obj["collectionTitles"])
        XCTAssertEqual(obj["surface"] as? String, "app_screen")
    }

    func testLabErrorsAreDistinct() {
        XCTAssertNotEqual(
            MultimodalContentLabError.consentDeclined,
            MultimodalContentLabError.gatewayUnavailable
        )
        XCTAssertEqual(
            MultimodalContentLabError.consentRequired,
            MultimodalContentLabError.consentRequired
        )
    }
}
