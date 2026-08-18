import Foundation
import UIKit

/// DEBUG-only Lab client for Sprint 8.3A content understanding.
/// Uses `/v1/content-understand` — never Collection-oriented `/v1/understand`.
/// Does not write Collections or feed production organize.
enum MultimodalContentUnderstandingLabClient {
    private struct RequestBody: Encodable {
        var correlationId: String
        var schemaVersion: String
        var createdAt: String?
        var imageBase64: String
        var imageMimeType: String
        var localEvidence: MultimodalContentLocalEvidence
    }

    private struct GatewayErrorBody: Decodable {
        var error: GatewayErrorPayload?
    }

    private struct GatewayErrorPayload: Decodable {
        var code: String?
        var message: String?
        var correlationId: String?
    }

    static func analyze(
        snapshot: VisualAnalysisDebugSnapshot,
        configuration: AppConfiguration,
        imageLoader: PhotoKitMultimodalImageLoader = PhotoKitMultimodalImageLoader(),
        session: URLSession = UnderstandingGatewayURLSession.shared
    ) async -> Result<MultimodalContentUnderstanding, MultimodalContentLabError> {
        switch CloudUnderstandingPreferences.consent {
        case .notDetermined:
            return .failure(.consentRequired)
        case .declined:
            return .failure(.consentDeclined)
        case .accepted:
            break
        }

        guard let baseURL = UnderstandingGatewayConfiguration.baseURL(from: configuration) else {
            return .failure(.gatewayUnavailable)
        }

        guard let localID = snapshot.photosLocalIdentifier, !localID.isEmpty else {
            return .failure(.missingPhotosIdentifier)
        }

        guard let image = await imageLoader.loadUIImage(localIdentifier: localID) else {
            return .failure(.imageLoadFailed)
        }
        guard let jpeg = MultimodalImageEncoder.jpegData(from: image) else {
            return .failure(.imageEncodeFailed)
        }

        let createdAtISO: String? = snapshot.createdAt.map {
            ISO8601DateFormatter().string(from: $0)
        }
        let localEvidence = MultimodalContentLocalEvidence(
            ocrText: snapshot.ocrText,
            visionLabels: snapshot.labels.map(\.identifier),
            facets: snapshot.facets,
            platform: snapshot.sourcePlatformField.value,
            contentType: snapshot.contentTypeField.value,
            contentFamily: snapshot.contentFamilyField.value,
            surface: snapshot.surfaceField.value,
            embeddedHints: snapshot.embeddedHints.map(\.debugLabel),
            createdAt: createdAtISO
        )

        let body = RequestBody(
            correlationId: snapshot.id.rawValue.uuidString,
            schemaVersion: MultimodalContentUnderstanding.schemaVersion,
            createdAt: createdAtISO,
            imageBase64: jpeg.base64EncodedString(),
            imageMimeType: "image/jpeg",
            localEvidence: localEvidence
        )

        let url = baseURL.appendingPathComponent("v1/content-understand")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = UnderstandingGatewayConfiguration.gatewayBearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 60
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            return .failure(.malformedResponse)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(.network(error.localizedDescription))
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.network("Non-HTTP response"))
        }

        if http.statusCode == 200 {
            do {
                let decoded = try JSONDecoder().decode(MultimodalContentUnderstanding.self, from: data)
                if let got = decoded.schemaVersion,
                   got != MultimodalContentUnderstanding.schemaVersion {
                    return .failure(.schemaMismatch(
                        expected: MultimodalContentUnderstanding.schemaVersion,
                        got: got
                    ))
                }
                if decoded.containsForbiddenCollectionFields {
                    return .failure(.forbiddenCollectionLeakage)
                }
                return .success(decoded)
            } catch {
                return .failure(.malformedResponse)
            }
        }

        if let err = try? JSONDecoder().decode(GatewayErrorBody.self, from: data),
           let payload = err.error {
            return .failure(.gateway(
                code: payload.code ?? "HTTP_\(http.statusCode)",
                message: payload.message ?? "Gateway error"
            ))
        }
        return .failure(.gateway(
            code: "HTTP_\(http.statusCode)",
            message: "Gateway returned status \(http.statusCode)"
        ))
    }
}
