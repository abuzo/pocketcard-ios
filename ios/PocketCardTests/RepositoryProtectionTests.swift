import XCTest
import Foundation
import PocketCardCore

final class RepositoryProtectionTests: XCTestCase {
    func testIOSFilesUseCompleteDataProtection() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("File protection attributes require a physical iPhone; Simulator returns nil.")
        #else
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let repo = CardRepository(root:root)
        let saved = try repo.save(Card(template:.photo),image:Data([1,2,3]))
        let url = root.appendingPathComponent("cards/\(saved.id.uuidString.lowercased()).json")
        let attributes = try FileManager.default.attributesOfItem(atPath:url.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType,.complete)
        #endif
    }
}
