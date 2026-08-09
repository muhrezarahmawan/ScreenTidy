import Foundation

/// Classifies gateway / LAN URLSession failures for DEBUG diagnosis (no secrets / payloads).
enum OrganizationNetworkFailureCategory: String, Sendable, Equatable {
    case localNetworkPermission = "local_network_permission"
    case atsRejected = "ats_rejected"
    case invalidURL = "invalid_url"
    case connectionRefused = "connection_refused"
    case timeout = "timeout"
    case offline = "device_offline"
    case gatewayHTTP = "gateway_http_error"
    case providerError = "provider_error"
    case malformedResponse = "malformed_structured_response"
    case unknownNetwork = "unknown_network"

    var displayName: String {
        switch self {
        case .localNetworkPermission: "Local Network permission failure"
        case .atsRejected: "ATS rejection"
        case .invalidURL: "invalid URL"
        case .connectionRefused: "connection refused"
        case .timeout: "timeout"
        case .offline: "device offline"
        case .gatewayHTTP: "gateway HTTP error"
        case .providerError: "OpenAI/provider error"
        case .malformedResponse: "malformed structured response"
        case .unknownNetwork: "unknown network error"
        }
    }

    static func classify(_ error: Error) -> OrganizationNetworkFailureCategory {
        if let urlError = error as? URLError {
            return classify(urlError: urlError)
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return classify(urlError: URLError(_nsError: ns))
        }
        return .unknownNetwork
    }

    static func classify(urlError: URLError) -> OrganizationNetworkFailureCategory {
        let pathKey = (urlError as NSError).userInfo["_NSURLErrorNWPathKey"] as? String ?? ""
        if pathKey.localizedCaseInsensitiveContains("Local network prohibited")
            || pathKey.localizedCaseInsensitiveContains("local network") {
            return .localNetworkPermission
        }

        switch urlError.code {
        case .appTransportSecurityRequiresSecureConnection:
            return .atsRejected
        case .badURL, .unsupportedURL:
            return .invalidURL
        case .timedOut:
            return .timeout
        case .cannotConnectToHost, .cannotFindHost:
            // Often indistinguishable from Local Network deny until permission is granted.
            if pathKey.localizedCaseInsensitiveContains("unsatisfied") {
                return .localNetworkPermission
            }
            return .connectionRefused
        case .networkConnectionLost:
            return .connectionRefused
        case .notConnectedToInternet, .dataNotAllowed:
            return .offline
        default:
            if pathKey.localizedCaseInsensitiveContains("unsatisfied") {
                return .localNetworkPermission
            }
            return .unknownNetwork
        }
    }
}

/// Shared URLSession for DEBUG LAN gateway health + understand calls.
/// `waitsForConnectivity` lets the first Local Network permission prompt finish instead of hard-failing.
enum UnderstandingGatewayURLSession {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
}
