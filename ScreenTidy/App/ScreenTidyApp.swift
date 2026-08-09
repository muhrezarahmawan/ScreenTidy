import SwiftUI

@main
struct ScreenTidyApp: App {
    @State private var dependencies = AppDependencies()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView(dependencies: dependencies)
                .environment(dependencies)
                .appTheme(.default)
                .onAppear {
                    AppLog.general.info("ScreenTidy launched")
                    dependencies.syncPhotosOnLaunch()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        dependencies.syncPhotosOnLaunch()
                    }
                }
        }
    }
}

/// Observes completion on `AppDependencies` itself (not a nested session).
private struct AppRootView: View {
    @Bindable var dependencies: AppDependencies

    var body: some View {
        Group {
            if dependencies.hasCompletedOnboarding {
                RootView()
            } else {
                OnboardingFlowView()
                    .id(dependencies.onboardingPresentationID)
            }
        }
    }
}
