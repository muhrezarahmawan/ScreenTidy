import Foundation

/// Builds safe FTS5 `MATCH` expressions from arbitrary user input (Sprint 6).
/// Never pass raw query strings to SQLite FTS.
enum SearchFTSQuery {
    static let maxTokens = 12

    /// Unicode letter/number tokens after OCR-aligned normalization.
    static func tokens(from raw: String) -> [String] {
        let normalized = OCRPipeline.normalizedForSearch(raw)
        guard !normalized.isEmpty else { return [] }
        var tokens: [String] = []
        tokens.reserveCapacity(8)
        var current = ""
        for scalar in normalized.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
                if tokens.count >= maxTokens { return tokens }
            }
        }
        if !current.isEmpty, tokens.count < maxTokens {
            tokens.append(current)
        }
        return tokens
    }

    /// FTS5 MATCH expression, or `nil` when the query has no searchable tokens.
    static func matchExpression(from raw: String) -> String? {
        let tokens = tokens(from: raw)
        guard !tokens.isEmpty else { return nil }
        return tokens.map(quotedToken(_:)).joined(separator: " AND ")
    }

    /// Double-quote token; double internal quotes. Prefix `*` for tokens with length ≥ 2.
    private static func quotedToken(_ token: String) -> String {
        let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
        if token.count >= 2 {
            return "\"\(escaped)\"*"
        }
        return "\"\(escaped)\""
    }
}
