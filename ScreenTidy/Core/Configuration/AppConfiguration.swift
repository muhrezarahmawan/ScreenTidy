import Foundation

/// Gateway URL + schema configuration. Provider/model live only on the gateway.
enum UnderstandingGatewayConfiguration {
    private static let urlKey = "screentidy.understandingGatewayURL"
    static let schemaVersion = "screentidy-understanding-v2"

    struct HealthInfo: Sendable, Equatable {
        var ok: Bool
        var schemaVersion: String?
        var modelConfigured: Bool?
        var endpoint: String
    }

    enum URLValidationError: LocalizedError, Equatable {
        case empty
        case invalid
        case missingScheme
        case missingHost
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .empty: "Enter a gateway URL."
            case .invalid: "That doesn’t look like a valid URL."
            case .missingScheme: "Include http:// or https://."
            case .missingHost: "Include a host (e.g. 192.168.1.20) and port."
            case .invalidPort: "Port must be between 1 and 65535."
            }
        }
    }

    /// Prefer DEBUG UserDefaults override, then bundled Info.plist URL, then AppConfiguration default.
    static func baseURL(from configuration: AppConfiguration) -> URL? {
        if let raw = overrideURLString,
           let url = try? validatedURL(from: raw) {
            return url
        }
        if let bundled = bundledBaseURL {
            return bundled
        }
        return configuration.apiBaseURL
    }

    /// Hosted HTTPS URL from build settings → Info.plist (`ScreenTidyGatewayBaseURL`).
    static var bundledBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ScreenTidyGatewayBaseURL") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("YOUR_RAILWAY_HOST"),
              let url = try? validatedURL(from: trimmed)
        else {
            return nil
        }
        return url
    }

    /// MVP/TestFlight gateway bearer token from Info.plist (`ScreenTidyGatewayToken`).
    /// Not the OpenAI API key. Embedding in the binary is not strong production auth.
    static var gatewayBearerToken: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ScreenTidyGatewayToken") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var displayURLString: String {
        if let override = overrideURLString, !override.isEmpty {
            return override
        }
        if let bundled = bundledBaseURL {
            return bundled.absoluteString
        }
        return AppConfiguration.current.apiBaseURL?.absoluteString ?? ""
    }

    static func setOverrideURL(_ string: String?) {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: urlKey)
        } else {
            UserDefaults.standard.removeObject(forKey: urlKey)
        }
    }

    static var overrideURLString: String? {
        UserDefaults.standard.string(forKey: urlKey)
    }

    /// Validates and normalizes a gateway base URL (no trailing path required).
    /// Uses `URLComponents` (not brittle regex) so LAN IPv4 hosts like `192.168.104.2` work.
    static func validatedURL(from raw: String) throws -> URL {
        let candidate = normalizeGatewayURLString(raw)
        guard !candidate.isEmpty else { throw URLValidationError.empty }

        guard var components = URLComponents(string: candidate) else {
            // Schemeless values like `192.168.104.2:8787` often fail to parse entirely.
            if !candidate.contains("://") {
                throw URLValidationError.missingScheme
            }
            throw URLValidationError.invalid
        }

        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw URLValidationError.missingScheme
        }
        components.scheme = scheme

        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            throw URLValidationError.missingHost
        }
        components.host = host

        if let port = components.port {
            guard (1...65_535).contains(port) else {
                throw URLValidationError.invalidPort
            }
        }

        // Base URL only — drop trailing slash / empty path noise.
        if components.path == "/" {
            components.path = ""
        } else if components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }

        guard let url = components.url else {
            throw URLValidationError.invalid
        }
        return url
    }

    /// Trim, strip invisible format chars, and normalize common fullwidth URL punctuation
    /// that iOS keyboards / paste can introduce (which makes `URL(string:)` return nil).
    static func normalizeGatewayURLString(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.unicodeScalars
            .filter { scalar in
                let isBom = scalar == "\u{FEFF}"
                let isFormat = CharacterSet.controlCharacters.contains(scalar)
                    || scalar.properties.generalCategory == .format
                return !isBom && !isFormat
            }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let replacements: [Character: Character] = [
            "\u{FF1A}": ":", // fullwidth colon
            "\u{FF0F}": "/", // fullwidth solidus
            "\u{2215}": "/", // division slash
            "\u{2044}": "/", // fraction slash
            "\u{FF0E}": ".", // fullwidth full stop
        ]
        trimmed = String(trimmed.map { replacements[$0] ?? $0 })

        if trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        return trimmed
    }

    enum HealthProbeFailure: Error, LocalizedError, Equatable {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let text): text
            }
        }
    }

    /// GET `{base}/health` — DEBUG connectivity check only.
    /// Uses a waitsForConnectivity session so the iOS Local Network permission prompt can complete.
    static func probeHealth(baseURL: URL, timeout: TimeInterval = 30) async -> Result<HealthInfo, HealthProbeFailure> {
        let endpoint = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await UnderstandingGatewayURLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.message("No HTTP response from \(endpoint.absoluteString)"))
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(.message("HTTP \(http.statusCode) from \(endpoint.absoluteString)"))
            }
            struct Payload: Decodable {
                var ok: Bool?
                var schemaVersion: String?
                var modelConfigured: Bool?
            }
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
            return .success(
                HealthInfo(
                    ok: payload?.ok ?? true,
                    schemaVersion: payload?.schemaVersion,
                    modelConfigured: payload?.modelConfigured,
                    endpoint: endpoint.absoluteString
                )
            )
        } catch {
            let category = OrganizationNetworkFailureCategory.classify(error)
            switch category {
            case .localNetworkPermission:
                return .failure(.message(
                    "Local Network permission blocked \(endpoint.absoluteString). Allow Local Network for ScreenTidy in Settings → Privacy & Security → Local Network, then Test Connection again."
                ))
            case .timeout:
                return .failure(.message(
                    "Timed out reaching \(endpoint.absoluteString). Confirm Mac gateway is running, same Wi‑Fi, and Local Network is allowed."
                ))
            case .connectionRefused:
                return .failure(.message(
                    "Cannot connect to \(endpoint.absoluteString) — is the gateway listening on 0.0.0.0:8787?"
                ))
            case .offline:
                return .failure(.message("Device is offline."))
            case .atsRejected:
                return .failure(.message("ATS blocked cleartext HTTP. NSAllowsLocalNetworking must be enabled for DEBUG LAN HTTP."))
            default:
                return .failure(.message("\(category.displayName): \(error.localizedDescription)"))
            }
        }
    }
}

struct AppConfiguration: Sendable {
    let environment: AppEnvironment
    let appDisplayName: String
    let bundleIdentifier: String
    /// ScreenTidy-owned understanding gateway (never a direct OpenAI URL).
    let apiBaseURL: URL?
    let loggingEnabled: Bool

    /// Default configuration derived from build configuration.
    static var current: AppConfiguration {
        #if DEBUG
        // Prefer hosted HTTPS from Secrets.xcconfig / Info.plist; Simulator may still use local override.
        return AppConfiguration(
            environment: .debug,
            appDisplayName: "ScreenTidy",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.screentidy.app",
            apiBaseURL: UnderstandingGatewayConfiguration.bundledBaseURL
                ?? URL(string: "http://127.0.0.1:8787"),
            loggingEnabled: true
        )
        #else
        return AppConfiguration(
            environment: .production,
            appDisplayName: "ScreenTidy",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.screentidy.app",
            apiBaseURL: UnderstandingGatewayConfiguration.bundledBaseURL,
            loggingEnabled: false
        )
        #endif
    }
}

enum AppEnvironment: String, Sendable {
    case debug
    case staging
    case production
}
