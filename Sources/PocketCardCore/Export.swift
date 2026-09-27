import Foundation

public struct ExportField: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: String
}

public struct ExportMetadata: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let revision: Int
    public let template: CardTemplate
    public let title: String
    public let caption: String?
    public let fields: [ExportField]
    public let theme: CardTheme
    public let includesImage: Bool
}

public extension Card {
    func exportMetadata() throws -> ExportMetadata {
        try validateForSave()
        guard !title.trimmed.isEmpty else { throw PocketCardError.validation("Добавьте название карточки.") }
        if template.usesImage && imageID == nil { throw PocketCardError.missingImage }
        if template.usesFields {
            guard !fields.isEmpty else { throw PocketCardError.validation("Добавьте хотя бы одно поле.") }
            guard fields.allSatisfy({ !$0.label.trimmed.isEmpty && !$0.value.trimmed.isEmpty }) else {
                throw PocketCardError.validation("Заполните название и значение каждого поля или удалите пустое поле.")
            }
        }
        return ExportMetadata(
            schemaVersion: 1, id: id.uuidString.lowercased(), revision: revision,
            template: template, title: title,
            caption: template.usesImage && !caption.isEmpty ? caption : nil,
            fields: template.usesFields ? fields.map { ExportField(id: $0.id.uuidString.lowercased(), label: $0.label, value: $0.value) } : [],
            theme: theme, includesImage: template.usesImage
        )
    }
}

public enum WalletObservation: Equatable, Sendable {
    case missing, present(revision: Int), unavailable
}

public enum WalletStatus: String, Equatable, Sendable {
    case draft = "Черновик"
    case ready = "Готова к добавлению"
    case installed = "В Wallet"
    case changed = "Есть изменения"
    case unknown = "Статус Wallet недоступен"
}

public extension Card {
    func walletStatus(observation: WalletObservation) -> WalletStatus {
        guard isReady else { return .draft }
        switch observation {
        case .missing: return .ready
        case .unavailable: return .unknown
        case .present(let installedRevision): return installedRevision == revision ? .installed : .changed
        }
    }
}
