import SwiftUI

/// Circular emoji chip — AI context hint only (no text).
struct STEmojiBadge: View {
    let emoji: String
    var size: CGFloat = 28
    var backgroundHex: String? = nil

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.46))
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(backgroundHex.map { STCollectionBadgePalette.color(forHex: $0) } ?? Color.white)
                    .stBadgeShadow()
            }
            .accessibilityHidden(true)
    }
}

#Preview("Emoji Badge") {
    HStack(spacing: 12) {
        STEmojiBadge(emoji: "✈️")
        STEmojiBadge(emoji: "🏠")
        STEmojiBadge(emoji: "💼")
        STEmojiBadge(emoji: "💬")
    }
    .padding()
    .background(STColor.background)
}
