import Foundation
import XCTest
@testable import PocketCardCore

final class IntegrationPolicyTests: XCTestCase {
    func testCropIsCenteredAndWithinSource() throws {
        let crop = CropSettings()
        let rect = try crop.rect(imageWidth: 400, imageHeight: 300)
        XCTAssertEqual(rect.height, 300, accuracy: 0.001)
        XCTAssertEqual(rect.width / rect.height, 358.0 / 448.0, accuracy: 0.0001)
        XCTAssertEqual(rect.x, (400 - rect.width) / 2, accuracy: 0.001)
    }
    func testCropZoomAndCornerDoNotReadOutsideImage() throws {
        var crop = CropSettings(); crop.zoom = 3; crop.horizontal = 1; crop.vertical = 0
        let rect = try crop.rect(imageWidth: 100, imageHeight: 200)
        XCTAssertEqual(rect.x + rect.width, 100, accuracy: 0.001)
        XCTAssertEqual(rect.y, 0)
        XCTAssertThrowsError(try crop.rect(imageWidth: .infinity, imageHeight: 100))
        XCTAssertThrowsError(try crop.rect(imageWidth: 0, imageHeight: 100))
    }
    func testEndpointOnlyAcceptsAnHTTPSOrigin() throws {
        XCTAssertEqual(try SignerEndpoint("https://example.test:8443/").issueURL.absoluteString, "https://example.test:8443/v1/passes")
        for text in ["http://example.test", "file:///secret", "https://u:p@example.test", "https://example.test/?token=x", "https://example.test/#x", "https://example.test/custom", "not a url"] {
            XCTAssertThrowsError(try SignerEndpoint(text), text)
        }
    }
    func testTokenPolicy() {
        XCTAssertTrue(SignerEndpoint.isValidToken(String(repeating: "a", count: 32)))
        XCTAssertFalse(SignerEndpoint.isValidToken("short"))
        XCTAssertFalse(SignerEndpoint.isValidToken(String(repeating: "a", count: 32) + "\n"))
        XCTAssertFalse(SignerEndpoint.isValidToken(String(repeating: "ю", count: 32)))
    }
    func testReceiptRejectsStaleOrForeignPass() throws {
        let id = UUID()
        let receipt = PassEvidence(cardID: id.uuidString.lowercased(), revision: 3, contentHash: String(repeating: "a",count: 64), passTypeIdentifier: "pass.test.card", teamIdentifier: "TESTTEAM01")
        XCTAssertNoThrow(try receipt.validate(cardID: id, revision: 3, contentHash: String(repeating: "a", count: 64), passTypeIdentifier: "pass.test.card", teamIdentifier: "TESTTEAM01"))
        XCTAssertThrowsError(try receipt.validate(cardID: id, revision: 4, contentHash: String(repeating: "a", count: 64), passTypeIdentifier: "pass.test.card", teamIdentifier: "TESTTEAM01"))
        XCTAssertThrowsError(try receipt.validate(cardID: UUID(), revision: 3, contentHash: String(repeating: "a", count: 64), passTypeIdentifier: "pass.test.card", teamIdentifier: "TESTTEAM01"))
        XCTAssertThrowsError(try receipt.validate(cardID: id, revision: 3, contentHash: String(repeating: "b", count: 64), passTypeIdentifier: "pass.test.card", teamIdentifier: "TESTTEAM01"))
    }
}
