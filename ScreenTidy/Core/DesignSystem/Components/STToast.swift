import SwiftUI
import UIKit

// MARK: - Style (architecture ready; Sprint 2 ships success only)

/// Semantic toast kind. Visual chrome stays dark for all styles in MVP —
/// only the leading glyph differs. Colorful state fills are deferred.
enum STToastStyle: Equatable, Sendable {
    case success
    case error
    case warning
    case info

    var systemImage: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }
}

/// Identifiable payload so replacements animate cleanly (no stacked toasts).
/// Action handlers live on `STFeedbackCenter` (not Equatable / not Sendable).
struct STToastPayload: Equatable, Identifiable, Sendable {
    let id: UUID
    let style: STToastStyle
    let message: String
    let actionTitle: String?

    init(
        style: STToastStyle = .success,
        message: String,
        actionTitle: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.style = style
        self.message = message
        self.actionTitle = actionTitle
    }

    var hasAction: Bool { actionTitle != nil }
}

// MARK: - Feedback center

/// Global ephemeral feedback — toast / snackbar (not for destructive confirms).
@MainActor
@Observable
final class STFeedbackCenter {
    private(set) var payload: STToastPayload?
    private var dismissTask: Task<Void, Never>?
    private var actionHandler: (() -> Void)?
    /// Called when the toast times out or is replaced — e.g. commit a pending mock undo.
    private var onExpire: (() -> Void)?

    /// Shows a temporary message. Replaces any currently visible toast (no stacking).
    func show(
        _ message: String,
        style: STToastStyle = .success,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onExpire: (() -> Void)? = nil,
        duration: TimeInterval? = nil
    ) {
        show(
            style: style,
            message: message,
            actionTitle: actionTitle,
            action: action,
            onExpire: onExpire,
            duration: duration
        )
    }

    func show(
        style: STToastStyle,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onExpire: (() -> Void)? = nil,
        duration: TimeInterval? = nil
    ) {
        // Superseding a toast commits any previous undo window.
        commitExpire()
        dismissTask?.cancel()

        let hold = duration
            ?? (actionTitle != nil
                ? STMotion.toastUndoHoldDuration
                : STMotion.toastHoldDuration)
        let next = STToastPayload(style: style, message: message, actionTitle: actionTitle)
        payload = next
        actionHandler = actionTitle != nil ? action : nil
        self.onExpire = onExpire

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard payload?.id == next.id else { return }
            commitExpire()
            payload = nil
            actionHandler = nil
        }
    }

    /// Invokes the trailing action (e.g. Undo), then dismisses without committing expire.
    func performAction() {
        guard let handler = actionHandler else { return }
        dismissTask?.cancel()
        actionHandler = nil
        onExpire = nil
        payload = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        handler()
    }

    func clear() {
        dismissTask?.cancel()
        commitExpire()
        payload = nil
        actionHandler = nil
    }

    private func commitExpire() {
        let expire = onExpire
        onExpire = nil
        expire?()
    }
}

enum STFeedbackCopy {
    static let collectionCreated = "Collection created"
    static let collectionRenamed = "Collection renamed"
    static let collectionDeleted = "Collection deleted"
    static let collectionRestored = "Collection restored"
    static let moveUndone = "Move undone"
    static let addUndone = "Add undone"
    static let removeFromCollectionUndone = "Remove undone"
    static let undoAction = "Undo"
    static let screenshotsSynced = "Screenshots synced"
    static let screenshotsUpToDate = "Everything is up to date"
    static let screenshotsSyncFailed = "Couldn't refresh screenshots"

    static func screenshotsOrganized(count: Int) -> String {
        if count == 1 {
            return "1 new screenshot organized"
        }
        return "\(count) new screenshots organized"
    }

    static func sync(_ result: ScreenshotSyncResult) -> String {
        switch result {
        case .upToDate:
            return screenshotsUpToDate
        case .synced:
            return screenshotsSynced
        case .organized(let count):
            return screenshotsOrganized(count: count)
        case .failed:
            return screenshotsSyncFailed
        }
    }

    static func screenshotsMoved(count: Int) -> String {
        if count == 1 {
            return "Screenshot moved"
        }
        return "\(count) screenshots moved"
    }

    static func screenshotsAddedToCollection(count: Int) -> String {
        if count == 1 {
            return "Added to Collection"
        }
        return "\(count) screenshots added to Collection"
    }

    static func screenshotsRemovedFromCollection(count: Int) -> String {
        if count == 1 {
            return "Removed from Collection"
        }
        return "\(count) screenshots removed from Collection"
    }

    static func screenshotsDeleted(count: Int) -> String {
        if count == 1 {
            return "Screenshot deleted"
        }
        return "\(count) screenshots deleted"
    }

    static func screenshotsRemoved(count: Int) -> String {
        if count == 1 {
            return "Screenshot removed from ScreenTidy"
        }
        return "\(count) screenshots removed from ScreenTidy"
    }

    static func screenshotsRestored(count: Int) -> String {
        if count == 1 {
            return "Screenshot restored"
        }
        return "\(count) screenshots restored"
    }
}

// MARK: - Toast view

/// Dark floating system toast — intentionally distinct from white Quiet Pocket surfaces.
struct STToast: View {
    let style: STToastStyle
    let message: String
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil

    init(
        style: STToastStyle = .success,
        message: String,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.style = style
        self.message = message
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    var body: some View {
        HStack(spacing: STSpacing.sm) {
            Image(systemName: style.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .accessibilityHidden(true)

            Text(message)
                .font(STTypography.toast)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if let actionTitle {
                Button {
                    onAction?()
                } label: {
                    Text(actionTitle)
                        .font(STTypography.toastAction)
                        .foregroundStyle(STColor.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionTitle)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        // Equal inset on all sides — same with or without Undo.
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(toastBackground)
        .shadow(
            color: Color.black.opacity(STShadow.Toast.opacity),
            radius: STShadow.Toast.radius,
            x: 0,
            y: STShadow.Toast.y
        )
        .accessibilityElement(children: actionTitle == nil ? .combine : .contain)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityLabel(message)
    }

    private var toastBackground: some View {
        Capsule(style: .continuous)
            .fill(.clear)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.52))
                }
            }
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }
}

// MARK: - Host

/// Hosts `STFeedbackCenter` above the system tab bar / bottom safe area.
struct STToastHost: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let feedback = dependencies.feedback
        let showsTabBar = dependencies.navigator.showsTabBar

        VStack {
            Spacer(minLength: 0)
            if let payload = feedback.payload {
                STToast(
                    style: payload.style,
                    message: payload.message,
                    actionTitle: payload.actionTitle,
                    onAction: { feedback.performAction() }
                )
                .frame(
                    maxWidth: payload.hasAction
                        ? STSpacing.toastActionMaxWidth
                        : STSpacing.toastMaxWidth,
                    alignment: .center
                )
                .padding(.horizontal, STSpacing.page)
                .padding(.bottom, bottomInset(showsTabBar: showsTabBar))
                .id(payload.id)
                .transition(toastTransition)
                // Only the toast receives hits (Undo); the dimming void stays pass-through.
                .allowsHitTesting(payload.hasAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(feedback.payload?.hasAction == true)
        .animation(STMotion.toastAppear(reduceMotion: reduceMotion), value: feedback.payload?.id)
    }

    private func bottomInset(showsTabBar: Bool) -> CGFloat {
        if showsTabBar {
            // Overlay sits above the full screen — clear the system tab bar + a small gap.
            return STSpacing.tabBarHeight + STSpacing.toastTabBarGap
        }
        // No tab bar — clear the home indicator; never flush to the edge.
        return STSpacing.xl
    }

    private var toastTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .modifier(
                active: STToastMotionModifier(progress: 0, appear: true),
                identity: STToastMotionModifier(progress: 1, appear: true)
            ),
            removal: .modifier(
                active: STToastMotionModifier(progress: 0, appear: false),
                identity: STToastMotionModifier(progress: 1, appear: false)
            )
        )
    }
}

/// Appear: fade + rise + 0.96→1. Dismiss: fade + slight settle down.
private struct STToastMotionModifier: ViewModifier {
    /// 0 = hidden, 1 = fully shown.
    var progress: Double
    var appear: Bool

    func body(content: Content) -> some View {
        let offset: CGFloat = appear
            ? (1 - progress) * 14
            : (1 - progress) * 8
        content
            .opacity(progress)
            .offset(y: offset)
            .scaleEffect(
                appear
                    ? STMotion.toastAppearScale + (1 - STMotion.toastAppearScale) * progress
                    : 1.0 - (1 - progress) * 0.02
            )
    }
}

#Preview("Dark success toast") {
    ZStack {
        STColor.background.ignoresSafeArea()
        VStack {
            Spacer()
            STToast(style: .success, message: "Collection renamed")
            STToast(
                style: .success,
                message: "Screenshot deleted",
                actionTitle: "Undo",
                onAction: {}
            )
            .padding(.top, 12)
            STToast(style: .success, message: "5 screenshots moved")
                .padding(.top, 12)
            Spacer().frame(height: 100)
        }
    }
}
