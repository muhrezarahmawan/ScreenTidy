import SwiftUI

/// Soft frosted-glass blue atmosphere for onboarding steps.
///
/// Related to `STHomeAtmosphere` but intentionally different:
/// - Full-screen fixed wash (not scroll-hero clipped)
/// - Deeper cool primary + sky secondary
/// - Glow bias toward top-leading (Home biases trailing)
/// - Softer mid-screen presence so pocket previews sit in atmosphere
struct STOnboardingAtmosphere: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            // MVP is Light Mode–locked; always use light Quiet Pocket wash intensities.
            let primaryOpacity = STOnboardingAtmosphereTokens.primaryOpacityLight
            let secondaryOpacity = STOnboardingAtmosphereTokens.secondaryOpacityLight
            let accentOpacity = STOnboardingAtmosphereTokens.accentOpacityLight
            let blurScale: CGFloat = reduceTransparency ? 0.45 : 1

            ZStack(alignment: .top) {
                // Layer 1 — large cool wash centered slightly high (taller than Home).
                Ellipse()
                    .fill(STColor.onboardingAtmosphereBlue.opacity(primaryOpacity))
                    .frame(width: width * 1.65, height: height * 0.78)
                    .blur(radius: STOnboardingAtmosphereTokens.primaryBlur * blurScale)
                    .offset(y: -height * 0.18)

                // Layer 2 — sky secondary, leading bias (Home uses trailing).
                Ellipse()
                    .fill(STColor.onboardingAtmosphereBlueSecondary.opacity(secondaryOpacity))
                    .frame(width: width * 1.15, height: height * 0.55)
                    .blur(radius: STOnboardingAtmosphereTokens.secondaryBlur * blurScale)
                    .offset(x: -width * 0.24, y: height * 0.02)

                // Layer 3 — quiet mid glow so pocket previews aren’t on flat white.
                Ellipse()
                    .fill(STColor.onboardingAtmosphereBlue.opacity(accentOpacity))
                    .frame(width: width * 1.2, height: height * 0.42)
                    .blur(radius: STOnboardingAtmosphereTokens.accentBlur * blurScale)
                    .offset(x: width * 0.12, y: height * 0.28)
            }
            .frame(width: width, height: height, alignment: .top)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.00),
                        .init(color: .black, location: 0.22),
                        .init(color: .black.opacity(0.72), location: 0.48),
                        .init(color: .black.opacity(0.32), location: 0.68),
                        .init(color: .black.opacity(0.08), location: 0.84),
                        .init(color: .clear, location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        STColor.background.opacity(0),
                        STColor.background.opacity(0.45),
                        STColor.background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height * 0.36)
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Onboarding atmosphere") {
    ZStack {
        STColor.background.ignoresSafeArea()
        STOnboardingAtmosphere()
            .ignoresSafeArea()
        VStack(alignment: .leading, spacing: STSpacing.homeSection) {
            Text("SCREENTIDY")
                .font(STTypography.caption)
                .foregroundStyle(STColor.secondaryLabel)
            Text("Your screenshots,\nquietly organized.")
                .font(STTypography.greeting)
            Spacer()
        }
        .padding(STSpacing.page)
        .padding(.top, STSpacing.xxl)
    }
}
