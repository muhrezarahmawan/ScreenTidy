import Foundation

/// Internal content-type evidence (Level 2) — never a Collection title.
struct FacetEvidence: Codable, Sendable, Equatable, Identifiable, Hashable {
    enum Strength: String, Codable, Sendable, Equatable, Hashable {
        case strong
        case weak
    }

    /// Bounded provenance tags for DEBUG (not free-form essays).
    enum Source: String, Codable, Sendable, Equatable, Hashable {
        case ocrKeyword = "ocr_keyword"
        case ocrPhrase = "ocr_phrase"
        case ocrStructure = "ocr_structure"
        case entityPattern = "entity_pattern"
        case visionAssist = "vision_assist"
        case metadata
        case conflictSuppressed = "conflict_suppressed"
    }

    var id: String
    var confidence: Float
    var strength: Strength
    var sources: [Source]

    var identifier: String { id }
}

/// Multi-signal Level 2 content typing. Labels/OCR are evidence only — never Collection names.
enum ScreenshotFacetDeriver {
    /// Confidence floor for emitting a facet at all.
    static let emitFloor: Float = 0.42
    /// Confidence floor for `strong` (else `weak` if ≥ emitFloor).
    static let strongFloor: Float = 0.72
    /// High-risk facets need this many independent cue families for strong.
    static let strongFamilyMinimum = 2

    /// Backward-compatible: strong facet identifiers only (for clustering / consumers).
    static func derive(
        ocrText: String?,
        labels: [VisualLabelObservation]
    ) -> [String] {
        evaluate(ocrText: ocrText, labels: labels)
            .filter { $0.strength == .strong }
            .map(\.id)
            .sorted()
    }

    /// Full Level 2 evidence for persistence / DEBUG.
    static func evaluate(
        ocrText: String?,
        labels: [VisualLabelObservation]
    ) -> [FacetEvidence] {
        let rawOCR = ocrText ?? ""
        let ocr = rawOCR.lowercased()
        let trimmed = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        let labelSet = Set(labels.map { $0.identifier.lowercased() })
        let lines = rawOCR
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var candidates: [FacetEvidence] = []

        if trimmed.isEmpty {
            return evaluateEmptyOCR(labelSet: labelSet)
        }

        // Vision `document` alone never defines a type — ignored as a defining cue.
        let flightScore = scoreFlight(ocr: ocr, lines: lines)
        let hotelScore = scoreHotel(
            ocr: ocr,
            lines: lines,
            flightDominant: flightScore.boarding.allowsStrong || flightScore.booking.allowsStrong
                || flightScore.boarding.score >= strongFloor || flightScore.booking.score >= strongFloor
        )
        let chatScore = scoreChat(ocr: ocr, lines: lines)
        let receiptScore = scoreReceipt(ocr: ocr, lines: lines)
        let mapScore = scoreMap(ocr: ocr, labelSet: labelSet)
        let productScore = scoreProduct(ocr: ocr, labelSet: labelSet)
        let designScore = scoreDesign(ocr: ocr)
        let reservationScore = scoreReservation(
            ocr: ocr,
            flightDominant: flightScore.boarding.allowsStrong || flightScore.booking.allowsStrong,
            hotelScore: hotelScore.score
        )
        let socialScore = scoreSocial(ocr: ocr, lines: lines)
        let articleScore = scoreArticle(ocr: ocr, lines: lines, socialScore: socialScore.score)

        append(&candidates, id: "boarding_pass", scored: flightScore.boarding)
        append(&candidates, id: "flight_booking", scored: flightScore.booking)
        append(&candidates, id: "hotel_booking", scored: hotelScore)
        append(&candidates, id: "chat", scored: chatScore)
        append(&candidates, id: "receipt", scored: receiptScore)
        append(&candidates, id: "map", scored: mapScore)
        append(&candidates, id: "product_page", scored: productScore)
        append(&candidates, id: "design_reference", scored: designScore)
        append(&candidates, id: "reservation", scored: reservationScore)
        append(&candidates, id: "social_post", scored: socialScore)
        append(&candidates, id: "article", scored: articleScore)

        return applyConflicts(finalize(candidates))
    }

    // MARK: - Empty / sparse OCR (no semantic image_only)

    /// Empty OCR is an analysis state, not a Level 2 semantic type.
    /// Unsupported / image-dominant / video-call / portrait → abstain (`—`).
    /// Vision-assist descriptors may still emit when labels clearly support them.
    private static func evaluateEmptyOCR(labelSet: Set<String>) -> [FacetEvidence] {
        var candidates: [FacetEvidence] = []

        if labelSet.contains(where: { ["sofa", "furniture", "chair", "table", "bed", "interior"].contains($0) }) {
            candidates.append(
                FacetEvidence(
                    id: "interior_reference",
                    confidence: 0.78,
                    strength: .strong,
                    sources: [.visionAssist]
                )
            )
        }
        if labelSet.contains(where: { ["airplane", "airport", "building", "city", "landmark", "skyscraper"].contains($0) }) {
            candidates.append(
                FacetEvidence(
                    id: "travel_imagery",
                    confidence: 0.75,
                    strength: .strong,
                    sources: [.visionAssist]
                )
            )
        }
        // Never emit semantic `image_only` — sparse OCR is DEBUG/pipeline metadata only.
        return finalize(candidates)
    }

    // MARK: - Scoring helpers

    private struct Scored {
        var score: Float
        var sources: [FacetEvidence.Source]
        /// Independent cue families contributing to this score.
        var families: Int
        var allowsStrong: Bool {
            score >= strongFloor && families >= strongFamilyMinimum
        }

        static let zero = Scored(score: 0, sources: [], families: 0)
    }

    private struct FlightScored {
        var boarding: Scored
        var booking: Scored
    }

    private static func append(_ list: inout [FacetEvidence], id: String, scored: Scored) {
        guard scored.score >= emitFloor else { return }
        let strength: FacetEvidence.Strength = scored.allowsStrong ? .strong : .weak
        // Cap confidence below strongFloor when diversity insufficient.
        let confidence: Float = {
            if scored.score >= strongFloor && !scored.allowsStrong {
                return min(scored.score, strongFloor - 0.01)
            }
            return min(0.98, scored.score)
        }()
        list.append(
            FacetEvidence(
                id: id,
                confidence: confidence,
                strength: strength,
                sources: Array(Set(scored.sources)).sorted { $0.rawValue < $1.rawValue }
            )
        )
    }

    private static func finalize(_ candidates: [FacetEvidence]) -> [FacetEvidence] {
        var best: [String: FacetEvidence] = [:]
        for item in candidates {
            if let existing = best[item.id] {
                if item.confidence > existing.confidence
                    || (item.confidence == existing.confidence && item.strength == .strong && existing.strength == .weak)
                {
                    best[item.id] = item
                }
            } else {
                best[item.id] = item
            }
        }
        return best.values.sorted { $0.id < $1.id }
    }

    /// Small conflict set — not a full exclusion matrix.
    private static func applyConflicts(_ candidates: [FacetEvidence]) -> [FacetEvidence] {
        let strongTravel = candidates.contains {
            $0.strength == .strong && ($0.id == "boarding_pass" || $0.id == "flight_booking")
        }

        return candidates.compactMap { item in
            if strongTravel, item.id == "chat" {
                let hasDialogueLexicon = item.sources.contains(.ocrPhrase) || item.sources.contains(.ocrKeyword)
                // Structure-only chat (adjacency/turns/senders without delivery/app) under travel → drop.
                if !hasDialogueLexicon {
                    return nil
                }
            }
            return item
        }
    }

    private static func containsAny(_ ocr: String, _ needles: [String]) -> Bool {
        needles.contains { ocr.contains($0) }
    }

    private static func countPhraseMatches(_ ocr: String, _ needles: [String]) -> Int {
        needles.filter { ocr.contains($0) }.count
    }

    /// Word-boundary match to avoid seat⊂Seattle, gate⊂navigate.
    private static func containsWord(_ ocr: String, _ word: String) -> Bool {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return ocr.contains(word)
        }
        return regex.firstMatch(in: ocr, range: NSRange(ocr.startIndex..<ocr.endIndex, in: ocr)) != nil
    }

    private static func countWordMatches(_ ocr: String, _ words: [String]) -> Int {
        words.filter { containsWord(ocr, $0) }.count
    }

    private static let iataDenylist: Set<String> = [
        "THE", "AND", "FOR", "YOU", "ARE", "BUT", "NOT", "ALL", "CAN", "HAD", "HER", "WAS", "ONE",
        "OUR", "OUT", "DAY", "GET", "HAS", "HIM", "HIS", "HOW", "MAN", "NEW", "NOW", "OLD", "SEE",
        "WAY", "WHO", "BOY", "DID", "ITS", "LET", "PUT", "SAY", "SHE", "TOO", "USE", "APP", "IOS",
        "USD", "EUR", "GBP", "PDF", "SMS", "OTP", "FAQ", "VIP", "ETA", "CEO", "CTO", "CFO",
        "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN", "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
        "JUL", "AUG", "SEP", "OCT", "NOV", "DEC", "AM", "PM", "GMT", "UTC", "EST", "PST", "CST",
        "YES", "NO", "OK", "OFF", "ON", "TOP", "END", "MAX", "MIN", "AVG", "SUM", "SET", "GET",
        "AIR", "CAR", "BUS", "TAX", "TIP", "BOX", "BAG", "KEY", "PIN", "ID", "SSID", "LTE", "GPS",
        "CPU", "GPU", "RAM", "ROM", "USB", "HDMI", "WIFI", "HOT", "COLD"
    ]

    /// Credible airport codes: uppercase 3-letter tokens minus common UI/weekday noise.
    private static func iataCodeCount(in lines: [String]) -> Int {
        let pattern = try? NSRegularExpression(pattern: #"\b[A-Z]{3}\b"#)
        var codes = Set<String>()
        for line in lines {
            guard let pattern else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for match in pattern.matches(in: line, range: range) {
                guard let swiftRange = Range(match.range, in: line) else { continue }
                let code = String(line[swiftRange])
                if !iataDenylist.contains(code) {
                    codes.insert(code)
                }
            }
        }
        return codes.count
    }

    /// Tight flight identifiers: airline designator + digits, or "flight 123".
    /// Avoids generic "to 12" / "at 3" / "on 25".
    private static func flightNumberHits(_ ocr: String) -> Int {
        let patterns = [
            #"\b(?:flight|flt)\s*#?\s*\d{1,4}\b"#,
            #"\b[a-z]{2}\s?\d{3,4}\b"# // AA123 / ey 474 — require 3–4 digits
        ]
        // Exclude common English bigrams that look like designators + numbers.
        let designatorBlock: Set<String> = [
            "to", "at", "on", "in", "by", "of", "or", "if", "is", "it", "be", "as", "an", "am",
            "pm", "no", "ok", "up", "do", "go", "so", "we", "me", "my", "id"
        ]
        var hits = 0
        if let flightRegex = try? NSRegularExpression(pattern: patterns[0]) {
            hits += flightRegex.numberOfMatches(in: ocr, range: NSRange(ocr.startIndex..<ocr.endIndex, in: ocr))
        }
        if let codeRegex = try? NSRegularExpression(pattern: patterns[1]) {
            let range = NSRange(ocr.startIndex..<ocr.endIndex, in: ocr)
            for match in codeRegex.matches(in: ocr, range: range) {
                guard let full = Range(match.range, in: ocr) else { continue }
                let token = String(ocr[full])
                let letters = String(token.prefix(while: { $0.isLetter }))
                if designatorBlock.contains(letters) { continue }
                hits += 1
            }
        }
        return hits
    }

    private static func timestampLikeCount(in lines: [String]) -> Int {
        let patterns = [
            #"\b\d{1,2}:\d{2}\b"#,
            #"\b\d{1,2}\.\d{2}\b"#
        ]
        var count = 0
        for line in lines {
            let lower = line.lowercased()
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                if regex.firstMatch(in: lower, range: NSRange(lower.startIndex..<lower.endIndex, in: lower)) != nil {
                    count += 1
                    break
                }
            }
        }
        return count
    }

    // MARK: - Cue families

    private static func scoreFlight(ocr: String, lines: [String]) -> FlightScored {
        var sources: [FacetEvidence.Source] = []
        var score: Float = 0
        var families = 0

        // Family A — route / airport
        let iata = iataCodeCount(in: lines)
        let hasRouteArrow = containsAny(ocr, ["→", "->", " to "]) && iata >= 1
        if iata >= 2 || hasRouteArrow {
            families += 1
            score += iata >= 2 ? 0.30 : 0.18
            sources.append(.entityPattern)
        } else if iata == 1 {
            score += 0.08
            sources.append(.entityPattern)
        }

        // Family B — hard aviation semantics (word-boundary where needed)
        let hardPhrases = countPhraseMatches(ocr, [
            "boarding pass", "flight details", "manage trip", "check-in opens",
            "select your seat", "e-ticket", "eticket"
        ])
        let hardWords = countWordMatches(ocr, [
            "boarding", "terminal", "departure", "arrival", "passenger", "airline", "cabin", "pnr"
        ])
        // "gate" / "seat" only as whole words
        let gateSeat = (containsWord(ocr, "gate") ? 1 : 0) + (containsWord(ocr, "seat") ? 1 : 0)
        let hardHits = hardPhrases + hardWords + gateSeat
        if hardHits >= 2 || hardPhrases >= 1 {
            families += 1
            score += min(0.40, 0.12 * Float(hardHits) + 0.10 * Float(hardPhrases))
            sources.append(.ocrPhrase)
        } else if hardHits == 1 {
            score += 0.10
            sources.append(.ocrKeyword)
        }

        // Family C — credible flight identifier
        let fn = flightNumberHits(ocr)
        if fn > 0 {
            families += 1
            score += min(0.22, 0.14 * Float(fn))
            sources.append(.entityPattern)
        }

        if containsWord(ocr, "flight") && families == 0 {
            score += 0.06
            sources.append(.ocrKeyword)
        }

        var boarding = Scored(score: score, sources: sources, families: families)
        var booking = Scored(score: score, sources: sources, families: families)
        if containsAny(ocr, ["boarding pass", "boarding"]) || containsWord(ocr, "gate") {
            boarding.score = min(0.98, boarding.score + 0.05)
        }
        if containsAny(ocr, ["manage trip", "flight details", "check-in opens"]) {
            booking.score = min(0.98, booking.score + 0.05)
        }

        // Soft single-family travel scraps (e.g. NC) stay weak.
        if families < strongFamilyMinimum {
            boarding.score = min(boarding.score, strongFloor - 0.05)
            booking.score = min(booking.score, strongFloor - 0.05)
            boarding.families = families
            booking.families = families
        }
        return FlightScored(boarding: boarding, booking: booking)
    }

    private static func scoreHotel(ocr: String, lines: [String], flightDominant: Bool) -> Scored {
        if flightDominant {
            return .zero
        }
        var sources: [FacetEvidence.Source] = []
        var score: Float = 0
        var families = 0

        // Family A — lodging semantics
        let lodgingHits = countWordMatches(ocr, [
            "hotel", "guest", "guests", "room", "rooms", "nights", "night", "accommodation",
            "property", "suite", "resort", "lodging", "stay"
        ])
        if lodgingHits > 0 {
            families += 1
            score += min(0.42, 0.12 * Float(lodgingHits))
            sources.append(.ocrPhrase)
        }

        // Family B — stay-date structure (check-in/out OR arrival/departure)
        let hasCheckIn = containsAny(ocr, ["check-in", "check in"])
        let hasCheckOut = containsAny(ocr, ["check-out", "check out", "checkout"])
        let hasArrival = containsWord(ocr, "arrival") || containsAny(ocr, ["arrives", "arriving"])
        let hasDeparture = containsWord(ocr, "departure") || containsAny(ocr, ["departs", "departing"])
        let stayDateStructure = (hasCheckIn && hasCheckOut) || (hasArrival && hasDeparture)
        if stayDateStructure {
            families += 1
            score += 0.34
            sources.append(.ocrStructure)
        } else if hasCheckIn && lodgingHits >= 1 {
            score += 0.08
            sources.append(.ocrKeyword)
        }

        // Family C — reservation / booking confirmation (lodging context only)
        let reservationHits = countPhraseMatches(ocr, [
            "reservation confirmed", "booking confirmation", "booking confirmed",
            "confirmation number", "booking reference", "confirmation #", "confirmation no",
            "reservation number", "booking number"
        ])
        if reservationHits > 0 && (lodgingHits > 0 || stayDateStructure) {
            families += 1
            score += min(0.30, 0.18 * Float(reservationHits))
            sources.append(.ocrPhrase)
        }

        // Family D — property / brand evidence
        let brands = countPhraseMatches(ocr, [
            "marriott", "hilton", "hyatt", "park hyatt", "ihg", "holiday inn", "airbnb",
            "ritz", "sheraton", "westin", "novotel", "mercure", "accor", "booking.com"
        ])
        if brands > 0 {
            families += 1
            score += min(0.28, 0.16 * Float(brands))
            sources.append(.ocrKeyword)
        }

        // Isolated airline-style check-in with no lodging context
        if hasCheckIn && lodgingHits == 0 && brands == 0 && !hasCheckOut && !hasArrival && !hasDeparture {
            return .zero
        }
        if families < strongFamilyMinimum {
            score = min(score, strongFloor - 0.05)
        }
        _ = lines
        return Scored(score: score, sources: sources, families: families)
    }

    private static func scoreChat(ocr: String, lines: [String]) -> Scored {
        // Feed / notification / settings card stacks must not become chat.
        if isFeedOrNotificationStructure(lines) {
            return .zero
        }

        var sources: [FacetEvidence.Source] = []
        var score: Float = 0
        var families = 0

        // Family — app chrome (optional; not required)
        let appHits = countPhraseMatches(ocr, [
            "whatsapp", "imessage", "i message", "telegram", "signal"
        ])
        if appHits > 0 {
            families += 1
            score += min(0.22, 0.18 * Float(appHits))
            sources.append(.ocrKeyword)
        }

        // Family — delivery / read status lines (not "read" inside message prose)
        let deliveryHits = lines.contains { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if chatStatusTokens.contains(t) { return true }
            if t.hasPrefix("delivered") || t.hasPrefix("read by") { return true }
            if t.contains("typing…") || t.contains("typing...") { return true }
            return false
        }
        if deliveryHits {
            families += 1
            score += 0.34
            sources.append(.ocrPhrase)
        }

        // Family — timestamp ↔ conversational-message adjacency
        let adjacentPairs = timestampMessageAdjacencyCount(in: lines)
        if adjacentPairs >= 3 {
            families += 1
            score += 0.40
            sources.append(.ocrStructure)
        } else if adjacentPairs == 2 {
            score += 0.18
            sources.append(.ocrStructure)
        }

        // Family — repeated conversational turns (dialogue continuity)
        let turnCount = conversationalMessageCount(in: lines)
        if turnCount >= 3 && adjacentPairs >= 2 {
            families += 1
            score += 0.36
            sources.append(.ocrStructure)
        }

        // Family — sender / recipient prefixes
        let senderLike = lines.filter {
            $0.range(of: #"^[A-Za-z][A-Za-z0-9 _.]{1,20}:"#, options: .regularExpression) != nil
        }.count
        if senderLike >= 2 {
            families += 1
            score += 0.22
            sources.append(.ocrStructure)
        }

        // One generic structure scrap alone stays weak / may not emit.
        if families < strongFamilyMinimum {
            score = min(score, strongFloor - 0.05)
        }
        return Scored(
            score: score,
            sources: Array(Set(sources)),
            families: families
        )
    }

    // MARK: - Chat structure helpers (dialogue vs feed)

    private static let chatStatusTokens: Set<String> = [
        "delivered", "read", "typing", "online", "sent"
    ]

    private static let dateGroupHeaders: Set<String> = [
        "today", "yesterday", "monday", "tuesday", "wednesday", "thursday", "friday",
        "saturday", "sunday", "mon", "tue", "wed", "thu", "fri", "sat", "sun"
    ]

    private static func isTimestampLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 16 else { return false }
        return timestampLikeCount(in: [trimmed]) > 0
    }

    private static func isDateGroupHeader(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return dateGroupHeaders.contains(lower)
    }

    /// Independent source/app/section headers (Weather, Messages, Mail, Wi‑Fi, …).
    private static func isIndependentSourceHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if isTimestampLine(trimmed) || isDateGroupHeader(trimmed) { return false }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count == 1 else { return false }
        let token = words[0]
        let letters = token.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard (3...22).contains(token.count), letters.count >= 3 else { return false }
        let lower = token.lowercased()
        if chatStatusTokens.contains(lower) { return false }
        // Mostly alphabetic label, not a sentence.
        return Double(letters.count) / Double(token.count) >= 0.8
    }

    private static func isConversationalMessage(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.count
        guard (8...140).contains(count) else { return false }
        if isTimestampLine(trimmed) || isDateGroupHeader(trimmed) { return false }
        if isIndependentSourceHeader(trimmed) { return false }
        let lower = trimmed.lowercased()
        if chatStatusTokens.contains(lower) { return false }
        return true
    }

    private static func isBodyAfterHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (6...140).contains(trimmed.count) else { return false }
        if isTimestampLine(trimmed) || isIndependentSourceHeader(trimmed) { return false }
        return true
    }

    private static func timestampMessageAdjacencyCount(in lines: [String]) -> Int {
        guard lines.count >= 2 else { return 0 }
        var pairs = 0
        for i in 0..<(lines.count - 1) {
            let a = lines[i]
            let b = lines[i + 1]
            if isTimestampLine(a) && isConversationalMessage(b) { pairs += 1 }
            else if isConversationalMessage(a) && isTimestampLine(b) { pairs += 1 }
        }
        return pairs
    }

    private static func conversationalMessageCount(in lines: [String]) -> Int {
        lines.filter { isConversationalMessage($0) }.count
    }

    private static func headerBodyCardCount(in lines: [String]) -> Int {
        guard lines.count >= 2 else { return 0 }
        var cards = 0
        for i in 0..<(lines.count - 1) {
            if isIndependentSourceHeader(lines[i]) && isBodyAfterHeader(lines[i + 1]) {
                cards += 1
            }
        }
        return cards
    }

    /// True for notification feeds, settings lists, stacked independent cards — not dialogue.
    private static func isFeedOrNotificationStructure(_ lines: [String]) -> Bool {
        let headers = lines.filter { isIndependentSourceHeader($0) }
        let headerCount = headers.count
        let distinctHeaders = Set(headers.map { $0.lowercased() }).count
        let cards = headerBodyCardCount(in: lines)
        let pairs = timestampMessageAdjacencyCount(in: lines)
        let dateHeaders = lines.filter { isDateGroupHeader($0) }.count
        let tinyLabels = lines.filter { $0.count <= 24 }.count

        // Stacked independent source cards (Notification Center / feeds).
        if cards >= 3 && cards >= pairs { return true }
        if headerCount >= 4 && distinctHeaders >= 3 && pairs < 3 { return true }
        if headerCount >= 3 && dateHeaders >= 1 && pairs < 3 { return true }

        // Settings-like: many tiny single-word labels + clocks, little dialogue text.
        let conversational = conversationalMessageCount(in: lines)
        if tinyLabels >= 8 && conversational < 3 && headerCount >= 3 { return true }

        return false
    }

    private static func scoreReceipt(ocr: String, lines: [String]) -> Scored {
        var sources: [FacetEvidence.Source] = []
        var score: Float = 0
        var families = 0
        let financeHits = countPhraseMatches(ocr, [
            "subtotal", "tax", "invoice", "receipt", "amount due", "payment", "change due"
        ])
        let currencyHits = countPhraseMatches(ocr, ["$", "€", "£", "usd", "eur", "gbp", "idr", "rp "])
        let totalHits = containsWord(ocr, "total")
        if financeHits > 0 {
            families += 1
            score += min(0.45, 0.16 * Float(financeHits))
            sources.append(.ocrPhrase)
        }
        if currencyHits > 0 {
            families += 1
            score += min(0.25, 0.12 * Float(currencyHits))
            sources.append(.entityPattern)
        }
        if totalHits && (financeHits > 0 || currencyHits > 0) {
            score += 0.18
            sources.append(.ocrKeyword)
        }
        if totalHits && financeHits == 0 && currencyHits == 0 {
            return .zero
        }
        let amountLike = lines.filter {
            $0.range(of: #"\d+[.,]\d{2}"#, options: .regularExpression) != nil
        }.count
        if amountLike >= 2 {
            families += 1
            score += 0.18
            sources.append(.ocrStructure)
        }
        if families < strongFamilyMinimum {
            score = min(score, strongFloor - 0.05)
        }
        return Scored(score: score, sources: sources, families: families)
    }

    private static func scoreMap(ocr: String, labelSet: Set<String>) -> Scored {
        var sources: [FacetEvidence.Source] = []
        var score: Float = 0
        var families = 0
        let navHits = countPhraseMatches(ocr, [
            "directions", "google maps", "apple maps", "min walk", "min drive", "navigation",
            "route", "destination", "eta ", "traffic"
        ])
        if navHits > 0 {
            families += 1
            score += min(0.50, 0.18 * Float(navHits))
            sources.append(.ocrPhrase)
        }
        if containsAny(ocr, ["km", "mi ", "miles"]) && navHits > 0 {
            score += 0.12
            sources.append(.ocrKeyword)
        }
        if labelSet.contains("map") {
            families += 1
            score += 0.22
            sources.append(.visionAssist)
        }
        if labelSet.contains("map") && navHits == 0 {
            score = min(score, emitFloor + 0.12)
            families = min(families, 1)
        }
        return Scored(score: score, sources: sources, families: families)
    }

    private static func scoreProduct(ocr: String, labelSet: Set<String>) -> Scored {
        var sources: [FacetEvidence.Source] = []
        var score: Float = 0
        var families = 0
        let commerce = countPhraseMatches(ocr, [
            "add to cart", "add to bag", "in stock", "sku", "buy now", "checkout"
        ])
        if commerce > 0 {
            families += 1
            score += min(0.55, 0.22 * Float(commerce))
            sources.append(.ocrPhrase)
        }
        if containsAny(ocr, ["ikea"]) {
            families += 1
            score += 0.18
            sources.append(.ocrKeyword)
        }
        let furniture = labelSet.contains(where: { ["furniture", "sofa", "chair", "table"].contains($0) })
        if furniture && containsAny(ocr, ["buy", "cart", "price", "shop", "$", "¥", "€"]) {
            families += 1
            score += 0.28
            sources.append(.visionAssist)
            sources.append(.ocrKeyword)
        }
        return Scored(score: score, sources: sources, families: families)
    }

    private static func scoreDesign(ocr: String) -> Scored {
        var sources: [FacetEvidence.Source] = []
        var score: Float = 0
        let hits = countPhraseMatches(ocr, [
            "figma", "sketch", "artboard", "prototype", "dribbble", "behance"
        ]) + (containsWord(ocr, "frame") ? 1 : 0)
        var families = 0
        if hits > 0 {
            families = 1
            score += min(0.70, 0.28 * Float(hits))
            sources.append(.ocrKeyword)
        }
        return Scored(score: score, sources: sources, families: families)
    }

    private static func scoreReservation(ocr: String, flightDominant: Bool, hotelScore: Float) -> Scored {
        if flightDominant { return .zero }
        var sources: [FacetEvidence.Source] = []
        var score: Float = 0
        var families = 0
        let hits = countPhraseMatches(ocr, [
            "opentable", "resy", "table for", "reservation confirmed", "dining reservation"
        ])
        if hits > 0 {
            families = 1
            score += min(0.70, 0.30 * Float(hits))
            sources.append(.ocrPhrase)
        }
        if containsAny(ocr, ["reservation", "booking"]) && hits == 0 {
            if hotelScore >= emitFloor {
                return .zero
            }
            score += 0.20
            sources.append(.ocrKeyword)
            score = min(score, emitFloor + 0.05)
            families = 1
        }
        return Scored(score: score, sources: sources, families: families)
    }

    private static func scoreSocial(ocr: String, lines: [String]) -> Scored {
        var sources: [FacetEvidence.Source] = []
        var score: Float = 0
        var families = 0
        let platform = countPhraseMatches(ocr, [
            "instagram", "tiktok", "twitter", "x.com", "linkedin", "facebook"
        ])
        let engagement = countPhraseMatches(ocr, [
            "liked by", "followers", "retweet", "comments", "shares", "replies"
        ])
        if platform > 0 {
            families += 1
            score += min(0.48, 0.28 * Float(platform))
            sources.append(.ocrKeyword)
        }
        if engagement > 0 {
            families += 1
            score += min(0.36, 0.16 * Float(engagement))
            sources.append(.ocrPhrase)
        }
        // Platform + engagement together is enough for strong social.
        if platform > 0 && engagement > 0 {
            score = max(score, strongFloor + 0.05)
        }
        _ = lines
        if platform == 0 {
            return .zero
        }
        if families < strongFamilyMinimum {
            score = min(score, strongFloor - 0.05)
        }
        return Scored(score: score, sources: sources, families: families)
    }

    private static func scoreArticle(ocr: String, lines: [String], socialScore: Float) -> Scored {
        if socialScore >= strongFloor {
            return .zero
        }
        var sources: [FacetEvidence.Source] = []
        var score: Float = 0
        var families = 0
        let longLines = lines.filter { $0.count > 100 }.count
        if longLines >= 2 {
            families += 1
            score += 0.28
            sources.append(.ocrStructure)
        }
        if containsAny(ocr, ["byline", "min read", "published", "newsletter", "opinion"]) {
            families += 1
            score += 0.25
            sources.append(.ocrPhrase)
        }
        if containsAny(ocr, ["http://", "https://", "medium.com", "nytimes", "bbc."]) {
            families += 1
            score += 0.18
            sources.append(.entityPattern)
        }
        if longLines < 2 {
            score = min(score, emitFloor + 0.05)
        }
        if families < strongFamilyMinimum {
            score = min(score, strongFloor - 0.05)
        }
        return Scored(score: score, sources: sources, families: families)
    }
}
