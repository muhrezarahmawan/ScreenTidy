#if DEBUG
import SwiftUI
import UIKit

/// DEBUG-only Visual Understanding evaluation (Sprint 8.1).
/// Vision labels are evidence only — never Collection titles.
struct VisualIntelligenceDebugInspectorView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var counts = VisualAnalysisStatusCounts(
        pending: 0,
        processing: 0,
        completed: 0,
        failed: 0,
        inaccessible: 0
    )
    @State private var failureSummary = VisualFailureSummary(
        totalFailed: 0,
        byErrorCode: [],
        attemptBuckets: []
    )
    @State private var rows: [VisualAnalysisDebugSnapshot] = []
    @State private var failedRows: [VisualAnalysisDebugSnapshot] = []
    @State private var diagnostics = VisualAnalysisQueueDiagnostics()
    @State private var isPolling = false
    @State private var isLoadingMore = false
    @State private var hasMoreRows = false
    @State private var overrideEnabled = VisualAnalysisDebugRuntime.isFilterOverrideEnabled()
    @State private var overrideFloor = Double(VisualLabelFilter.Settings.production.confidenceFloor)
    @State private var overrideMax = Double(VisualLabelFilter.Settings.production.maxCount)

    var body: some View {
        List {
            Section("Visual Pipeline") {
                LabeledContent("Classify version", value: "\(VisualAnalysisPipeline.classifyVersion)")
                LabeledContent("Feature-print version", value: "\(VisualAnalysisPipeline.featurePrintVersion)")
                Text(VisualAnalysisPipeline.analysisInputLongEdgeNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                LabeledContent("Pending", value: "\(counts.pending)")
                LabeledContent("Completed", value: "\(counts.completed)")
                LabeledContent("Completed · FP failed", value: "\(counts.completedFeaturePrintFailed)")
                LabeledContent("Failed", value: "\(counts.failed)")
                LabeledContent("Inaccessible", value: "\(counts.inaccessible)")
            }

            Section {
                Toggle("DEBUG filter override (does not change production defaults)", isOn: $overrideEnabled)
                    .onChange(of: overrideEnabled) { _, enabled in
                        applyOverride()
                    }
                if overrideEnabled {
                    VStack(alignment: .leading) {
                        Text(String(format: "Confidence floor %.2f", overrideFloor))
                        Slider(value: $overrideFloor, in: 0.05...0.80, step: 0.01)
                            .onChange(of: overrideFloor) { _, _ in applyOverride() }
                        Text("Max filtered labels \(Int(overrideMax))")
                        Slider(value: $overrideMax, in: 1...16, step: 1)
                            .onChange(of: overrideMax) { _, _ in applyOverride() }
                    }
                    Text("Overrides apply to new classify / reprocess while enabled. Production path uses floor \(VisualAnalysisPipeline.confidenceFloor) / max \(VisualAnalysisPipeline.maxPersistedLabels) when override is off.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("DEBUG filter experiment")
            }

            Section("Failure summary") {
                LabeledContent("Failed total", value: "\(failureSummary.totalFailed)")
                if failureSummary.byErrorCode.isEmpty {
                    Text("No failed rows.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(failureSummary.byErrorCode) { row in
                        LabeledContent(row.code, value: "\(row.count)")
                    }
                }
            }

            Section("Worker") {
                LabeledContent("State", value: diagnostics.workerState.rawValue)
                LabeledContent("Last wake", value: format(diagnostics.lastWakeAt))
                LabeledContent("Processed this session", value: "\(diagnostics.processedThisSession)")
                LabeledContent("Last queue error", value: diagnostics.lastError ?? "—")
            }

            Section("Actions") {
                Button("Kick Visual Queue") {
                    dependencies.visualScheduler.kick()
                    Task { await pollAfterKick() }
                }
                Button("Reprocess All Visual", role: .destructive) {
                    Task {
                        await dependencies.visualScheduler.reprocessAll()
                        await pollAfterKick()
                    }
                }
            }

            if !failedRows.isEmpty {
                Section("Failed screenshots (≤40)") {
                    ForEach(failedRows) { row in
                        NavigationLink {
                            VisualIntelligenceFailedDetailView(snapshot: row)
                        } label: {
                            VisualIntelligenceFailedRowView(row: row)
                        }
                    }
                }
            }

            Section {
                if rows.isEmpty {
                    Text(counts.completed == 0
                         ? "No completed Visual analysis yet."
                         : "No screenshots in this page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        NavigationLink {
                            VisualIntelligenceDebugDetailView(listSeed: row)
                        } label: {
                            VisualIntelligenceDebugRowView(row: row)
                        }
                        .onAppear {
                            if row.id == rows.last?.id {
                                Task { await loadMoreRowsIfNeeded() }
                            }
                        }
                    }
                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            } header: {
                Text(evaluateSectionTitle)
            } footer: {
                Text("Scroll to browse all completed Visual analysis. Open a shot to compare RAW vs FILTERED labels, feature-print neighbors (thumbnails), and cluster members. Formal Sprint 8.1 sample is still ~10–20 diverse shots. Vision nouns never become Collection names.")
            }
        }
        .navigationTitle("Visual Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var evaluateSectionTitle: String {
        if counts.completed > 0 {
            return "Evaluate screenshots · \(counts.completed)"
        }
        return "Evaluate screenshots"
    }

    private func applyOverride() {
        var settings = VisualLabelFilter.Settings.production
        settings.confidenceFloor = Float(overrideFloor)
        settings.maxCount = Int(overrideMax)
        VisualAnalysisDebugRuntime.setFilterOverride(enabled: overrideEnabled, settings: settings)
    }

    private func reload() async {
        counts = (try? await dependencies.visualStore.fetchVisualStatusCounts()) ?? counts
        failureSummary = (try? await dependencies.visualStore.fetchVisualFailureSummary()) ?? failureSummary
        failedRows = (try? await dependencies.visualStore.fetchVisualFailedDebugSnapshots(limit: 40)) ?? []
        let pageSize = VisualAnalysisPipeline.debugListPageSize
        let page = (try? await dependencies.visualStore.fetchVisualDebugListPage(offset: 0, limit: pageSize)) ?? []
        rows = page
        hasMoreRows = page.count == pageSize
        isLoadingMore = false
        diagnostics = VisualAnalysisDebugRuntime.current()
        overrideEnabled = VisualAnalysisDebugRuntime.isFilterOverrideEnabled()
    }

    private func loadMoreRowsIfNeeded() async {
        guard hasMoreRows, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let pageSize = VisualAnalysisPipeline.debugListPageSize
        let offset = rows.count
        let page = (try? await dependencies.visualStore.fetchVisualDebugListPage(offset: offset, limit: pageSize)) ?? []
        let existing = Set(rows.map(\.id))
        let appended = page.filter { !existing.contains($0.id) }
        rows.append(contentsOf: appended)
        hasMoreRows = page.count == pageSize
    }

    private func pollAfterKick() async {
        guard !isPolling else {
            await reload()
            return
        }
        isPolling = true
        defer { isPolling = false }
        for _ in 0..<40 {
            await reload()
            if counts.pending == 0 && counts.processing == 0 { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        await reload()
    }

    private func format(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .standard)
    }
}

private struct VisualIntelligenceFailedRowView: View {
    let row: VisualAnalysisDebugSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            debugThumb(localID: row.photosLocalIdentifier)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.visualLastError ?? "failed")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("attempts \(row.visualAttemptCount) · FP \(row.featurePrintStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct VisualIntelligenceFailedDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    let snapshot: VisualAnalysisDebugSnapshot
    @State private var isReprocessing = false

    var body: some View {
        List {
            Section("Thumbnail") {
                largeThumb(localID: snapshot.photosLocalIdentifier)
            }
            Section("Failure") {
                LabeledContent("Last error", value: snapshot.visualLastError ?? "—")
                LabeledContent("Attempts", value: "\(snapshot.visualAttemptCount)")
            }
            Section {
                Button("Reprocess this screenshot") {
                    Task {
                        isReprocessing = true
                        await dependencies.visualScheduler.reprocess(id: snapshot.id)
                        isReprocessing = false
                    }
                }
                .disabled(isReprocessing)
            }
        }
        .navigationTitle("Failed Visual")
    }
}

private struct VisualIntelligenceDebugRowView: View {
    let row: VisualAnalysisDebugSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            debugThumb(localID: row.photosLocalIdentifier)
            VStack(alignment: .leading, spacing: 4) {
                Text(statusLine)
                    .font(.subheadline.weight(.semibold))
                Text(labelLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if row.isImageOnlyEvidence {
                    Text("Image-only / weak OCR")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        switch row.visualStatus {
        case .completed:
            if row.featurePrintStatus == "failed" {
                return row.labels.isEmpty ? "OK · FP failed · no labels" : "OK · FP failed"
            }
            return row.labels.isEmpty ? "OK · no labels" : "Visual OK"
        case .pending: return "Pending"
        case .processing: return "Processing…"
        case .failed: return row.visualLastError ?? "Failed"
        case .inaccessible: return "Inaccessible"
        }
    }

    private var labelLine: String {
        if row.labels.isEmpty {
            return "No filtered Vision labels"
        }
        return row.labels.prefix(4).map { "\($0.identifier) \(Int($0.confidence * 100))%" }.joined(separator: " · ")
    }
}

private struct VisualIntelligenceDebugDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    /// Lightweight list row seed; expensive neighbors/cluster load on appear.
    let listSeed: VisualAnalysisDebugSnapshot

    @State private var snapshot: VisualAnalysisDebugSnapshot
    @State private var isLoadingDetailExtras = true
    /// True only after a successful Live classify — never seeded from persisted rows.
    @State private var hasLiveEvaluation = false
    @State private var liveRaw: [VisualLabelObservation] = []
    @State private var liveFiltered: [VisualLabelObservation] = []
    @State private var liveDropped: [VisualLabelFilter.DroppedLabel] = []
    @State private var liveLongEdge: Int?
    @State private var liveError: String?
    @State private var isClassifying = false
    @State private var isReprocessing = false
    @State private var previewProbe = ThumbnailLoadProbe()
    @State private var previewEpoch = 0
    @State private var isTestingPhotoKit = false
    @State private var isolatedTestReport: String = "—"
    // Sprint 8.3A Multimodal Understanding Lab (DEBUG only)
    @State private var isRunningMultimodalLab = false
    @State private var multimodalResult: MultimodalContentUnderstanding?
    @State private var multimodalError: String?
    @State private var multimodalJudge: MultimodalContentLabJudge?
    @State private var multimodalLatencyMs: Int?

    init(listSeed: VisualAnalysisDebugSnapshot) {
        self.listSeed = listSeed
        _snapshot = State(initialValue: listSeed)
    }

    var body: some View {
        List {
            Section("Screenshot") {
                largeThumb(
                    localID: snapshot.photosLocalIdentifier,
                    retryGeneration: previewEpoch,
                    probe: previewProbe
                )
                if snapshot.isImageOnlyEvidence {
                    Text("Image-only / weak OCR — judge Vision evidence, not final Collection names.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("Preview load (DEBUG)") {
                // Isolated child: TimelineView ticks must NOT remount the screenshot preview row.
                VisualEvalPreviewDiagnosticsView(probe: previewProbe)
                Button("Retry Preview") {
                    previewEpoch &+= 1
                }
                Button(isTestingPhotoKit ? "Testing PhotoKit…" : "Test PhotoKit Preview") {
                    Task { await runIsolatedPhotoKitTest() }
                }
                .disabled(isTestingPhotoKit || (snapshot.photosLocalIdentifier ?? "").isEmpty)
                Text("Isolated test: \(isolatedTestReport)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Section("OCR snippet") {
                Text(ocrSummary)
                    .font(.body.monospaced())
            }

            Section {
                Text("Stored analysis only. May be older than the current filter pipeline. Empty RAW does not mean Vision returned nothing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("PERSISTED RESULT")
            }

            Section {
                if let message = VisualEvalDebugMessaging.persistedRawEmptyExplanation(
                    rawCount: snapshot.rawLabels.count,
                    filteredCount: snapshot.labels.count
                ) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.rawLabels, id: \.identifier) { label in
                        LabeledContent(label.identifier, value: String(format: "%.2f", label.confidence))
                    }
                }
            } header: {
                Text("PERSISTED · RAW Vision labels")
            }

            Section {
                if snapshot.labels.isEmpty {
                    Text("None persisted / none survived filter")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.labels, id: \.identifier) { label in
                        LabeledContent(label.identifier, value: String(format: "%.2f", label.confidence))
                    }
                }
            } header: {
                Text("PERSISTED · FILTERED Vision labels")
            }

            Section {
                Text("Authoritative Sprint 8.1 RAW → FILTERED comparison. Same current classify + filter pipeline. Does not persist or change Collections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await liveClassify() }
                } label: {
                    if isClassifying { ProgressView() } else { Text("Live classify (DEBUG)") }
                }
                .disabled(isClassifying)

                if let liveError {
                    Text(liveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !hasLiveEvaluation {
                    Text("Not run yet — tap Live classify (DEBUG) above.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("LIVE · RAW")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if liveRaw.isEmpty {
                        Text("Vision returned no RAW labels (or all empty).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(liveRaw, id: \.identifier) { label in
                            LabeledContent(label.identifier, value: String(format: "%.2f", label.confidence))
                        }
                    }

                    Text("LIVE · FILTERED")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    if liveFiltered.isEmpty {
                        Text("None survived filter")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(liveFiltered, id: \.identifier) { label in
                            LabeledContent(label.identifier, value: String(format: "%.2f", label.confidence))
                        }
                    }

                    if !liveDropped.isEmpty {
                        Text("LIVE · Dropped (why)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(liveDropped) { drop in
                            LabeledContent(
                                "\(drop.identifier) \(String(format: "%.2f", drop.confidence))",
                                value: drop.reason.rawValue
                            )
                        }
                    }

                    if let liveLongEdge {
                        LabeledContent("Live CGImage long-edge", value: "\(liveLongEdge)px")
                    }
                }
            } header: {
                Text("LIVE EVALUATION RESULT")
            }

            Section("Facets / pipeline (persisted)") {
                Text("Level 2 content typing — evidence only, never Collection titles. Vision nouns stay Level 1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if snapshot.facetEvidence.isEmpty {
                    Text(snapshot.facets.isEmpty ? "—" : snapshot.facets.joined(separator: ", "))
                } else {
                    ForEach(snapshot.facetEvidence) { facet in
                        VStack(alignment: .leading, spacing: 2) {
                            LabeledContent(
                                facet.id,
                                value: String(format: "%@ · %.2f", facet.strength.rawValue, facet.confidence)
                            )
                            Text(facet.sources.map(\.rawValue).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                LabeledContent("Feature print", value: snapshot.featurePrintStatus)
                LabeledContent("FP present", value: snapshot.featurePrintPresent ? "yes" : "no")
                LabeledContent("Visual version", value: "\(snapshot.visualVersion)")
                Text(snapshot.analysisInputNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Feature-print distance = visual similarity only — not semantic context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isLoadingDetailExtras {
                    ProgressView("Loading neighbors…")
                } else if snapshot.neighbors.isEmpty {
                    Text("No neighbors (missing prints or no close matches in library sample).")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.neighbors) { neighbor in
                        HStack(spacing: 12) {
                            debugThumb(localID: neighbor.photosLocalIdentifier)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bandTitle(neighbor.band))
                                    .font(.subheadline.weight(.semibold))
                                Text(String(format: "distance %.3f · similarity %.2f", neighbor.distance, neighbor.similarity))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let id = neighbor.photosLocalIdentifier, !id.isEmpty {
                                    Text(String(id.prefix(18)) + "…")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Visual neighbors (feature print)")
            }

            Section {
                Text("CANDIDATE GROUP — NOT A COLLECTION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("Precision-first local grouping. On-demand only — does not name or mutate Collections.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("LAYERED EVIDENCE (R2a DEBUG)")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 2)
                evidenceFieldBlock(title: "PLATFORM", field: snapshot.sourcePlatformField)
                evidenceFieldBlock(title: "TYPE", field: snapshot.contentTypeField)
                evidenceFieldBlock(title: "FAMILY", field: snapshot.contentFamilyField)
                evidenceFieldBlock(title: "SURFACE", field: snapshot.surfaceField)
                Text("EMBEDDED HINTS")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 4)
                if snapshot.embeddedHints.isEmpty {
                    Text("none")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.embeddedHints) { hint in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hint.debugLabel)
                                .font(.caption.monospaced())
                            LabeledContent(
                                "confidence",
                                value: String(format: "%.2f", hint.confidence)
                            )
                            .font(.caption2)
                            if !hint.evidence.isEmpty {
                                Text("evidence: " + hint.evidence.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Text("Internal evidence only — not a Collection name. Embedded hints do not redefine platform/type.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("EVIDENCE TRACES")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 6)
                evidenceTraceBlock(title: "PLATFORM TRACE", lines: snapshot.sourcePlatformField.trace)
                evidenceTraceBlock(title: "TYPE TRACE", lines: snapshot.contentTypeField.trace)
                evidenceTraceBlock(title: "FAMILY TRACE", lines: snapshot.contentFamilyField.trace)
                evidenceTraceBlock(title: "SURFACE TRACE", lines: snapshot.surfaceField.trace)
                if snapshot.embeddedHints.isEmpty {
                    evidenceTraceBlock(
                        title: "EMBEDDED TRACE",
                        lines: ["EMBEDDED: none — no notification/app cue inside lock/NC surface"]
                    )
                } else {
                    evidenceTraceBlock(
                        title: "EMBEDDED TRACE",
                        lines: snapshot.embeddedHints.map {
                            "EMBEDDED: \($0.debugLabel) conf=\(String(format: "%.2f", $0.confidence)) · \($0.evidence.joined(separator: ", "))"
                        }
                    )
                }

                if isLoadingDetailExtras {
                    ProgressView("Loading candidate group…")
                } else {
                    LabeledContent("Peers scored", value: "\(snapshot.clusterInputPeerCount)")
                    if snapshot.clusterMembers.filter({ !$0.pruned }).count <= 1 {
                        Text("Singleton / no multi-member candidate group.")
                            .foregroundStyle(.secondary)
                        if let reason = snapshot.clusterSingletonReason {
                            Text("SINGLETON REASON")
                                .font(.caption.weight(.semibold))
                            Text(reason)
                                .font(.body.monospaced())
                                .foregroundStyle(.orange)
                        }
                        if !snapshot.clusterFlags.isEmpty {
                            Text("flags: " + snapshot.clusterFlags.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        let pruned = snapshot.clusterMembers.filter(\.pruned)
                        if !pruned.isEmpty {
                            Text("Pruned outliers (group collapsed)")
                                .font(.caption.weight(.semibold))
                            ForEach(pruned) { member in
                                HStack(alignment: .top, spacing: 8) {
                                    debugThumb(localID: member.photosLocalIdentifier)
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let support = member.support {
                                            Text(String(format: "support %.3f", support))
                                                .font(.caption)
                                        }
                                        if let reason = member.pruneReason {
                                            Text(reason)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        LabeledContent("Group size", value: "\(snapshot.clusterMemberIDs.count)")
                        LabeledContent("Mean cohesion", value: String(format: "%.3f", snapshot.clusterCohesion ?? 0))
                        if let weakest = snapshot.clusterWeakestMemberSupport {
                            LabeledContent("Weakest member", value: String(format: "%.3f", weakest))
                        }
                        if let weakestPair = snapshot.clusterWeakestPairSupport {
                            LabeledContent("Weakest pair", value: String(format: "%.3f", weakestPair))
                        }
                        if let edges = snapshot.clusterSupportedEdgeCount {
                            LabeledContent("Contextual edges", value: "\(edges)")
                        }
                        if !snapshot.clusterFlags.isEmpty {
                            Text("flags: " + snapshot.clusterFlags.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !snapshot.clusterSignalBreakdown.isEmpty {
                            Text("Signal breakdown")
                                .font(.caption.weight(.semibold))
                            ForEach(snapshot.clusterSignalBreakdown.keys.sorted(), id: \.self) { key in
                                LabeledContent(key, value: String(format: "%.3f", snapshot.clusterSignalBreakdown[key] ?? 0))
                            }
                        }
                        Text("Members (why linked)")
                            .font(.caption.weight(.semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(snapshot.clusterMembers.filter { !$0.pruned }) { member in
                                    VStack(alignment: .leading, spacing: 4) {
                                        debugThumb(localID: member.photosLocalIdentifier)
                                        if let support = member.support {
                                            Text(String(format: "sup %.2f", support))
                                                .font(.caption2)
                                        }
                                        if !member.strongFacets.isEmpty {
                                            Text(member.strongFacets.prefix(2).joined(separator: ","))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        if !member.topSignals.isEmpty {
                                            Text(
                                                member.topSignals.sorted { $0.value > $1.value }
                                                    .prefix(2)
                                                    .map { "\($0.key)" }
                                                    .joined(separator: ",")
                                            )
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        }
                                    }
                                    .frame(width: 72)
                                }
                            }
                        }
                        Text("ADMITTED MEMBER AUDITS")
                            .font(.caption.weight(.semibold))
                            .padding(.top, 4)
                        ForEach(snapshot.clusterMembers.filter { !$0.pruned }) { member in
                            admittedMemberAuditRow(member)
                        }
                        let pruned = snapshot.clusterMembers.filter(\.pruned)
                        if !pruned.isEmpty {
                            Text("Pruned outliers")
                                .font(.caption.weight(.semibold))
                            ForEach(pruned) { member in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        debugThumb(localID: member.photosLocalIdentifier)
                                        VStack(alignment: .leading) {
                                            if let support = member.support {
                                                Text(String(format: "support %.3f", support))
                                                    .font(.caption)
                                            }
                                            if let reason = member.pruneReason {
                                                Text(reason)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text("BEST REJECTED CANDIDATES")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 4)
                    if snapshot.clusterRejectedCandidates.isEmpty {
                        Text("No rejected peers (empty pool or none scored).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.clusterRejectedCandidates) { rejected in
                            rejectedCandidateRow(rejected)
                        }
                    }
                }
            } header: {
                Text("Candidate group (Sprint 8.2B — not a Collection)")
            }

            Section {
                Text("CONTENT UNDERSTANDING ONLY — not Collection naming / reuse / create.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Image is authoritative. Local evidence is supporting. Model may disagree.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await runMultimodalLab() }
                } label: {
                    if isRunningMultimodalLab {
                        ProgressView("Analyzing with Multimodal AI…")
                    } else {
                        Text("Analyze with Multimodal AI")
                    }
                }
                .disabled(isRunningMultimodalLab || isLoadingDetailExtras)

                if let multimodalError {
                    Text(multimodalError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("LOCAL UNDERSTANDING")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 4)
                LabeledContent("platform", value: snapshot.sourcePlatformField.value)
                LabeledContent("type", value: snapshot.contentTypeField.value)
                LabeledContent("family", value: snapshot.contentFamilyField.value)
                LabeledContent("surface", value: snapshot.surfaceField.value)
                if !snapshot.embeddedHints.isEmpty {
                    Text("embedded: " + snapshot.embeddedHints.map(\.debugLabel).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let multimodalResult {
                    Text("MULTIMODAL UNDERSTANDING")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 6)
                    multimodalLabeledRow("platform", multimodalResult.platform)
                    multimodalLabeledRow("type", multimodalResult.contentType)
                    multimodalLabeledRow("family", multimodalResult.contentFamily)
                    multimodalLabeledRow("surface", multimodalResult.surface)
                    if !multimodalResult.embeddedHints.isEmpty {
                        Text("embedded:")
                            .font(.caption2.weight(.semibold))
                        ForEach(multimodalResult.embeddedHints) { hint in
                            Text("\(hint.debugLabel) · \(String(format: "%.2f", hint.confidence))")
                                .font(.caption2.monospaced())
                        }
                    }
                    if !multimodalResult.openDescriptors.isEmpty {
                        Text("Descriptors:")
                            .font(.caption2.weight(.semibold))
                        Text(multimodalResult.openDescriptors.joined(separator: "\n"))
                            .font(.caption2)
                    }
                    if !multimodalResult.evidenceNotes.isEmpty {
                        Text("Evidence notes:")
                            .font(.caption2.weight(.semibold))
                        ForEach(Array(multimodalResult.evidenceNotes.enumerated()), id: \.offset) { _, note in
                            Text("• \(note)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent(
                        "Disagrees with local",
                        value: multimodalResult.disagreesWithLocal ? "yes" : "no"
                    )
                    .font(.caption2)
                    if let multimodalLatencyMs {
                        LabeledContent("Latency", value: "\(multimodalLatencyMs) ms")
                            .font(.caption2)
                    }
                    if let provider = multimodalResult.provider {
                        Text("provider \(provider) · prompt \(multimodalResult.promptVersion ?? "—")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text("Manual evaluation (DEBUG only)")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 4)
                    HStack {
                        ForEach(MultimodalContentLabJudge.allCases) { judge in
                            Button(judge.rawValue) {
                                multimodalJudge = judge
                            }
                            .buttonStyle(.bordered)
                            .tint(multimodalJudge == judge ? .accentColor : .secondary)
                            .font(.caption2)
                        }
                    }
                    if let multimodalJudge {
                        Text("Judged: \(multimodalJudge.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Multimodal Understanding Lab (Sprint 8.3A)")
            }

            Section("Judge (for your notes)") {
                Text("Labels: USEFUL / MIXED / USELESS")
                Text("Neighbors: RELATED / PARTIAL / UNRELATED")
                Text("Image-only evidence: USEFUL / WEAK / NONE")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Actions") {
                Button {
                    Task {
                        isReprocessing = true
                        await dependencies.visualScheduler.reprocess(id: snapshot.id)
                        isReprocessing = false
                    }
                } label: {
                    if isReprocessing { ProgressView() } else { Text("Reprocess this screenshot") }
                }
                .disabled(isReprocessing)
                Text("Reprocess updates persisted analysis. Live classify above does not.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Visual eval")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: listSeed.id) {
            resetLiveEvaluation()
            isLoadingDetailExtras = true
            defer { isLoadingDetailExtras = false }
            guard let full = try? await dependencies.visualStore.fetchVisualDebugDetailSnapshot(id: listSeed.id)
            else { return }
            snapshot = full
        }
    }

    private func resetLiveEvaluation() {
        hasLiveEvaluation = false
        liveRaw = []
        liveFiltered = []
        liveDropped = []
        liveLongEdge = nil
        liveError = nil
        multimodalResult = nil
        multimodalError = nil
        multimodalJudge = nil
        multimodalLatencyMs = nil
    }

    private func runMultimodalLab() async {
        isRunningMultimodalLab = true
        multimodalError = nil
        multimodalResult = nil
        multimodalJudge = nil
        multimodalLatencyMs = nil
        defer { isRunningMultimodalLab = false }

        let started = Date()
        let result = await MultimodalContentUnderstandingLabClient.analyze(
            snapshot: snapshot,
            configuration: dependencies.configuration
        )
        multimodalLatencyMs = Int(Date().timeIntervalSince(started) * 1000)
        switch result {
        case .success(let understanding):
            multimodalResult = understanding
        case .failure(let error):
            multimodalError = error.localizedDescription
            if error == .consentRequired {
                dependencies.presentCloudUnderstandingDisclosureIfNeeded()
            }
        }
    }

    @ViewBuilder
    private func multimodalLabeledRow(_ title: String, _ value: MultimodalContentLabeledValue) -> some View {
        LabeledContent(
            title,
            value: "\(value.id) · \(String(format: "%.2f", value.confidence))"
        )
        .font(.caption)
    }

    private var ocrSummary: String {
        let trimmed = snapshot.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return snapshot.ocrStatus == .completed ? "(empty — image-only)" : "OCR \(snapshot.ocrStatus.rawValue)"
        }
        return String(trimmed.prefix(400))
    }

    private func bandTitle(_ band: VisualNeighborBand) -> String {
        switch band {
        case .strong: return "Strong visual neighbor"
        case .weak: return "Weak visual neighbor"
        case .far: return "Far visual neighbor"
        }
    }

    @ViewBuilder
    private func evidenceFieldBlock(title: String, field: VisualSourceFieldDebug) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            LabeledContent("value", value: field.value)
                .font(.caption)
            LabeledContent("confidence", value: String(format: "%.2f", field.confidence))
                .font(.caption2)
            if !field.evidence.isEmpty {
                Text("evidence: " + field.evidence.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func evidenceTraceBlock(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func admittedMemberAuditRow(_ member: VisualClusterMemberDebug) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                debugThumb(localID: member.photosLocalIdentifier)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.photosLocalIdentifier ?? member.id.rawValue.uuidString)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                    if let score = member.admissionTotalScore {
                        LabeledContent("Score", value: String(format: "%.3f", score))
                    }
                    if let contextual = member.admissionHasContextualSupport {
                        LabeledContent(
                            "Contextual support",
                            value: contextual ? "PASS" : "FAIL"
                        )
                    }
                    if !member.admissionContextualFamilies.isEmpty {
                        Text(
                            "families: "
                                + member.admissionContextualFamilies.joined(separator: ", ")
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    if member.bridgeInvolved {
                        Text("bridge: involved")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let outlier = member.outlierValidationPassed {
                        LabeledContent(
                            "Outlier validation",
                            value: outlier ? "PASS" : "FAIL"
                        )
                        .font(.caption2)
                    }
                }
            }
            let parts = member.admissionSignalParts.isEmpty ? member.topSignals : member.admissionSignalParts
            let keys = [
                "ocr_tokens", "ocr_entities", "facets", "weak_facets",
                "source_platform", "content_type", "content_family",
                "vision", "feature_print", "time", "profile"
            ]
            ForEach(keys, id: \.self) { key in
                if let value = parts[key], value > 0 {
                    LabeledContent(key, value: String(format: "+%.3f", value))
                        .font(.caption2)
                }
            }
            if !member.correlatedSemanticChannels.isEmpty {
                Text("correlated semantic evidence:")
                    .font(.caption2.weight(.semibold))
                Text(member.correlatedSemanticChannels.joined(separator: " · "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
            }
            Text(
                "ADMITTED · "
                    + (member.admissionReason ?? "unknown").uppercased().replacingOccurrences(of: "_", with: " ")
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func rejectedCandidateRow(_ rejected: VisualRejectedCandidateDebug) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                debugThumb(localID: rejected.photosLocalIdentifier)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rejected.photosLocalIdentifier ?? rejected.id.rawValue.uuidString)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                    LabeledContent("Score", value: String(format: "%.3f", rejected.totalScore))
                    LabeledContent(
                        "Contextual support",
                        value: rejected.hasContextualSupport ? "PASS" : "FAIL"
                    )
                    if !rejected.contextualFamilies.isEmpty {
                        Text("families: " + rejected.contextualFamilies.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        "src \(rejected.sourcePlatform) · type \(rejected.contentType) · fam \(rejected.contentFamily)"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
            }
            let parts = rejected.signalParts
            let keys = [
                "ocr_tokens", "ocr_entities", "facets", "weak_facets",
                "source_platform", "content_type", "content_family",
                "vision", "feature_print", "time", "profile"
            ]
            ForEach(keys, id: \.self) { key in
                if let value = parts[key], value > 0 {
                    LabeledContent(key, value: String(format: "+%.3f", value))
                        .font(.caption2)
                }
            }
            if !rejected.correlatedSemanticChannels.isEmpty {
                Text("correlated semantic evidence:")
                    .font(.caption2.weight(.semibold))
                Text(rejected.correlatedSemanticChannels.joined(separator: " · "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
            }
            Text("REJECTED · " + rejected.rejectionReason.uppercased().replacingOccurrences(of: "_", with: " "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
    }

    private func runIsolatedPhotoKitTest() async {
        guard let localID = snapshot.photosLocalIdentifier, !localID.isEmpty else {
            isolatedTestReport = "missing localIdentifier"
            return
        }
        isTestingPhotoKit = true
        defer { isTestingPhotoKit = false }
        let report = await DebugPhotoKitPreviewTester.run(
            localIdentifier: localID,
            targetSize: visualEvalPreviewTargetSize
        )
        isolatedTestReport = [
            "asset=\(report.assetFound ? "YES" : "NO")",
            "callbacks=\(report.callbackCount)",
            "degraded=\(report.degradedCallback ? "Y" : "N")",
            "final=\(report.finalCallback ? "Y" : "N")",
            "timeout=\(report.timedOut ? "Y" : "N")",
            String(format: "elapsed=%.1fs", report.elapsedSeconds),
            report.imageWidth.map { "size=\($0)x\(report.imageHeight ?? 0)" } ?? "size=—",
            report.inCloud.map { "cloud=\($0 ? "Y" : "N")" } ?? "cloud=—",
            report.error.map { "err=\($0)" } ?? "err=—"
        ].joined(separator: " · ")
        previewProbe.noteIsolatedTestSummary(isolatedTestReport)
    }

    private func liveClassify() async {
        guard let localID = snapshot.photosLocalIdentifier, !localID.isEmpty else {
            liveError = "Missing Photos local identifier"
            return
        }
        isClassifying = true
        liveError = nil
        defer { isClassifying = false }
        do {
            let loader = PhotoKitOCRImageLoader(longEdge: VisualAnalysisPipeline.imageLongEdge)
            let cgImage = try await loader.loadCGImage(localIdentifier: localID)
            liveLongEdge = max(cgImage.width, cgImage.height)
            // Same classify + filter path as production analyze (classifyExplained); no DB write.
            let outcome = try await VisionVisualAnalysisService().classifyExplained(cgImage: cgImage)
            liveRaw = outcome.raw
            liveFiltered = outcome.filtered
            liveDropped = outcome.dropped
            hasLiveEvaluation = true
        } catch {
            liveError = VisualAnalysisErrorCode.sanitizeDebugNote(error.localizedDescription)
            hasLiveEvaluation = false
        }
    }
}

/// Neighbor / list DEBUG thumbs — small display (~56pt), bounded PhotoKit target.
private var visualEvalNeighborTargetSize: CGSize {
    let side = min(UIScreen.main.scale * 56, 160)
    return CGSize(width: side, height: side)
}

/// Main Visual Eval preview — display×scale for Retina sharpness (not original).
/// Container is ~screen-width × 220pt; request enough pixels for the fitted screenshot.
private var visualEvalPreviewTargetSize: CGSize {
    let scale = UIScreen.main.scale
    let displayLongEdgePt = max(UIScreen.main.bounds.width, CGFloat(220))
    let pixels = min(displayLongEdgePt * scale, 1_200)
    return CGSize(width: pixels, height: pixels)
}

@ViewBuilder
private func debugThumb(localID: String?) -> some View {
    PhotosThumbnailImage(
        localIdentifier: localID,
        targetSize: visualEvalNeighborTargetSize,
        contentMode: .aspectFill,
        allowsNetworkAccess: true,
        deliveryStyle: .firstUsable
    ) {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
    }
    .frame(width: 56, height: 56)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
}

@ViewBuilder
private func largeThumb(
    localID: String?,
    retryGeneration: Int = 0,
    probe: ThumbnailLoadProbe? = nil
) -> some View {
    PhotosThumbnailImage(
        localIdentifier: localID,
        targetSize: visualEvalPreviewTargetSize,
        contentMode: .aspectFit,
        allowsNetworkAccess: true,
        retryGeneration: retryGeneration,
        deliveryStyle: .progressive,
        loadProbe: probe
    ) {
        Color.secondary.opacity(0.12)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 220)
    .listRowInsets(EdgeInsets())
}

/// Reads a non-observable probe on a timer. Must stay a separate List row from the preview.
private struct VisualEvalPreviewDiagnosticsView: View {
    let probe: ThumbnailLoadProbe

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = probe.elapsedSeconds(at: context.date)
            VStack(alignment: .leading, spacing: 4) {
                Text("Asset local identifier: \(probe.shortAssetID)")
                Text("Request ID: \(probe.requestID)")
                Text("State: \(probe.state.rawValue)")
                Text("Displayed quality: \(probe.displayedQuality.rawValue)")
                Text("Request started: \(probe.requestStartedAt?.formatted(date: .omitted, time: .standard) ?? "—")")
                Text(String(format: "Elapsed: %.1f seconds", elapsed))
                Text("Callback count: \(probe.callbackCount)")
                Text("Degraded callback: \(probe.degradedCallback ? "yes" : "no")")
                Text("Final callback: \(probe.finalCallback ? "yes" : "no")")
                if let w = probe.degradedWidth, let h = probe.degradedHeight {
                    Text("Degraded image size: \(w)×\(h)")
                } else {
                    Text("Degraded image size: —")
                }
                if let w = probe.finalWidth, let h = probe.finalHeight {
                    Text("Final image size: \(w)×\(h)")
                } else {
                    Text("Final image size: —")
                }
                if let w = probe.imageWidth, let h = probe.imageHeight {
                    Text("Current displayed image size: \(w)×\(h)")
                } else {
                    Text("Current displayed image size: —")
                }
                Text("PhotoKit cancelled: \(probe.photoKitCancelled ? "yes" : "no")")
                Text("Task started: \(probe.taskRestartCount)")
                Text("Last event: \(probe.lastEvent)")
                Text("PHAsset found: \(probe.assetFound.map { $0 ? "YES" : "NO" } ?? "—")")
                Text("In cloud hint: \(probe.inCloudHint.map { $0 ? "YES" : "NO" } ?? "—")")
                if let err = probe.photoKitError, !err.isEmpty {
                    Text("PhotoKit error: \(err)")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption2.monospaced())
            .textSelection(.enabled)
        }
    }
}
#endif
