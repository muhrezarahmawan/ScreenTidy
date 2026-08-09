import SwiftUI

/// Home greeting + rotating approved subtitle (`STHomeCopy`).
struct STGreetingHeader: View {
    let greeting: String
    var organizingMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: STSpacing.sm) {
            Text("\(greeting) 👋")
                .font(STTypography.greeting)
                .foregroundStyle(STColor.label)
                .accessibilityAddTraits(.isHeader)

            if let organizingMessage {
                Text(organizingMessage)
                    .font(STTypography.aiLine)
                    .foregroundStyle(STColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(organizingMessage)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .animation(
            reduceMotion ? .easeInOut(duration: STMotion.quickDuration) : .easeInOut(duration: STMotion.standardDuration),
            value: organizingMessage
        )
    }
}

/// Simple section title for lists / secondary screens.
struct STSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: STSpacing.xs) {
            Text(title)
                .font(STTypography.sectionTitle)
                .foregroundStyle(STColor.label)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Home Collections row: section title + compact “+ New” (not a CTA button).
/// Hide `showsNew` in the empty state — the empty CTA covers create.
struct STCollectionsSectionHeader: View {
    var showsNew: Bool = true
    let onNew: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: STSpacing.md) {
            Text("Collections")
                .font(STTypography.sectionTitle)
                .foregroundStyle(STColor.label)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: STSpacing.sm)

            if showsNew {
                Button(action: onNew) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                        Text("New")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(STColor.primary)
                    .padding(.horizontal, STSpacing.xs)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Collection")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Compatibility aliases used during Home craft.
typealias HomeHeader = STGreetingHeader

#Preview("Headers") {
    VStack(alignment: .leading, spacing: 24) {
        STGreetingHeader(
            greeting: "Good morning",
            organizingMessage: STHomeCopy.subtitles[0]
        )
        STNeedsReviewCard(count: 2, previews: Array(MockData.coreScreenshots.suffix(2)))
        STCollectionsSectionHeader(onNew: {})
        STSectionHeader(title: "Suggestions", subtitle: "You stay in control.")
    }
    .padding(STSpacing.page)
    .background(STColor.background)
}
