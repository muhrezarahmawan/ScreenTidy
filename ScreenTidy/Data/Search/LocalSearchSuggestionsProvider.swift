import Foundation

/// Zero-query shortcuts from live Collections (Sprint 6). Falls back to static chips when empty.
struct LocalSearchSuggestionsProvider: SearchSuggestionsProviding {
    private let memory: any MemoryReading

    init(memory: any MemoryReading) {
        self.memory = memory
    }

    func suggestions() async -> [SearchSuggestion] {
        let contexts = (try? await memory.fetchPromotedContexts()) ?? []
        let fromCollections = contexts
            .filter { $0.kind != .unassigned && !$0.isArchived }
            .prefix(8)
            .map {
                SearchSuggestion(
                    id: "collection-\($0.id.rawValue.uuidString)",
                    title: $0.title
                )
            }
        if !fromCollections.isEmpty {
            return Array(fromCollections)
        }
        return MockSearchSuggestionsProvider.sprint2Mocks
    }
}
