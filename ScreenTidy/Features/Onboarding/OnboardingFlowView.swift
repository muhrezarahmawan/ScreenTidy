import SwiftUI

/// Sprint 2 mock onboarding — Quiet Pocket language, no Photos/network AI wiring.
/// Flow: Welcome → Photos → Import → Organizing/Empty → Home (organization always on).
struct OnboardingFlowView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: OnboardingViewModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let viewModel {
                onboardingBody(viewModel)
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            viewModel.handleAppBecameActive()
                        }
                    }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(STColor.background.ignoresSafeArea())
                    .task {
                        viewModel = OnboardingViewModel(
                            memory: dependencies.memoryStore,
                            photos: dependencies.photosProvider,
                            sync: dependencies.screenshotSync,
                            shouldSimulateEmptyLibrary: {
                                dependencies.onboarding.simulateEmptyLibrary
                            },
                            onComplete: { dependencies.completeOnboarding() }
                        )
                    }
            }
        }
    }

    @ViewBuilder
    private func onboardingBody(_ viewModel: OnboardingViewModel) -> some View {
        @Bindable var viewModel = viewModel
        ZStack {
            STColor.background.ignoresSafeArea()
            STOnboardingAtmosphere()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                OnboardingProgressIndicator(
                    stage: viewModel.step.progressStage,
                    total: OnboardingProgress.totalStages,
                    stageName: viewModel.step.progressAccessibilityName
                )
                .padding(.horizontal, STSpacing.page)
                .padding(.top, STSpacing.lg)
                .padding(.bottom, STSpacing.sm)

                OnboardingCarouselPager(viewModel: viewModel, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHint("Swipe left to continue, swipe right to go back")
    }
}

// MARK: - Interactive carousel

/// Native paging carousel — page position tracks the finger in realtime.
private struct OnboardingCarouselPager: View {
    @Bindable var viewModel: OnboardingViewModel
    let reduceMotion: Bool

    @State private var scrollStep: OnboardingStep?
    @State private var isProgrammaticScroll = false

    /// Swipeable strip for the current branch of the flow.
    private var pages: [OnboardingStep] {
        switch viewModel.step {
        case .welcome, .photosPermission:
            return [.welcome, .photosPermission]
        case .photosDenied:
            return [.photosPermission, .photosDenied]
        case .importing, .emptyLibrary, .organizing:
            return [viewModel.step]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = max(geo.size.height, 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(pages, id: \.self) { step in
                        stepContent(step, interactive: step == viewModel.step)
                            .frame(width: width, height: height)
                            .id(step)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollStep)
            .scrollDisabled(pages.count < 2)
            .onAppear {
                scrollStep = viewModel.step
            }
            .onChange(of: viewModel.step) { _, newStep in
                guard scrollStep != newStep else { return }
                isProgrammaticScroll = true
                withAnimation(reduceMotion ? .easeInOut(duration: STMotion.quickDuration) : .smooth(duration: 0.3)) {
                    scrollStep = newStep
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isProgrammaticScroll = false
                }
            }
            .onChange(of: scrollStep) { _, newStep in
                guard let newStep, !isProgrammaticScroll, newStep != viewModel.step else { return }
                viewModel.commitCarouselPage(newStep)
            }
        }
    }

    @ViewBuilder
    private func stepContent(_ step: OnboardingStep, interactive: Bool) -> some View {
        Group {
            switch step {
            case .welcome:
                WelcomeOnboardingStep {
                    viewModel.goToWelcomeContinue()
                }
            case .photosPermission:
                PhotosPermissionOnboardingStep {
                    viewModel.allowFullPhotos()
                }
            case .photosDenied:
                PhotosDeniedOnboardingStep(
                    onEnablePhotos: { viewModel.enablePhotosAccess() },
                    onExit: { viewModel.exitScreenTidy() }
                )
            case .importing:
                ImportOnboardingStep(progress: viewModel.importProgress)
            case .emptyLibrary:
                EmptyLibraryOnboardingStep {
                    viewModel.continueFromEmptyLibrary()
                }
            case .organizing:
                OrganizingOnboardingStep(
                    collections: viewModel.libraryCollections,
                    revealedCount: viewModel.organizingRevealCount,
                    onContinue: { viewModel.finishOrganizing() }
                )
            }
        }
        .allowsHitTesting(interactive)
        .accessibilityHidden(!interactive)
    }
}

// MARK: - Progress

/// Quiet Pocket progress — minimal dots (not a form wizard).
/// VoiceOver: “Step 2 of 4, Photos access”.
private struct OnboardingProgressIndicator: View {
    let stage: Int
    let total: Int
    let stageName: String

    var body: some View {
        HStack(spacing: 7) {
            ForEach(1...total, id: \.self) { index in
                Circle()
                    .fill(dotColor(for: index))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stage) of \(total), \(stageName)")
        .animation(STMotion.pressAnimation, value: stage)
    }

    private func dotColor(for index: Int) -> Color {
        if index < stage {
            return STColor.label.opacity(0.35)
        }
        if index == stage {
            return STColor.label.opacity(0.85)
        }
        return STColor.secondaryLabel.opacity(0.22)
    }
}

// MARK: - Shared chrome

private struct OnboardingStepLayout<Content: View, Footer: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    private var showsFooter: Bool { Footer.self != EmptyView.self }

    var body: some View {
        ScrollView {
            content()
                .padding(.horizontal, STSpacing.page)
                .padding(.top, STSpacing.lg)
                .padding(.bottom, STSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Vertical scroll steals the horizontal carousel pan — pages are sized to fit.
        .scrollDisabled(true)
        .scrollBounceBehavior(.basedOnSize)
        // Pin primary actions to the bottom safe area — home indicator provides clearance (HIG).
        // Avoid stacking large extra bottom padding on top of the safe area.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsFooter {
                VStack(spacing: STSpacing.md) {
                    footer()
                }
                .padding(.horizontal, STSpacing.page)
                .padding(.top, STSpacing.md)
                .padding(.bottom, STSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            STColor.background.opacity(0),
                            STColor.background.opacity(0.92),
                            STColor.background
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}

extension OnboardingStepLayout where Footer == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.footer = { EmptyView() }
    }
}

private struct OnboardingEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(STTypography.caption)
            .foregroundStyle(STColor.secondaryLabel)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

// MARK: - Welcome

private struct WelcomeOnboardingStep: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepLayout {
            VStack(alignment: .leading, spacing: STSpacing.homeSection) {
                OnboardingEyebrow(text: "ScreenTidy")

                Text("Your screenshots,\nquietly organized.")
                    .font(STTypography.greeting)
                    .foregroundStyle(STColor.label)
                    .fixedSize(horizontal: false, vertical: true)

                Text("ScreenTidy automatically organizes your screenshots into Collections for trips, projects, plans, and more.")
                    .font(STTypography.aiLine)
                    .foregroundStyle(STColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                // Soft preview of the signature pocket language (same component as Home).
                // Welcome uses store fixtures for atmosphere; Organizing uses live promoted library.
                HStack(spacing: STSpacing.collectionGridGutter) {
                    ForEach(Array(MockData.contexts.filter { $0.memberCount >= 3 }.prefix(2))) { context in
                        ContextCollectionPocketView(collection: context)
                    }
                }
                .padding(.top, STSpacing.sm)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                Text("Your screenshots stay in Photos. ScreenTidy keeps them organized without moving them.")
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .padding(.top, STSpacing.sm)
            }
        } footer: {
            STPrimaryButton(title: "Continue", action: onContinue)
        }
    }
}

// MARK: - Photos permission

private struct PhotosPermissionOnboardingStep: View {
    let onAllow: () -> Void

    var body: some View {
        OnboardingStepLayout {
            VStack(alignment: .leading, spacing: STSpacing.lg) {
                OnboardingEyebrow(text: "Photos")

                Text("Allow access to your\nscreenshots")
                    .font(STTypography.greeting)
                    .foregroundStyle(STColor.label)

                Text("ScreenTidy uses your screenshots to automatically organize them into Collections.")
                    .font(STTypography.aiLine)
                    .foregroundStyle(STColor.secondaryLabel)

                STPrimaryCard {
                    VStack(alignment: .leading, spacing: STSpacing.sm) {
                        Label("Screenshots stay in Photos", systemImage: "photo.on.rectangle")
                        Label("ScreenTidy only organizes your screenshots", systemImage: "square.stack.3d.up")
                        Label("You can change access later in Settings", systemImage: "gearshape")
                    }
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                }
                .padding(.top, STSpacing.sm)
            }
        } footer: {
            STPrimaryButton(title: "Allow Access", action: onAllow)
        }
    }
}

private struct PhotosDeniedOnboardingStep: View {
    let onEnablePhotos: () -> Void
    let onExit: () -> Void

    var body: some View {
        OnboardingStepLayout {
            VStack(alignment: .leading, spacing: STSpacing.lg) {
                OnboardingEyebrow(text: "Photos")

                Text("Photos access is required")
                    .font(STTypography.greeting)
                    .foregroundStyle(STColor.label)

                Text("ScreenTidy organizes your screenshots into Collections.\n\nWithout access to your screenshots, ScreenTidy can’t work.\n\nYou can enable Photos access in Settings and return to continue.")
                    .font(STTypography.aiLine)
                    .foregroundStyle(STColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            STPrimaryButton(title: "Enable Photos Access", action: onEnablePhotos)
            STSecondaryButton(title: "Exit ScreenTidy", action: onExit)
        }
    }
}

// MARK: - Import

private struct ImportOnboardingStep: View {
    let progress: Double

    var body: some View {
        OnboardingStepLayout {
            VStack(alignment: .leading, spacing: STSpacing.lg) {
                OnboardingEyebrow(text: "Import")

                Text("Finding your screenshots")
                    .font(STTypography.greeting)
                    .foregroundStyle(STColor.label)

                Text("Gathering your screenshots so ScreenTidy can organize them.")
                    .font(STTypography.aiLine)
                    .foregroundStyle(STColor.secondaryLabel)

                ProgressView(value: progress)
                    .tint(STColor.primary)
                    .padding(.top, STSpacing.md)

                Text("\(Int(progress * 100))%")
                    .font(STTypography.pocketMeta)
                    .foregroundStyle(STColor.secondaryLabel)
            }
        }
    }
}

// MARK: - Empty library

private struct EmptyLibraryOnboardingStep: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepLayout {
            VStack(alignment: .leading, spacing: STSpacing.lg) {
                OnboardingEyebrow(text: "Ready")

                Text("No screenshots yet")
                    .font(STTypography.greeting)
                    .foregroundStyle(STColor.label)

                Text("When you capture screenshots, ScreenTidy will quietly organize them into Collections. You can explore the app now.")
                    .font(STTypography.aiLine)
                    .foregroundStyle(STColor.secondaryLabel)
            }
        } footer: {
            STPrimaryButton(title: "Go to Home", action: onContinue)
        }
    }
}

// MARK: - Organizing

private struct OrganizingOnboardingStep: View {
    let collections: [ContextCollection]
    let revealedCount: Int
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: STSpacing.collectionGridGutter),
        GridItem(.flexible(), spacing: STSpacing.collectionGridGutter)
    ]

    var body: some View {
        OnboardingStepLayout {
            VStack(alignment: .leading, spacing: STSpacing.lg) {
                OnboardingEyebrow(text: "Organizing")

                Text("Organizing your screenshots")
                    .font(STTypography.greeting)
                    .foregroundStyle(STColor.label)

                Text("ScreenTidy is grouping your screenshots into Collections based on what they’re about.")
                    .font(STTypography.aiLine)
                    .foregroundStyle(STColor.secondaryLabel)

                LazyVGrid(columns: columns, spacing: STSpacing.collectionGridRow) {
                    ForEach(Array(collections.prefix(revealedCount))) { context in
                        // Exact Home signature component — single source of truth (D-022).
                        ContextCollectionPocketView(collection: context)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(.top, STSpacing.sm)
                .animation(.easeOut(duration: 0.35), value: revealedCount)
            }
        } footer: {
            STPrimaryButton(title: "Continue to Home", action: onContinue)
        }
    }
}

#Preview("Onboarding") {
    OnboardingFlowView()
        .environment(AppDependencies())
        .appTheme(.default)
}
