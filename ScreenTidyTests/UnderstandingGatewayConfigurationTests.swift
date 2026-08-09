import XCTest
@testable import ScreenTidy

final class UnderstandingGatewayConfigurationTests: XCTestCase {
    func testValidatesLANIPv4WithPort_192_168_104_2() throws {
        let url = try UnderstandingGatewayConfiguration.validatedURL(from: "http://192.168.104.2:8787")
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "192.168.104.2")
        XCTAssertEqual(url.port, 8787)
        XCTAssertEqual(url.absoluteString, "http://192.168.104.2:8787")
    }

    func testValidatesLANIPv4WithPort_192_168_1_47() throws {
        let url = try UnderstandingGatewayConfiguration.validatedURL(from: "http://192.168.1.47:8787")
        XCTAssertEqual(url.host, "192.168.1.47")
        XCTAssertEqual(url.port, 8787)
    }

    func testValidatesLoopback() throws {
        let url = try UnderstandingGatewayConfiguration.validatedURL(from: "http://127.0.0.1:8787")
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.port, 8787)
    }

    func testValidatesLocalhost() throws {
        let url = try UnderstandingGatewayConfiguration.validatedURL(from: "http://localhost:8787")
        XCTAssertEqual(url.host, "localhost")
        XCTAssertEqual(url.port, 8787)
    }

    func testValidatesHTTPSFutureGateway() throws {
        let url = try UnderstandingGatewayConfiguration.validatedURL(from: "https://example.com")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "example.com")
        XCTAssertNil(url.port)
    }

    func testAcceptsPrivateRanges_10_and_172() throws {
        let ten = try UnderstandingGatewayConfiguration.validatedURL(from: "http://10.0.0.5:8787")
        XCTAssertEqual(ten.host, "10.0.0.5")

        let seventeen = try UnderstandingGatewayConfiguration.validatedURL(from: "http://172.16.4.8:8787")
        XCTAssertEqual(seventeen.host, "172.16.4.8")
    }

    func testTrimsWhitespaceAndTrailingSlash() throws {
        let url = try UnderstandingGatewayConfiguration.validatedURL(from: "  http://192.168.104.2:8787/ \n")
        XCTAssertEqual(url.absoluteString, "http://192.168.104.2:8787")
    }

    func testNormalizesFullwidthColon() throws {
        // iOS / paste can introduce U+FF1A, which makes URL(string:) return nil.
        let raw = "http://192.168.104.2\u{FF1A}8787"
        let url = try UnderstandingGatewayConfiguration.validatedURL(from: raw)
        XCTAssertEqual(url.absoluteString, "http://192.168.104.2:8787")
    }

    func testRejectsMissingScheme() {
        XCTAssertThrowsError(try UnderstandingGatewayConfiguration.validatedURL(from: "192.168.104.2:8787")) { error in
            XCTAssertEqual(error as? UnderstandingGatewayConfiguration.URLValidationError, .missingScheme)
        }
    }

    func testRejectsEmpty() {
        XCTAssertThrowsError(try UnderstandingGatewayConfiguration.validatedURL(from: "   ")) { error in
            XCTAssertEqual(error as? UnderstandingGatewayConfiguration.URLValidationError, .empty)
        }
    }

    func testRejectsNonHTTPSchemes() {
        XCTAssertThrowsError(try UnderstandingGatewayConfiguration.validatedURL(from: "ftp://192.168.104.2:8787")) { error in
            XCTAssertEqual(error as? UnderstandingGatewayConfiguration.URLValidationError, .missingScheme)
        }
    }

    func testHealthPathAppend() throws {
        let base = try UnderstandingGatewayConfiguration.validatedURL(from: "http://192.168.104.2:8787")
        XCTAssertEqual(base.appendingPathComponent("health").absoluteString, "http://192.168.104.2:8787/health")
    }
}
