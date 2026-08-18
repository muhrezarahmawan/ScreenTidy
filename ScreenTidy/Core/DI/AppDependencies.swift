import Foundation

@MainActor
@Observable
final class AppDependencies {
    private static let onboardingCompletedKey = "screentidy.onboarding.completed"
    /// Obsolete optional-AI preference — removed; clear on launch so no dead state remains.
    private static let obsoleteAIOrganizationKey = "screentidy.ai.organizationEnabled"

    let configuration: AppConfiguration
    let navigator: AppNavigator
    let onboarding: OnboardingSession

    /// Persistent SQLite stack (Sprint 3). Source of truth for organization metadata.
    let database: AppDatabase

    /// Feature-facing memory port (protocol). Backed by GRDB in Sprint 3.
    let memoryStore: any MemoryRepository
    let searchProvider: any SearchProviding
    let cleanupProvider: any CleanupProviding
    let photosProvider: any PhotosProviding
    let organizer: any Organizing
    let screenshotSync: any ScreenshotSyncing
    let thumbnailProvider: any ThumbnailProviding
    let searchSuggestions: any SearchSuggestionsProviding
    let ocrScheduler: any OCRScheduling
    let ocrStore: any OCRPersisting
    let visualScheduler: any VisualAnalysisScheduling
    let visualStore: any VisualAnalysisPersisting
    let organizationStore: any OrganizationPersisting
    let organizationScheduler: any OrganizationScheduling
    let feedback: STFeedbackCenter

    /// Typed mock Photos provider for status sync from onboarding (Sprint 2/3 mock).
    private let mockPhotos: MockPhotosProvider

    /// Bumped after memory mutations so mounted tab roots (e.g. Home) refresh.
    private(set) var memoryEpoch: UInt = 0

    /// Image backups captured before Photos delete, used by Undo to re-create library assets.
    private var pendingPhotosRestores: [UUID: [PhotosAssetBackup]] = [:]

    /// Owned here (not nested) so `@Bindable` root UI always observes completion changes.
    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingCompletedKey)
        }
    }

    /// Bumped on every replay so OnboardingFlowView gets a fresh identity.
    private(set) var onboardingPresentationID: UInt = 0

    /// Drives cloud understanding disclosure sheet.
    var showCloudUnderstandingDisclosure = false

    init(configuration: AppConfiguration = .current) {
        self.configuration = configuration
        self.navigator = AppNavigator()
        self.onboarding = OnboardingSession()
        self.feedback = STFeedbackCenter()
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)

        UserDefaults.standard.removeObject(forKey: Self.obsoleteAIOrganizationKey)

        var database: AppDatabase
        do {
            database = try AppDatabase(path: try AppDatabase.defaultPath)
            try DatabaseSeeder.seedIfNeeded(database)
        } catch {
            AppLog.general.error(
                "Failed to open ScreenTidy database: \(error.localizedDescription, privacy: .public)"
            )
            do {
                database = try AppDatabase.makeEmptyInMemory()
                try DatabaseSeeder.seedIfNeeded(database)
            } catch {
                preconditionFailure("ScreenTidy persistence failed to start: \(error)")
            }
        }
        self.database = database

        let memory = GRDBMemoryRepository(database: database)
        let mockPhotos = MockPhotosProvider(initialStatus: onboarding.mockPhotosAccess)
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let photoProvider: any PhotosProviding = isPreview ? mockPhotos : PhotoKitPhotosProvider()
        self.memoryStore = memory
        self.searchProvider = memory
        self.cleanupProvider = memory
        self.mockPhotos = mockPhotos
        self.photosProvider = photoProvider
        self.ocrStore = memory
        self.visualStore = memory
        self.organizationStore = memory

        let epochBump = OrganizationEpochBump()
        let understandingProvider = CompositeUnderstandingProvider(configuration: configuration)
        let organizationService = OrganizationService(
            store: memory,
            understanding: understandingProvider,
            memory: memory,
            policy: .current,
            onMutated: { epochBump.bump() }
        )
        self.organizer = organizationService

        if isPreview {
            self.screenshotSync = MockScreenshotSyncService(ingest: memory)
            self.thumbnailProvider = MockThumbnailProvider()
            self.searchSuggestions = LocalSearchSuggestionsProvider(memory: memory)
            self.ocrScheduler = NoOpOCRScheduler()
            self.visualScheduler = NoOpVisualAnalysisScheduler()
            self.organizationScheduler = NoOpOrganizationScheduler()
        } else {
            let orgQueue = OrganizationQueue(
                store: memory,
                organizer: organizationService,
                onMutated: { epochBump.bump() }
            )
            self.organizationScheduler = orgQueue

            let photoSync = PhotoKitScreenshotSyncService(repository: memory, photos: photoProvider)
            let imageLoader = PhotoKitOCRImageLoader(longEdge: OCRPipeline.imageLongEdge)
            let visualImageLoader = PhotoKitOCRImageLoader(longEdge: VisualAnalysisPipeline.imageLongEdge)
            let visualQueue = VisualAnalysisProcessingQueue(
                repository: memory,
                analyzer: VisionVisualAnalysisService(),
                images: visualImageLoader,
                onVisualFinished: { [weak orgQueue] id in
                    Task {
                        try? await memory.tryMarkReadyForOrganize(id: id)
                        orgQueue?.kick()
                    }
                }
            )
            let ocrQueue = OCRProcessingQueue(
                repository: memory,
                ocr: VisionOCRService(),
                images: imageLoader,
                onOCRFinished: { [weak orgQueue] id in
                    Task {
                        try? await memory.tryMarkReadyForOrganize(id: id)
                        orgQueue?.kick()
                    }
                }
            )
            self.screenshotSync = photoSync
            self.thumbnailProvider = PhotoKitThumbnailProvider()
            self.searchSuggestions = LocalSearchSuggestionsProvider(memory: memory)
            self.ocrScheduler = ocrQueue
            self.visualScheduler = visualQueue
            photoSync.onDidSync = { [weak self] in
                self?.noteMemoryMutation()
                self?.ocrScheduler.kick()
                self?.visualScheduler.kick()
                self?.organizationScheduler.kick()
            }
        }

        epochBump.handler = { [weak self] in
            Task { @MainActor in
                self?.noteMemoryMutation()
            }
        }

        AppLog.general.info(
            "AppDependencies ready (\(configuration.environment.rawValue, privacy: .public); GRDB persistence)"
        )
    }

    /// Preview / test injection with an explicit database (in-memory or temp path).
    init(configuration: AppConfiguration = .current, database: AppDatabase) {
        self.configuration = configuration
        self.navigator = AppNavigator()
        self.onboarding = OnboardingSession()
        self.feedback = STFeedbackCenter()
        self.hasCompletedOnboarding = false
        self.database = database

        let memory = GRDBMemoryRepository(database: database)
        let photos = MockPhotosProvider(initialStatus: .notDetermined)
        self.memoryStore = memory
        self.searchProvider = memory
        self.cleanupProvider = memory
        self.mockPhotos = photos
        self.photosProvider = photos
        self.ocrStore = memory
        self.visualStore = memory
        self.organizationStore = memory
        self.organizer = OrganizationService(
            store: memory,
            understanding: OnDeviceStructuredUnderstandingProvider(),
            memory: memory
        )
        self.screenshotSync = MockScreenshotSyncService(ingest: memory)
        self.thumbnailProvider = MockThumbnailProvider()
        self.searchSuggestions = LocalSearchSuggestionsProvider(memory: memory)
        self.ocrScheduler = NoOpOCRScheduler()
        self.visualScheduler = NoOpVisualAnalysisScheduler()
        self.organizationScheduler = NoOpOrganizationScheduler()
    }

    func noteMemoryMutation() {
        memoryEpoch &+= 1
    }

    func presentCloudUnderstandingDisclosureIfNeeded() {
        guard hasCompletedOnboarding else { return }
        guard CloudUnderstandingPreferences.consent == .notDetermined else { return }
        showCloudUnderstandingDisclosure = true
    }

    func acceptCloudUnderstanding() {
        CloudUnderstandingPreferences.consent = .accepted
        showCloudUnderstandingDisclosure = false
        Task {
            try? await organizationStore.requeueSkippedConsentJobs()
            organizationScheduler.kick()
            noteMemoryMutation()
        }
    }

    func declineCloudUnderstanding() {
        CloudUnderstandingPreferences.consent = .declined
        showCloudUnderstandingDisclosure = false
        Task {
            // Reduced on-device path still runs without multimodal.
            try? await organizationStore.requeueSkippedConsentJobs()
            organizationScheduler.kick()
            noteMemoryMutation()
        }
    }

    /// Keeps Settings Photos row aligned with mock onboarding grants.
    func noteMockPhotosAccess(_ access: MockPhotosAccess) {
        onboarding.mockPhotosAccess = access
        Task { await mockPhotos.setStatus(access) }
    }

    /// Shows the Photos system confirmation immediately, then soft-removes from ScreenTidy.
    /// Captures image backups first so Undo can restore both Photos and app metadata.
    @discardableResult
    func deleteScreenshotsFromCollectionAndPhotos(ids: Set<ScreenshotMemoryID>) async throws -> MockUndoToken {
        guard !ids.isEmpty else { return MockUndoToken() }

        var localIdentifiers: [String] = []
        localIdentifiers.reserveCapacity(ids.count)
        for id in ids {
            if let shot = try await memoryStore.fetchScreenshot(id: id),
               let identifier = shot.photosLocalIdentifier,
               !identifier.isEmpty {
                localIdentifiers.append(identifier)
            }
        }

        var backups: [PhotosAssetBackup] = []
        if !localIdentifiers.isEmpty {
            backups = try await photosProvider.exportAssetsForRestore(localIdentifiers: localIdentifiers)
            // System confirmation appears here — before any ScreenTidy mutation.
            try await photosProvider.deleteAssets(localIdentifiers: localIdentifiers)
        }

        let token: MockUndoToken
        do {
            token = try await cleanupProvider.mockRemoveScreenshots(ids: ids)
        } catch {
            // Photos already deleted — put library copies back so the user isn't stranded.
            if !backups.isEmpty {
                _ = try? await photosProvider.restoreAssets(backups)
            }
            throw error
        }

        if !backups.isEmpty {
            pendingPhotosRestores[token.id] = backups
        }
        noteMemoryMutation()
        return token
    }

    /// Shows an Undo snackbar. Undo restores ScreenTidy metadata and re-creates Photos assets.
    func presentUndoableFeedback(
        message: String,
        token: MockUndoToken,
        restoredMessage: String,
        onRestored: (() async -> Void)? = nil
    ) {
        feedback.show(
            message,
            actionTitle: STFeedbackCopy.undoAction,
            action: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    let backups = self.pendingPhotosRestores.removeValue(forKey: token.id) ?? []
                    let restored = await self.memoryStore.undo(token: token)
                    guard restored else { return }

                    if !backups.isEmpty {
                        do {
                            let mapping = try await self.photosProvider.restoreAssets(backups)
                            try await self.memoryStore.remapPhotosLocalIdentifiers(mapping)
                        } catch {
                            AppLog.general.error(
                                "Photos restore after Undo failed: \(error.localizedDescription, privacy: .public)"
                            )
                            self.noteMemoryMutation()
                            await onRestored?()
                            self.feedback.show(
                                "Restored in ScreenTidy, but Photos restore failed",
                                style: .error
                            )
                            return
                        }
                    }

                    self.noteMemoryMutation()
                    await onRestored?()
                    self.feedback.show(restoredMessage)
                }
            },
            onExpire: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.pendingPhotosRestores.removeValue(forKey: token.id)
                    await self.memoryStore.discardUndo(token: token)
                }
            }
        )
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        AppLog.general.info("Onboarding completed")
        ocrScheduler.kick()
        visualScheduler.kick()
        organizationScheduler.kick()
        presentCloudUnderstandingDisclosureIfNeeded()
    }

    func syncPhotosOnLaunch() {
        Task {
            let status = await photosProvider.authorizationStatus
            guard status == .full || status == .limited else { return }
            _ = try? await screenshotSync.syncIncremental()
            noteMemoryMutation()
            ocrScheduler.kick()
            visualScheduler.kick()
            organizationScheduler.kick()
            presentCloudUnderstandingDisclosureIfNeeded()
        }
    }

    /// Settings / debug — reset mock onboarding and present Welcome immediately.
    func replayOnboarding() {
        onboarding.resetTransientState()
        onboarding.clearPhotosAccessForReplay()
        Task { await mockPhotos.setStatus(.notDetermined) }
        hasCompletedOnboarding = false
        onboardingPresentationID &+= 1

        navigator.selectedTab = .home
        for tab in AppTab.allCases {
            navigator.popToRoot(of: tab)
        }

        AppLog.general.info("Onboarding replay requested (id \(self.onboardingPresentationID))")
    }

    /// Developer: Replay onboarding and force the empty-library import path (0 screenshots).
    func replayEmptyLibraryOnboarding() {
        replayOnboarding()
        onboarding.simulateEmptyLibrary = true
    }

    #if DEBUG
    /// Wipes SQLite and reseeds fixtures. Does not change onboarding completion.
    func resetDatabaseAndReseed() async {
        do {
            try await DatabaseMaintenance.resetAndReseed(database)
            noteMemoryMutation()
            feedback.show("Database reset")
            AppLog.general.info("DEBUG database reset + reseed complete")
        } catch {
            AppLog.general.error(
                "Database reset failed: \(error.localizedDescription, privacy: .public)"
            )
            feedback.show("Couldn't reset database")
        }
    }
    #endif
}

/// Bridges organization pipeline mutations back to `AppDependencies.memoryEpoch`.
final class OrganizationEpochBump: @unchecked Sendable {
    var handler: (@Sendable () -> Void)?

    func bump() {
        handler?()
    }
}
