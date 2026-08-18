import Foundation

/// Sprint 8.3A — multimodal screenshot CONTENT understanding (DEBUG Lab).
/// Taxonomy-neutral. Never includes Collection names / IDs / reuse-create.
struct MultimodalContentLabeledValue: Sendable, Equatable, Codable, Hashable {
    var id: String
    var confidence: Float
}

struct MultimodalEmbeddedHint: Sendable, Equatable, Codable, Hashable, Identifiable {
    var id: String
    var kind: String
    var confidence: Float

    var debugLabel: String { "\(id)_\(kind)" }
}

struct MultimodalContentUnderstanding: Sendable, Equatable, Codable {
    static let schemaVersion = "8.3a-content-v1"

    var surface: MultimodalContentLabeledValue
    var platform: MultimodalContentLabeledValue
    var contentType: MultimodalContentLabeledValue
    var contentFamily: MultimodalContentLabeledValue
    var embeddedHints: [MultimodalEmbeddedHint]
    var openDescriptors: [String]
    var evidenceNotes: [String]
    var disagreesWithLocal: Bool
    var provider: String?
    var promptVersion: String?
    var schemaVersion: String?

    /// Reject payloads that look like Collection proposals (defensive).
    var containsForbiddenCollectionFields: Bool {
        // Codable decode won't include unknown keys; check notes/descriptors for leakage.
        let haystack = (evidenceNotes + openDescriptors).joined(separator: " ").lowercased()
        return haystack.contains("proposednewcollection")
            || haystack.contains("create collection")
            || haystack.contains("reuse collection")
    }
}

/// Local supporting evidence sent with the image (not authoritative).
struct MultimodalContentLocalEvidence: Sendable, Equatable, Encodable {
    var ocrText: String?
    var visionLabels: [String]
    var facets: [String]
    var platform: String
    var contentType: String
    var contentFamily: String
    var surface: String
    var embeddedHints: [String]
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case ocrText, visionLabels, facets, platform, contentType, contentFamily
        case surface, embeddedHints, createdAt
    }
}

enum MultimodalContentLabJudge: String, Sendable, Equatable, CaseIterable, Identifiable {
    case correct = "CORRECT"
    case partiallyCorrect = "PARTIALLY CORRECT"
    case wrong = "WRONG"

    var id: String { rawValue }
}

enum MultimodalContentLabError: LocalizedError, Equatable {
    case consentRequired
    case consentDeclined
    case gatewayUnavailable
    case missingPhotosIdentifier
    case imageLoadFailed
    case imageEncodeFailed
    case schemaMismatch(expected: String, got: String?)
    case gateway(code: String, message: String)
    case network(String)
    case malformedResponse
    case forbiddenCollectionLeakage

    var errorDescription: String? {
        switch self {
        case .consentRequired:
            return "Accept cloud understanding consent to run the Multimodal Lab."
        case .consentDeclined:
            return "Cloud understanding is declined — Lab blocked."
        case .gatewayUnavailable:
            return "No understanding gateway URL configured (Settings → Resolver DEBUG)."
        case .missingPhotosIdentifier:
            return "Screenshot has no Photos localIdentifier."
        case .imageLoadFailed:
            return "Could not load screenshot image from Photos."
        case .imageEncodeFailed:
            return "Could not encode screenshot JPEG for upload."
        case .schemaMismatch(let expected, let got):
            return "Schema mismatch — expected \(expected), got \(got ?? "nil")."
        case .gateway(let code, let message):
            return "\(code): \(message)"
        case .network(let detail):
            return "Network error: \(detail)"
        case .malformedResponse:
            return "Gateway returned an invalid content-understanding payload."
        case .forbiddenCollectionLeakage:
            return "Rejected response that appeared to propose Collections."
        }
    }
}
