#if DEBUG
import SwiftUI

/// DEBUG-only inspector for Collection Resolver decisions + evaluation labels.
struct ResolverDebugInspectorView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var snapshots: [OrganizationDebugSnapshot] = []
    @State private var metrics: OrganizationMetrics?
    @State private var evalStats: OrganizationEvalStats?
    @State private var gatewayRequests = 0
    @State private var policy = ResolverPolicy.current
    @State private var isLoading = true
    @State private var gatewayURL = UnderstandingGatewayConfiguration.displayURLString
    @State private var activeGatewayURL = UnderstandingGatewayConfiguration.displayURLString
    @State private var requeueMessage: String?
    @State private var gatewaySaveMessage: String?
    @State private var gatewayHealthMessage: String?
    @State private var isTestingGateway = false
    @State private var latestPipelineTrace: OrganizationPipelineTrace?
    @State private var pipelineRefreshTick = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: STSpacing.lg) {
                Text("Resolver Inspector")
                    .font(STTypography.greeting)
                    .foregroundStyle(STColor.label)

                gatewayBlock
                pipelineTraceBlock
                if let metrics { metricsBlock(metrics) }
                if let evalStats { evalBlock(evalStats) }
                policyBlock
                actionsBlock

                if let requeueMessage {
                    Text(requeueMessage)
                        .font(STTypography.rowMeta)
                        .foregroundStyle(STColor.primary)
                }

                if isLoading {
                    ProgressView()
                } else if snapshots.isEmpty {
                    Text("No screenshots yet.")
                        .foregroundStyle(STColor.secondaryLabel)
                } else {
                    ForEach(snapshots) { snap in
                        snapshotCard(snap)
                    }
                }
            }
            .padding(STSpacing.page)
            .padding(.bottom, STSpacing.tabBarHeight)
        }
        .background(STColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await reload() }
        .refreshable { await reload() }
        .onAppear {
            let active = UnderstandingGatewayConfiguration.displayURLString
            gatewayURL = active
            activeGatewayURL = active
        }
    }

    private var gatewayBlock: some View {
        VStack(alignment: .leading, spacing: STSpacing.sm) {
            Text("Gateway")
                .font(STTypography.sectionTitle)
                .foregroundStyle(STColor.label)

            Text("Editable DEBUG override — default is the hosted HTTPS gateway from Secrets.xcconfig (no Mac LAN required).")
                .font(STTypography.rowMeta)
                .foregroundStyle(STColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            TextField("https://….up.railway.app", text: $gatewayURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.asciiCapable)
                .font(STTypography.rowTitle)
                .foregroundStyle(STColor.label)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(STColor.secondaryLabel.opacity(0.35), lineWidth: 1)
                )
                .accessibilityLabel("Gateway URL")

            HStack(spacing: STSpacing.md) {
                Button("Save gateway URL") {
                    saveGatewayURL()
                }
                .font(STTypography.rowMeta.weight(.semibold))
                .foregroundStyle(STColor.primary)

                Button {
                    Task { await testGatewayConnection() }
                } label: {
                    if isTestingGateway {
                        ProgressView()
                    } else {
                        Text("Test Connection")
                            .font(STTypography.rowMeta.weight(.semibold))
                    }
                }
                .foregroundStyle(STColor.primary)
                .disabled(isTestingGateway)
            }

            if let gatewaySaveMessage {
                Text(gatewaySaveMessage)
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let gatewayHealthMessage {
                Text(gatewayHealthMessage)
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.label)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Active URL: \(activeGatewayURL)")
                .font(STTypography.rowMeta)
                .foregroundStyle(STColor.secondaryLabel)
                .textSelection(.enabled)

            Text("Provider resolves to: \(providerResolvedURLLabel)")
                .font(STTypography.rowMeta)
                .foregroundStyle(STColor.secondaryLabel)
                .textSelection(.enabled)

            Text("Cloud consent: \(CloudUnderstandingPreferences.consent.rawValue)")
                .font(STTypography.rowMeta)
                .foregroundStyle(
                    CloudUnderstandingPreferences.consent == .accepted
                        ? STColor.secondaryLabel
                        : STColor.destructive
                )

            Text("Local Network is only needed for an optional local Mac gateway. Hosted HTTPS does not require it.")
                .font(STTypography.rowMeta)
                .foregroundStyle(STColor.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            Text("Gateway token configured: \(UnderstandingGatewayConfiguration.gatewayBearerToken == nil ? "no" : "yes (MVP/TestFlight only)")")
                .font(STTypography.rowMeta)
                .foregroundStyle(STColor.secondaryLabel)

            Text("Cloud requests (local counter): \(gatewayRequests)")
                .font(STTypography.rowMeta)
                .foregroundStyle(STColor.secondaryLabel)
            Text("iOS never holds OpenAI keys — configure the ScreenTidy gateway.")
                .font(STTypography.rowMeta)
                .foregroundStyle(STColor.secondaryLabel)
        }
        .padding(STSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(STColor.pocket)
        )
    }

    private var providerResolvedURLLabel: String {
        UnderstandingGatewayConfiguration.baseURL(from: dependencies.configuration)?.absoluteString
            ?? "(none — on-device only)"
    }

    private var pipelineTraceBlock: some View {
        VStack(alignment: .leading, spacing: STSpacing.sm) {
            Text("Latest pipeline attempt")
                .font(STTypography.sectionTitle)
                .foregroundStyle(STColor.label)

            if let trace = latestPipelineTrace {
                ForEach(trace.summaryLines, id: \.self) { line in
                    Text(line)
                        .font(STTypography.rowMeta)
                        .foregroundStyle(
                            trace.stage == .failed ? STColor.destructive : STColor.secondaryLabel
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No organize attempt traced yet. Use “Reprocess this screenshot” on one card.")
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Refresh pipeline trace") {
                latestPipelineTrace = OrganizationPipelineDebugStore.latest
                pipelineRefreshTick &+= 1
            }
            .font(STTypography.rowMeta.weight(.semibold))
            .foregroundStyle(STColor.primary)
        }
        .padding(STSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(STColor.pocket)
        )
        .id(pipelineRefreshTick)
    }

    private func saveGatewayURL() {
        do {
            let url = try UnderstandingGatewayConfiguration.validatedURL(from: gatewayURL)
            persistActiveGatewayURL(url)
            gatewaySaveMessage = "Saved. Next organize requests use \(url.absoluteString) (no reinstall needed)."
            gatewayHealthMessage = nil
        } catch {
            gatewaySaveMessage = "Save failed — \(error.localizedDescription)"
        }
    }

    private func testGatewayConnection() async {
        isTestingGateway = true
        defer { isTestingGateway = false }
        do {
            // Prefer the field text; fall back to the active persisted URL.
            let raw = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? activeGatewayURL
                : gatewayURL
            let url = try UnderstandingGatewayConfiguration.validatedURL(from: raw)
            persistActiveGatewayURL(url)
            switch await UnderstandingGatewayConfiguration.probeHealth(baseURL: url) {
            case .success(let health):
                var lines = ["Connected ✓"]
                lines.append("gateway reachable: \(health.endpoint)")
                if let schema = health.schemaVersion {
                    lines.append("schema version: \(schema)")
                }
                if let modelConfigured = health.modelConfigured {
                    lines.append("model configured: \(modelConfigured ? "yes" : "no (OPENAI_API_KEY missing)")")
                }
                gatewayHealthMessage = lines.joined(separator: "\n")
                gatewaySaveMessage = "Saved \(url.absoluteString)"
            case .failure(let failure):
                gatewayHealthMessage = "Connection failed — \(failure.localizedDescription)"
            }
        } catch {
            gatewayHealthMessage = "Connection failed — \(error.localizedDescription)"
        }
    }

    private func persistActiveGatewayURL(_ url: URL) {
        UnderstandingGatewayConfiguration.setOverrideURL(url.absoluteString)
        gatewayURL = url.absoluteString
        activeGatewayURL = url.absoluteString
    }

    private var policyBlock: some View {
        VStack(alignment: .leading, spacing: STSpacing.xs) {
            Text("Policy (tunable)")
                .font(STTypography.sectionTitle)
            Text("assign ≥ \(String(format: "%.2f", policy.assignThreshold))")
            Text("create ≥ \(String(format: "%.2f", policy.createThreshold)) + corroboration")
            Text("userCollectionAutoAdd = \(policy.userCollectionAutoAdd)")
            Text("resolverVersion = \(policy.resolverVersion)")
            Text("maxBatchSize = \(policy.maxBatchSize)")
            Text("image longEdge=\(Int(MultimodalImagePolicy.current.longEdge)) jpeg=\(MultimodalImagePolicy.current.jpegQuality)")
            Text("cloudConsent = \(CloudUnderstandingPreferences.consent.rawValue)")
        }
        .font(STTypography.rowMeta)
        .foregroundStyle(STColor.secondaryLabel)
    }

    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: STSpacing.sm) {
            Text("Actions")
                .font(STTypography.sectionTitle)
            Button("Kick organization queue (pendingNetwork recovery)") {
                dependencies.organizationScheduler.kick()
                requeueMessage = "Organization queue kicked — pendingNetwork items reclaim after 15s backoff (or use Reprocess on one card)."
                Task { await reload() }
            }
            .font(STTypography.rowMeta.weight(.semibold))
            .foregroundStyle(STColor.primary)

            Button("Re-run Needs Review organization") {
                Task {
                    let count = try? await dependencies.organizationStore.requeueNeedsReviewForResolver(
                        version: policy.resolverVersion
                    )
                    dependencies.organizationScheduler.kick()
                    requeueMessage = "Requeued \(count ?? 0) screenshots for resolver v\(policy.resolverVersion)"
                    await reload()
                }
            }
            .font(STTypography.rowMeta)
        }
    }

    private func metricsBlock(_ metrics: OrganizationMetrics) -> some View {
        VStack(alignment: .leading, spacing: STSpacing.xs) {
            Text("Queue")
                .font(STTypography.sectionTitle)
            Text("pending \(metrics.pending) · pendingNetwork \(metrics.pendingNetwork) · ready \(metrics.ready)")
            Text("failed \(metrics.failed) · locked \(metrics.locked) · skippedConsent \(metrics.skippedNoConsent)")
        }
        .font(STTypography.rowMeta)
        .foregroundStyle(STColor.secondaryLabel)
    }

    private func evalBlock(_ stats: OrganizationEvalStats) -> some View {
        VStack(alignment: .leading, spacing: STSpacing.xs) {
            Text("DEBUG evaluation")
                .font(STTypography.sectionTitle)
            Text("evaluated \(stats.totalEvaluated) · coverage \(pct(stats.autoFileCoverage))")
            Text("correct \(pct(stats.correctRate)) · wrong-file \(pct(stats.wrongFileRate)) · NR \(pct(stats.needsReviewRate))")
            Text("reuse✓ \(stats.reuseCorrect) · create✓ \(stats.createCorrect) · wrong-name \(stats.wrongName) · should-NR \(stats.shouldBeNeedsReview)")
        }
        .font(STTypography.rowMeta)
        .foregroundStyle(STColor.secondaryLabel)
    }

    private func snapshotCard(_ snap: OrganizationDebugSnapshot) -> some View {
        VStack(alignment: .leading, spacing: STSpacing.sm) {
            HStack(alignment: .top, spacing: STSpacing.md) {
                PhotosThumbnailImage(
                    localIdentifier: snap.photosLocalIdentifier,
                    targetSize: CGSize(width: 72, height: 96),
                    contentMode: .aspectFill,
                    allowsNetworkAccess: true
                ) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(STColor.pocket)
                }
                .frame(width: 56, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(snap.titleHint)
                        .font(STTypography.rowTitle)
                        .foregroundStyle(STColor.label)
                        .lineLimit(2)
                    Text("status: \(snap.organizeStatus.rawValue) · resolver v\(snap.resolverVersion.map(String.init) ?? "—")")
                    if snap.locked {
                        Text("LOCKED (user authoritative)")
                            .foregroundStyle(STColor.destructive)
                    }
                    if let kind = snap.decisionKind {
                        Text("decision: \(kind.rawValue.uppercased()) \(snap.decisionTitle.map { "→ \($0)" } ?? "") \(snap.proposedEmoji ?? "")")
                            .foregroundStyle(STColor.primary)
                    }
                    if let provider = snap.provider {
                        Text("provider: \(provider)")
                    }
                }
            }

            if let conf = snap.maxConfidence, let assign = snap.assignThreshold {
                Text("final \(String(format: "%.2f", conf)) · assign \(String(format: "%.2f", assign)) · create \(String(format: "%.2f", snap.createThreshold ?? policy.createThreshold))")
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
            }

            if let components = snap.confidenceComponents {
                Text("scores p=\(fmt(components.provider)) profile=\(fmt(components.profileMatch)) entity=\(fmt(components.entityOverlap)) tv=\(fmt(components.textVisualAgreement)) batch=\(fmt(components.batchCorroboration)) conflict=-\(fmt(components.conflictPenalty)) → \(fmt(components.final)) corr=\(components.createCorroborated)")
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if snap.ocrAvailable {
                Text("OCR: \(snap.ocrPreview ?? "yes")")
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .lineLimit(2)
            } else {
                Text("OCR: empty (image-only path)")
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
            }
            if let normalized = snap.normalizedOCRPreview {
                Text("normalized: \(normalized)")
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .lineLimit(2)
            }

            if !snap.entities.isEmpty {
                Text("entities: " + snap.entities.map { "\($0.type):\($0.value)" }.joined(separator: ", "))
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .lineLimit(2)
            }
            if !snap.visualDescriptors.isEmpty {
                Text("visual: " + snap.visualDescriptors.joined(separator: ", "))
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .lineLimit(2)
            }
            if !snap.typeFacets.isEmpty {
                Text("typeFacets: " + snap.typeFacets.joined(separator: ", "))
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
            }
            if let batchID = snap.batchID {
                Text("batch (\(snap.batchMemberCount ?? 0)): \(batchID)")
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .lineLimit(2)
            }

            if let reason = snap.reason {
                Text(reason)
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !snap.candidates.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Candidates / profiles considered")
                        .font(STTypography.rowMeta.weight(.semibold))
                    ForEach(Array(snap.candidates.enumerated()), id: \.offset) { _, candidate in
                        Text("\(candidate.title) — \(String(format: "%.2f", candidate.confidence)) \(candidate.reasonSignals.joined(separator: ","))")
                            .font(STTypography.rowMeta)
                            .foregroundStyle(STColor.secondaryLabel)
                    }
                }
            }

            if !snap.memberships.isEmpty {
                Text("memberships: " + snap.memberships.map { "\($0.title)(\($0.source))" }.joined(separator: ", "))
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.secondaryLabel)
            }

            evalButtons(for: snap)

            Button("Reprocess this screenshot") {
                Task {
                    try? await dependencies.organizationStore.requeueSingleOrganize(id: snap.id)
                    OrganizationPipelineDebugStore.reset(screenshotID: snap.id)
                    dependencies.organizationScheduler.kick()
                    requeueMessage = "Reprocessing one screenshot (\(snap.id.rawValue.uuidString.prefix(8))…)"
                    // Poll briefly so Latest pipeline attempt updates without full backlog requeue.
                    for _ in 0..<12 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        latestPipelineTrace = OrganizationPipelineDebugStore.trace(for: snap.id)
                            ?? OrganizationPipelineDebugStore.latest
                        pipelineRefreshTick &+= 1
                        if latestPipelineTrace?.stage == .completed
                            || latestPipelineTrace?.stage == .failed {
                            break
                        }
                    }
                    await reload()
                }
            }
            .font(STTypography.rowMeta.weight(.semibold))
            .foregroundStyle(STColor.primary)

            if let err = snap.lastError {
                Text("error: \(err)")
                    .font(STTypography.rowMeta)
                    .foregroundStyle(STColor.destructive)
            }

            if let trace = OrganizationPipelineDebugStore.trace(for: snap.id) {
                Text("pipeline: \(trace.stage.displayName) — \(trace.detail)")
                    .font(STTypography.rowMeta)
                    .foregroundStyle(trace.stage == .failed ? STColor.destructive : STColor.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(STSpacing.md)
        .background(RoundedRectangle(cornerRadius: 12).fill(STColor.pocket))
    }

    private func evalButtons(for snap: OrganizationDebugSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Eval label: \(snap.evalLabel?.rawValue ?? "none")")
                .font(STTypography.rowMeta.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(OrganizationEvalLabel.allCases, id: \.rawValue) { label in
                    Button(shortLabel(label)) {
                        Task {
                            try? await dependencies.organizationStore.setOrganizationEvalLabel(
                                screenshotID: snap.id,
                                label: label
                            )
                            await reload()
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func shortLabel(_ label: OrganizationEvalLabel) -> String {
        switch label {
        case .correct: "Correct"
        case .wrongCollection: "Wrong coll"
        case .shouldBeNeedsReview: "Should NR"
        case .wrongCollectionName: "Wrong name"
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        policy = .current
        let active = UnderstandingGatewayConfiguration.displayURLString
        gatewayURL = active
        activeGatewayURL = active
        metrics = try? await dependencies.organizationStore.fetchOrganizationMetrics()
        evalStats = try? await dependencies.organizationStore.fetchOrganizationEvalStats()
        gatewayRequests = (try? await dependencies.organizationStore.fetchCloudRequestCount()) ?? 0
        snapshots = (try? await dependencies.organizationStore.fetchOrganizationDebugSnapshots(limit: 40)) ?? []
        latestPipelineTrace = OrganizationPipelineDebugStore.latest
    }

    private func pct(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
#endif
