import Vision
import CoreGraphics

/// On-device Vision OCR. Never logs recognized text.
final class VisionOCRService: OCRProviding, @unchecked Sendable {
    func recognize(cgImage: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRJobError.visionFailed(error.localizedDescription))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var lines: [String] = []
                lines.reserveCapacity(observations.count)
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first,
                          candidate.confidence >= OCRPipeline.confidenceFloor
                    else { continue }
                    lines.append(candidate.string)
                }
                // Empty lines → completed with "" (valid "no text detected").
                continuation.resume(returning: OCRResult(text: lines.joined(separator: "\n"), language: nil))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRJobError.visionFailed(error.localizedDescription))
            }
        }
    }
}

struct MockOCRService: OCRProviding {
    var result: OCRResult = OCRResult(text: "mock ocr", language: "en")

    func recognize(cgImage: CGImage) async throws -> OCRResult {
        result
    }
}
