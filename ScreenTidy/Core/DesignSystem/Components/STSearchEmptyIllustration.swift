import SwiftUI

/// Soft Quiet Pocket illustration for Search’s no-results state —
/// same fan footprint + spacing as `STCollectionsEmptyIllustration`.
struct STSearchEmptyIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    var body: some View {
        ZStack {
            emptyShot(
                width: 118,
                opacity: 0.55,
                rotation: -14,
                x: -52,
                y: 10,
                z: 0,
                showsGlyph: false
            )
            emptyShot(
                width: 118,
                opacity: 0.55,
                rotation: 14,
                x: 52,
                y: 10,
                z: 1,
                showsGlyph: false
            )
            emptyShot(
                width: 136,
                opacity: 1,
                rotation: -2,
                x: 0,
                y: 0,
                z: 2,
                showsGlyph: true
            )
        }
        .frame(width: 220, height: 148)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94)
        .offset(y: appeared ? 0 : 8)
        .accessibilityHidden(true)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                    appeared = true
                }
            }
        }
    }

    private func emptyShot(
        width: CGFloat,
        opacity: Double,
        rotation: Double,
        x: CGFloat,
        y: CGFloat,
        z: Double,
        showsGlyph: Bool
    ) -> some View {
        // Match Collection empty folders’ overall footprint so text spacing reads the same.
        let layout = FolderLayout(width: width)
        let height = layout.totalHeight
        let corner = layout.frontRadius

        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(SearchEmptyChrome.back)
                .frame(width: width, height: height)

            RoundedRectangle(cornerRadius: corner * 0.92, style: .continuous)
                .fill(SearchEmptyChrome.front)
                .frame(width: width, height: layout.frontHeight)
                .overlay {
                    if showsGlyph {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: layout.iconFontSize * 1.35, weight: .medium))
                            .foregroundStyle(STColor.primary.opacity(0.85))
                    } else {
                        ghostContent(width: width, height: layout.frontHeight)
                    }
                }
                .padding(.top, layout.frontTop)
        }
        .background {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.black.opacity(0.001))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 5)
                .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
        .frame(width: width, height: height)
        .opacity(opacity)
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .offset(x: x, y: y)
        .zIndex(z)
    }

    private func ghostContent(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: width * 0.045) {
            RoundedRectangle(cornerRadius: width * 0.06, style: .continuous)
                .fill(Color(red: 0.88, green: 0.91, blue: 0.96))
                .frame(height: height * 0.36)

            Capsule()
                .fill(Color(red: 0.90, green: 0.92, blue: 0.94))
                .frame(width: width * 0.42, height: 6)
            Capsule()
                .fill(Color(red: 0.86, green: 0.90, blue: 0.95))
                .frame(width: width * 0.30, height: 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, width * 0.12)
        .padding(.top, width * 0.1)
        .opacity(0.95)
    }
}

private enum SearchEmptyChrome {
    static let back = Color(red: 0.93, green: 0.933, blue: 0.94)
    static let front = Color.white
}

#Preview("Search empty illustration") {
    VStack(spacing: STSpacing.lg) {
        STSearchEmptyIllustration()
        Text("No screenshots found")
            .font(STTypography.emptyTitle)
        Text("Try another word or description.")
            .font(STTypography.emptyMessage)
            .foregroundStyle(STColor.secondaryLabel)
            .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(STColor.background)
}
