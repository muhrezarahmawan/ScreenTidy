import SwiftUI

struct AppTheme: Equatable {
    var background: Color = STColor.pageBackground
    var backgroundSecondary: Color = STColor.backgroundSecondary
    var pocket: Color = STColor.surfaceElevated
    var label: Color = STColor.textPrimary
    var secondaryLabel: Color = STColor.textSecondary
    var accent: Color = STColor.primary
    var pagePadding: CGFloat = STSpacing.page
    var contextCardRadius: CGFloat = STRadius.pocket

    static let `default` = AppTheme()
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.default
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension View {
    /// Applies Quiet Pocket theme tokens and **locks Light Mode for MVP**.
    /// Dark Mode is not designed yet — forcing light prevents hybrid white-on-white text
    /// when the device is in Dark Mode while surfaces stay light.
    func appTheme(_ theme: AppTheme) -> some View {
        environment(\.appTheme, theme)
            .preferredColorScheme(.light)
            .tint(theme.accent)
    }
}
