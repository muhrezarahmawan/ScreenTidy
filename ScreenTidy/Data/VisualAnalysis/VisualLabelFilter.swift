import Foundation
import Vision

/// Bounded filtering for Apple Vision classifications.
/// Labels are evidence only — never Collection titles.
enum VisualLabelFilter {
    /// Ultra-generic / low-information identifiers that rarely help context.
    static let lowInformationIdentifiers: Set<String> = [
        "indoor", "outdoor", "person", "people", "human", "man", "woman",
        "screenshot", "text", "font", "electronics", "computer", "laptop",
        "monitor", "screen", "display", "smartphone", "mobile_phone", "phone",
        "pattern", "abstract", "design", "art", "drawing", "illustration",
        "room", "floor", "wall", "ceiling", "window", "door",
        "sky", "cloud", "clouds", "nature", "plant", "tree", "grass",
        "animal", "mammal", "object", "thing", "scene", "landscape",
        "photo", "photograph", "image", "picture"
    ]

    /// Identifiers that must never become Collection titles.
    static var visionNounDenylist: Set<String> { VisionEvidencePolicy.nounDenylist }

    /// Production defaults — DEBUG overrides must not silently replace these.
    struct Settings: Equatable, Sendable {
        var confidenceFloor: Float
        var minimumPrecision: Float
        var recallForPrecision: Float
        var precisionBypassDelta: Float
        var maxCount: Int
        /// How many top raw labels to retain for DEBUG / persistence.
        var maxRawCount: Int

        static let production = Settings(
            confidenceFloor: VisualAnalysisPipeline.confidenceFloor,
            minimumPrecision: VisualAnalysisPipeline.minimumPrecision,
            recallForPrecision: VisualAnalysisPipeline.recallForPrecision,
            precisionBypassDelta: 0.12,
            maxCount: VisualAnalysisPipeline.maxPersistedLabels,
            maxRawCount: VisualAnalysisPipeline.maxRawPersistedLabels
        )
    }

    enum DropReason: String, Sendable, Equatable {
        case empty
        case lowInformation = "low_information"
        case belowConfidenceFloor = "below_confidence_floor"
        case precisionGate = "precision_gate"
        case duplicate
        case overCap = "over_cap"
    }

    struct DroppedLabel: Sendable, Equatable, Identifiable {
        var id: String { "\(identifier)-\(reason.rawValue)-\(confidence)" }
        var identifier: String
        var confidence: Float
        var reason: DropReason
    }

    struct Outcome: Sendable, Equatable {
        /// Top raw labels (pre-filter), confidence-sorted, capped.
        var raw: [VisualLabelObservation]
        /// Labels that survive production (or DEBUG override) filtering.
        var filtered: [VisualLabelObservation]
        /// Raw candidates that did not survive, with reason.
        var dropped: [DroppedLabel]
        var settings: Settings
    }

    static func filter(
        observations: [VNClassificationObservation],
        settings: Settings = .production
    ) -> [VisualLabelObservation] {
        filterExplained(observations: observations, settings: settings).filtered
    }

    /// Convenience matching older call sites.
    static func filter(
        observations: [VNClassificationObservation],
        maxCount: Int = VisualAnalysisPipeline.maxPersistedLabels,
        confidenceFloor: Float = VisualAnalysisPipeline.confidenceFloor
    ) -> [VisualLabelObservation] {
        var settings = Settings.production
        settings.maxCount = maxCount
        settings.confidenceFloor = confidenceFloor
        return filter(observations: observations, settings: settings)
    }

    static func filterExplained(
        observations: [VNClassificationObservation],
        settings: Settings = .production
    ) -> Outcome {
        let sorted = observations.sorted { $0.confidence > $1.confidence }
        let candidates: [Candidate] = sorted.map { observation in
            let precisionOK = observation.hasMinimumPrecision(
                settings.minimumPrecision,
                forRecall: settings.recallForPrecision
            )
            return Candidate(
                identifier: observation.identifier,
                confidence: observation.confidence,
                precisionOK: precisionOK
            )
        }
        return filterCandidates(candidates, settings: settings)
    }

    /// Testable path without constructing `VNClassificationObservation`.
    static func filterCandidates(
        _ candidates: [Candidate],
        settings: Settings = .production
    ) -> Outcome {
        var raw: [VisualLabelObservation] = []
        raw.reserveCapacity(min(settings.maxRawCount, candidates.count))
        var filtered: [VisualLabelObservation] = []
        filtered.reserveCapacity(min(settings.maxCount, candidates.count))
        var dropped: [DroppedLabel] = []

        for candidate in candidates {
            let identifier = candidate.identifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let confidence = candidate.confidence

            if raw.count < settings.maxRawCount, !identifier.isEmpty {
                if !raw.contains(where: { $0.identifier == identifier }) {
                    raw.append(VisualLabelObservation(identifier: identifier, confidence: confidence))
                }
            }

            if identifier.isEmpty {
                dropped.append(DroppedLabel(identifier: "(empty)", confidence: confidence, reason: .empty))
                continue
            }
            if lowInformationIdentifiers.contains(identifier) {
                dropped.append(DroppedLabel(identifier: identifier, confidence: confidence, reason: .lowInformation))
                continue
            }
            if !(candidate.precisionOK || confidence >= settings.confidenceFloor + settings.precisionBypassDelta) {
                dropped.append(DroppedLabel(identifier: identifier, confidence: confidence, reason: .precisionGate))
                continue
            }
            if confidence < settings.confidenceFloor {
                dropped.append(DroppedLabel(identifier: identifier, confidence: confidence, reason: .belowConfidenceFloor))
                continue
            }
            if filtered.contains(where: { $0.identifier == identifier }) {
                dropped.append(DroppedLabel(identifier: identifier, confidence: confidence, reason: .duplicate))
                continue
            }
            if filtered.count >= settings.maxCount {
                dropped.append(DroppedLabel(identifier: identifier, confidence: confidence, reason: .overCap))
                continue
            }
            filtered.append(VisualLabelObservation(identifier: identifier, confidence: confidence))
        }

        return Outcome(
            raw: raw,
            filtered: filtered.sorted { $0.confidence > $1.confidence },
            dropped: dropped,
            settings: settings
        )
    }

    struct Candidate: Sendable, Equatable {
        var identifier: String
        var confidence: Float
        var precisionOK: Bool
    }
}
