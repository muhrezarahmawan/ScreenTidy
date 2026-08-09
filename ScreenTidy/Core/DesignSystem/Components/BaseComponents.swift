import SwiftUI

/// Page chrome — Quiet Pocket canvas + standard horizontal padding.
struct STPage<Content: View>: View {
    @Environment(\.appTheme) private var theme
    var includeTabClearance: Bool = false
    private let content: Content

    init(includeTabClearance: Bool = false, @ViewBuilder content: () -> Content) {
        self.includeTabClearance = includeTabClearance
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, theme.pagePadding)
            .padding(.bottom, includeTabClearance ? STSpacing.tabBarClearance : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.background.ignoresSafeArea())
    }
}

/// Alias — PageContainer naming for docs / future screens.
typealias STPageContainer = STPage

struct STPrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(STTypography.button)
                .frame(maxWidth: .infinity)
                .padding(.vertical, STSpacing.md)
        }
        .buttonStyle(.borderedProminent)
        .tint(STColor.primary)
        .disabled(!isEnabled)
    }
}

struct STSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.body.weight(.medium))
            .foregroundStyle(STColor.label)
    }
}

struct STSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search your screenshots"
    var isFocused: FocusState<Bool>.Binding?
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: STSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(STColor.secondaryLabel)
                .accessibilityHidden(true)

            textField

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(STColor.tertiaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, STSpacing.lg)
        .padding(.vertical, 14)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: STRadius.searchField, style: .continuous)
                .fill(STColor.pocket)
                .stSearchFieldShadow()
        )
        .overlay(
            RoundedRectangle(cornerRadius: STRadius.searchField, style: .continuous)
                .strokeBorder(STColor.searchFieldStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placeholder)
        .accessibilityAddTraits(.isSearchField)
    }

    @ViewBuilder
    private var textField: some View {
        let field = TextField(placeholder, text: $text)
            .font(STTypography.search)
            .foregroundStyle(STColor.label)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit { onSubmit?() }

        if let isFocused {
            field.focused(isFocused)
        } else {
            field
        }
    }
}


struct STEmptyState: View {
    let title: String
    let message: String
    var systemImage: String = "sparkles"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: STSpacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(STColor.secondaryLabel)
                .accessibilityHidden(true)

            VStack(spacing: STSpacing.sm) {
                Text(title)
                    .font(STTypography.emptyTitle)
                    .foregroundStyle(STColor.label)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(STTypography.emptyMessage)
                    .foregroundStyle(STColor.secondaryLabel)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                STPrimaryButton(title: actionTitle, action: action)
                    .padding(.top, STSpacing.sm)
            }
        }
        .padding(STSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Soft primary surface for non-pocket content (cleanup rows, settings cards).
struct STPrimaryCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(STSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(STColor.pocket)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.pocket, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: STRadius.pocket, style: .continuous)
                    .strokeBorder(STColor.hairline, lineWidth: 0.5)
            }
            .stCardShadow()
    }
}

typealias STCard = STPrimaryCard
