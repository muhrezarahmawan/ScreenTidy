import Foundation
import SwiftUI
import UIKit

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case photosPermission
    case photosDenied
    case importing
    case emptyLibrary
    case organizing

    var id: Int { rawValue }

    /// 1...4 progress stages. Photos permission + denied recovery share stage 2.
    var progressStage: Int {
        switch self {
        case .welcome:
            return 1
        case .photosPermission, .photosDenied:
            return 2
        case .importing:
            return 3
        case .emptyLibrary, .organizing:
            return 4
        }
    }

    var progressAccessibilityName: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .photosPermission, .photosDenied:
            return "Photos access"
        case .importing:
            return "Import"
        case .emptyLibrary:
            return "No screenshots found"
        case .organizing:
            return "Organizing"
        }
    }
}

enum OnboardingProgress {
    static let totalStages = 4
}


@MainActor
@Observable
final class OnboardingViewModel {
    private let memory: any MemoryReading
    private let photos: any PhotosProviding
    private let sync: any ScreenshotSyncing
    private let onComplete: () -> Void
    /// DEBUG: force empty-library path without importing the real Photos library.
    private let shouldSimulateEmptyLibrary: () -> Bool

    var step: OnboardingStep = .welcome
    var importProgress: Double = 0
    var organizingRevealCount: Int = 0
    /// True when the latest step change should animate in from the trailing edge.
    private(set) var navigatesForward = true

    /// Page to the left of the current step (revealed when swiping right).
    var previousCarouselStep: OnboardingStep? {
        switch step {
        case .photosPermission: return .welcome
        case .photosDenied: return .photosPermission
        case .welcome, .importing, .emptyLibrary, .organizing: return nil
        }
    }

    /// Page to the right of the current step (revealed when swiping left).
    /// Photos → Import is an optimistic peek; grant still runs on commit.
    var nextCarouselStep: OnboardingStep? {
        switch step {
        case .welcome: return .photosPermission
        case .photosPermission: return .importing
        case .photosDenied, .importing, .emptyLibrary, .organizing: return nil
        }
    }

    var canCarouselForward: Bool {
        switch step {
        case .welcome, .photosPermission, .photosDenied, .emptyLibrary, .organizing:
            return true
        case .importing:
            return false
        }
    }

    var canCarouselBack: Bool {
        previousCarouselStep != nil
    }

    /// Same promoted Collections Home will show (`fetchPromotedContexts`).
    private(set) var libraryCollections: [ContextCollection] = []

    init(
        memory: any MemoryReading,
        photos: any PhotosProviding,
        sync: any ScreenshotSyncing,
        shouldSimulateEmptyLibrary: @escaping () -> Bool = { false },
        onComplete: @escaping () -> Void
    ) {
        self.memory = memory
        self.photos = photos
        self.sync = sync
        self.shouldSimulateEmptyLibrary = shouldSimulateEmptyLibrary
        self.onComplete = onComplete
    }

    func goToWelcomeContinue() {
        navigate(to: .photosPermission, forward: true)
    }

    func allowFullPhotos() {
        requestPhotos(presentLimitedPicker: false)
    }

    func allowLimitedPhotos() {
        requestPhotos(presentLimitedPicker: true)
    }

    func denyPhotos() {
        Task {
            let status = await photos.requestAuthorization()
            if status == .full || status == .limited {
                beginImport()
            } else {
                navigate(to: .photosDenied, forward: true)
            }
        }
    }

    /// Denied recovery: iOS will not show the system prompt again after Deny.
    /// Open Settings so the user can enable Photos, then resume when they return.
    func enablePhotosAccess() {
        Task {
            let current = await photos.authorizationStatus
            switch current {
            case .full, .limited:
                beginImport()
            case .notDetermined:
                requestPhotos(presentLimitedPicker: false)
            case .denied:
                openAppSettings()
            }
        }
    }

    /// Call when the app becomes active (e.g. returning from Settings).
    func handleAppBecameActive() {
        guard step == .photosDenied else { return }
        Task {
            let status = await photos.authorizationStatus
            if status == .full || status == .limited {
                beginImport()
            }
        }
    }

    /// Leaves the app; onboarding stays incomplete.
    func exitScreenTidy() {
        AppLog.general.info("User exited from Photos denied recovery")
        exit(0)
    }

    func continueFromEmptyLibrary() {
        onComplete()
    }

    func finishOrganizing() {
        onComplete()
    }

    /// Called when the paging carousel settles on a neighboring page.
    func commitCarouselPage(_ page: OnboardingStep) {
        switch (step, page) {
        case (.welcome, .photosPermission):
            navigate(to: .photosPermission, forward: true)
        case (.photosPermission, .welcome):
            navigate(to: .welcome, forward: false)
        case (.photosDenied, .photosPermission):
            navigate(to: .photosPermission, forward: false)
        case (.photosPermission, .photosDenied):
            navigate(to: .photosDenied, forward: true)
        default:
            break
        }
    }

    /// Horizontal swipe: left = continue / primary action, right = go back.
    func handleHorizontalSwipe(translationWidth: CGFloat) {
        let threshold: CGFloat = 64
        if translationWidth <= -threshold {
            commitCarouselForward()
        } else if translationWidth >= threshold {
            commitCarouselBack()
        }
    }

    /// Called after an interactive carousel page settles on the next page.
    func commitCarouselForward() {
        swipeForward()
    }

    /// Called after an interactive carousel page settles on the previous page.
    func commitCarouselBack() {
        swipeBack()
    }

    private func swipeForward() {
        switch step {
        case .welcome:
            goToWelcomeContinue()
        case .photosPermission:
            allowFullPhotos()
        case .photosDenied:
            enablePhotosAccess()
        case .emptyLibrary:
            continueFromEmptyLibrary()
        case .organizing:
            finishOrganizing()
        case .importing:
            break
        }
    }

    private func swipeBack() {
        switch step {
        case .photosPermission:
            navigate(to: .welcome, forward: false)
        case .photosDenied:
            navigate(to: .photosPermission, forward: false)
        case .welcome, .importing, .emptyLibrary, .organizing:
            break
        }
    }

    private func navigate(to newStep: OnboardingStep, forward: Bool) {
        navigatesForward = forward
        step = newStep
    }

    /// Photos grant → Import. Organization is always-on core product (no preference step).
    private func requestPhotos(presentLimitedPicker: Bool) {
        Task {
            let existing = await photos.authorizationStatus
            if existing == .denied {
                navigate(to: .photosDenied, forward: true)
                return
            }

            let status = await photos.requestAuthorization()
            guard status == .full || status == .limited else {
                navigate(to: .photosDenied, forward: true)
                return
            }
            if presentLimitedPicker || status == .limited {
                await photos.presentLimitedLibraryPicker()
            }
            beginImport()
        }
    }

    private func beginImport() {
        importProgress = 0
        navigate(to: .importing, forward: true)
        Task {
            if shouldSimulateEmptyLibrary() {
                importProgress = 1
                libraryCollections = []
                navigate(to: .emptyLibrary, forward: true)
                return
            }
            do {
                _ = try await sync.initialImport { [weak self] progress in
                    Task { @MainActor in self?.importProgress = progress }
                }
                finishImportPath()
            } catch {
                AppLog.general.error("Onboarding import failed: \(error.localizedDescription, privacy: .public)")
                navigate(to: .photosDenied, forward: true)
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func finishImportPath() {
        Task {
            let count = (try? await memory.fetchUnassignedCount()) ?? 0
            if count == 0 {
                libraryCollections = []
                navigate(to: .emptyLibrary, forward: true)
                return
            }
            // Sprint 4: real screenshots land in Needs Review only — no fake AI filing.
            // Show organizing only when Collections already have members (e.g. user-created).
            let promoted = ((try? await memory.fetchPromotedContexts()) ?? [])
                .filter { $0.memberCount > 0 }
            if promoted.isEmpty {
                onComplete()
            } else {
                libraryCollections = promoted
                navigate(to: .organizing, forward: true)
                revealCollections()
            }
        }
    }

    private func revealCollections() {
        organizingRevealCount = 0
        Task {
            let total = libraryCollections.count
            for i in 1...total {
                try? await Task.sleep(nanoseconds: 380_000_000)
                organizingRevealCount = i
            }
        }
    }
}
