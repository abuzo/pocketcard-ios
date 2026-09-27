import Foundation

public struct CropRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

public extension CropSettings {
    func rect(imageWidth: Double, imageHeight: Double) throws -> CropRect {
        guard isValid, imageWidth.isFinite, imageHeight.isFinite, imageWidth > 0, imageHeight > 0 else {
            throw PocketCardError.validation("Проверьте параметры фотографии.")
        }
        let baseWidth = min(imageWidth, imageHeight * aspect.ratio)
        let baseHeight = baseWidth / aspect.ratio
        let w = baseWidth / zoom
        let h = baseHeight / zoom
        return CropRect(x: (imageWidth - w) * horizontal, y: (imageHeight - h) * vertical, width: w, height: h)
    }
}

public struct SignerEndpoint: Equatable, Sendable {
    public let baseURL: URL
    public var issueURL: URL { baseURL.appendingPathComponent("v1/passes") }

    public init(_ text: String) throws {
        guard let components = URLComponents(string: text.trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.port.map({ (1...65535).contains($0) }) ?? true,
              let url = components.url else {
            throw PocketCardError.validation("Введите HTTPS-адрес сервиса без пути, логина и параметров, например https://passes.example.com.")
        }
        baseURL = url
    }
    public static func isValidToken(_ text: String) -> Bool {
        guard (32...256).contains(text.utf8.count) else { return false }
        return text.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }
}

public struct PassEvidence: Equatable, Sendable {
    public let cardID: String
    public let revision: Int
    public let contentHash: String
    public let passTypeIdentifier: String
    public let teamIdentifier: String
    public init(cardID: String, revision: Int, contentHash: String, passTypeIdentifier: String, teamIdentifier: String) {
        self.cardID = cardID; self.revision = revision; self.contentHash = contentHash
        self.passTypeIdentifier = passTypeIdentifier; self.teamIdentifier = teamIdentifier
    }
    public func validate(cardID: UUID, revision: Int, contentHash: String, passTypeIdentifier: String, teamIdentifier: String) throws {
        guard self.cardID == cardID.uuidString.lowercased(), self.revision == revision,
              self.contentHash == contentHash, self.passTypeIdentifier == passTypeIdentifier,
              self.teamIdentifier == teamIdentifier else {
            throw PocketCardError.validation("Полученная карточка не соответствует запросу. Повторите выпуск.")
        }
    }
}
