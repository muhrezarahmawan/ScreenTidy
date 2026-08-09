import Foundation

/// Offline / declined-consent stand-in. Not product multimodal quality.
struct OnDeviceStructuredUnderstandingProvider: UnderstandingProviding {
    func understand(_ input: UnderstandingInput) async throws -> ScreenshotUnderstanding {
        let ocr = OrganizationOCRNormalizer.normalize(input.ocrText)
        let ocrLower = ocr.lowercased()

        var entities: [UnderstandingEntity] = []
        var visualDescriptors: [String] = []
        var candidates: [UnderstandingCandidate] = []
        var proposed: ProposedNewCollection?

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

        let titles = input.eligibleCollectionContexts.map(\.title)
        let titleList = titles.isEmpty ? input.eligibleCollectionTitles : titles

        for title in titleList {
            let score = overlapScore(title: title, ocr: ocrLower, entities: entities)
            if score >= 0.45 {
                candidates.append(
                    UnderstandingCandidate(
                        title: title,
                        confidence: min(0.96, score),
                        reasonSignals: ["ocr_title_overlap"]
                    )
                )
            }
        }

        let bestExisting = candidates.map(\.confidence).max() ?? 0
        if !ocr.isEmpty, bestExisting < 0.70 {
            if let proposal = proposeNewCollection(ocr: ocrLower, entities: entities) {
                let normalizedProposal = CollectionResolver.normalizeTitle(proposal.title)
                if let existingTitle = titleList.first(where: {
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

        if ocr.isEmpty {
            visualDescriptors.append("image_only")
            return ScreenshotUnderstanding(
                summary: nil,
                typeFacets: [],
                entities: [],
                locations: [],
                dates: [],
                visualDescriptors: visualDescriptors,
                candidateCollections: [],
                proposedNewCollection: nil,
                reasonSignals: ["ondevice_no_multimodal"],
                provider: "ondevice-structured-v1",
                normalizedOCRPreview: nil
            )
        }

        let summary: String?
        if let top = entities.first {
            summary = "\(top.value) screenshot"
        } else if !ocr.isEmpty {
            summary = String(ocr.prefix(80))
        } else {
            summary = nil
        }

        return ScreenshotUnderstanding(
            summary: summary,
            typeFacets: [],
            entities: entities,
            locations: entities.filter { $0.type == "city" }.map(\.value),
            dates: [],
            visualDescriptors: visualDescriptors,
            candidateCollections: candidates.sorted { $0.confidence > $1.confidence },
            proposedNewCollection: proposed,
            reasonSignals: ["ondevice_heuristic"],
            provider: "ondevice-structured-v1",
            normalizedOCRPreview: OrganizationOCRNormalizer.preview(input.ocrText)
        )
    }

    private func overlapScore(title: String, ocr: String, entities: [UnderstandingEntity]) -> Double {
        let titleTokens = title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }
        guard !titleTokens.isEmpty else { return 0 }
        var hits = 0
        for token in titleTokens where ocr.contains(token) {
            hits += 1
        }
        for entity in entities {
            let value = entity.value.lowercased()
            if title.lowercased().contains(value) || value.split(separator: " ").contains(where: { title.lowercased().contains($0) }) {
                hits += 1
            }
        }
        let base = Double(hits) / Double(titleTokens.count)
        return min(0.96, base * 0.85 + (hits >= titleTokens.count ? 0.15 : 0))
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
