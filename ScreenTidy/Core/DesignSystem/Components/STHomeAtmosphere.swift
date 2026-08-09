import SwiftUI

/// Soft frosted-glass blue atmosphere for the Home hero only.
///
/// Layered, heavily blurred ellipses + a white fade mask. Scrolls with the
/// greeting / search / Needs Review region so the collection grid stays clean white.
/// Does not alter Quiet Pocket cards or other Home chrome.
struct STHomeAtmosphere: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            // MVP is Light Mode–locked; always use light Quiet Pocket wash intensities.
            let primaryOpacity = STHomeAtmosphereTokens.primaryOpacityLight
            let secondaryOpacity = STHomeAtmosphereTokens.secondaryOpacityLight
            let blurScale: CGFloat = reduceTransparency ? 0.45 : 1

            ZStack(alignment: .top) {
                // Layer 1 — large soft cool-blue glow, upper-center.
                Ellipse()
                    .fill(STColor.homeAtmosphereBlue.opacity(primaryOpacity))
                    .frame(width: width * 1.55, height: height * 0.92)
                    .blur(radius: STHomeAtmosphereTokens.primaryBlur * blurScale)
                    .offset(y: -height * 0.28)

                // Layer 2 — quieter secondary glow, offset to avoid symmetry.
                Ellipse()
                    .fill(STColor.homeAtmosphereBlueSecondary.opacity(secondaryOpacity))
                    .frame(width: width * 1.05, height: height * 0.62)
                    .blur(radius: STHomeAtmosphereTokens.secondaryBlur * blurScale)
                    .offset(x: width * 0.22, y: -height * 0.08)

                // Layer 3 — faint cooler wash near the leading edge (very soft).
                Ellipse()
                    .fill(STColor.homeAtmosphereBlue.opacity(secondaryOpacity * 0.55))
                    .frame(width: width * 0.85, height: height * 0.48)
                    .blur(radius: STHomeAtmosphereTokens.secondaryBlur * blurScale)
                    .offset(x: -width * 0.28, y: height * 0.02)
            }
            .frame(width: width, height: height, alignment: .top)
            // Soft white dissolve — no hard band; nearly white by collection grid.
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.00),
                        .init(color: .black, location: 0.28),
                        .init(color: .black.opacity(0.55), location: 0.52),
                        .init(color: .black.opacity(0.18), location: 0.72),
                        .init(color: .clear, location: 0.92),
                        .init(color: .clear, location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // Extra bottom veil so the mask edge never reads as a line.
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        STColor.background.opacity(0),
                        STColor.background.opacity(0.55),
                        STColor.background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height * 0.42)
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Hero wash that grows upward into rubber-band / pull-to-refresh overscroll so the
/// greeting and the bounce region stay one continuous color (no hard seam).
struct STStretchyHomeAtmosphere: View {
    var coordinateSpaceName: String

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named(coordinateSpaceName)).minY
            // When content is pulled down, minY > 0 — extend the wash into that spill.
            let spill = max(0, minY)
            let baseHeight = STHomeAtmosphereTokens.height + STHomeAtmosphereTokens.topBleed

            STHomeAtmosphere()
                .frame(width: geo.size.width, height: baseHeight + spill)
                .offset(y: -STHomeAtmosphereTokens.topBleed - spill)
        }
        .frame(height: STHomeAtmosphereTokens.height)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Home atmosphere") {
    ScrollView {
        ZStack(alignment: .top) {
            STHomeAtmosphere()
                .frame(height: STHomeAtmosphereTokens.height)
                .padding(.top, -STHomeAtmosphereTokens.topBleed)

            VStack(alignment: .leading, spacing: STSpacing.homeSection) {
                STGreetingHeader(
                    greeting: "Good afternoon",
                    organizingMessage: STHomeCopy.subtitles[0]
                )
                STNeedsReviewCard(count: 2, previews: Array(MockData.coreScreenshots.suffix(2)))
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: STSpacing.collectionGridGutter),
                        GridItem(.flexible(), spacing: STSpacing.collectionGridGutter)
                    ],
                    spacing: STSpacing.collectionGridRow
                ) {
                    ForEach(MockData.contexts.filter { $0.kind != .unassigned }.prefix(4)) { context in
                        ContextCollectionPocketView(collection: context)
                    }
                }
            }
            .padding(.horizontal, STSpacing.page)
            .padding(.top, STSpacing.lg)
        }
    }
    .background(STColor.background.ignoresSafeArea())
}
