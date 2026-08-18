import SwiftUI

/// Settings — Quiet Pocket grid (24pt), calm Apple-like section rhythm.
struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var photosStatus: PhotosAccessStatus = .notDetermined

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(STTypography.greeting)
                    .foregroundStyle(STColor.label)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, STSpacing.lg)

                VStack(alignment: .leading, spacing: STSpacing.settingsSectionGap) {
                    librarySection
                    organizationSection
                    aboutSection(dependencies: dependencies)
                    developerSection(dependencies: dependencies)
                }

                Text("Your screenshots stay in Photos. ScreenTidy keeps them organized on this device.")
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, STSpacing.md)
            }
            .padding(.horizontal, STSpacing.page)
            .padding(.top, STSpacing.lg)
            .padding(.bottom, STSpacing.tabBarHeight + STSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .stTabRootAtmosphere()
        }
        .coordinateSpace(name: STHomeAtmosphereTokens.scrollCoordinateSpace)
        .stTabRootScrollBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            photosStatus = await dependencies.photosProvider.authorizationStatus
        }
    }

    private var librarySection: some View {
        SettingsSection(title: "Library") {
            SettingsRow(title: "Photos") {
                HStack(spacing: STSpacing.sm) {
                    Text(photosStatus.settingsLabel)
                        .font(STTypography.rowMeta)
                        .foregroundStyle(STColor.secondaryLabel)
                    if photosStatus == .limited {
                        Button("Manage") {
                            Task { @MainActor in
                                await dependencies.photosProvider.presentLimitedLibraryPicker()
                                photosStatus = await dependencies.photosProvider.authorizationStatus
                            }
                        }
                        .font(STTypography.rowMeta)
                    }
                }
            }
        }
    }

    private var organizationSection: some View {
        SettingsSection(title: "Organization") {
            VStack(spacing: 0) {
                SettingsRow(title: "Cloud understanding") {
                    Text(cloudConsentLabel)
                        .font(STTypography.rowMeta)
                        .foregroundStyle(STColor.secondaryLabel)
                }
                if CloudUnderstandingPreferences.consent != .notDetermined {
                    Divider().padding(.leading, STSpacing.lg)
                    Button {
                        dependencies.showCloudUnderstandingDisclosure = true
                    } label: {
                        Text("Review cloud understanding")
                            .font(STTypography.rowTitle)
                            .foregroundStyle(STColor.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, STSpacing.lg)
                    .padding(.vertical, STSpacing.settingsRowVertical)
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private var cloudConsentLabel: String {
        switch CloudUnderstandingPreferences.consent {
        case .notDetermined: "Not decided"
        case .accepted: "On"
        case .declined: "Off"
        }
    }

    private func aboutSection(dependencies: AppDependencies) -> some View {
        SettingsSection(title: "About") {
            VStack(spacing: 0) {
                SettingsRow(title: "Environment") {
                    Text(dependencies.configuration.environment.rawValue.capitalized)
                        .font(STTypography.rowMeta)
                        .foregroundStyle(STColor.secondaryLabel)
                }
                Divider().padding(.leading, STSpacing.lg)
                SettingsRow(title: "Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                        .font(STTypography.rowMeta)
                        .foregroundStyle(STColor.secondaryLabel)
                }
            }
        }
    }

    private func developerSection(dependencies: AppDependencies) -> some View {
        SettingsSection(title: "Developer") {
            VStack(spacing: 0) {
                Button {
                    dependencies.replayOnboarding()
                } label: {
                    Text("Replay Onboarding")
                        .font(STTypography.rowTitle)
                        .foregroundStyle(STColor.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, STSpacing.lg)
                .padding(.vertical, STSpacing.settingsRowVertical)
                .frame(minHeight: 44)

                #if DEBUG
                Divider().padding(.leading, STSpacing.lg)
                Button {
                    dependencies.replayEmptyLibraryOnboarding()
                } label: {
                    Text("Empty Library Onboarding")
                        .font(STTypography.rowTitle)
                        .foregroundStyle(STColor.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, STSpacing.lg)
                .padding(.vertical, STSpacing.settingsRowVertical)
                .frame(minHeight: 44)
                .accessibilityHint("Replays onboarding with zero screenshots found")

                Divider().padding(.leading, STSpacing.lg)
                Button {
                    Task { await dependencies.resetDatabaseAndReseed() }
                } label: {
                    Text("Reset Database & Reseed")
                        .font(STTypography.rowTitle)
                        .foregroundStyle(STColor.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, STSpacing.lg)
                .padding(.vertical, STSpacing.settingsRowVertical)
                .frame(minHeight: 44)
                .accessibilityHint("Deletes local SQLite data and restores Sprint 3 fixtures")

                Divider().padding(.leading, STSpacing.lg)
                NavigationLink {
                    OCRDebugInspectorView()
                } label: {
                    Text("OCR Inspector")
                        .font(STTypography.rowTitle)
                        .foregroundStyle(STColor.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, STSpacing.lg)
                .padding(.vertical, STSpacing.settingsRowVertical)
                .frame(minHeight: 44)

                Divider().padding(.leading, STSpacing.lg)
                NavigationLink {
                    VisualIntelligenceDebugInspectorView()
                } label: {
                    Text("Visual Intelligence")
                        .font(STTypography.rowTitle)
                        .foregroundStyle(STColor.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, STSpacing.lg)
                .padding(.vertical, STSpacing.settingsRowVertical)
                .frame(minHeight: 44)

                Divider().padding(.leading, STSpacing.lg)
                NavigationLink {
                    ResolverDebugInspectorView()
                } label: {
                    Text("Resolver Inspector")
                        .font(STTypography.rowTitle)
                        .foregroundStyle(STColor.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, STSpacing.lg)
                .padding(.vertical, STSpacing.settingsRowVertical)
                .frame(minHeight: 44)
                #endif
            }
        }
    }
}

// MARK: - Settings primitives (24pt page grid)

private struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(STTypography.caption)
                .foregroundStyle(STColor.secondaryLabel)
                .textCase(.uppercase)
                .tracking(0.4)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(STColor.pocket)
                .clipShape(RoundedRectangle(cornerRadius: STRadius.settingsGroup, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: STRadius.settingsGroup, style: .continuous)
                        .strokeBorder(STColor.hairline, lineWidth: 0.5)
                }
                .stCardShadow()
                .padding(.top, STSpacing.settingsLabelToCard)

            if let footer {
                Text(footer)
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, STSpacing.settingsCardToFooter)
            }
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(STTypography.rowTitle)
                .foregroundStyle(STColor.label)
            Spacer(minLength: STSpacing.sm)
            trailing()
        }
        .padding(.horizontal, STSpacing.lg)
        .padding(.vertical, STSpacing.settingsRowVertical)
        .frame(minHeight: 44)
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
    }
    .environment(AppDependencies())
    .appTheme(.default)
}
