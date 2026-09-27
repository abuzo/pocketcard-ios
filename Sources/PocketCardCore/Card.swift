import Foundation

public enum CardTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case photo, information, mixed
    public var id: String { rawValue }
    public var title: String {
        switch self { case .photo: return "Фото"; case .information: return "Информация"; case .mixed: return "Фото + информация" }
    }
    public var symbol: String {
        switch self { case .photo: return "photo"; case .information: return "text.alignleft"; case .mixed: return "rectangle.on.rectangle" }
    }
    public var usesImage: Bool { self != .information }
    public var usesFields: Bool { self != .photo }
}

public enum CardTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case ocean, forest, plum, sand
    public var id: String { rawValue }
    public var title: String {
        switch self { case .ocean: return "Океан"; case .forest: return "Лес"; case .plum: return "Слива"; case .sand: return "Песок" }
    }
    public var backgroundRGB: [Double] {
        switch self {
        case .ocean: return [19, 48, 74]
        case .forest: return [20, 62, 48]
        case .plum: return [66, 36, 71]
        case .sand: return [243, 232, 210]
        }
    }
    public var usesDarkText: Bool { self == .sand }
}

public enum CropAspect: String, Codable, CaseIterable, Identifiable, Sendable {
    case poster, square, landscape
    public var id: String { rawValue }
    public var ratio: Double {
        switch self { case .poster: return 358.0 / 448.0; case .square: return 1; case .landscape: return 4.0 / 3.0 }
    }
    public var title: String {
        switch self { case .poster: return "Портрет"; case .square: return "Квадрат"; case .landscape: return "Альбом" }
    }
}

public struct CropSettings: Codable, Equatable, Sendable {
    public var aspect: CropAspect = .poster
    public var zoom: Double = 1
    public var horizontal: Double = 0.5
    public var vertical: Double = 0.5
    public init() {}
    public var isValid: Bool {
        zoom.isFinite && (1...3).contains(zoom) && horizontal.isFinite && (0...1).contains(horizontal)
            && vertical.isFinite && (0...1).contains(vertical)
    }
}

public struct CardField: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var value: String
    public init(id: UUID = UUID(), label: String = "", value: String = "") {
        self.id = id; self.label = label; self.value = value
    }
    public var frontValue: String { value.unicodeScalars.count > 80 ? "См. подробности" : value }
}

public struct IssueRecord: Codable, Equatable, Sendable {
    public var revision: Int
    public var contentHash: String
    public var passTypeIdentifier: String
    public var serialNumber: String
    public init(revision: Int, contentHash: String, passTypeIdentifier: String, serialNumber: String) {
        self.revision = revision; self.contentHash = contentHash
        self.passTypeIdentifier = passTypeIdentifier; self.serialNumber = serialNumber
    }
}

public enum PocketCardError: LocalizedError, Equatable {
    case validation(String), staleRevision, missingImage, unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .validation(let text): return text
        case .staleRevision: return "Карточка уже изменена. Откройте текущую версию и повторите действие."
        case .missingImage: return "Фото недоступно. Выберите изображение повторно."
        case .unsupportedVersion: return "Эта карточка создана более новой версией PocketCard."
        }
    }
}

public struct Card: Identifiable, Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var id: UUID
    public var template: CardTemplate
    public var title = ""
    public var caption = ""
    public var fields: [CardField] = []
    public var theme: CardTheme = .ocean
    public var imageID: UUID?
    public var crop = CropSettings()
    public var createdAt: Date
    public var updatedAt: Date
    public var revision = 1
    public var lastIssued: IssueRecord?

    public init(id: UUID = UUID(), template: CardTemplate = .mixed, now: Date = Date()) {
        self.id = id; self.template = template; createdAt = now; updatedAt = now
    }
    public var displayTitle: String { title.trimmed.isEmpty ? "Без названия" : title }
    public var isReady: Bool { (try? exportMetadata()) != nil }

    public func validateForSave() throws {
        guard schemaVersion == 1 else { throw PocketCardError.unsupportedVersion }
        guard revision > 0, revision < Int.max, crop.isValid else { throw PocketCardError.validation("Проверьте параметры карточки.") }
        try Self.limit(title, maximum: 60, name: "Название")
        try Self.limit(caption, maximum: 500, name: "Подпись")
        guard fields.count <= 10 else { throw PocketCardError.validation("Можно добавить до 10 полей.") }
        guard Set(fields.map(\.id)).count == fields.count else { throw PocketCardError.validation("Поля должны иметь разные идентификаторы.") }
        for field in fields {
            try Self.limit(field.label, maximum: 40, name: "Название поля")
            try Self.limit(field.value, maximum: 2_000, name: "Значение поля")
        }
    }
    private static func limit(_ text: String, maximum: Int, name: String) throws {
        guard text.unicodeScalars.count <= maximum else {
            throw PocketCardError.validation("\(name): максимум \(maximum) символов Unicode.")
        }
        guard !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw PocketCardError.validation("\(name): удалите нулевой управляющий символ.")
        }
    }
    public func duplicate(now: Date = Date()) -> Card {
        var result = self
        result.id = UUID(); result.createdAt = now; result.updatedAt = now
        result.revision = 1; result.lastIssued = nil
        result.fields = fields.map { CardField(label: $0.label, value: $0.value) }
        return result
    }
    public func hasSameContent(as other: Card) -> Bool {
        template == other.template && title == other.title && caption == other.caption
        && fields == other.fields && theme == other.theme && imageID == other.imageID && crop == other.crop
    }
}

public extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
