import Foundation

/// One DEBUG-facing evidence field (platform / type / family / surface).
struct SourceEvidenceField: Codable, Sendable, Equatable, Hashable {
    var value: String
    /// 0…1 confidence in this field alone.
    var confidence: Float
    /// Short provenance tags (e.g. `ocr_platform`, `facet`).
    var evidence: [String]
    /// Human-readable choose / abstain reasons for DEBUG traces.
    var trace: [String]

    static func unknown(trace: [String], evidence: [String] = []) -> SourceEvidenceField {
        SourceEvidenceField(
            value: ScreenshotSourceEvidence.unknown,
            confidence: 0,
            evidence: evidence,
            trace: trace
        )
    }
}

/// Embedded app/content cue inside another surface (e.g. Gmail on lock screen).
/// Never alone redefines screenshot platform / type for grouping.
struct EmbeddedContentHint: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// e.g. `gmail`, `whatsapp`
    var value: String
    /// e.g. `notification`
    var kind: String
    var confidence: Float
    var evidence: [String]

    var id: String { "\(kind):\(value)" }

    /// DEBUG label such as `gmail_notification`.
    var debugLabel: String { "\(value)_\(kind)" }
}

/// Sprint 8.2B-R1/R2a — parallel grouping evidence (not Collection identity).
/// Distinct from Level 2A `FacetEvidence` and from later contextual Collection titles.
struct ScreenshotSourceEvidence: Codable, Sendable, Equatable, Hashable {
    var platform: SourceEvidenceField
    var type: SourceEvidenceField
    var family: SourceEvidenceField
    var surface: SourceEvidenceField
    var embeddedHints: [EmbeddedContentHint]

    static let unknown = "unknown"

    /// Surfaces (container), not app identity.
    static let surfaces: Set<String> = [
        "lock_screen", "notification_center", "app_screen", "unknown"
    ]

    static let abstain = ScreenshotSourceEvidence(
        platform: .unknown(trace: ["abstain: empty OCR and no strong facets"]),
        type: .unknown(trace: ["abstain: empty OCR and no strong facets"]),
        family: .unknown(trace: ["abstain: empty OCR and no strong facets"]),
        surface: .unknown(trace: ["abstain: empty OCR and no strong facets"]),
        embeddedHints: []
    )

    // MARK: - Backward-compatible flat accessors (clustering / R1 call sites)

    var sourcePlatform: String { platform.value }
    var contentType: String { type.value }
    var contentFamily: String { family.value }

    /// Blended confidence for legacy DEBUG field (not a substitute for per-field confidence).
    var confidence: Float {
        var sum: Float = 0
        var n: Float = 0
        for field in [platform, type, family, surface] where field.value != Self.unknown {
            sum += field.confidence
            n += 1
        }
        if n == 0 { return 0 }
        return min(1, sum / n)
    }

    /// Flattened provenance tags (legacy).
    var sources: [String] {
        var tags = platform.evidence + type.evidence + family.evidence + surface.evidence
        for hint in embeddedHints {
            tags.append(contentsOf: hint.evidence)
        }
        return Array(Set(tags)).sorted()
    }

    var isAbstain: Bool {
        sourcePlatform == Self.unknown
            && contentType == Self.unknown
            && contentFamily == Self.unknown
            && surface.value == Self.unknown
            && embeddedHints.isEmpty
    }
}

/// Correlated facet / type / family describing the same semantic fact (DEBUG only — no score change).
enum SemanticCorrelationDiagnostics {
    /// Returns labels like `facet(chat)`, `type(chat)`, `family(messaging)` when ≥2 channels agree.
    static func correlatedChannels(
        facets: [String],
        contentType: String,
        contentFamily: String,
        signalParts: [String: Double] = [:]
    ) -> [String] {
        let typeKnown = contentType != ScreenshotSourceEvidence.unknown && !contentType.isEmpty
        let familyKnown = contentFamily != ScreenshotSourceEvidence.unknown && !contentFamily.isEmpty
        let strongFacets = Set(facets).subtracting(["image_only"])

        let facetHit = (signalParts["facets"] ?? 0) > 0 || !strongFacets.isEmpty
        let typeHit = (signalParts["content_type"] ?? 0) > 0 || typeKnown
        let familyHit = (signalParts["content_family"] ?? 0) > 0 || familyKnown

        // Pairwise: require contribution when parts provided; otherwise use known values.
        let useParts = !signalParts.isEmpty
        let facetContributed = useParts ? (signalParts["facets"] ?? 0) > 0 : facetHit
        let typeContributed = useParts ? (signalParts["content_type"] ?? 0) > 0 : typeHit
        let familyContributed = useParts ? (signalParts["content_family"] ?? 0) > 0 : familyHit

        var labels: [String] = []

        func appendFacetMatch(_ facetID: String, family: String) {
            var local: [String] = []
            if strongFacets.contains(facetID), facetContributed {
                local.append("facet(\(facetID))")
            }
            if typeKnown, contentType == facetID, typeContributed {
                local.append("type(\(facetID))")
            }
            if familyKnown, contentFamily == family, familyContributed {
                local.append("family(\(family))")
            }
            if local.count >= 2 {
                labels.append(contentsOf: local)
            }
        }

        appendFacetMatch("chat", family: "messaging")
        appendFacetMatch("social_post", family: "social_media")
        appendFacetMatch("map", family: "navigation")
        appendFacetMatch("product_page", family: "commerce")
        appendFacetMatch("receipt", family: "commerce")
        appendFacetMatch("boarding_pass", family: "travel")
        appendFacetMatch("flight_booking", family: "travel")
        appendFacetMatch("hotel_booking", family: "travel")
        appendFacetMatch("reservation", family: "travel")

        // Email: type/family without a Level 2A facet id of the same name.
        if typeKnown, contentType == "email", familyKnown, contentFamily == "email" {
            var local: [String] = []
            if typeContributed { local.append("type(email)") }
            if familyContributed { local.append("family(email)") }
            if local.count >= 2 { labels.append(contentsOf: local) }
        }

        // Deduplicate while preserving order.
        var seen = Set<String>()
        return labels.filter { seen.insert($0).inserted }
    }

    /// Pair-level: only when multiple correlated channels actually contributed to the score.
    static func correlatedChannelsForPair(
        sharedFacets: [String],
        sharedContentType: String,
        sharedContentFamily: String,
        signalParts: [String: Double]
    ) -> [String] {
        let stackCount = [
            (signalParts["facets"] ?? 0) > 0,
            (signalParts["content_type"] ?? 0) > 0,
            (signalParts["content_family"] ?? 0) > 0
        ].filter { $0 }.count
        guard stackCount >= 2 else { return [] }
        return correlatedChannels(
            facets: sharedFacets,
            contentType: sharedContentType,
            contentFamily: sharedContentFamily,
            signalParts: signalParts
        )
    }
}

/// Derives sourcePlatform / contentType / contentFamily (+ R2a surface / embedded DEBUG) from local OCR + facets.
/// Precision-first: unknown preferred over false confidence.
/// R2a: layered confidence / traces / surface / embedded — **does not change R1 type/platform values**.
enum ScreenshotSourceDeriver {
    /// Bounded platform vocabulary.
    static let platforms: Set<String> = [
        "instagram", "linkedin", "facebook", "whatsapp", "imessage", "messenger",
        "gmail", "mail", "maps", "browser", "unknown"
    ]

    /// Bounded type vocabulary.
    static let types: Set<String> = [
        "social_post", "chat", "email", "identity_document", "product_page", "map",
        "boarding_pass", "flight_booking", "hotel_booking", "receipt", "reservation",
        "unknown"
    ]

    /// Bounded family vocabulary.
    static let families: Set<String> = [
        "social_media", "messaging", "email", "identity_document", "commerce",
        "navigation", "travel", "unknown"
    ]

    static func derive(
        ocrText: String?,
        labels: [VisualLabelObservation] = [],
        strongFacets: [String] = [],
        facetEvidence: [FacetEvidence] = []
    ) -> ScreenshotSourceEvidence {
        let raw = ocrText ?? ""
        let ocr = raw.lowercased()
        let trimmed = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let facets = Set(strongFacets).union(
            Set(facetEvidence.filter { $0.strength == .strong }.map(\.id))
        )
        // Vision `document` alone never defines identity_document / email / etc.
        _ = labels

        if trimmed.isEmpty, facets.isEmpty {
            return .abstain
        }

        let platformField = detectPlatform(ocr: ocr)
        let typed = detectTypeAndFamily(
            ocr: ocr,
            lines: lines,
            platform: platformField.value,
            facets: facets
        )
        let surfaceField = detectSurface(
            ocr: ocr,
            lines: lines,
            platform: platformField.value,
            type: typed.type.value,
            facets: facets
        )
        let embedded = detectEmbeddedHints(
            ocr: ocr,
            surface: surfaceField.value
        )

        // R2a: on lock/NC, app chrome is EMBEDDED — never screenshot platform/type.
        let (finalPlatform, finalType, finalFamily, finalEmbedded) = demoteEmbeddedAppChrome(
            platform: platformField,
            type: typed.type,
            family: typed.family,
            surface: surfaceField,
            embedded: embedded,
            ocr: ocr
        )

        return ScreenshotSourceEvidence(
            platform: finalPlatform,
            type: finalType,
            family: finalFamily,
            surface: surfaceField,
            embeddedHints: finalEmbedded
        )
    }

    /// When surface is lock/NC, strip platform/type that came only from notification app chrome.
    private static func demoteEmbeddedAppChrome(
        platform: SourceEvidenceField,
        type: SourceEvidenceField,
        family: SourceEvidenceField,
        surface: SourceEvidenceField,
        embedded: [EmbeddedContentHint],
        ocr: String
    ) -> (SourceEvidenceField, SourceEvidenceField, SourceEvidenceField, [EmbeddedContentHint]) {
        guard surface.value == "lock_screen" || surface.value == "notification_center" else {
            return (platform, type, family, embedded)
        }

        var hints = embedded
        var platformOut = platform
        var typeOut = type
        var familyOut = family

        let notifiable: Set<String> = [
            "gmail", "mail", "whatsapp", "instagram", "imessage", "messenger", "maps", "messages"
        ]

        if notifiable.contains(platform.value) {
            if !hints.contains(where: { $0.value == platform.value }) {
                hints.append(
                    EmbeddedContentHint(
                        value: platform.value,
                        kind: "notification",
                        confidence: min(0.75, platform.confidence),
                        evidence: ["demoted_from_platform", "ocr_embedded"]
                    )
                )
            }
            platformOut = .unknown(trace: [
                "PLATFORM: abstained — surface is \(surface.value)",
                "PLATFORM: \"\(platform.value)\" demoted to EMBEDDED hint (not screenshot platform)",
                "PLATFORM: whole screenshot must not become \(platform.value) from a notification"
            ])
        }

        // Do not classify lock/NC as email/chat/map solely from embedded notification chrome.
        let demoteTypes: Set<String> = ["email", "chat", "social_post", "map"]
        if demoteTypes.contains(type.value) {
            typeOut = .unknown(trace: [
                "TYPE: abstained — surface is \(surface.value); \"\(type.value)\" not applied to whole screenshot",
                "TYPE: embedded notification content is recorded under EMBEDDED HINTS"
            ])
            familyOut = .unknown(trace: [
                "FAMILY: abstained — follows type demotion on \(surface.value)"
            ])
        }

        // Ensure gmail-like OCR still surfaces as embedded even if platform was already unknown.
        if hints.isEmpty {
            hints = detectEmbeddedHints(ocr: ocr, surface: surface.value)
        }

        return (platformOut, typeOut, familyOut, hints)
    }

    // MARK: - Platform

    private static func detectPlatform(ocr: String) -> SourceEvidenceField {
        // Order matters: more specific chrome first.
        let checks: [(String, [String])] = [
            ("instagram", ["instagram", "liked by", "reels"]),
            ("linkedin", ["linkedin", "connection request", "people also viewed"]),
            ("facebook", ["facebook", "news feed"]),
            ("whatsapp", ["whatsapp", "voice message", "tap to call"]),
            ("imessage", ["imessage"]),
            ("messenger", ["messenger", "facebook messenger"]),
            ("gmail", ["gmail", "google mail"]),
            ("mail", ["mailboxes", "all inboxes"]),
            ("maps", ["google maps", "apple maps"]),
            ("browser", ["safari"])
        ]
        for (platform, needles) in checks {
            if let hit = needles.first(where: { ocr.contains($0) }) {
                return SourceEvidenceField(
                    value: platform,
                    confidence: 0.85,
                    evidence: ["ocr_platform"],
                    trace: [
                        "PLATFORM: \(platform) from OCR chrome needle \"\(hit)\"",
                        "PLATFORM: confidence 0.85 (literal chrome)"
                    ]
                )
            }
        }
        return .unknown(trace: [
            "PLATFORM: abstained — no OCR platform chrome needles matched",
            "PLATFORM: needles checked include app names + a few chrome phrases (e.g. whatsapp|voice message|tap to call)",
            "PLATFORM: structure alone does not set platform (R2a/R2b: unknown is acceptable)"
        ])
    }

    // MARK: - Type / family

    private struct Typed {
        var type: SourceEvidenceField
        var family: SourceEvidenceField
    }

    private static func detectTypeAndFamily(
        ocr: String,
        lines: [String],
        platform: String,
        facets: Set<String>
    ) -> Typed {
        // Strong facets map directly when present (already precision-gated in 8.2A).
        let facetPriority: [(String, String)] = [
            ("boarding_pass", "travel"),
            ("flight_booking", "travel"),
            ("hotel_booking", "travel"),
            ("reservation", "travel"),
            ("map", "navigation"),
            ("product_page", "commerce"),
            ("receipt", "commerce"),
            ("chat", "messaging"),
            ("social_post", "social_media")
        ]
        for (facet, family) in facetPriority where facets.contains(facet) {
            return Typed(
                type: SourceEvidenceField(
                    value: facet == "chat" ? "chat" : (facet == "social_post" ? "social_post" : (facet == "map" ? "map" : facet)),
                    confidence: 0.80,
                    evidence: ["facet"],
                    trace: [
                        "TYPE: \(facet == "chat" ? "chat" : (facet == "social_post" ? "social_post" : (facet == "map" ? "map" : facet))) from strong Level 2A facet \"\(facet)\"",
                        "TYPE: platform may remain unknown — valid when facet supports type"
                    ]
                ),
                family: SourceEvidenceField(
                    value: family,
                    confidence: 0.80,
                    evidence: ["facet"],
                    trace: [
                        "FAMILY: \(family) mapped from strong facet \"\(facet)\""
                    ]
                )
            )
        }

        // Platform-led types when structural cues support them.
        switch platform {
        case "instagram", "linkedin", "facebook":
            if hasSocialStructure(ocr: ocr, lines: lines) || platform != ScreenshotSourceEvidence.unknown {
                return Typed(
                    type: SourceEvidenceField(
                        value: "social_post",
                        confidence: 0.70,
                        evidence: ["platform_structure"],
                        trace: ["TYPE: social_post from platform \(platform) + social structure/chrome"]
                    ),
                    family: SourceEvidenceField(
                        value: "social_media",
                        confidence: 0.70,
                        evidence: ["platform_structure"],
                        trace: ["FAMILY: social_media from platform \(platform)"]
                    )
                )
            }
        case "whatsapp", "imessage", "messenger":
            return Typed(
                type: SourceEvidenceField(
                    value: "chat",
                    confidence: 0.75,
                    evidence: ["platform_structure"],
                    trace: ["TYPE: chat from messaging platform \(platform)"]
                ),
                family: SourceEvidenceField(
                    value: "messaging",
                    confidence: 0.75,
                    evidence: ["platform_structure"],
                    trace: ["FAMILY: messaging from messaging platform \(platform)"]
                )
            )
        case "gmail", "mail":
            if hasEmailStructure(ocr: ocr, lines: lines) || platform == "gmail" {
                return Typed(
                    type: SourceEvidenceField(
                        value: "email",
                        confidence: 0.70,
                        evidence: ["platform_structure"],
                        trace: ["TYPE: email from mail platform \(platform)"]
                    ),
                    family: SourceEvidenceField(
                        value: "email",
                        confidence: 0.70,
                        evidence: ["platform_structure"],
                        trace: ["FAMILY: email from mail platform \(platform)"]
                    )
                )
            }
        case "maps":
            return Typed(
                type: SourceEvidenceField(
                    value: "map",
                    confidence: 0.75,
                    evidence: ["platform_structure"],
                    trace: ["TYPE: map from maps platform chrome"]
                ),
                family: SourceEvidenceField(
                    value: "navigation",
                    confidence: 0.75,
                    evidence: ["platform_structure"],
                    trace: ["FAMILY: navigation from maps platform chrome"]
                )
            )
        default:
            break
        }

        if hasEmailStructure(ocr: ocr, lines: lines) {
            return Typed(
                type: SourceEvidenceField(
                    value: "email",
                    confidence: 0.65,
                    evidence: ["ocr_structure"],
                    trace: ["TYPE: email from OCR email structure (subject/from/inbox cues)"]
                ),
                family: SourceEvidenceField(
                    value: "email",
                    confidence: 0.65,
                    evidence: ["ocr_structure"],
                    trace: ["FAMILY: email from OCR email structure"]
                )
            )
        }
        if hasIdentityDocumentCues(ocr: ocr) {
            return Typed(
                type: SourceEvidenceField(
                    value: "identity_document",
                    confidence: 0.70,
                    evidence: ["ocr_structure"],
                    trace: ["TYPE: identity_document from multiple identity OCR cues"]
                ),
                family: SourceEvidenceField(
                    value: "identity_document",
                    confidence: 0.70,
                    evidence: ["ocr_structure"],
                    trace: ["FAMILY: identity_document from multiple identity OCR cues"]
                )
            )
        }
        if hasCommerceCues(ocr: ocr) {
            return Typed(
                type: SourceEvidenceField(
                    value: "product_page",
                    confidence: 0.60,
                    evidence: ["ocr_keyword"],
                    trace: ["TYPE: product_page from commerce OCR cues"]
                ),
                family: SourceEvidenceField(
                    value: "commerce",
                    confidence: 0.60,
                    evidence: ["ocr_keyword"],
                    trace: ["FAMILY: commerce from commerce OCR cues"]
                )
            )
        }

        return Typed(
            type: .unknown(trace: [
                "TYPE: abstained — no strong facet and no platform-led / OCR structure match",
                "TYPE: independent structural chat inference is deferred to R2b (R2a DEBUG only)"
            ]),
            family: .unknown(trace: [
                "FAMILY: abstained — follows type; no family mapping without type evidence",
                "FAMILY: R2b may set messaging from chat structure without platform"
            ])
        )
    }

    // MARK: - Surface / embedded (R2a DEBUG)

    private static func detectSurface(
        ocr: String,
        lines: [String],
        platform: String,
        type: String,
        facets: Set<String>
    ) -> SourceEvidenceField {
        let lockNeedles = [
            "swipe up to unlock", "press home to unlock", "touch id to unlock",
            "face id", "unlock to open", "slide to unlock", "swipe up for"
        ]
        if let hit = lockNeedles.first(where: { ocr.contains($0) }) {
            return SourceEvidenceField(
                value: "lock_screen",
                confidence: 0.90,
                evidence: ["ocr_surface"],
                trace: [
                    "SURFACE: lock_screen from unlock chrome \"\(hit)\"",
                    "SURFACE: embedded notification apps must not redefine screenshot platform"
                ]
            )
        }

        let ncNeedles = [
            "notification center", "no older notifications", "notifications"
        ]
        // Prefer explicit NC chrome; bare "notifications" alone is weak.
        if ocr.contains("notification center") || ocr.contains("no older notifications") {
            return SourceEvidenceField(
                value: "notification_center",
                confidence: 0.88,
                evidence: ["ocr_surface"],
                trace: [
                    "SURFACE: notification_center from NC chrome",
                    "SURFACE: embedded app names are hints only"
                ]
            )
        }

        // Lock-screen controls often appear together without unlock copy in OCR crops.
        let hasFlashlight = ocr.contains("flashlight")
        let hasCameraControl = lines.contains { $0.lowercased() == "camera" } || ocr.contains("camera")
        if hasFlashlight, hasCameraControl, !facets.contains("chat") {
            return SourceEvidenceField(
                value: "lock_screen",
                confidence: 0.72,
                evidence: ["ocr_surface"],
                trace: [
                    "SURFACE: lock_screen from Flashlight + Camera control chrome",
                    "SURFACE: confidence moderate — not unlock copy"
                ]
            )
        }

        // Notification-style crop: app names + clocks, no full email/chat app structure.
        // DEBUG surface only — does not set platform/type (embedded hints carry app names).
        if looksLikeNotificationSurface(ocr: ocr, lines: lines, facets: facets) {
            return SourceEvidenceField(
                value: "lock_screen",
                confidence: 0.62,
                evidence: ["ocr_surface", "notification_stack"],
                trace: [
                    "SURFACE: lock_screen (notification-stack heuristic)",
                    "SURFACE: app names in OCR become EMBEDDED hints — not screenshot platform",
                    "SURFACE: confidence moderate — unlock chrome absent"
                ]
            )
        }

        let knownPlatform = platform != ScreenshotSourceEvidence.unknown
        let knownType = type != ScreenshotSourceEvidence.unknown
        if knownPlatform || knownType || !facets.isEmpty {
            return SourceEvidenceField(
                value: "app_screen",
                confidence: knownPlatform ? 0.75 : 0.60,
                evidence: ["surface_default"],
                trace: [
                    "SURFACE: app_screen — content/platform/facet evidence without lock/NC chrome",
                    knownPlatform
                        ? "SURFACE: platform \(platform) supports app_screen"
                        : "SURFACE: type/facet present; platform may still be unknown"
                ]
            )
        }

        if !lines.isEmpty {
            return SourceEvidenceField(
                value: "app_screen",
                confidence: 0.40,
                evidence: ["surface_default"],
                trace: [
                    "SURFACE: app_screen (weak default) — OCR present, no lock/NC chrome",
                    "SURFACE: abstain preferred when uncertain; weak default for DEBUG layout"
                ]
            )
        }

        _ = ncNeedles
        return .unknown(trace: [
            "SURFACE: abstained — no lock/NC chrome and no content evidence"
        ])
    }

    /// Heuristic: stacked notification lines (not full mail/chat app). R2a DEBUG surface only.
    private static func looksLikeNotificationSurface(
        ocr: String,
        lines: [String],
        facets: Set<String>
    ) -> Bool {
        if facets.contains("chat") || facets.contains("social_post") || facets.contains("map") {
            return false
        }
        if hasEmailStructure(ocr: ocr, lines: lines) { return false }
        let appMentions = ["gmail", "google mail", "whatsapp", "instagram", "messages", "mail"]
            .filter { ocr.contains($0) }
        guard !appMentions.isEmpty else { return false }
        let clockLines = lines.filter {
            $0.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) != nil
                || $0.range(of: #"\d{1,2}:\d{2}\s?(am|pm)"#, options: [.regularExpression, .caseInsensitive]) != nil
        }.count
        // Short stacked lines typical of NC / lock notifications.
        let shortLines = lines.filter { (4...48).contains($0.count) }.count
        return clockLines >= 1 || shortLines >= 4
    }

    private static func detectEmbeddedHints(
        ocr: String,
        surface: String
    ) -> [EmbeddedContentHint] {
        guard surface == "lock_screen" || surface == "notification_center" else {
            return []
        }
        var hints: [EmbeddedContentHint] = []
        let checks: [(String, [String])] = [
            ("gmail", ["gmail", "google mail"]),
            ("whatsapp", ["whatsapp"]),
            ("instagram", ["instagram"]),
            ("mail", ["mail"]),
            ("messages", ["messages", "imessage"]),
            ("maps", ["maps"])
        ]
        for (value, needles) in checks {
            if let hit = needles.first(where: { ocr.contains($0) }) {
                hints.append(
                    EmbeddedContentHint(
                        value: value,
                        kind: "notification",
                        confidence: 0.70,
                        evidence: ["ocr_embedded", "needle:\(hit)"]
                    )
                )
            }
        }
        return hints
    }

    private static func hasSocialStructure(ocr: String, lines: [String]) -> Bool {
        let engagement = ["liked by", "followers", "comments", "shares", "replies", "retweet"]
        if engagement.contains(where: { ocr.contains($0) }) { return true }
        return lines.count >= 4
    }

    private static func hasEmailStructure(ocr: String, lines: [String]) -> Bool {
        let cues = ["subject:", "from:", "to:", "inbox", "unsubscribe", "sent items"]
        let hits = cues.filter { ocr.contains($0) }.count
        return hits >= 2 || (hits >= 1 && lines.count >= 5)
    }

    /// Requires multiple identity-specific cues — never Vision `document` alone.
    private static func hasIdentityDocumentCues(ocr: String) -> Bool {
        let cues = [
            "passport", "national id", "resident id", "identity card", "date of birth",
            "nationality", "document no", "id number", "emirates id", "qid "
        ]
        return cues.filter { ocr.contains($0) }.count >= 2
    }

    private static func hasCommerceCues(ocr: String) -> Bool {
        let cues = ["add to cart", "add to bag", "buy now", "checkout", "in stock", "sku"]
        return cues.filter { ocr.contains($0) }.count >= 1
    }
}
