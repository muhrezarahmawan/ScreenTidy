import SwiftUI

/// User-facing copy for the internal `unassigned` review inbox.
enum STNeedsReviewCopy {
    static let title = "Needs Review"

    static func headline(count: Int) -> String {
        if count == 1 {
            return "1 screenshot needs your help"
        }
        return "\(count) screenshots need your help"
    }

    static func subtitle(count: Int) -> String {
        if count == 1 {
            return "Review where this screenshot belongs"
        }
        return "Review where these screenshots belong"
    }

    /// Maps domain titles for UI. Keeps model `kind == .unassigned`.
    static func displayTitle(for context: ContextCollection) -> String {
        context.kind == .unassigned ? title : context.title
    }

    static func displayTitle(kind: ContextCollectionKind, storedTitle: String) -> String {
        kind == .unassigned ? title : storedTitle
    }
}

/// Compact Home Needs Review entry — entire card tappable via parent NavigationLink.
/// Locked: peeks + human copy only (no sparkles, no oversized Review CTA).
struct STNeedsReviewCard: View {
    let count: Int
    var previews: [ScreenshotMemory] = []

    private var peekMemories: [ScreenshotMemory] {
        Array(previews.prefix(3))
    }

    var body: some View {
        HStack(alignment: .center, spacing: STSpacing.md) {
            if !peekMemories.isEmpty {
                overlappingPeeks
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(STNeedsReviewCopy.headline(count: count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(STColor.label)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(STNeedsReviewCopy.subtitle(count: count))
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, STSpacing.md)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: STRadius.searchField, style: .continuous)
                .fill(STColor.pocket)
        )
        .overlay(
            RoundedRectangle(cornerRadius: STRadius.searchField, style: .continuous)
                .strokeBorder(STColor.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: STRadius.searchField, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(STNeedsReviewCopy.title). \(STNeedsReviewCopy.headline(count: count)). \(STNeedsReviewCopy.subtitle(count: count))"
        )
        .accessibilityHint("Opens Needs Review")
        .accessibilityAddTraits(.isButton)
    }

    private var overlappingPeeks: some View {
        let size = CGSize(width: 28, height: 36)
        let step: CGFloat = 12
        return ZStack(alignment: .leading) {
            ForEach(Array(peekMemories.enumerated()), id: \.element.id) { index, memory in
                ScreenshotPreview(
                    kind: MockShotKindResolver.kind(for: memory),
                    seed: memory.id.rawValue.hashValue,
                    showsDeviceChrome: false
                )
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 1.25)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 1.5, y: 0.5)
                .rotationEffect(.degrees(peekRotation(index)))
                .offset(x: CGFloat(index) * step, y: peekY(index))
                .zIndex(Double(index))
            }
        }
        .frame(
            width: size.width + CGFloat(max(peekMemories.count - 1, 0)) * step,
            height: size.height + 2,
            alignment: .leading
        )
        .accessibilityHidden(true)
    }

    private func peekRotation(_ index: Int) -> Double {
        switch index {
        case 0: return -5
        case 1: return 2
        default: return -1
        }
    }

    private func peekY(_ index: Int) -> CGFloat {
        switch index {
        case 0: return 1
        case 1: return 0
        default: return 0.5
        }
    }
}

/// Compatibility alias. Prefer `STNeedsReviewCard`.
typealias STUnassignedRow = STNeedsReviewCard
typealias UnassignedRow = STNeedsReviewCard
