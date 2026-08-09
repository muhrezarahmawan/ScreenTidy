import Foundation

/// Sprint 2 static prompts — later swap for library-derived / recent terms.
struct MockSearchSuggestionsProvider: SearchSuggestionsProviding {
    func suggestions() async -> [SearchSuggestion] {
        Self.sprint2Mocks
    }

    static let sprint2Mocks: [SearchSuggestion] = [
        SearchSuggestion(id: "boarding-pass", title: "Boarding pass"),
        SearchSuggestion(id: "blue-sofa", title: "Blue sofa"),
        SearchSuggestion(id: "tokyo", title: "Tokyo"),
        SearchSuggestion(id: "receipt", title: "Receipt"),
        SearchSuggestion(id: "qatar-airways", title: "Qatar Airways"),
        SearchSuggestion(id: "restaurant", title: "Restaurant"),
        SearchSuggestion(id: "ikea", title: "IKEA"),
        SearchSuggestion(id: "visa", title: "Visa")
    ]
}
