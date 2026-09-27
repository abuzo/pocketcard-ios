import Foundation

public struct LibrarySnapshot: Sendable {
    public let cards: [Card]
    public let unreadableFiles: [String]
}

/// Serializes all file operations. Image writes precede the atomic JSON replacement.
public final class CardRepository: @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private let fm = FileManager.default
    private var cardsURL: URL { root.appendingPathComponent("cards", isDirectory: true) }
    private var imagesURL: URL { root.appendingPathComponent("images", isDirectory: true) }
    public init(root: URL) { self.root = root }

    public func load() throws -> LibrarySnapshot {
        lock.lock(); defer { lock.unlock() }
        try prepareDirectories()
        return try loadUnlocked()
    }
    public func save(_ input: Card, image: Data? = nil) throws -> Card {
        lock.lock(); defer { lock.unlock() }
        try input.validateForSave()
        try prepareDirectories()
        var result = input
        let path = cardURL(input.id)
        let existing: Card? = fm.fileExists(atPath: path.path) ? try decode(path) : nil
        if let existing, existing.revision != input.revision { throw PocketCardError.staleRevision }
        var newImageURL: URL?
        do {
            if let image {
                guard image.count <= 25 * 1024 * 1024 else { throw PocketCardError.validation("Фото превышает 25 MiB.") }
                let newID = UUID()
                newImageURL = imageURL(newID)
                try protectedWrite(image, to: imageURL(newID))
                result.imageID = newID
            } else if let id = result.imageID, !fm.fileExists(atPath: imageURL(id).path) {
                throw PocketCardError.missingImage
            }
            if let existing {
                result.createdAt = existing.createdAt
                if !existing.hasSameContent(as: result) {
                    guard existing.revision < Int.max - 1 else {
                        throw PocketCardError.validation("Достигнут предел версий. Создайте копию карточки.")
                    }
                    result.revision = existing.revision + 1
                    result.updatedAt = Date()
                } else { result.updatedAt = existing.updatedAt }
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try protectedWrite(encoder.encode(result), to: path)
        } catch {
            if let newImageURL { try? fm.removeItem(at: newImageURL) }
            throw error
        }
        // Cleanup failure must not misreport a successfully saved card as a failed save.
        if let oldID = existing?.imageID, oldID != result.imageID { try? removeImageIfUnreferenced(oldID) }
        return result
    }
    public func delete(_ id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let card = try decode(cardURL(id))
        try fm.removeItem(at: cardURL(id))
        if let imageID = card.imageID { try? removeImageIfUnreferenced(imageID) }
    }
    public func imageData(for card: Card) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let id = card.imageID else { return nil }
        return try Data(contentsOf: imageURL(id))
    }
    private func loadUnlocked() throws -> LibrarySnapshot {
        var cards: [Card] = []; var unreadable: [String] = []
        for path in try fm.contentsOfDirectory(at: cardsURL, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) {
            do {
                let card = try decode(path)
                guard path.deletingPathExtension().lastPathComponent == card.id.uuidString.lowercased() else {
                    throw PocketCardError.validation("Идентификатор файла отличается от карточки.")
                }
                cards.append(card)
            } catch { unreadable.append(path.lastPathComponent) }
        }
        return LibrarySnapshot(cards: cards.sorted { $0.updatedAt > $1.updatedAt }, unreadableFiles: unreadable.sorted())
    }
    private func decode(_ path: URL) throws -> Card {
        let card = try JSONDecoder().decode(Card.self, from: Data(contentsOf: path))
        try card.validateForSave()
        return card
    }
    private func cardURL(_ id: UUID) -> URL { cardsURL.appendingPathComponent(id.uuidString.lowercased() + ".json") }
    private func imageURL(_ id: UUID) -> URL { imagesURL.appendingPathComponent(id.uuidString.lowercased() + ".jpg") }
    private func prepareDirectories() throws {
        for path in [root, cardsURL, imagesURL] {
            #if os(iOS)
            try fm.createDirectory(at: path, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            #else
            try fm.createDirectory(at: path, withIntermediateDirectories: true)
            #endif
        }
    }
    private func protectedWrite(_ data: Data, to path: URL) throws {
        #if os(iOS)
        try data.write(to: path, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: path, options: .atomic)
        #endif
    }
    private func removeImageIfUnreferenced(_ id: UUID) throws {
        let snapshot = try loadUnlocked()
        // A damaged record may still own this image. Never destroy its recovery path.
        guard snapshot.unreadableFiles.isEmpty, !snapshot.cards.contains(where: { $0.imageID == id }) else { return }
        try? fm.removeItem(at: imageURL(id))
    }
}
