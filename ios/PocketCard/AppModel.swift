import SwiftUI
import PocketCardCore

struct UserMessage: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    init(_ text: String, title: String = "PocketCard") { self.text = text; self.title = title }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var cards: [Card] = []
    @Published private(set) var unreadableFiles: [String] = []
    @Published var error: UserMessage?
    let repository: CardRepository
    let configurationStore = ConfigurationStore()

    init() {
        // The system supplies this sandbox URL; never hard-code its per-installation UUID.
        let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("PocketCard",isDirectory:true)
        repository = CardRepository(root:root)
        reload()
    }
    func reload() {
        do {
            let snapshot = try repository.load()
            cards = snapshot.cards; unreadableFiles = snapshot.unreadableFiles
        } catch { self.error = message(for:error) }
    }
    func card(_ id: UUID) -> Card? { cards.first { $0.id == id } }
    @discardableResult
    func save(_ card: Card, image: Data? = nil) throws -> Card {
        let saved = try repository.save(card,image:image)
        reload()
        return saved
    }
    func duplicate(_ card: Card) {
        do { _ = try save(card.duplicate()) }
        catch { self.error = message(for:error) }
    }
    func delete(_ id: UUID) throws { try repository.delete(id); reload() }
    func message(for error: Error) -> UserMessage {
        if let known = error as? PocketCardError { return UserMessage(known.localizedDescription) }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
            return UserMessage("Освободите место на устройстве и повторите сохранение. Редактор остаётся открытым.")
        }
        return UserMessage("Операция с локальными данными сейчас недоступна. Разблокируйте iPhone и повторите действие. Исходные файлы сохранены.")
    }
}
