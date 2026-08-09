import Foundation

/// Transient mock onboarding state (Photos access, import count). Completion lives on `AppDependencies`.
@Observable
@MainActor
final class OnboardingSession {
    private static let photosAccessKey = "screentidy.mock.photosAccess"

    var mockPhotosAccess: MockPhotosAccess {
        didSet { Self.persist(mockPhotosAccess) }
    }

    var importedCount: Int = 0

    /// DEBUG/Developer: next successful Photos grant imports 0 screenshots → empty-library step.
    var simulateEmptyLibrary: Bool = false

    init() {
        self.mockPhotosAccess = Self.loadPersistedAccess()
    }

    func resetTransientState() {
        importedCount = 0
        simulateEmptyLibrary = false
        // Keep persisted Photos status for Settings unless onboarding re-grants.
    }

    /// Clear Photos mock status (e.g. fresh Replay that should re-prompt).
    func clearPhotosAccessForReplay() {
        mockPhotosAccess = .notDetermined
    }

    var photosSettingsLabel: String {
        mockPhotosAccess.settingsLabel
    }

    private static func persist(_ access: MockPhotosAccess) {
        UserDefaults.standard.set(access.rawValue, forKey: photosAccessKey)
    }

    private static func loadPersistedAccess() -> MockPhotosAccess {
        guard let raw = UserDefaults.standard.string(forKey: photosAccessKey),
              let access = MockPhotosAccess(rawValue: raw) else {
            return .notDetermined
        }
        return access
    }
}
