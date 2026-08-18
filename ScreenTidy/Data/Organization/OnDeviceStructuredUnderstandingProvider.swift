import Foundation

/// Offline / declined-consent stand-in. Not product multimodal quality.
/// P1: consumes cached Vision labels as evidence — never as Collection titles.
struct OnDeviceStructuredUnderstandingProvider: UnderstandingProviding {
    func understand(_ input: UnderstandingInput) async throws -> ScreenshotUnderstanding {
        let ocr = OrganizationOCRNormalizer.normalize(input.ocrText)
        let ocrLower = ocr.lowercased()

        var entities: [UnderstandingEntity] = []
        var visualDescriptors: [String] = input.visualLabels.map(\.identifier)
        var candidates: [UnderstandingCandidate] = []
        var proposed: ProposedNewCollection?
        var reasonSignals = ["ondevice_heuristic"]

        if !input.visualFacets.isEmpty {
            reasonSignals.append("visual_facets")
        }
        if !input.visualLabels.isEmpty {
            reasonSignals.append("vision_labels")
            for label in input.visualLabels.prefix(5) {
                entities.append(
                    UnderstandingEntity(
                        type: "visual",
                        value: label.identifier,
                        confidence: Double(label.confidence)
                    )
                )
            }
        }

        let entitySeeds: [(String, String, [String])] = [
            ("city", "Tokyo", ["tokyo", "nrt", "shinjuku", "shibuya"]),
            ("city", "Doha", ["doha", "doh", "qatar"]),
            ("airline", "Qatar Airways", ["qatar airways", "qatar"]),
            ("hotel", "Park Hyatt", ["park hyatt"]),
            ("topic", "Visa", ["visa", "embassy", "passport"]),
            ("topic", "Apartment", ["ikea", "apartment", "lease", "furniture"]),
            ("topic", "Restaurant", ["restaurant", "menu", "reservation", "ramen", "sushi"])
        ]
        for (type, value, needles) in entitySeeds {
            if needles.contains(where: { ocrLower.contains($0) }) {
                entities.append(UnderstandingEntity(type: type, value: value, confidence: 0.82))
            }
        }

        // Soft entity assists from Vision — still not titles.
        let labelSet = Set(input.visualLabels.map(\.identifier))
        if labelSet.contains(where: { ["sofa", "furniture", "chair", "table"].contains($0) }),
           !entities.contains(where: { $0.value == "Apartment" }) {
            entities.append(UnderstandingEntity(type: "topic", value: "Apartment", confidence: 0.55))
        }
        if labelSet.contains(where: { ["airplane", "airport", "landmark", "city", "building"].contains($0) }),
           !entities.contains(where: { $0.type == "city" }) {
            // Travel imagery without OCR city — evidence only; do not invent Japan Trip title here.
            reasonSignals.append("travel_imagery")
        }

        let titles = input.eligibleCollectionContexts.map(\.title)
        let titleList = titles.isEmpty ? input.eligibleCollectionTitles : titles

        for title in titleList {
            let score = overlapScore(
                title: title,
                ocr: ocrLower,
                entities: entities,
                visualLabels: labelSet,
                contexts: input.eligibleCollectionContexts
            )
            if score >= 0.40 {
                candidates.append(
                    UnderstandingCandidate(
                        title: title,
                        confidence: min(0.96, score),
                        reasonSignals: ocr.isEmpty ? ["vision_profile_overlap"] : ["ocr_title_overlap"]
                    )
                )
            }
        }

        let bestExisting = candidates.map(\.confidence).max() ?? 0

        // Image-dominant / empty OCR: Level 1 labels only — never invent semantic image_only facet.
        if ocr.isEmpty {
            return ScreenshotUnderstanding(
                summary: summaryForSparseOCR(labels: input.visualLabels, facets: input.visualFacets),
                typeFacets: input.visualFacets.filter { $0 != "image_only" },
                entities: entities.filter { $0.type != "visual" || $0.confidence >= 0.4 },
                locations: entities.filter { $0.type == "city" }.map(\.value),
                dates: [],
                visualDescriptors: visualDescriptors,
                candidateCollections: candidates.sorted { $0.confidence > $1.confidence },
                proposedNewCollection: nil,
                reasonSignals: reasonSignals + ["sparse_ocr"],
                provider: "ondevice-structured-v2-vision",
                normalizedOCRPreview: nil
            )
        }

        if bestExisting < 0.70 {
            if let proposal = proposeNewCollection(ocr: ocrLower, entities: entities) {
                let normalizedProposal = CollectionResolver.normalizeTitle(proposal.title)
                // Hard ban: Vision nouns cannot become proposed titles.
                if VisionEvidencePolicy.nounDenylist.contains(normalizedProposal)
                    || ResolverPolicy.genericTitleDenylist.contains(normalizedProposal) {
                    proposed = nil
                } else if let existingTitle = titleList.first(where: {
                    CollectionResolver.normalizeTitle($0) == normalizedProposal
                        || CollectionResolver.similarity(
                            CollectionResolver.normalizeTitle($0),
                            normalizedProposal
                        ) >= 0.90
                }) {
                    candidates.append(
                        UnderstandingCandidate(
                            title: existingTitle,
                            confidence: max(proposal.confidence, 0.86),
                            reasonSignals: ["proposed_matches_existing"]
                        )
                    )
                } else {
                    proposed = proposal
                }
            }
        }

        let summary: String?
        if let top = entities.first(where: { $0.type != "visual" }) {
            summary = "\(top.value) screenshot"
        } else if !ocr.isEmpty {
            summary = String(ocr.prefix(80))
        } else {
            summary = nil
        }

        return ScreenshotUnderstanding(
            summary: summary,
            typeFacets: input.visualFacets,
            entities: entities,
            locations: entities.filter { $0.type == "city" }.map(\.value),
            dates: [],
            visualDescriptors: visualDescriptors,
            candidateCollections: candidates.sorted { $0.confidence > $1.confidence },
            proposedNewCollection: proposed,
            reasonSignals: reasonSignals,
            provider: "ondevice-structured-v2-vision",
            normalizedOCRPreview: OrganizationOCRNormalizer.preview(input.ocrText)
        )
    }

    private func summaryForSparseOCR(labels: [VisualLabelObservation], facets: [String]) -> String? {
        if let top = labels.first {
            return "Image · \(top.identifier)"
        }
        if let facet = facets.first(where: { $0 != "image_only" }) {
            return "Image · \(facet)"
        }
        return "Image · sparse OCR"
    }

    private func overlapScore(
        title: String,
        ocr: String,
        entities: [UnderstandingEntity],
        visualLabels: Set<String>,
        contexts: [EligibleCollectionContext]
    ) -> Double {
        let titleTokens = title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }
        guard !titleTokens.isEmpty else { return 0 }
        var hits = 0.0
        if !ocr.isEmpty {
            for token in titleTokens where ocr.contains(token) {
                hits += 1
            }
        }
        for entity in entities where entity.type != "visual" {
            let value = entity.value.lowercased()
            if title.lowercased().contains(value)
                || value.split(separator: " ").contains(where: { title.lowercased().contains($0) }) {
                hits += 1
            }
        }
        if let context = contexts.first(where: { $0.title == title }) {
            let profileVisual = Set(context.visualDescriptors.map { $0.lowercased() })
            if !profileVisual.isEmpty, !visualLabels.isEmpty {
                hits += Double(profileVisual.intersection(visualLabels).count) * 0.5
            }
            let profileEntities = Set(context.keyEntities.map { $0.lowercased() })
            for entity in entities where entity.type != "visual" {
                if profileEntities.contains(entity.value.lowercased()) {
                    hits += 0.75
                }
            }
        }
        // Soft Vision assist toward known contextual Collections (not noun folders).
        let titleLower = title.lowercased()
        if titleLower.contains("japan") || titleLower.contains("trip") {
            if visualLabels.contains(where: { ["airplane", "airport", "city", "building", "landmark"].contains($0) }) {
                hits += 0.6
            }
        }
        if titleLower.contains("apartment") {
            if visualLabels.contains(where: { ["sofa", "furniture", "chair", "table"].contains($0) }) {
                hits += 0.6
            }
        }
        let base = hits / Double(titleTokens.count)
        return min(0.96, base * 0.85 + (hits >= Double(titleTokens.count) ? 0.15 : 0))
    }

    private func proposeNewCollection(ocr: String, entities: [UnderstandingEntity]) -> ProposedNewCollection? {
        if entities.contains(where: { $0.value == "Visa" }) || ocr.contains("visa") {
            return ProposedNewCollection(title: "Visa Application", emoji: "🛂", confidence: 0.88)
        }
        if entities.contains(where: { $0.value == "Tokyo" }) || ocr.contains("tokyo") {
            return ProposedNewCollection(title: "Japan Trip", emoji: "✈️", confidence: 0.87)
        }
        if entities.contains(where: { $0.value == "Qatar Airways" }) || ocr.contains("qatar") {
            return ProposedNewCollection(title: "Qatar Airways", emoji: "✈️", confidence: 0.88)
        }
        if entities.contains(where: { $0.value == "Apartment" }) || ocr.contains("ikea") {
            return ProposedNewCollection(title: "Apartment Setup", emoji: "🏠", confidence: 0.86)
        }
        if entities.contains(where: { $0.value == "Restaurant" }) {
            return ProposedNewCollection(title: "Weekend Restaurants", emoji: "🍜", confidence: 0.86)
        }
        return nil
    }
}
