import SwiftUI

/// Explicit choice before first cloud / improved automatic organization pass.
struct CloudUnderstandingDisclosureSheet: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: STSpacing.lg) {
                Text("Improve automatic organization")
                    .font(STTypography.greeting)
                    .foregroundStyle(STColor.label)

                Text(
                    "To better understand screenshots, ScreenTidy can send a small preview and extracted text to ScreenTidy’s secure AI service for ephemeral processing."
                )
                .font(STTypography.rowTitle)
                .foregroundStyle(STColor.label)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: STSpacing.sm) {
                    bullet("Your original screenshots stay in Photos.")
                    bullet("Only a small preview and extracted text may leave this device.")
                    bullet("ScreenTidy does not keep a cloud photo library.")
                    bullet("Retention follows the deployed AI account configuration — ask before assuming Zero Data Retention.")
                    bullet("You can keep using ScreenTidy if you decline; automatic filing may be limited.")
                }

                Spacer(minLength: STSpacing.lg)

                STPrimaryButton(title: "Continue") {
                    onAccept()
                }

                Button("Not Now") {
                    onDecline()
                }
                .font(STTypography.button)
                .foregroundStyle(STColor.secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.bottom, STSpacing.md)
            }
            .padding(STSpacing.page)
            .background(STColor.background.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: STSpacing.sm) {
            Text("•")
                .foregroundStyle(STColor.secondaryLabel)
            Text(text)
                .font(STTypography.rowMeta)
                .foregroundStyle(STColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
