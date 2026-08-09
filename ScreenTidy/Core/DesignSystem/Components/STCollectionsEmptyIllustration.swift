import SwiftUI

/// Soft Quiet Pocket illustration for the Home Collections empty state —
/// a small fan of empty folders so the section never feels blank.
struct STCollectionsEmptyIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    var body: some View {
        ZStack {
            emptyFolder(
                width: 118,
                opacity: 0.55,
                rotation: -14,
                x: -52,
                y: 10,
                z: 0
            )
            emptyFolder(
                width: 118,
                opacity: 0.55,
                rotation: 14,
                x: 52,
                y: 10,
                z: 1
            )
            emptyFolder(
                width: 136,
                opacity: 1,
                rotation: -2,
                x: 0,
                y: 0,
                z: 2,
                showsPlus: true
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

    private func emptyFolder(
        width: CGFloat,
        opacity: Double,
        rotation: Double,
        x: CGFloat,
        y: CGFloat,
        z: Double,
        showsPlus: Bool = false
    ) -> some View {
        let layout = FolderLayout(width: width)

        return ZStack(alignment: .top) {
            FolderBackShape(layout: layout)
                .fill(FolderEmptyChrome.back)
                .frame(width: layout.width, height: layout.totalHeight)

            // Soft ghost peeks — hint that Collections hold screenshots.
            if showsPlus {
                HStack(spacing: width * 0.06) {
                    ghostPeek(tint: Color(red: 0.86, green: 0.90, blue: 0.95))
                    ghostPeek(tint: Color(red: 0.90, green: 0.92, blue: 0.94))
                    ghostPeek(tint: Color(red: 0.88, green: 0.91, blue: 0.96))
                }
                .frame(width: layout.peekStageWidth)
                .padding(.top, layout.mouthTop + 4)
                .opacity(0.9)
            }

            RoundedRectangle(cornerRadius: layout.frontRadius, style: .continuous)
                .fill(FolderEmptyChrome.front)
                .overlay {
                    if showsPlus {
                        Image(systemName: "plus")
                            .font(.system(size: layout.iconFontSize * 1.2, weight: .medium))
                            .foregroundStyle(STColor.primary.opacity(0.85))
                    }
                }
                .frame(width: layout.width, height: layout.frontHeight)
                .padding(.top, layout.frontTop)
        }
        .background {
            FolderBackShape(layout: layout)
                .fill(Color.black.opacity(0.001))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 5)
                .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
        .frame(width: layout.width, height: layout.totalHeight)
        .opacity(opacity)
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .offset(x: x, y: y)
        .zIndex(z)
    }

    private func ghostPeek(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tint)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .aspectRatio(0.62, contentMode: .fit)
            .frame(height: 46)
            .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
    }
}

private enum FolderEmptyChrome {
    static let back = Color(red: 0.93, green: 0.933, blue: 0.94)
    static let front = Color.white
}

#Preview("Collections empty illustration") {
    VStack(spacing: STSpacing.lg) {
        STCollectionsEmptyIllustration()
        Text("No Collections yet")
            .font(STTypography.rowTitle)
        Text("Create a collection to start organizing screenshots.")
            .font(STTypography.rowMeta)
            .foregroundStyle(STColor.secondaryLabel)
            .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(STColor.background)
}
