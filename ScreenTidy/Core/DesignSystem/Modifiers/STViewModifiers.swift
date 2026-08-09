import SwiftUI

// MARK: - Elevation (Design System — use these everywhere)

extension View {
    /// Soft resting elevation for cards, pockets, settings groups, onboarding containers.
    /// Barely noticeable — Apple Settings / Photos / Journal language.
    func stSurfaceShadow() -> some View {
        self
            .shadow(
                color: Color.black.opacity(STShadow.Surface.nearOpacity),
                radius: STShadow.Surface.nearRadius,
                x: 0,
                y: STShadow.Surface.nearY
            )
            .shadow(
                color: Color.black.opacity(STShadow.Surface.farOpacity),
                radius: STShadow.Surface.farRadius,
                x: 0,
                y: STShadow.Surface.farY
            )
    }

    /// Alias — Context Collection pockets use the same surface language as cards.
    func stPocketShadow() -> some View {
        stSurfaceShadow()
    }

    /// Alias — primary / settings cards.
    func stCardShadow() -> some View {
        stSurfaceShadow()
    }

    /// Search field — whisper lift; outline carries most contrast over atmosphere.
    func stSearchFieldShadow() -> some View {
        shadow(
            color: Color.black.opacity(STShadow.SearchField.opacity),
            radius: STShadow.SearchField.radius,
            x: 0,
            y: STShadow.SearchField.y
        )
    }

    /// Screenshot peeks inside a pocket.
    func stPeekShadow() -> some View {
        shadow(
            color: Color.black.opacity(STShadow.Peek.opacity),
            radius: STShadow.Peek.radius,
            x: 0,
            y: STShadow.Peek.y
        )
    }

    /// Emoji chip.
    func stBadgeShadow() -> some View {
        shadow(
            color: Color.black.opacity(STShadow.Badge.opacity),
            radius: STShadow.Badge.radius,
            x: 0,
            y: STShadow.Badge.y
        )
    }

    /// Soft cool-blue hero wash behind tab-root scroll content (Home, Search, Cleanup, Settings).
    /// Stretches upward during pull-to-refresh so overscroll matches the greeting wash.
    /// Pair the enclosing `ScrollView` with `.coordinateSpace(name: STHomeAtmosphereTokens.scrollCoordinateSpace)`.
    func stTabRootAtmosphere() -> some View {
        ZStack(alignment: .top) {
            STStretchyHomeAtmosphere(coordinateSpaceName: STHomeAtmosphereTokens.scrollCoordinateSpace)
            self
        }
    }

    /// Page fill for tab roots — Quiet Pocket base tinted with the same hero blue so any
    /// brief gap behind the stretchy wash still matches (never a flat white band).
    func stTabRootScrollBackground() -> some View {
        background {
            ZStack(alignment: .top) {
                STColor.background

                // Flat wash matching the greeting — continuous under status bar + overscroll.
                LinearGradient(
                    stops: [
                        .init(
                            color: STColor.homeAtmosphereBlue.opacity(
                                STHomeAtmosphereTokens.primaryOpacityLight
                            ),
                            location: 0
                        ),
                        .init(
                            color: STColor.homeAtmosphereBlueSecondary.opacity(
                                STHomeAtmosphereTokens.secondaryOpacityLight
                            ),
                            location: 0.35
                        ),
                        .init(color: STColor.background, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: STHomeAtmosphereTokens.height + STHomeAtmosphereTokens.topBleed)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Opaque cover over the status-bar band so scrolled titles never collide with system chrome.
    /// Keeps nav bars hidden while preserving a readable status bar.
    func stStatusBarCover() -> some View {
        overlay(alignment: .top) {
            GeometryReader { geo in
                let topInset = geo.safeAreaInsets.top
                STColor.background
                    .frame(width: geo.size.width, height: topInset)
                    .position(x: geo.size.width / 2, y: topInset / 2)
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension ToolbarContent {
    /// Hides iOS 26 liquid-glass shared backgrounds when available.
    @ToolbarContentBuilder
    func stHideSharedBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

// MARK: - Photos-style screenshot zoom (iOS 18+)

private enum STScreenshotZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Shared by gallery thumbnails and the fullscreen viewer for zoom navigation.
    var screenshotZoomNamespace: Namespace.ID? {
        get { self[STScreenshotZoomNamespaceKey.self] }
        set { self[STScreenshotZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Marks a gallery thumbnail as the zoom source for fullscreen open/dismiss.
    func stScreenshotZoomSource(id: ScreenshotMemoryID) -> some View {
        modifier(STScreenshotZoomSourceModifier(id: id))
    }

    /// Fullscreen viewer destination — zooms back to the matching thumbnail on dismiss.
    func stScreenshotZoomDestination(id: ScreenshotMemoryID) -> some View {
        modifier(STScreenshotZoomDestinationModifier(id: id))
    }
}

private struct STScreenshotZoomSourceModifier: ViewModifier {
    @Environment(\.screenshotZoomNamespace) private var namespace
    let id: ScreenshotMemoryID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct STScreenshotZoomDestinationModifier: ViewModifier {
    @Environment(\.screenshotZoomNamespace) private var namespace
    let id: ScreenshotMemoryID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

// MARK: - Interaction

/// Subtle press feedback for tappable cards / pockets.
struct STCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? STMotion.pressScale : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : STMotion.pressAnimation,
                value: configuration.isPressed
            )
    }
}
