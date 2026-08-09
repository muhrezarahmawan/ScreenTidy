import SwiftUI

/// WhatsApp-style soft backgrounds for collection emoji badges.
enum STCollectionBadgePalette {
    struct Swatch: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let hex: String

        var color: Color { Color(stHex: hex) }
    }

    static let swatches: [Swatch] = [
        Swatch(id: "yellow", name: "Yellow", hex: "#F4E6A8"),
        Swatch(id: "orange", name: "Orange", hex: "#F0C49A"),
        Swatch(id: "pink", name: "Pink", hex: "#F0C4C8"),
        Swatch(id: "gray", name: "Gray", hex: "#E4E4E4"),
        Swatch(id: "blue", name: "Blue", hex: "#C5D4EE"),
        Swatch(id: "teal", name: "Teal", hex: "#B5DED4"),
        Swatch(id: "salmon", name: "Salmon", hex: "#EBB8B0"),
        Swatch(id: "beige", name: "Beige", hex: "#E8D9C8"),
    ]

    static let `default` = swatches[7] // Beige

    static func swatch(forHex hex: String?) -> Swatch {
        guard let hex, let match = swatches.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }) else {
            return `default`
        }
        return match
    }

    static func color(forHex hex: String?) -> Color {
        swatch(forHex: hex).color
    }
}

extension Color {
    /// Parses `#RRGGBB` or `RRGGBB` hex into a Color (falls back to secondary background).
    init(stHex: String) {
        var cleaned = stHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = STColor.backgroundSecondary
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

enum STCollectionEmojiValidator {
    /// True when the string is one or more emoji grapheme clusters (no letters/digits/punctuation).
    static func isEmojiOnly(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var sawEmoji = false
        for character in trimmed {
            let scalars = character.unicodeScalars
            let isEmojiChar = scalars.contains {
                $0.properties.isEmoji
                    || $0.properties.isEmojiModifier
                    || $0.properties.isEmojiModifierBase
                    || $0.properties.isJoinControl
                    || $0.properties.isVariationSelector
                    || $0 == "\u{200D}"
                    || $0 == "\u{FE0F}"
            }
            let isLetterOrNumber = scalars.contains {
                $0.properties.generalCategory.isLetter
                    || $0.properties.generalCategory.isNumber
            }
            if isLetterOrNumber { return false }
            if !isEmojiChar {
                // Allow skin-tone / ZWJ sequences already covered; reject plain ASCII.
                if scalars.allSatisfy({ $0.isASCII }) { return false }
            }
            if scalars.contains(where: { $0.properties.isEmoji || $0.properties.isEmojiPresentation }) {
                sawEmoji = true
            }
        }
        return sawEmoji
    }

    /// Keeps the last emoji grapheme cluster from a valid emoji-only string.
    static func normalizedSingleEmoji(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "" }
        return String(last)
    }
}

private extension Unicode.GeneralCategory {
    var isLetter: Bool {
        switch self {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            true
        default:
            false
        }
    }

    var isNumber: Bool {
        switch self {
        case .decimalNumber, .letterNumber, .otherNumber:
            true
        default:
            false
        }
    }
}
