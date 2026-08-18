import Vision
import CoreGraphics
import Foundation

/// On-device Vision classification + feature prints (iOS 17 Revision 2).
/// Classify and feature-print run separately so a feature-print failure keeps labels.
/// Never logs image contents or raw label dumps at scale.
final class VisionVisualAnalysisService: VisualAnalysisProviding, @unchecked Sendable {
    func analyze(cgImage: CGImage) async throws -> VisualAnalysisResult {
        let settings = VisualAnalysisDebugRuntime.filterSettings()
        return try await Task.detached(priority: .utility) {
            try Self.analyzeSync(cgImage: cgImage, settings: settings)
        }.value
    }

    /// DEBUG: classify only — raw vs filtered with drop reasons. Does not run feature print.
    func classifyExplained(cgImage: CGImage, settings: VisualLabelFilter.Settings? = nil) async throws -> VisualLabelFilter.Outcome {
        let resolved = settings ?? VisualAnalysisDebugRuntime.filterSettings()
        return try await Task.detached(priority: .utility) {
            try Self.classifyExplainedSync(cgImage: cgImage, settings: resolved)
        }.value
    }

    private static func analyzeSync(
        cgImage: CGImage,
        settings: VisualLabelFilter.Settings
    ) throws -> VisualAnalysisResult {
        let outcome = try classifyExplainedSync(cgImage: cgImage, settings: settings)
        let labels = outcome.filtered
        let longEdge = max(cgImage.width, cgImage.height)

        let classifyRevision: Int
        if #available(iOS 17.0, *) {
            classifyRevision = VNClassifyImageRequestRevision2
        } else {
            classifyRevision = 1
        }

        var printData: Data?
        var printRevision = 2
        var printStatus = "failed"
        var printError: String? = VisualAnalysisErrorCode.visionFeaturePrintFailed

        let featurePrint = VNGenerateImageFeaturePrintRequest()
        if #available(iOS 17.0, *) {
            featurePrint.revision = VNGenerateImageFeaturePrintRequestRevision2
            printRevision = VNGenerateImageFeaturePrintRequestRevision2
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([featurePrint])
            if let printObservation = featurePrint.results?.first as? VNFeaturePrintObservation {
                printData = archive(printObservation)
                if printData != nil {
                    printStatus = "generated"
                    printError = nil
                } else {
                    printStatus = "failed"
                    printError = VisualAnalysisErrorCode.featurePrintArchiveFailed
                }
            } else {
                printStatus = "failed"
                printError = VisualAnalysisErrorCode.visionFeaturePrintFailed
            }
        } catch {
            printData = nil
            printStatus = "failed"
            printError = VisualAnalysisErrorCode.visionFeaturePrintFailed
        }

        let facets = ScreenshotFacetDeriver.derive(ocrText: nil, labels: labels)
        return VisualAnalysisResult(
            labels: labels,
            rawLabels: outcome.raw,
            featurePrintData: printData,
            classifyRevision: classifyRevision,
            featurePrintRevision: printRevision,
            facets: facets,
            featurePrintStatus: printStatus,
            featurePrintErrorCode: printError,
            analysisLongEdge: longEdge
        )
    }

    private static func classifyExplainedSync(
        cgImage: CGImage,
        settings: VisualLabelFilter.Settings
    ) throws -> VisualLabelFilter.Outcome {
        let classify = VNClassifyImageRequest()
        if #available(iOS 17.0, *) {
            classify.revision = VNClassifyImageRequestRevision2
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([classify])
        } catch {
            throw VisualAnalysisJobError.visionClassifyFailed
        }
        let observations = (classify.results as? [VNClassificationObservation]) ?? []
        return VisualLabelFilter.filterExplained(observations: observations, settings: settings)
    }

    private static func archive(_ observation: VNFeaturePrintObservation) -> Data? {
        if let secure = try? NSKeyedArchiver.archivedData(
            withRootObject: observation,
            requiringSecureCoding: true
        ) {
            return secure
        }
        return try? NSKeyedArchiver.archivedData(
            withRootObject: observation,
            requiringSecureCoding: false
        )
    }

    static func distance(between lhs: Data, and rhs: Data) -> Float? {
        guard
            let a = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self,
                from: lhs
            ),
            let b = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self,
                from: rhs
            )
        else { return nil }

        var distance: Float = 0
        do {
            try a.computeDistance(&distance, to: b)
            return distance
        } catch {
            return nil
        }
    }

    static func similarity(distance: Float) -> Float {
        1 / (1 + max(0, distance))
    }
}

struct MockVisualAnalysisService: VisualAnalysisProviding {
    enum Behavior: Sendable {
        case succeed(VisualAnalysisResult)
        case classifyFail
    }

    var behavior: Behavior = .succeed(
        VisualAnalysisResult(
            labels: [VisualLabelObservation(identifier: "sofa", confidence: 0.9)],
            rawLabels: [
                VisualLabelObservation(identifier: "sofa", confidence: 0.9),
                VisualLabelObservation(identifier: "indoor", confidence: 0.7)
            ],
            featurePrintData: Data([1, 2, 3]),
            classifyRevision: 2,
            featurePrintRevision: 2,
            facets: ["interior_reference"],
            featurePrintStatus: "generated",
            analysisLongEdge: 1_024
        )
    )

    var result: VisualAnalysisResult {
        get {
            if case .succeed(let value) = behavior { return value }
            return VisualAnalysisResult(
                labels: [],
                rawLabels: [],
                featurePrintData: nil,
                classifyRevision: 2,
                featurePrintRevision: 2,
                facets: [],
                featurePrintStatus: "failed"
            )
        }
        set { behavior = .succeed(newValue) }
    }

    init(result: VisualAnalysisResult) {
        self.behavior = .succeed(result)
    }

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    init() {}

    func analyze(cgImage: CGImage) async throws -> VisualAnalysisResult {
        switch behavior {
        case .succeed(let value):
            return value
        case .classifyFail:
            throw VisualAnalysisJobError.visionClassifyFailed
        }
    }
}
