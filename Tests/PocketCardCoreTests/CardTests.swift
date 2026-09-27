import Foundation
import XCTest
@testable import PocketCardCore

final class CardTests: XCTestCase {
    func complete(_ template: CardTemplate = .mixed) -> Card {
        var card = Card(template: template)
        card.title = "Дом 🏠"
        card.caption = "Личная подпись"
        card.fields = [CardField(label: "Код", value: "0000123")]
        card.imageID = UUID()
        return card
    }

    func testPhotoProjectionDoesNotLeakHiddenFields() throws {
        var card = complete()
        card.template = .photo
        let exported = try card.exportMetadata()
        XCTAssertTrue(exported.fields.isEmpty)
        XCTAssertEqual(card.fields.count, 1)
        XCTAssertEqual(exported.caption, card.caption)
    }

    func testInfoProjectionDoesNotLeakHiddenPhotoOrCaption() throws {
        let exported = try complete(.information).exportMetadata()
        XCTAssertFalse(exported.includesImage)
        XCTAssertNil(exported.caption)
        XCTAssertEqual(exported.fields.first?.value, "0000123")
    }

    func testDraftCanBeSavedButNotIssued() throws {
        let card = Card(template: .photo)
        XCTAssertNoThrow(try card.validateForSave())
        XCTAssertThrowsError(try card.exportMetadata())
    }

    func testFieldsStayStringsAndLongFrontValueIsOnlyAPlaceholder() throws {
        var card = complete(.information)
        card.fields[0].value = String(repeating: "я", count: 81)
        XCTAssertEqual(card.fields[0].frontValue, "См. подробности")
        XCTAssertEqual(try card.exportMetadata().fields[0].value.count, 81)
    }

    func testLimitsRejectInsteadOfTruncating() {
        var card = complete()
        card.title = String(repeating: "x", count: 61)
        XCTAssertThrowsError(try card.validateForSave())
        card.title = "Дом"
        card.fields = Array(repeating: CardField(label: "a", value: "b"), count: 11)
        XCTAssertThrowsError(try card.validateForSave())
    }

    func testDuplicateFieldIDsAreRejected() {
        var card = complete()
        card.fields.append(card.fields[0])
        XCTAssertThrowsError(try card.validateForSave())
    }

    func testCopyGetsIndependentIdentityAndNoIssueRecord() {
        let card = complete()
        let copy = card.duplicate()
        XCTAssertNotEqual(copy.id, card.id)
        XCTAssertNotEqual(copy.fields[0].id, card.fields[0].id)
        XCTAssertNil(copy.lastIssued)
        XCTAssertEqual(copy.fields[0].value, "0000123")
    }

    func testInvalidCropRejected() {
        var card = complete()
        card.crop.zoom = .infinity
        XCTAssertThrowsError(try card.validateForSave())
    }

    func testWalletStatusDependsOnObservedRevisionNotIssueMetadata() {
        let card = complete(.information)
        XCTAssertEqual(card.walletStatus(observation: .missing), .ready)
        XCTAssertEqual(card.walletStatus(observation: .present(revision: card.revision)), .installed)
        XCTAssertEqual(card.walletStatus(observation: .present(revision: card.revision - 1)), .changed)
        XCTAssertEqual(card.walletStatus(observation: .unavailable), .unknown)
    }

    func testExportUsesStableLowercaseUUIDAndContainsNoImageReference() throws {
        let card = complete()
        let encoder = JSONEncoder()
        let data = try encoder.encode(card.exportMetadata())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, card.id.uuidString.lowercased())
        XCTAssertNil(object["imageID"])
        XCTAssertNil(object["crop"])
    }
}
