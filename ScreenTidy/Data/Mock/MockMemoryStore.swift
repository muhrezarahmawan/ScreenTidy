import Foundation

/// In-memory fixtures for UI development and Xcode Previews.
/// Mutation APIs (`mockRemoveScreenshots`) are Sprint 2 demo-only — not PhotoKit.
///
/// **Mock undo:** reversible mutations retain a full store snapshot until `undo` or
/// `discardUndo`. This is **not** a stand-in for future PhotoKit restore semantics.
actor MockMemoryStore: MemoryRepository, ScreenshotIngesting, SearchProviding, CleanupProviding, Organizing {
    private var contexts: [ContextCollection]
    private var screenshots: [ScreenshotMemory]
    private var memberships: [ContextCollectionID: [ScreenshotMemoryID]]
    private var duplicateGroups: [DuplicateGroup]
    private let oldThresholdMonths: Int

    /// At most one pending undo window — newer mutations commit the previous one.
    private var pendingUndo: (token: MockUndoToken, snapshot: StoreSnapshot)?

    private struct StoreSnapshot: Sendable {
        let contexts: [ContextCollection]
        let screenshots: [ScreenshotMemory]
        let memberships: [ContextCollectionID: [ScreenshotMemoryID]]
        let duplicateGroups: [DuplicateGroup]
    }

    init(
        contexts: [ContextCollection] = MockData.contexts,
        screenshots: [ScreenshotMemory] = MockData.allScreenshots,
        memberships: [ContextCollectionID: [ScreenshotMemoryID]] = MockData.memberships,
        duplicateGroups: [DuplicateGroup] = MockData.duplicateGroups,
        oldThresholdMonths: Int = MockData.oldThresholdMonths
    ) {
        self.contexts = contexts
        self.screenshots = screenshots
        self.memberships = memberships
        self.duplicateGroups = duplicateGroups
        self.oldThresholdMonths = oldThresholdMonths
        // Keep pocket counts aligned with membership — required after mutations.
        self.syncMemberCounts()
    }

    // MARK: - Undo (mock only)

    /// Restores the snapshot captured for `token`. Returns `false` if expired or already used.
    @discardableResult
    func undo(token: MockUndoToken) async -> Bool {
        guard let pending = pendingUndo, pending.token == token else { return false }
        contexts = pending.snapshot.contexts
        screenshots = pending.snapshot.screenshots
        memberships = pending.snapshot.memberships
        duplicateGroups = pending.snapshot.duplicateGroups
        pendingUndo = nil
        return true
    }

    /// Drops retained snapshot without restoring (toast timeout / superseded).
    func discardUndo(token: MockUndoToken) async {
        guard pendingUndo?.token == token else { return }
        pendingUndo = nil
    }

    private func captureSnapshot() -> StoreSnapshot {
        StoreSnapshot(
            contexts: contexts,
            screenshots: screenshots,
            memberships: memberships,
            duplicateGroups: duplicateGroups
        )
    }

    /// Begins an undoable mutation: commits any previous pending undo, then snapshots.
    private func beginUndoableMutation() -> MockUndoToken {
        pendingUndo = nil
        let token = MockUndoToken()
        pendingUndo = (token, captureSnapshot())
        return token
    }

    private func invalidatePendingUndo() {
        pendingUndo = nil
    }

    func fetchPromotedContexts() async throws -> [ContextCollection] {
        let threshold = 3
        return contexts
            .filter { $0.kind != .unassigned && !$0.isArchived }
            // User-created collections always appear (may be empty). AI contexts need pin or threshold.
            .filter { $0.isPinned || $0.kind == .userContext || $0.memberCount >= threshold }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func fetchUnassignedCount() async throws -> Int {
        contexts.first(where: { $0.kind == .unassigned })?.memberCount ?? 0
    }

    func fetchUnassignedContext() async throws -> ContextCollection? {
        contexts.first(where: { $0.kind == .unassigned })
    }

    func fetchRecentScreenshots(limit: Int) async throws -> [ScreenshotMemory] {
        Array(screenshots.prefix(limit))
    }

    func fetchScreenshot(id: ScreenshotMemoryID) async throws -> ScreenshotMemory? {
        screenshots.first { $0.id == id }
    }

    func fetchContext(id: ContextCollectionID) async throws -> ContextCollection? {
        contexts.first { $0.id == id }
    }

    func fetchScreenshots(in contextID: ContextCollectionID) async throws -> [ScreenshotMemory] {
        try await fetchScreenshots(in: contextID, limit: Int.max, offset: 0)
    }

    func fetchScreenshots(in contextID: ContextCollectionID, limit: Int, offset: Int) async throws -> [ScreenshotMemory] {
        guard limit > 0, offset >= 0 else { return [] }
        let ids = memberships[contextID] ?? []
        let byID = Dictionary(uniqueKeysWithValues: screenshots.map { ($0.id, $0) })
        let ordered = ids.compactMap { byID[$0] }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        return Array(ordered.dropFirst(offset).prefix(limit))
    }

    func search(query: String) async throws -> SearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let tokens = Self.searchTokens(from: trimmed)
        guard !tokens.isEmpty else { return .empty }

        // Collection title matches (strong) — exclude Needs Review inbox from “Collections” hits.
        let matchedCollections = contexts
            .filter { $0.kind != .unassigned && !$0.isArchived }
            .compactMap { context -> (ContextCollection, Double)? in
                let title = context.title
                let hitCount = tokens.filter { Self.contains(title, $0) }.count
                guard hitCount > 0 else { return nil }
                let score = Double(hitCount) / Double(tokens.count)
                return (context, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map(\.0)

        // Screenshot membership → collection titles for ranking.
        let titlesByShot: [ScreenshotMemoryID: [String]] = {
            var map: [ScreenshotMemoryID: [String]] = [:]
            for (contextID, memberIDs) in memberships {
                guard let title = contexts.first(where: { $0.id == contextID })?.title else { continue }
                for id in memberIDs {
                    map[id, default: []].append(title)
                }
            }
            return map
        }()

        var hits: [SearchHit] = []
        hits.reserveCapacity(screenshots.count)
        for shot in screenshots {
            if let hit = Self.scoreScreenshot(
                shot,
                tokens: tokens,
                collectionTitles: titlesByShot[shot.id] ?? []
            ) {
                hits.append(hit)
            }
        }
        hits.sort { lhs, rhs in
            if lhs.relevanceScore != rhs.relevanceScore {
                return lhs.relevanceScore > rhs.relevanceScore
            }
            return (lhs.screenshot.createdAt ?? .distantPast) > (rhs.screenshot.createdAt ?? .distantPast)
        }

        return SearchResponse(collections: Array(matchedCollections), hits: hits)
    }

    private static func searchTokens(from query: String) -> [String] {
        query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 1 }
    }

    /// Sprint 2 mock ranking — mirrors future multi-signal SearchService behavior.
    private static func scoreScreenshot(
        _ shot: ScreenshotMemory,
        tokens: [String],
        collectionTitles: [String]
    ) -> SearchHit? {
        let ocr = shot.ocrText ?? ""
        let summary = shot.summary ?? ""
        let entities = shot.entityLabels
        let facets = shot.facetKeys
        let visual = shot.visualLabels
        let semantic = shot.semanticKeywords

        // Single searchable blob for resilient substring matching (case/diacritic insensitive).
        let haystackParts: [String] = [ocr, summary]
            + entities
            + facets
            + visual
            + semantic
            + collectionTitles
        let haystack = haystackParts.joined(separator: " ")

        var score = 0.0
        var signals = Set<SearchSignal>()
        var matchedTokens = 0

        for token in tokens {
            var matched = false

            if Self.contains(ocr, token) {
                score += 1.0
                signals.insert(.ocr)
                matched = true
            }
            if entities.contains(where: { Self.contains($0, token) }) {
                score += 0.95
                signals.insert(.semantic)
                matched = true
            }
            if collectionTitles.contains(where: { Self.contains($0, token) }) {
                score += 0.9
                signals.insert(.collection)
                matched = true
            }
            if visual.contains(where: { Self.contains($0, token) || Self.contains(token, $0) }) {
                score += 0.85
                signals.insert(.visual)
                matched = true
            }
            if facets.contains(where: { Self.contains($0, token) })
                || semantic.contains(where: { Self.contains($0, token) })
            {
                score += 0.75
                signals.insert(.semantic)
                matched = true
            }
            if Self.contains(summary, token) {
                score += 0.7
                signals.insert(.semantic)
                matched = true
            }

            // Fallback: token appears anywhere in the combined haystack.
            if !matched, Self.contains(haystack, token) {
                score += 0.55
                signals.insert(.semantic)
                matched = true
            }

            // Lightweight date/recency hooks for future NL time queries.
            if token == "old" || token == "older" {
                if let created = shot.createdAt,
                   created < Date().addingTimeInterval(-150 * 24 * 60 * 60)
                {
                    score += 0.4
                    signals.insert(.date)
                    matched = true
                }
            }
            if matched { matchedTokens += 1 }
        }

        guard matchedTokens > 0 else { return nil }

        // Soft AND: prefer hits that cover more of a multi-word query.
        if tokens.count > 1 {
            let coverage = Double(matchedTokens) / Double(tokens.count)
            score *= (0.55 + 0.45 * coverage)
        }

        let phrase = tokens.joined(separator: " ")
        if phrase.count > 2, Self.contains(haystack, phrase) {
            score += 0.55
            if Self.contains(ocr, phrase) { signals.insert(.ocr) }
            if visual.contains(where: { Self.contains($0, phrase) }) { signals.insert(.visual) }
        }

        return SearchHit(
            screenshot: shot,
            relevanceScore: score,
            matchedSignals: signals
        )
    }

    private static func contains(_ text: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        return text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    func fetchCleanupOverview() async throws -> CleanupOverview {
        let old = try await fetchOldScreenshots()
        let groups = duplicateGroups.filter { $0.count >= 2 }
        return CleanupOverview(
            duplicateScreenshotCount: groups.reduce(0) { $0 + $1.count },
            duplicateGroupCount: groups.count,
            oldScreenshotCount: old.count,
            oldThresholdMonths: oldThresholdMonths
        )
    }

    func fetchDuplicateGroups() async throws -> [DuplicateGroup] {
        duplicateGroups.filter { $0.count >= 2 }
    }

    func fetchOldScreenshots() async throws -> [ScreenshotMemory] {
        let cutoff = Calendar.current.date(
            byAdding: .month,
            value: -oldThresholdMonths,
            to: Date()
        ) ?? Date.distantPast
        return screenshots
            .filter { ($0.createdAt ?? .distantFuture) < cutoff }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    @discardableResult
    func mockRemoveScreenshots(ids: Set<ScreenshotMemoryID>) async throws -> MockUndoToken {
        let token = beginUndoableMutation()
        guard !ids.isEmpty else { return token }
        screenshots.removeAll { ids.contains($0.id) }
        for key in memberships.keys {
            memberships[key]?.removeAll { ids.contains($0) }
        }
        duplicateGroups = duplicateGroups.compactMap { group in
            let remaining = group.screenshotIDs.filter { !ids.contains($0) }
            guard remaining.count >= 2 else { return nil }
            var updated = group
            updated.screenshotIDs = remaining
            if let keep = group.recommendedKeepID, ids.contains(keep) {
                updated.recommendedKeepID = remaining.first
            }
            return updated
        }
        syncMemberCounts()
        return token
    }

    /// Internal remove used when already inside another undoable mutation (e.g. delete collection + shots).
    private func removeScreenshotsWithoutUndo(ids: Set<ScreenshotMemoryID>) {
        guard !ids.isEmpty else { return }
        screenshots.removeAll { ids.contains($0.id) }
        for key in memberships.keys {
            memberships[key]?.removeAll { ids.contains($0) }
        }
        duplicateGroups = duplicateGroups.compactMap { group in
            let remaining = group.screenshotIDs.filter { !ids.contains($0) }
            guard remaining.count >= 2 else { return nil }
            var updated = group
            updated.screenshotIDs = remaining
            if let keep = group.recommendedKeepID, ids.contains(keep) {
                updated.recommendedKeepID = remaining.first
            }
            return updated
        }
    }

    // MARK: - MemoryWriting (Sprint 2 mock)

    func fetchContextsForPicker(excluding excludedID: ContextCollectionID?) async throws -> [ContextCollection] {
        contexts
            .filter { !$0.isArchived }
            .filter { $0.id != excludedID }
            .sorted { lhs, rhs in
                if (lhs.kind == .unassigned) != (rhs.kind == .unassigned) {
                    return lhs.kind != .unassigned
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func fetchContextsForAddPicker(
        screenshotIDs: Set<ScreenshotMemoryID>,
        excluding excludedID: ContextCollectionID?
    ) async throws -> [ContextCollection] {
        let alreadyInAll = collectionsContainingAll(ids: screenshotIDs)
        return contexts
            .filter { !$0.isArchived && $0.kind != .unassigned }
            .filter { $0.id != excludedID }
            .filter { !alreadyInAll.contains($0.id) }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private func collectionsContainingAll(ids: Set<ScreenshotMemoryID>) -> Set<ContextCollectionID> {
        guard !ids.isEmpty else { return [] }
        return Set(
            memberships.compactMap { collectionID, members in
                ids.isSubset(of: Set(members)) ? collectionID : nil
            }
        )
    }

    func createContext(title: String, badgeEmoji: String?, badgeColor: String?) async throws -> ContextCollection {
        invalidatePendingUndo()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.underlying(message: "Name is required")
        }
        let nextOrder = (contexts.map(\.sortOrder).max() ?? -1) + 1
        let context = ContextCollection(
            id: ContextCollectionID(),
            kind: .userContext,
            title: trimmed,
            isPinned: false,
            isArchived: false,
            sortOrder: nextOrder,
            memberCount: 0,
            memberPreviewSymbols: [],
            badgeEmoji: badgeEmoji.flatMap { $0.isEmpty ? nil : $0 },
            badgeColor: badgeColor.flatMap { $0.isEmpty ? nil : $0 },
            insight: nil
        )
        contexts.append(context)
        memberships[context.id] = []
        syncMemberCounts()
        return context
    }

    func reorderContexts(orderedIDs: [ContextCollectionID]) async throws {
        invalidatePendingUndo()
        guard !orderedIDs.isEmpty else { return }
        for (index, id) in orderedIDs.enumerated() {
            guard let i = contexts.firstIndex(where: { $0.id == id }),
                  contexts[i].kind != .unassigned
            else { continue }
            contexts[i].sortOrder = index
        }
    }

    func remapPhotosLocalIdentifiers(_ mapping: [String: String]) async throws {
        guard !mapping.isEmpty else { return }
        for index in screenshots.indices {
            guard let previous = screenshots[index].photosLocalIdentifier,
                  let next = mapping[previous],
                  !next.isEmpty
            else { continue }
            screenshots[index].photosLocalIdentifier = next
        }
    }

    func updateContext(id: ContextCollectionID, title: String?, badgeEmoji: String?, badgeColor: String?) async throws {
        invalidatePendingUndo()
        guard let index = contexts.firstIndex(where: { $0.id == id }) else {
            throw AppError.underlying(message: "Collection not found")
        }
        if contexts[index].kind == .unassigned {
            throw AppError.underlying(message: "Needs Review can’t be renamed")
        }
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AppError.underlying(message: "Name is required")
            }
            contexts[index].title = trimmed
        }
        if let badgeEmoji {
            contexts[index].badgeEmoji = badgeEmoji.isEmpty ? nil : badgeEmoji
        }
        if let badgeColor {
            contexts[index].badgeColor = badgeColor.isEmpty ? nil : badgeColor
        }
    }

    @discardableResult
    func deleteContext(id: ContextCollectionID, deleteScreenshots: Bool) async throws -> MockUndoToken {
        guard let context = contexts.first(where: { $0.id == id }) else {
            // No mutation — return a dead token (undo/discard are no-ops).
            return MockUndoToken()
        }
        guard context.kind != .unassigned else {
            throw AppError.underlying(message: "Needs Review can’t be deleted")
        }
        let token = beginUndoableMutation()
        let memberIDs = memberships[id] ?? []
        if deleteScreenshots {
            // Sprint 2 mock: undo restores in-memory rows. Production PhotoKit delete
            // must not offer Undo unless Photos assets can actually be restored.
            removeScreenshotsWithoutUndo(ids: Set(memberIDs))
        } else {
            // Collection only: Photos assets stay. Orphans move to Needs Review (unassigned).
            // Screenshots that still belong to another collection keep those memberships.
            if let unassigned = contexts.first(where: { $0.kind == .unassigned }) {
                var unassignedMembers = memberships[unassigned.id] ?? []
                for shotID in memberIDs {
                    let stillOwnedElsewhere = memberships.contains { key, value in
                        key != id && key != unassigned.id && value.contains(shotID)
                    }
                    if !stillOwnedElsewhere && !unassignedMembers.contains(shotID) {
                        unassignedMembers.append(shotID)
                    }
                }
                memberships[unassigned.id] = unassignedMembers
            }
            // Screenshot rows remain in `screenshots` — mock stand-in for Photos library untouched.
        }
        contexts.removeAll { $0.id == id }
        memberships[id] = nil
        syncMemberCounts()
        return token
    }

    @discardableResult
    func moveScreenshots(ids: Set<ScreenshotMemoryID>, to destinationID: ContextCollectionID) async throws -> MockUndoToken {
        guard contexts.contains(where: { $0.id == destinationID }) else {
            throw AppError.underlying(message: "Destination not found")
        }
        let token = beginUndoableMutation()
        guard !ids.isEmpty else { return token }

        for key in memberships.keys {
            memberships[key]?.removeAll { ids.contains($0) }
        }
        var dest = memberships[destinationID] ?? []
        for id in ids where !dest.contains(id) {
            dest.append(id)
        }
        memberships[destinationID] = dest
        applyNeedsReviewInvariant(for: ids)
        syncMemberCounts()
        return token
    }

    @discardableResult
    func addScreenshots(ids: Set<ScreenshotMemoryID>, to destinationID: ContextCollectionID) async throws -> MockUndoToken {
        guard let destination = contexts.first(where: { $0.id == destinationID }) else {
            throw AppError.underlying(message: "Destination not found")
        }
        guard destination.kind != .unassigned else {
            throw AppError.underlying(message: "Use Move to send screenshots to Needs Review")
        }
        let token = beginUndoableMutation()
        guard !ids.isEmpty else { return token }
        var dest = memberships[destinationID] ?? []
        for id in ids where !dest.contains(id) {
            dest.append(id)
        }
        memberships[destinationID] = dest
        applyNeedsReviewInvariant(for: ids)
        syncMemberCounts()
        return token
    }

    @discardableResult
    func removeScreenshots(ids: Set<ScreenshotMemoryID>, from collectionID: ContextCollectionID) async throws -> MockUndoToken {
        guard let collection = contexts.first(where: { $0.id == collectionID }) else {
            throw AppError.underlying(message: "Collection not found")
        }
        guard collection.kind != .unassigned else {
            throw AppError.underlying(message: "Remove from Collection isn’t available in Needs Review")
        }
        let token = beginUndoableMutation()
        guard !ids.isEmpty else { return token }
        memberships[collectionID]?.removeAll { ids.contains($0) }
        applyNeedsReviewInvariant(for: ids)
        syncMemberCounts()
        return token
    }

    /// Needs Review invariant for the in-memory mock (mirrors GRDB).
    private func applyNeedsReviewInvariant(for ids: Set<ScreenshotMemoryID>) {
        guard let inbox = contexts.first(where: { $0.kind == .unassigned }) else { return }
        var inboxMembers = memberships[inbox.id] ?? []
        let normalIDs = Set(contexts.filter { $0.kind != .unassigned }.map(\.id))

        for shotID in ids {
            let inNormal = normalIDs.contains { collectionID in
                memberships[collectionID]?.contains(shotID) == true
            }
            if inNormal {
                inboxMembers.removeAll { $0 == shotID }
            } else if !inboxMembers.contains(shotID) {
                inboxMembers.append(shotID)
            }
        }
        memberships[inbox.id] = inboxMembers
    }

    private func syncMemberCounts() {
        let shotSymbol: [ScreenshotMemoryID: String] = Dictionary(
            uniqueKeysWithValues: screenshots.map { ($0.id, $0.previewSymbol) }
        )
        contexts = contexts.map { context in
            var copy = context
            let members = memberships[context.id] ?? []
            copy.memberCount = members.count
            // Keep Quiet Pocket peeks in sync with real members when possible.
            let symbols = members.compactMap { shotSymbol[$0] }
            if !symbols.isEmpty {
                copy.memberPreviewSymbols = Array(symbols.prefix(3))
            }
            return copy
        }
    }

    func organizeIfNeeded(screenshotID: ScreenshotMemoryID) async throws {
        throw AppError.unavailable(feature: "Organization")
    }

    /// Sprint 2 mock: invents new screenshot rows and attaches them to a promoted collection
    /// or Needs Review — stands in for incremental Photos ingest + organize.
    @discardableResult
    func mockIngestNewScreenshots(count: Int) async throws -> Int {
        invalidatePendingUndo()
        guard count > 0 else { return 0 }

        let kinds: [(symbol: String, facet: String)] = [
            ("airplane", "flight"),
            ("building.2", "hotel"),
            ("doc.text", "document"),
            ("fork.knife", "restaurant"),
            ("map", "map"),
            ("photo", "photo")
        ]

        var createdIDs: [ScreenshotMemoryID] = []
        for i in 0..<count {
            let kind = kinds[i % kinds.count]
            let id = ScreenshotMemoryID()
            createdIDs.append(id)
            screenshots.insert(
                ScreenshotMemory(
                    id: id,
                    createdAt: Date(),
                    isFavorite: false,
                    ocrText: "Synced screenshot \(screenshots.count + 1)",
                    summary: nil,
                    facetKeys: [kind.facet],
                    entityLabels: [],
                    previewSymbol: kind.symbol
                ),
                at: 0
            )
        }

        // Prefer attaching to a pinned / promoted context; otherwise Needs Review.
        let destinationID: ContextCollectionID
        if let japan = contexts.first(where: { $0.id == MockData.japanTripID }) {
            destinationID = japan.id
        } else if let unassigned = contexts.first(where: { $0.kind == .unassigned }) {
            destinationID = unassigned.id
        } else if let first = contexts.first(where: { $0.kind != .unassigned }) {
            destinationID = first.id
        } else {
            return 0
        }

        var members = memberships[destinationID] ?? []
        members.insert(contentsOf: createdIDs, at: 0)
        memberships[destinationID] = members
        syncMemberCounts()
        return createdIDs.count
    }
}

enum MockData {
    // Fixed UUIDs keep previews, persistence fixtures, and tests aligned across launches.
    static let japanTripID = ContextCollectionID(FixtureIDs.uuid("japan-trip"))
    static let apartmentID = ContextCollectionID(FixtureIDs.uuid("apartment-setup"))
    static let qatarID = ContextCollectionID(FixtureIDs.uuid("qatar-airways"))
    static let visaID = ContextCollectionID(FixtureIDs.uuid("visa-application"))
    static let weekendID = ContextCollectionID(FixtureIDs.uuid("weekend-restaurants"))
    static let unassignedID = ContextCollectionID(FixtureIDs.uuid("needs-review"))

    /// Demo AI folders from fixture seed — removed on Photos handoff (not user-created).
    static let seedDemoCollectionIDs: [ContextCollectionID] = [
        japanTripID, apartmentID, qatarID, visaID, weekendID
    ]

    static let shotA = ScreenshotMemoryID(FixtureIDs.uuid("shot-a"))
    static let shotB = ScreenshotMemoryID(FixtureIDs.uuid("shot-b"))
    static let shotC = ScreenshotMemoryID(FixtureIDs.uuid("shot-c"))
    static let shotD = ScreenshotMemoryID(FixtureIDs.uuid("shot-d"))
    static let shotE = ScreenshotMemoryID(FixtureIDs.uuid("shot-e"))
    static let shotF = ScreenshotMemoryID(FixtureIDs.uuid("shot-f"))
    static let shotG = ScreenshotMemoryID(FixtureIDs.uuid("shot-g"))
    static let shotH = ScreenshotMemoryID(FixtureIDs.uuid("shot-h"))
    static let shotI = ScreenshotMemoryID(FixtureIDs.uuid("shot-i"))
    static let shotJ = ScreenshotMemoryID(FixtureIDs.uuid("shot-j"))
    static let shotK = ScreenshotMemoryID(FixtureIDs.uuid("shot-k"))
    static let shotL = ScreenshotMemoryID(FixtureIDs.uuid("shot-l"))
    static let shotM = ScreenshotMemoryID(FixtureIDs.uuid("shot-m"))
    static let shotN = ScreenshotMemoryID(FixtureIDs.uuid("shot-n"))
    static let shotO = ScreenshotMemoryID(FixtureIDs.uuid("shot-o"))
    static let shotP = ScreenshotMemoryID(FixtureIDs.uuid("shot-p"))
    static let shotQ = ScreenshotMemoryID(FixtureIDs.uuid("shot-q"))
    static let shotR = ScreenshotMemoryID(FixtureIDs.uuid("shot-r"))
    static let shotS = ScreenshotMemoryID(FixtureIDs.uuid("shot-s"))
    static let shotT = ScreenshotMemoryID(FixtureIDs.uuid("shot-t"))
    static let shotU = ScreenshotMemoryID(FixtureIDs.uuid("shot-u"))
    static let shotV = ScreenshotMemoryID(FixtureIDs.uuid("shot-v"))
    static let shotW = ScreenshotMemoryID(FixtureIDs.uuid("shot-w"))
    static let shotX = ScreenshotMemoryID(FixtureIDs.uuid("shot-x"))
    static let shotY = ScreenshotMemoryID(FixtureIDs.uuid("shot-y"))
    static let shotZ = ScreenshotMemoryID(FixtureIDs.uuid("shot-z"))

    static let oldThresholdMonths = 6

    static let contexts: [ContextCollection] = [
        ContextCollection(
            id: unassignedID,
            kind: .unassigned,
            title: "Needs Review",
            isPinned: false,
            isArchived: false,
            sortOrder: 0,
            memberCount: 2,
            memberPreviewSymbols: [MockShotKind.photo.rawValue, MockShotKind.receipt.rawValue],
            badgeEmoji: nil,
            insight: nil
        ),
        ContextCollection(
            id: japanTripID,
            kind: .aiContext,
            title: "Japan Trip",
            isPinned: true,
            isArchived: false,
            sortOrder: 0,
            memberCount: 6,
            memberPreviewSymbols: [
                MockShotKind.hotel.rawValue,
                MockShotKind.map.rawValue,
                MockShotKind.boarding.rawValue
            ],
            badgeEmoji: "✈️",
            insight: nil
        ),
        ContextCollection(
            id: apartmentID,
            kind: .aiContext,
            title: "Apartment Setup",
            isPinned: false,
            isArchived: false,
            sortOrder: 1,
            memberCount: 8,
            memberPreviewSymbols: [
                MockShotKind.furniture.rawValue,
                MockShotKind.delivery.rawValue,
                MockShotKind.shopping.rawValue
            ],
            badgeEmoji: "🏠",
            insight: nil
        ),
        ContextCollection(
            id: qatarID,
            kind: .aiContext,
            title: "Qatar Airways",
            isPinned: false,
            isArchived: false,
            sortOrder: 2,
            memberCount: 5,
            memberPreviewSymbols: [
                MockShotKind.boarding.rawValue,
                MockShotKind.receipt.rawValue,
                MockShotKind.map.rawValue
            ],
            badgeEmoji: "✈️",
            insight: nil
        ),
        ContextCollection(
            id: visaID,
            kind: .aiContext,
            title: "Visa Application",
            isPinned: false,
            isArchived: false,
            sortOrder: 3,
            memberCount: 3,
            memberPreviewSymbols: [
                MockShotKind.document.rawValue,
                MockShotKind.chat.rawValue,
                MockShotKind.receipt.rawValue
            ],
            badgeEmoji: "💼",
            insight: nil
        ),
        ContextCollection(
            id: weekendID,
            kind: .aiContext,
            title: "Weekend Restaurants",
            isPinned: false,
            isArchived: false,
            sortOrder: 4,
            memberCount: 3,
            memberPreviewSymbols: [
                MockShotKind.restaurant.rawValue,
                MockShotKind.receipt.rawValue
            ],
            badgeEmoji: "🍜",
            insight: nil
        )
    ]

    static let coreScreenshots: [ScreenshotMemory] = [
        ScreenshotMemory(
            id: shotA,
            createdAt: Date().addingTimeInterval(-86_400),
            isFavorite: true,
            ocrText: "Park Hyatt Tokyo confirmation",
            summary: "Hotel booking in Tokyo",
            facetKeys: ["hotel", "receipt"],
            entityLabels: ["Tokyo", "Park Hyatt"],
            previewSymbol: "building.2"
        ),
        ScreenshotMemory(
            id: shotB,
            createdAt: Date().addingTimeInterval(-172_800),
            isFavorite: false,
            ocrText: "Qatar Airways boarding pass DOH to NRT",
            summary: "Boarding pass",
            facetKeys: ["flight", "boarding_pass"],
            entityLabels: ["Qatar Airways", "Tokyo"],
            previewSymbol: "airplane"
        ),
        ScreenshotMemory(
            id: shotC,
            createdAt: Date().addingTimeInterval(-200_000),
            isFavorite: false,
            ocrText: "IKEA order pickup",
            summary: "Furniture order",
            facetKeys: ["shopping", "receipt"],
            entityLabels: ["IKEA"],
            previewSymbol: "shippingbox"
        ),
        ScreenshotMemory(
            id: shotD,
            createdAt: Date().addingTimeInterval(-250_000),
            isFavorite: false,
            ocrText: "Visa appointment confirmation",
            summary: "Embassy appointment",
            facetKeys: ["document"],
            entityLabels: ["Embassy"],
            previewSymbol: "globe"
        ),
        ScreenshotMemory(
            id: shotG,
            createdAt: Date().addingTimeInterval(-260_000),
            isFavorite: false,
            ocrText: "Passport scan checklist",
            summary: "Documents needed",
            facetKeys: ["document"],
            entityLabels: ["Passport"],
            previewSymbol: "doc.text"
        ),
        ScreenshotMemory(
            id: shotH,
            createdAt: Date().addingTimeInterval(-270_000),
            isFavorite: false,
            ocrText: "Application fee receipt VFS",
            summary: "Visa fee receipt",
            facetKeys: ["receipt", "document"],
            entityLabels: ["VFS"],
            previewSymbol: "doc.text"
        ),
        ScreenshotMemory(
            id: shotE,
            createdAt: Date().addingTimeInterval(-10_000),
            isFavorite: false,
            ocrText: "Random promo code",
            summary: nil,
            facetKeys: [],
            entityLabels: [],
            previewSymbol: "questionmark.square"
        ),
        ScreenshotMemory(
            id: shotF,
            createdAt: Date().addingTimeInterval(-20_000),
            isFavorite: false,
            ocrText: "Untitled screenshot",
            summary: nil,
            facetKeys: [],
            entityLabels: [],
            previewSymbol: "photo"
        ),
        ScreenshotMemory(
            id: shotI,
            createdAt: Date().addingTimeInterval(-90_000),
            isFavorite: false,
            ocrText: "Tokyo Metro map",
            summary: nil,
            facetKeys: ["map"],
            entityLabels: ["Tokyo"],
            previewSymbol: "map"
        ),
        ScreenshotMemory(
            id: shotJ,
            createdAt: Date().addingTimeInterval(-95_000),
            isFavorite: false,
            ocrText: "Ramen reservation Shibuya",
            summary: nil,
            facetKeys: ["restaurant"],
            entityLabels: ["Shibuya"],
            previewSymbol: "fork.knife"
        ),
        ScreenshotMemory(
            id: shotK,
            createdAt: Date().addingTimeInterval(-100_000),
            isFavorite: false,
            ocrText: nil,
            summary: nil,
            facetKeys: ["photo"],
            entityLabels: [],
            previewSymbol: "photo"
        ),
        ScreenshotMemory(
            id: shotL,
            createdAt: Date().addingTimeInterval(-105_000),
            isFavorite: false,
            ocrText: "Hotel Wi-Fi password",
            summary: nil,
            facetKeys: ["hotel"],
            entityLabels: ["Park Hyatt"],
            previewSymbol: "building.2"
        ),
        // Apartment Setup extras (keep Home promotion ≥ 3 after syncMemberCounts)
        ScreenshotMemory(
            id: shotM,
            createdAt: Date().addingTimeInterval(-210_000),
            isFavorite: false,
            ocrText: "Sofa delivery window",
            summary: nil,
            facetKeys: ["delivery"],
            entityLabels: ["IKEA"],
            previewSymbol: "shippingbox"
        ),
        ScreenshotMemory(
            id: shotN,
            createdAt: Date().addingTimeInterval(-215_000),
            isFavorite: false,
            ocrText: "Lamp order confirmation",
            summary: nil,
            facetKeys: ["shopping"],
            entityLabels: ["Amazon"],
            previewSymbol: "shippingbox"
        ),
        ScreenshotMemory(
            id: shotO,
            createdAt: Date().addingTimeInterval(-220_000),
            isFavorite: false,
            ocrText: "Apartment floor plan",
            summary: nil,
            facetKeys: ["document"],
            entityLabels: [],
            previewSymbol: "doc.text"
        ),
        ScreenshotMemory(
            id: shotP,
            createdAt: Date().addingTimeInterval(-225_000),
            isFavorite: false,
            ocrText: "Kitchen stool listing",
            summary: nil,
            facetKeys: ["shopping"],
            entityLabels: [],
            previewSymbol: "shippingbox"
        ),
        ScreenshotMemory(
            id: shotQ,
            createdAt: Date().addingTimeInterval(-230_000),
            isFavorite: false,
            ocrText: "Curtain measurements",
            summary: nil,
            facetKeys: ["shopping"],
            entityLabels: [],
            previewSymbol: "photo"
        ),
        ScreenshotMemory(
            id: shotR,
            createdAt: Date().addingTimeInterval(-235_000),
            isFavorite: false,
            ocrText: "Moving checklist",
            summary: nil,
            facetKeys: ["document"],
            entityLabels: [],
            previewSymbol: "doc.text"
        ),
        ScreenshotMemory(
            id: shotS,
            createdAt: Date().addingTimeInterval(-240_000),
            isFavorite: false,
            ocrText: "Utility setup confirmation",
            summary: nil,
            facetKeys: ["document"],
            entityLabels: [],
            previewSymbol: "doc.text"
        ),
        // Qatar Airways extras
        ScreenshotMemory(
            id: shotT,
            createdAt: Date().addingTimeInterval(-180_000),
            isFavorite: false,
            ocrText: "Qatar airways e-ticket",
            summary: nil,
            facetKeys: ["flight"],
            entityLabels: ["Qatar Airways"],
            previewSymbol: "airplane"
        ),
        ScreenshotMemory(
            id: shotU,
            createdAt: Date().addingTimeInterval(-185_000),
            isFavorite: false,
            ocrText: "Seat selection 14A",
            summary: nil,
            facetKeys: ["flight"],
            entityLabels: ["Qatar Airways"],
            previewSymbol: "airplane"
        ),
        ScreenshotMemory(
            id: shotV,
            createdAt: Date().addingTimeInterval(-190_000),
            isFavorite: false,
            ocrText: "Baggage allowance",
            summary: nil,
            facetKeys: ["flight"],
            entityLabels: ["Qatar Airways"],
            previewSymbol: "airplane"
        ),
        ScreenshotMemory(
            id: shotW,
            createdAt: Date().addingTimeInterval(-195_000),
            isFavorite: false,
            ocrText: "Lounge invite",
            summary: nil,
            facetKeys: ["flight"],
            entityLabels: ["Qatar Airways"],
            previewSymbol: "building.2"
        ),
        // Weekend restaurants (still below Home threshold unless pinned)
        ScreenshotMemory(
            id: shotX,
            createdAt: Date().addingTimeInterval(-50_000),
            isFavorite: false,
            ocrText: "Omakase waitlist",
            summary: nil,
            facetKeys: ["restaurant"],
            entityLabels: [],
            previewSymbol: "fork.knife"
        ),
        ScreenshotMemory(
            id: shotY,
            createdAt: Date().addingTimeInterval(-55_000),
            isFavorite: false,
            ocrText: "Cafe reservation",
            summary: nil,
            facetKeys: ["restaurant"],
            entityLabels: [],
            previewSymbol: "fork.knife"
        ),
        ScreenshotMemory(
            id: shotZ,
            createdAt: Date().addingTimeInterval(-60_000),
            isFavorite: false,
            ocrText: "Dessert menu",
            summary: nil,
            facetKeys: ["restaurant"],
            entityLabels: [],
            previewSymbol: "fork.knife"
        )
    ]

    /// Extra fixtures for Cleanup galleries (duplicates + old). Built once so IDs stay stable.
    private static let cleanupFixture: (shots: [ScreenshotMemory], groups: [DuplicateGroup]) = {
        var items: [ScreenshotMemory] = []
        let sixMonths: TimeInterval = -180 * 24 * 60 * 60
        let kinds: [(String, String)] = [
            ("airplane", "boarding"),
            ("building.2", "hotel"),
            ("doc.text", "document"),
            ("shippingbox", "delivery"),
            ("fork.knife", "restaurant"),
            ("map", "map"),
            ("photo", "photo"),
            ("globe", "document")
        ]

        var groups: [DuplicateGroup] = []
        let sizes = [3, 4, 3, 3, 3]
        for (groupIndex, size) in sizes.enumerated() {
            let kind = kinds[groupIndex % kinds.count]
            var ids: [ScreenshotMemoryID] = []
            for i in 0..<size {
                let id = ScreenshotMemoryID(FixtureIDs.uuid("duplicate-\(groupIndex)-\(i)"))
                ids.append(id)
                items.append(
                    ScreenshotMemory(
                        id: id,
                        createdAt: Date().addingTimeInterval(-86_400 * Double(groupIndex + i + 1)),
                        isFavorite: false,
                        ocrText: "Duplicate \(groupIndex + 1).\(i + 1)",
                        summary: nil,
                        facetKeys: [kind.1],
                        entityLabels: [],
                        previewSymbol: kind.0
                    )
                )
            }
            groups.append(
                DuplicateGroup(
                    id: FixtureIDs.uuid("duplicate-group-\(groupIndex)"),
                    screenshotIDs: ids,
                    recommendedKeepID: ids.first
                )
            )
        }

        for i in 0..<18 {
            let kind = kinds[i % kinds.count]
            items.append(
                ScreenshotMemory(
                    id: ScreenshotMemoryID(FixtureIDs.uuid("old-\(i)")),
                    createdAt: Date().addingTimeInterval(sixMonths - Double(i) * 86_400 * 3),
                    isFavorite: false,
                    ocrText: "Old screenshot \(i + 1)",
                    summary: nil,
                    facetKeys: [kind.1],
                    entityLabels: [],
                    previewSymbol: kind.0
                )
            )
        }

        return (items, groups)
    }()

    static var cleanupScreenshots: [ScreenshotMemory] { cleanupFixture.shots }
    static var duplicateGroups: [DuplicateGroup] { cleanupFixture.groups }

    static var allScreenshots: [ScreenshotMemory] {
        var core = coreScreenshots
        if let idx = core.firstIndex(where: { $0.id == shotF }) {
            core[idx].createdAt = Date().addingTimeInterval(-200 * 24 * 60 * 60)
        }
        if let idx = core.firstIndex(where: { $0.id == shotC }) {
            core[idx].createdAt = Date().addingTimeInterval(-190 * 24 * 60 * 60)
        }
        var combined = core + cleanupScreenshots
        applySearchEnrichment(&combined)
        return combined
    }

    /// Sprint 2 mock: enrich searchable visual + semantic signals (not shown in UI).
    private static func applySearchEnrichment(_ shots: inout [ScreenshotMemory]) {
        func enrich(
            _ id: ScreenshotMemoryID,
            visual: [String] = [],
            semantic: [String] = []
        ) {
            guard let idx = shots.firstIndex(where: { $0.id == id }) else { return }
            if !visual.isEmpty { shots[idx].visualLabels = visual }
            if !semantic.isEmpty { shots[idx].semanticKeywords = semantic }
        }

        enrich(
            shotA,
            visual: ["hotel", "lobby", "building", "tokyo"],
            semantic: ["travel", "japan", "hotel", "booking"]
        )
        enrich(
            shotB,
            visual: ["boarding pass", "airplane", "ticket"],
            semantic: ["travel", "flight", "qatar", "japan"]
        )
        enrich(
            shotC,
            visual: ["furniture", "box", "delivery"],
            semantic: ["apartment", "shopping", "ikea"]
        )
        enrich(
            shotD,
            visual: ["document", "passport", "form"],
            semantic: ["visa", "embassy", "travel"]
        )
        enrich(
            shotG,
            visual: ["document", "checklist", "passport"],
            semantic: ["visa", "documents"]
        )
        enrich(
            shotH,
            visual: ["receipt", "paper"],
            semantic: ["visa", "fee", "payment", "invoice"]
        )
        if let idx = shots.firstIndex(where: { $0.id == shotH }) {
            shots[idx].ocrText = "Application fee receipt VFS invoice QAR 250"
        }
        enrich(
            shotE,
            visual: ["promo", "code", "ui"],
            semantic: ["unclear"]
        )
        enrich(
            shotF,
            visual: ["photo", "blur"],
            semantic: ["unclear"]
        )
        enrich(
            shotI,
            visual: ["map", "metro", "tokyo"],
            semantic: ["travel", "japan", "tokyo", "transit"]
        )
        enrich(
            shotJ,
            visual: ["restaurant", "ramen", "food"],
            semantic: ["travel", "japan", "restaurant", "food"]
        )
        enrich(
            shotK,
            visual: ["photo", "street", "tokyo"],
            semantic: ["travel", "japan"]
        )
        enrich(
            shotL,
            visual: ["hotel", "wifi", "sign"],
            semantic: ["travel", "japan", "hotel"]
        )
        enrich(
            shotM,
            visual: ["blue sofa", "sofa", "furniture", "living room"],
            semantic: ["apartment", "furniture", "delivery"]
        )
        enrich(
            shotN,
            visual: ["lamp", "box", "package"],
            semantic: ["apartment", "shopping"]
        )
        enrich(
            shotO,
            visual: ["floor plan", "document", "apartment"],
            semantic: ["apartment", "home"]
        )
        enrich(
            shotP,
            visual: ["stool", "furniture", "kitchen"],
            semantic: ["apartment", "shopping"]
        )
        enrich(
            shotQ,
            visual: ["curtain", "window", "fabric"],
            semantic: ["apartment", "shopping"]
        )
        enrich(
            shotR,
            visual: ["checklist", "document"],
            semantic: ["apartment", "moving"]
        )
        enrich(
            shotS,
            visual: ["document", "utility"],
            semantic: ["apartment", "setup"]
        )
        enrich(
            shotT,
            visual: ["ticket", "airplane", "boarding pass"],
            semantic: ["travel", "flight", "qatar"]
        )
        enrich(
            shotU,
            visual: ["seat map", "airplane", "ui"],
            semantic: ["travel", "flight", "qatar"]
        )
        enrich(
            shotV,
            visual: ["baggage", "airplane"],
            semantic: ["travel", "flight", "qatar"]
        )
        enrich(
            shotW,
            visual: ["lounge", "airport", "interior"],
            semantic: ["travel", "flight", "qatar"]
        )
        enrich(
            shotX,
            visual: ["restaurant", "sushi", "food"],
            semantic: ["restaurant", "food", "omakase"]
        )
        enrich(
            shotY,
            visual: ["cafe", "restaurant", "menu"],
            semantic: ["restaurant", "food"]
        )
        enrich(
            shotZ,
            visual: ["dessert", "menu", "food"],
            semantic: ["restaurant", "food"]
        )
    }

    static let memberships: [ContextCollectionID: [ScreenshotMemoryID]] = [
        japanTripID: [shotA, shotB, shotI, shotJ, shotK, shotL],
        apartmentID: [shotC, shotM, shotN, shotO, shotP, shotQ, shotR, shotS],
        qatarID: [shotB, shotT, shotU, shotV, shotW],
        visaID: [shotD, shotG, shotH],
        weekendID: [shotX, shotY, shotZ],
        unassignedID: [shotE, shotF]
    ]
}

private enum FixtureIDs {
    /// Deterministic UUID derivation for local fixtures only (not a user-data ID scheme).
    static func uuid(_ value: String) -> UUID {
        func hash(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
            bytes.reduce(seed) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }
        let bytes = Array(value.utf8)
        let high = hash(bytes, seed: 14_695_981_039_346_656_037)
        let low = hash(Array(bytes.reversed()), seed: 1_099_511_628_211)
        return UUID(uuid: (
            UInt8(truncatingIfNeeded: high >> 56),
            UInt8(truncatingIfNeeded: high >> 48),
            UInt8(truncatingIfNeeded: high >> 40),
            UInt8(truncatingIfNeeded: high >> 32),
            UInt8(truncatingIfNeeded: high >> 24),
            UInt8(truncatingIfNeeded: high >> 16),
            UInt8(truncatingIfNeeded: high >> 8),
            UInt8(truncatingIfNeeded: high),
            UInt8(truncatingIfNeeded: low >> 56),
            UInt8(truncatingIfNeeded: low >> 48),
            UInt8(truncatingIfNeeded: low >> 40),
            UInt8(truncatingIfNeeded: low >> 32),
            UInt8(truncatingIfNeeded: low >> 24),
            UInt8(truncatingIfNeeded: low >> 16),
            UInt8(truncatingIfNeeded: low >> 8),
            UInt8(truncatingIfNeeded: low)
        ))
    }
}
