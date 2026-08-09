import SwiftUI

// MARK: - Spacing

enum STSpacing {
    /// Page horizontal padding — locked at 24pt.
    static let page: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xl: CGFloat = 24
    static let lg: CGFloat = 16
    static let md: CGFloat = 12
    static let sm: CGFloat = 8
    static let xs: CGFloat = 4

    /// Home vertical rhythm between major blocks.
    static let homeSection: CGFloat = 28
    /// Approximate system tab bar height above the home indicator (toast overlay math only).
    /// Scroll content relies on native `TabView` safe-area insets — do not pad this again on tab roots.
    static let tabBarHeight: CGFloat = 49
    /// Comfortable gap between toast bottom and the top of the system tab bar.
    static let toastTabBarGap: CGFloat = 12
    /// Optional breathing room above the system tab inset when a screen opts into `STPage` clearance.
    static let tabBarClearance: CGFloat = lg
    /// Content-hugging toast max width — never edge-to-edge.
    static let toastMaxWidth: CGFloat = 320
    /// Slightly wider when a trailing action (e.g. Undo) is present.
    static let toastActionMaxWidth: CGFloat = 360

    /// Settings — Apple-like section rhythm.
    static let settingsSectionGap: CGFloat = 22
    static let settingsLabelToCard: CGFloat = 8
    static let settingsCardToFooter: CGFloat = 8
    static let settingsRowVertical: CGFloat = 12
    static let settingsToggleVertical: CGFloat = 14
    static let settingsTitleToBody: CGFloat = 4

    /// Two-column collection grid — balanced breathing room between folder cells.
    static let collectionGridGutter: CGFloat = 20
    /// Row gap — enough for peeks + soft shadow without feeling sparse.
    static let collectionGridRow: CGFloat = 34
    /// Context Detail photo-gallery gutters (tight photo-grid rhythm).
    static let galleryGridGutter: CGFloat = 6

    /// Pocket internal padding (locked).
    static let pocketLeading: CGFloat = 18
    static let pocketBottom: CGFloat = 20
    static let pocketTop: CGFloat = 12
    static let pocketEmojiLeading: CGFloat = 14
    static let pocketTitleMeta: CGFloat = 4
}

// MARK: - Radius

enum STRadius {
    /// Soft folder corners — Quiet Pocket language.
    static let pocket: CGFloat = 26
    /// Alias for pocket.
    static let contextCard: CGFloat = pocket
    static let screenshotPeek: CGFloat = 12
    static let screenshotTile: CGFloat = 14
    /// Context Detail gallery cells — photo-gallery corners (kept modest vs pocket cards).
    static let galleryTile: CGFloat = 8
    static let searchField: CGFloat = 14
    static let button: CGFloat = 14
    /// Settings grouped lists — tighter than pocket so single rows aren’t capsule-tall.
    static let settingsGroup: CGFloat = 16
    static let sheet: CGFloat = 20
    static let emojiBadge: CGFloat = 14
}

// MARK: - Aspect

enum STAspect {
    /// Portrait iPhone screenshot width ÷ height (~9:19.5, modern Super Retina).
    /// Used by the fullscreen Screenshot Viewer — not Context Detail tiles.
    static let iphoneScreenshot: CGFloat = 9.0 / 19.5
    /// Context Detail gallery cells — compact square tiles (3-column grid).
    static let galleryTile: CGFloat = 1

    /// Largest size that fits `bounds` while keeping iPhone screenshot proportions.
    static func fittedIPhoneScreenshot(in bounds: CGSize) -> CGSize {
        let byWidth = CGSize(
            width: bounds.width,
            height: bounds.width / iphoneScreenshot
        )
        if byWidth.height <= bounds.height { return byWidth }
        return CGSize(
            width: bounds.height * iphoneScreenshot,
            height: bounds.height
        )
    }
}

// MARK: - Colors

/// Quiet Pocket palette — surfaces and text are intentionally **light-mode locked** for MVP.
/// Do **not** use `Color.primary` / `Color.secondary` for product UI: they flip with system
/// Dark Mode while our page/pocket surfaces stay light, which produces white-on-white text.
enum STColor {
    // MARK: Surfaces (light Quiet Pocket)

    static let background = Color(red: 0.965, green: 0.965, blue: 0.970)
    static let backgroundSecondary = Color(red: 0.94, green: 0.94, blue: 0.95)
    static let pocket = Color.white
    /// Semantic aliases
    static let pageBackground = background
    static let surfacePrimary = background
    static let surfaceElevated = pocket

    // MARK: Text (always dark-on-light for MVP — never system Color.primary)

    /// Primary readable text on Quiet Pocket surfaces (~near-black).
    static let textPrimary = Color(red: 0.07, green: 0.07, blue: 0.09)
    /// Secondary meta / supporting copy — readable gray on white Quiet Pocket surfaces.
    static let textSecondary = Color(red: 0.33, green: 0.33, blue: 0.36)
    /// Tertiary / quiet captions.
    static let textTertiary = Color(red: 0.48, green: 0.48, blue: 0.51)

    /// Legacy names — resolve to explicit Quiet Pocket text (not system adaptive).
    static let label = textPrimary
    static let secondaryLabel = textSecondary
    static let tertiaryLabel = textTertiary

    // MARK: Brand primary (#008BFF)

    /// Canonical ScreenTidy primary / CTA / selection / active nav. Source: #008BFF.
    static let primary = Color(red: 0.0, green: 139.0 / 255.0, blue: 1.0)
    /// Slightly deeper press state derived from #008BFF.
    static let primaryPressed = Color(red: 0.0, green: 112.0 / 255.0, blue: 0.90)
    /// Whisper tint for selected pills / soft fills (not a solid blue block).
    static let primarySubtle = Color(red: 0.0, green: 139.0 / 255.0, blue: 1.0).opacity(0.12)

    /// Alias — prefer `primary` for new code.
    static let accent = primary

    static let destructive = Color(red: 0.86, green: 0.18, blue: 0.18)
    static let hairline = Color.black.opacity(0.035)
    /// Opaque fallback when Reduce Transparency is on — Quiet Pocket bright surface.
    static let tabBarFill = Color.white
    static let tabBarStroke = Color.black.opacity(0.05)
    /// Search field outline — readable over Home/Search atmosphere wash.
    static let searchFieldStroke = Color.black.opacity(0.06)

    // MARK: Home atmosphere (Quiet Pocket hero wash — light MVP)

    /// Primary cool-blue glow behind greeting / search.
    static let homeAtmosphereBlue = Color(red: 0.72, green: 0.80, blue: 0.91)
    /// Secondary offset glow (slightly cooler) — breaks mechanical symmetry.
    static let homeAtmosphereBlueSecondary = Color(red: 0.78, green: 0.86, blue: 0.94)

    /// Onboarding primary wash — slightly deeper cool blue than Home (related, not identical).
    static let onboardingAtmosphereBlue = Color(red: 0.68, green: 0.77, blue: 0.92)
    /// Onboarding secondary — softer sky bias, opposite offset from Home.
    static let onboardingAtmosphereBlueSecondary = Color(red: 0.80, green: 0.87, blue: 0.96)
}

/// Tunable Home atmosphere intensities — start subtle; adjust in Simulator.
enum STHomeAtmosphereTokens {
    /// Vertical extent of the atmospheric wash (scrolls with hero content).
    static let height: CGFloat = 430
    /// How far the wash bleeds above the scroll content into the status-bar region.
    static let topBleed: CGFloat = 72
    /// Shared scroll space for stretchy pull-to-refresh wash.
    static let scrollCoordinateSpace = "stTabRootScroll"

    static let primaryOpacityLight: Double = 0.34
    static let primaryOpacityDark: Double = 0.28
    static let secondaryOpacityLight: Double = 0.22
    static let secondaryOpacityDark: Double = 0.18

    static let primaryBlur: CGFloat = 72
    static let secondaryBlur: CGFloat = 64
}

/// Onboarding atmosphere — related Quiet Pocket wash, tuned for full-step screens.
enum STOnboardingAtmosphereTokens {
    static let primaryOpacityLight: Double = 0.40
    static let primaryOpacityDark: Double = 0.32
    static let secondaryOpacityLight: Double = 0.26
    static let secondaryOpacityDark: Double = 0.20
    static let accentOpacityLight: Double = 0.16
    static let accentOpacityDark: Double = 0.14

    static let primaryBlur: CGFloat = 88
    static let secondaryBlur: CGFloat = 76
    static let accentBlur: CGFloat = 70
}

extension Color {
    /// Adaptive color for Light / Dark Mode without asset catalogs.
    init(light: Color, dark: Color) {
        self.init(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(dark)
                    : UIColor(light)
            }
        )
    }
}

// MARK: - Shadow tokens (Apple-native, barely noticeable)

/// Single elevation language — soft rest above the canvas, never the focus.
/// Inspired by Settings / Photos / Journal — not Material Design.
/// Prefer hairline strokes + whisper shadows over obvious drop shadows.
enum STShadow {
    /// Cards, pockets, settings groups, onboarding containers.
    enum Surface {
        static let nearOpacity: Double = 0.010
        static let nearRadius: CGFloat = 0.5
        static let nearY: CGFloat = 0.25

        static let farOpacity: Double = 0.020
        static let farRadius: CGFloat = 4
        static let farY: CGFloat = 1
    }

    /// Search field — whisper only; stroke carries most definition over atmosphere.
    enum SearchField {
        static let opacity: Double = 0.03
        static let radius: CGFloat = 4
        static let y: CGFloat = 1
    }

    /// Dark transient toast — soft lift above white Quiet Pocket surfaces.
    enum Toast {
        static let opacity: Double = 0.22
        static let radius: CGFloat = 12
        static let y: CGFloat = 4
    }

    /// Screenshot peeks tucked in a pocket.
    enum Peek {
        static let opacity: Double = 0.04
        static let radius: CGFloat = 2
        static let y: CGFloat = 0.5
    }

    /// Emoji chip on pocket flap.
    enum Badge {
        static let opacity: Double = 0.03
        static let radius: CGFloat = 1.5
        static let y: CGFloat = 0.5
    }

    // MARK: Legacy numeric aliases (prefer `.stSurfaceShadow()`)

    static let cardRadius: CGFloat = Surface.farRadius
    static let cardY: CGFloat = Surface.farY
}

// MARK: - Typography

/// SF Pro / Dynamic Type roles for Quiet Pocket.
enum STTypography {
    static let greeting = Font.largeTitle.weight(.bold)
    static let aiLine = Font.body
    static let sectionTitle = Font.title3.weight(.semibold)
    static let pocketTitle = Font.subheadline.weight(.bold)
    static let pocketMeta = Font.caption
    static let rowTitle = Font.body.weight(.medium)
    static let rowMeta = Font.footnote
    static let search = Font.body
    static let button = Font.headline
    static let tabLabel = Font.caption2
    static let emptyTitle = Font.title3.weight(.semibold)
    static let emptyMessage = Font.body
    static let caption = Font.caption.weight(.semibold)
    /// Compact dark toast message.
    static let toast = Font.subheadline.weight(.semibold)
    /// Trailing toast action (Undo) — distinct from message weight/color.
    static let toastAction = Font.subheadline.weight(.semibold)
}

// MARK: - Motion

enum STMotion {
    static let pressScale: CGFloat = 0.985
    static let pressDuration: TimeInterval = 0.18
    static let standardDuration: TimeInterval = 0.28
    static let quickDuration: TimeInterval = 0.2
    static let toastAppearScale: CGFloat = 0.96
    /// Informational success toast (no action).
    static let toastHoldDuration: TimeInterval = 2.5
    /// Toast with Undo — longer window to act before the mutation commits.
    static let toastUndoHoldDuration: TimeInterval = 5.0
    /// Real-time search debounce after typing pauses.
    static let searchDebounceDuration: TimeInterval = 0.25

    static var pressAnimation: Animation {
        .easeOut(duration: pressDuration)
    }

    static func standard(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: quickDuration) : .easeInOut(duration: standardDuration)
    }

    /// Lightweight appear for the dark floating toast.
    static func toastAppear(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: quickDuration)
            : .spring(response: 0.34, dampingFraction: 0.86)
    }

    /// Restrained dismiss — fade + slight settle.
    static func toastDismiss(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeIn(duration: quickDuration)
            : .easeIn(duration: 0.18)
    }
}
