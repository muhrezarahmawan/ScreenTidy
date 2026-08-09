import Foundation

/// Preview / tests — OCR pipeline disabled.
final class NoOpOCRScheduler: OCRScheduling, @unchecked Sendable {
    func kick() {}
    func reprocess(id: ScreenshotMemoryID) async {}
    func reprocessAll() async {}
}
