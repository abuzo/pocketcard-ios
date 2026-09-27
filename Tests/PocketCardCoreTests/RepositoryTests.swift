import Foundation
import XCTest
@testable import PocketCardCore

final class RepositoryTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func card() -> Card { var c = Card(template: .information); c.title = "Карточка"; c.fields = [CardField(label: "Код", value: "001")]; return c }

    func testRoundTripAndRestart() throws {
        let saved = try CardRepository(root: root).save(card())
        let list = try CardRepository(root: root).load()
        XCTAssertEqual(list.cards, [saved])
        XCTAssertTrue(list.unreadableFiles.isEmpty)
    }
    func testUnchangedSaveDoesNotIncreaseRevision() throws {
        let repo = CardRepository(root: root)
        let first = try repo.save(card())
        XCTAssertEqual(try repo.save(first).revision, first.revision)
    }
    func testUpdateIncreasesRevisionAndStaleEditIsRejected() throws {
        let repo = CardRepository(root: root)
        let first = try repo.save(card())
        var update = first; update.title = "Новое название"
        let second = try repo.save(update)
        XCTAssertEqual(second.revision, first.revision + 1)
        XCTAssertThrowsError(try repo.save(first))
        XCTAssertEqual(try repo.load().cards.first?.title, "Новое название")
    }
    func testCorruptRecordDoesNotHideOtherCards() throws {
        let repo = CardRepository(root: root)
        _ = try repo.save(card())
        let broken = root.appendingPathComponent("cards").appendingPathComponent(UUID().uuidString.lowercased() + ".json")
        try Data("invalid".utf8).write(to: broken)
        let snapshot = try repo.load()
        XCTAssertEqual(snapshot.cards.count, 1)
        XCTAssertEqual(snapshot.unreadableFiles.count, 1)
    }
    func testFailedValidationKeepsPreviousVersion() throws {
        let repo = CardRepository(root: root)
        var saved = try repo.save(card())
        saved.title = String(repeating: "x", count: 61)
        XCTAssertThrowsError(try repo.save(saved))
        XCTAssertEqual(try repo.load().cards[0].title, "Карточка")
    }
    func testImageAndCopySurviveDeletingOriginal() throws {
        let repo = CardRepository(root: root)
        let first = try repo.save(card(), image: Data([1, 2, 3]))
        let copy = try repo.save(first.duplicate())
        try repo.delete(first.id)
        XCTAssertEqual(try repo.imageData(for: copy), Data([1, 2, 3]))
    }
    func testFutureSchemaIsReportedNotSilentlyDeleted() throws {
        let repo = CardRepository(root: root)
        let c = try repo.save(card())
        let path = root.appendingPathComponent("cards/\(c.id.uuidString.lowercased()).json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
        object["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        let snapshot = try repo.load()
        XCTAssertTrue(snapshot.cards.isEmpty)
        XCTAssertEqual(snapshot.unreadableFiles.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }
    func testRevisionLimitNeverOverwritesReadableRecord() throws {
        let repo = CardRepository(root: root)
        var input = card(); input.revision = Int.max - 1
        let original = try repo.save(input)
        var edited = original; edited.title = "Изменение"
        XCTAssertThrowsError(try repo.save(edited))
        let snapshot = try repo.load()
        XCTAssertEqual(snapshot.cards, [original])
        XCTAssertTrue(snapshot.unreadableFiles.isEmpty)
    }

}
