import XCTest
@testable import ScreenTidy

final class OrganizationNetworkDiagnosticsTests: XCTestCase {
    func testClassifiesTimeout() {
        let error = URLError(.timedOut)
        XCTAssertEqual(
            OrganizationNetworkFailureCategory.classify(urlError: error),
            .timeout
        )
    }

    func testClassifiesATS() {
        let error = URLError(.appTransportSecurityRequiresSecureConnection)
        XCTAssertEqual(
            OrganizationNetworkFailureCategory.classify(urlError: error),
            .atsRejected
        )
    }

    func testClassifiesLocalNetworkProhibitedPath() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.cannotConnectToHost.rawValue,
            userInfo: [
                "_NSURLErrorNWPathKey": "unsatisfied (Local network prohibited), interface: en0"
            ]
        )
        XCTAssertEqual(
            OrganizationNetworkFailureCategory.classify(error),
            .localNetworkPermission
        )
    }

    func testGatewayOverrideWinsOverDefaultLocalhost() throws {
        let previous = UnderstandingGatewayConfiguration.overrideURLString
        defer { UnderstandingGatewayConfiguration.setOverrideURL(previous) }

        UnderstandingGatewayConfiguration.setOverrideURL("http://192.168.104.2:8787")
        let config = AppConfiguration(
            environment: .debug,
            appDisplayName: "ScreenTidy",
            bundleIdentifier: "test",
            apiBaseURL: URL(string: "http://127.0.0.1:8787"),
            loggingEnabled: true
        )
        let resolved = UnderstandingGatewayConfiguration.baseURL(from: config)
        XCTAssertEqual(resolved?.absoluteString, "http://192.168.104.2:8787")
        XCTAssertNotEqual(resolved?.host, "127.0.0.1")
    }
}
