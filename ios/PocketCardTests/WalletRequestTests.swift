import XCTest
import CryptoKit
import PocketCardCore
@testable import PocketCard

final class WalletRequestTests: XCTestCase {
    func testInformationNeverSendsHiddenPhotoAndCaption() throws {
        var card = Card(template: .information)
        card.title = "Дом"; card.caption = "HIDDEN"; card.imageID = UUID()
        card.fields = [CardField(label: "Код", value: "0001")]
        let prepared = try PreparedIssue(card: card, image: nil)
        let envelope = prepared.envelope
        XCTAssertNil(envelope.imageBase64)
        XCTAssertFalse(envelope.metadata.contains("HIDDEN"))
        XCTAssertFalse(envelope.metadata.contains("imageID"))
        let expected = SHA256.hash(data: Data(envelope.metadata.utf8) + Data([0])).map { String(format:"%02x",$0) }.joined()
        XCTAssertEqual(envelope.contentHash, expected)
    }
    func testPhotoNeverExportsHiddenFields() throws {
        var card = Card(template: .photo); card.title = "Фото"; card.imageID = UUID()
        card.fields = [CardField(label: "Секрет", value: "HIDDEN")]
        let prepared = try PreparedIssue(card: card, image: Data([1,2,3]))
        XCTAssertFalse(prepared.envelope.metadata.contains("HIDDEN"))
        XCTAssertNotNil(prepared.envelope.imageBase64)
    }
    func testPhotoRequiresPreparedImageAndInfoRejectsOne() throws {
        var card = Card(template: .photo); card.title = "Фото"; card.imageID = UUID()
        XCTAssertThrowsError(try PreparedIssue(card: card,image: nil))
        card.template = .information; card.fields = [CardField(label:"Код",value:"1")]
        XCTAssertThrowsError(try PreparedIssue(card: card,image: Data([1])))
    }
    func testResponseMIMEAndSizePolicy() {
        XCTAssertEqual(WalletClient.maximumResponseBytes,12*1024*1024)
        XCTAssertEqual(WalletClient.expectedMIME,"application/vnd.apple.pkpass")
    }
}
