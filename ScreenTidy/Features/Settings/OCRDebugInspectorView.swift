#if DEBUG
import SwiftUI

/// DEBUG-only OCR inspector. Not included in production UI.
/// Purpose: validate Apple Vision OCR quality against real Photos screenshots.
struct OCRDebugInspectorView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var counts = OCRStatusCounts(
        pending: 0,
        processing: 0,
        completed: 0,
        failed: 0,
        inaccessible: 0
    )
    @State private var rows: [ScreenshotMemory] = []

    var body: some View {
        List {
            Section("Pipeline") {
                LabeledContent("OCR version", value: "\(OCRPipeline.currentVersion)")
                LabeledContent("Pending", value: "\(counts.pending)")
                LabeledContent("Processing", value: "\(counts.processing)")
                LabeledContent("Completed", value: "\(counts.completed)")
                LabeledContent("Failed", value: "\(counts.failed)")
                LabeledContent("Inaccessible", value: "\(counts.inaccessible)")
            }

            Section("Actions") {
                Button("Kick OCR Queue") {
                    dependencies.ocrScheduler.kick()
                    Task { await reload() }
                }
                Button("Reprocess All OCR", role: .destructive) {
                    Task {
                        await dependencies.ocrScheduler.reprocessAll()
                        await reload()
                    }
                }
            }

            Section {
                if rows.isEmpty {
                    Text("No Photos screenshots yet. Sync from Photos, then pull to refresh.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        NavigationLink {
                            OCRDebugDetailView(screenshotID: row.id)
                        } label: {
                            OCRDebugRowView(row: row)
                        }
                    }
                }
            } header: {
                Text("Recent Photos Screenshots")
            } footer: {
                Text("Tap a row to compare the screenshot with its stored OCR text.")
            }
        }
        .navigationTitle("OCR Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        counts = (try? await dependencies.ocrStore.fetchOCRStatusCounts()) ?? counts
        rows = (try? await dependencies.ocrStore.fetchOCRDebugRows(limit: 40)) ?? []
    }
}

// MARK: - List row

private struct OCRDebugRowView: View {
    let row: ScreenshotMemory

    private var previewText: String {
        let trimmed = row.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch row.ocrStatus {
        case .completed:
            if trimmed.isEmpty {
                return "No text detected"
            }
            return trimmed
        case .pending:
            return "Waiting for OCR…"
        case .processing:
            return "OCR in progress…"
        case .failed:
            return row.ocrLastError?.isEmpty == false
                ? (row.ocrLastError ?? "OCR failed")
                : "OCR failed"
        case .inaccessible:
            return "Photos asset inaccessible"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PhotosThumbnailImage(
                localIdentifier: row.photosLocalIdentifier,
                targetSize: CGSize(width: 160, height: 160),
                contentMode: .aspectFill,
                allowsNetworkAccess: true
            ) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(previewText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(row.ocrStatus.rawValue.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusTint.opacity(0.18), in: Capsule())
                        .foregroundStyle(statusTint)

                    Text("v\(row.ocrVersion)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Screenshot OCR \(row.ocrStatus.rawValue), version \(row.ocrVersion)")
    }

    private var statusTint: Color {
        switch row.ocrStatus {
        case .completed: .green
        case .pending: .orange
        case .processing: .blue
        case .failed: .red
        case .inaccessible: .secondary
        }
    }
}

// MARK: - Detail

private struct OCRDebugDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    let screenshotID: ScreenshotMemoryID

    @State private var row: ScreenshotMemory?
    @State private var isReprocessing = false
    @State private var statusMessage: String?

    private static let processedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        Group {
            if let row {
                content(for: row)
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("OCR Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private func content(for row: ScreenshotMemory) -> some View {
        List {
            Section {
                PhotosThumbnailImage(
                    localIdentifier: row.photosLocalIdentifier,
                    targetSize: CGSize(width: 1_200, height: 1_200),
                    contentMode: .aspectFit,
                    allowsNetworkAccess: true
                ) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            } header: {
                Text("Screenshot")
            } footer: {
                Text("Compare visible text in the image with the extracted OCR below.")
            }

            Section("OCR Status") {
                LabeledContent("Outcome", value: outcomeTitle(for: row))
                LabeledContent("State", value: row.ocrStatus.rawValue)
                LabeledContent("OCR version", value: "\(row.ocrVersion)")
                LabeledContent("Attempt count", value: "\(row.ocrAttemptCount)")
                LabeledContent("Last processed", value: formattedDate(row.ocrLastAttemptAt))
                LabeledContent("Access state", value: row.accessState.rawValue)
                if let error = row.ocrLastError, !error.isEmpty, row.ocrStatus == .failed {
                    LabeledContent("Last error", value: error)
                }
            }

            Section {
                ocrTextBody(for: row)
            } header: {
                Text("Extracted OCR Text")
            } footer: {
                Text(ocrTextFooter(for: row))
            }

            Section("PhotoKit") {
                LabeledContent("Local identifier") {
                    Text(row.photosLocalIdentifier ?? "—")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Memory ID") {
                    Text(row.id.rawValue.uuidString)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                Button {
                    Task { await reprocess(row) }
                } label: {
                    if isReprocessing {
                        HStack {
                            ProgressView()
                            Text("Reprocessing…")
                        }
                    } else {
                        Text("Reprocess OCR")
                    }
                }
                .disabled(isReprocessing || row.accessState != .available)
            } footer: {
                if let statusMessage {
                    Text(statusMessage)
                } else if row.accessState != .available {
                    Text("Reprocess is unavailable while the Photos asset is inaccessible.")
                } else {
                    Text("Queues this screenshot for OCR again, then refreshes this screen.")
                }
            }
        }
    }

    @ViewBuilder
    private func ocrTextBody(for row: ScreenshotMemory) -> some View {
        switch row.ocrStatus {
        case .completed:
            let trimmed = row.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("COMPLETED — NO TEXT DETECTED")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("OCR finished successfully. Vision did not find readable text in this screenshot.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("COMPLETED — TEXT FOUND")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(row.ocrText ?? "")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Text("FAILED")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Text(row.ocrLastError?.isEmpty == false
                     ? (row.ocrLastError ?? "OCR failed.")
                     : "OCR failed. No additional error details were stored.")
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
        case .inaccessible:
            VStack(alignment: .leading, spacing: 8) {
                Text("INACCESSIBLE")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("The Photos asset is currently inaccessible (limited library, deleted, or iCloud unavailable). OCR text may be missing or stale until access is restored.")
                    .font(.body)
            }
            .padding(.vertical, 4)
        case .pending:
            Text("OCR has not run yet. Use Reprocess OCR or Kick OCR Queue.")
                .font(.body)
                .foregroundStyle(.secondary)
        case .processing:
            Text("OCR is currently processing this screenshot.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func ocrTextFooter(for row: ScreenshotMemory) -> String {
        switch row.ocrStatus {
        case .completed:
            let trimmed = row.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                return "Empty OCR after completion is a valid result — not a failure."
            }
            return "Full stored raw ocr_text. Select and copy to inspect off-device."
        case .failed:
            return "Failure details are limited to safe metadata (no crash payloads)."
        case .inaccessible:
            return "Fix Photos access, then reprocess if needed."
        case .pending, .processing:
            return "Pull to refresh after the queue drains."
        }
    }

    private func outcomeTitle(for row: ScreenshotMemory) -> String {
        switch row.ocrStatus {
        case .completed:
            let trimmed = row.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "COMPLETED — NO TEXT DETECTED" : "COMPLETED — TEXT FOUND"
        case .failed:
            return "FAILED"
        case .inaccessible:
            return "INACCESSIBLE"
        case .pending:
            return "PENDING"
        case .processing:
            return "PROCESSING"
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return Self.processedDateFormatter.string(from: date)
    }

    private func reload() async {
        row = try? await dependencies.memoryStore.fetchScreenshot(id: screenshotID)
    }

    private func reprocess(_ current: ScreenshotMemory) async {
        guard !isReprocessing else { return }
        isReprocessing = true
        statusMessage = "Queued for OCR…"
        defer { isReprocessing = false }

        await dependencies.ocrScheduler.reprocess(id: current.id)
        await reload()

        // Poll briefly so the detail screen updates with the new result without leaving.
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            await reload()
            guard let latest = row else { continue }
            switch latest.ocrStatus {
            case .completed, .failed, .inaccessible:
                statusMessage = "Updated · \(outcomeTitle(for: latest))"
                return
            case .pending, .processing:
                statusMessage = "OCR \(latest.ocrStatus.rawValue)…"
            }
        }
        statusMessage = "Still running — pull to refresh."
    }
}
#endif
