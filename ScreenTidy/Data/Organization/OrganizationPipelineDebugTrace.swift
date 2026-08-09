import Foundation

/// DEBUG-only stage trace for one organization attempt (no OCR text, images, or secrets).
enum OrganizationPipelineStage: String, Sendable, CaseIterable, Equatable {
    case preparing
    case imageLoaded
    case ocrAttached
    case requestStarted
    case gatewayReached
    case providerRequestStarted
    case providerResponseReceived
    case structuredCandidateDecoded
    case resolverEvaluated
    case persisted
    case completed
    case failed

    var displayName: String {
        switch self {
        case .preparing: "Preparing"
        case .imageLoaded: "Image loaded"
        case .ocrAttached: "OCR attached"
        case .requestStarted: "Request started"
        case .gatewayReached: "Gateway reached"
        case .providerRequestStarted: "Provider request started"
        case .providerResponseReceived: "Provider response received"
        case .structuredCandidateDecoded: "Structured candidate decoded"
        case .resolverEvaluated: "Resolver evaluated"
        case .persisted: "Persisted"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

struct OrganizationPipelineTrace: Sendable, Equatable {
    var screenshotID: ScreenshotMemoryID
    var updatedAt: Date
    var stage: OrganizationPipelineStage
    var detail: String
    var failureCategory: OrganizationNetworkFailureCategory?
    var gatewayHost: String?
    var imageAttached: Bool?
    var ocrAttached: Bool?
    var collectionContextAttached: Bool?
    var batchContext: Bool?
    var decisionKind: String?
    var provider: String?

    var summaryLines: [String] {
        var lines: [String] = [
            "Stage: \(stage.displayName)",
            detail
        ]
        if let gatewayHost { lines.append("Gateway host: \(gatewayHost)") }
        if let imageAttached {
            lines.append("Image: \(imageAttached ? "attached" : "missing")")
        }
        if let ocrAttached {
            lines.append("OCR: \(ocrAttached ? "attached" : "empty")")
        }
        if let collectionContextAttached {
            lines.append("Collection context: \(collectionContextAttached ? "attached" : "none")")
        }
        if let batchContext {
            lines.append("Batch context: \(batchContext ? "yes" : "no")")
        }
        if let provider { lines.append("Provider: \(provider)") }
        if let decisionKind { lines.append("Decision: \(decisionKind)") }
        if let failureCategory {
            lines.append("Failure: \(failureCategory.displayName)")
        }
        return lines
    }
}

/// In-memory DEBUG probe store. Release builds keep the API but discard data.
enum OrganizationPipelineDebugStore {
    private static let lock = NSLock()
    private static var traces: [UUID: OrganizationPipelineTrace] = [:]
    private static var latestID: UUID?

    static func reset(screenshotID: ScreenshotMemoryID) {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        traces[screenshotID.rawValue] = OrganizationPipelineTrace(
            screenshotID: screenshotID,
            updatedAt: Date(),
            stage: .preparing,
            detail: "Organize started",
            failureCategory: nil,
            gatewayHost: nil,
            imageAttached: nil,
            ocrAttached: nil,
            collectionContextAttached: nil,
            batchContext: nil,
            decisionKind: nil,
            provider: nil
        )
        latestID = screenshotID.rawValue
        #endif
    }

    static func update(
        screenshotID: ScreenshotMemoryID,
        stage: OrganizationPipelineStage,
        detail: String,
        failureCategory: OrganizationNetworkFailureCategory? = nil,
        gatewayHost: String? = nil,
        imageAttached: Bool? = nil,
        ocrAttached: Bool? = nil,
        collectionContextAttached: Bool? = nil,
        batchContext: Bool? = nil,
        decisionKind: String? = nil,
        provider: String? = nil
    ) {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        var trace = traces[screenshotID.rawValue] ?? OrganizationPipelineTrace(
            screenshotID: screenshotID,
            updatedAt: Date(),
            stage: stage,
            detail: detail
        )
        trace.updatedAt = Date()
        trace.stage = stage
        trace.detail = detail
        if let failureCategory { trace.failureCategory = failureCategory }
        if let gatewayHost { trace.gatewayHost = gatewayHost }
        if let imageAttached { trace.imageAttached = imageAttached }
        if let ocrAttached { trace.ocrAttached = ocrAttached }
        if let collectionContextAttached { trace.collectionContextAttached = collectionContextAttached }
        if let batchContext { trace.batchContext = batchContext }
        if let decisionKind { trace.decisionKind = decisionKind }
        if let provider { trace.provider = provider }
        traces[screenshotID.rawValue] = trace
        latestID = screenshotID.rawValue
        #endif
    }

    static func trace(for screenshotID: ScreenshotMemoryID) -> OrganizationPipelineTrace? {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        return traces[screenshotID.rawValue]
        #else
        return nil
        #endif
    }

    static var latest: OrganizationPipelineTrace? {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        guard let latestID else { return nil }
        return traces[latestID]
        #else
        return nil
        #endif
    }
}
