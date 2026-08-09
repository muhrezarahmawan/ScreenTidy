import Foundation

/// Organization-only OCR cleanup. Does **not** mutate Search FTS / raw `ocr_text`.
enum OrganizationOCRNormalizer {
    static func normalize(_ raw: String?) -> String {
        guard let raw else { return "" }
        var lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        lines = lines.filter { !isLikelyStatusChrome($0) }

        let joined = lines.joined(separator: "\n")
        let collapsed = joined
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Bound payload size for gateway cost/latency.
        if collapsed.count > 4_000 {
            return String(collapsed.prefix(4_000))
        }
        return collapsed
    }

    static func preview(_ raw: String?, limit: Int = 160) -> String? {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return nil }
        if normalized.count <= limit { return normalized }
        return String(normalized.prefix(limit)) + "…"
    }

    private static func isLikelyStatusChrome(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 2 { return true }

        // Clock-like: 9:41, 18:29
        if trimmed.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil {
            return true
        }
        // Battery percent alone
        if trimmed.range(of: #"^\d{1,3}%$"#, options: .regularExpression) != nil {
            return true
        }
        let lower = trimmed.lowercased()
        let chromeTokens: Set<String> = [
            "lte", "5g", "4g", "wifi", "wi-fi", "vpn", "ssd", "sos",
            "carrier", "no service", "searching…"
        ]
        if chromeTokens.contains(lower) { return true }
        // Very short all-caps status crumbs
        if trimmed.count <= 4, trimmed.uppercased() == trimmed, trimmed.rangeOfCharacter(from: .letters) != nil {
            return true
        }
        return false
    }
}
