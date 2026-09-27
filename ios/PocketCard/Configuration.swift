import Foundation
import Security
import PocketCardCore

struct SignerConfiguration: Codable, Equatable, Sendable {
    var baseURL: String
    var operatorName: String
    var token: String
    func validate() throws {
        _ = try SignerEndpoint(baseURL)
        guard !operatorName.trimmed.isEmpty, operatorName.unicodeScalars.count <= 100 else {
            throw PocketCardError.validation("Укажите оператора сервиса — до 100 символов.")
        }
        guard SignerEndpoint.isValidToken(token) else {
            throw PocketCardError.validation("Токен: 32–256 латинских букв, цифр, дефисов или подчёркиваний.")
        }
    }
}

enum BuildIdentity {
    static var passTypeIdentifier: String { Bundle.main.object(forInfoDictionaryKey:"PocketCardPassTypeIdentifier") as? String ?? "" }
    static var teamIdentifier: String { Bundle.main.object(forInfoDictionaryKey:"PocketCardTeamIdentifier") as? String ?? "" }
    static var walletAccessEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey:"PocketCardWalletAccessEnabled")
        if let value = value as? Bool { return value }
        return (value as? NSString)?.boolValue ?? false
    }
    static var isConfigured: Bool { walletAccessEnabled && passTypeIdentifier.hasPrefix("pass.") && teamIdentifier.count == 10 }
}

/// Device-only, non-synchronizing Keychain item; no credentials go into preferences or files.
struct ConfigurationStore {
    private let service = "PocketCard.private-signer.v1"
    private var query: [String:Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "installation",
         kSecAttrSynchronizable as String: false]
    }
    func load() throws -> SignerConfiguration? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PocketCardError.validation("Настройки сервиса сейчас недоступны. Разблокируйте iPhone и повторите действие.")
        }
        return try JSONDecoder().decode(SignerConfiguration.self,from:data)
    }
    func save(_ configuration: SignerConfiguration) throws {
        try configuration.validate()
        let data = try JSONEncoder().encode(configuration)
        let attributes: [String:Any] = [kSecValueData as String:data,
                                      kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary,attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            attributes.forEach { insertion[$0.key] = $0.value }
            status = SecItemAdd(insertion as CFDictionary,nil)
        }
        guard status == errSecSuccess else { throw PocketCardError.validation("Настройки не сохранены. Повторите действие после разблокировки iPhone.") }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PocketCardError.validation("Настройки сервиса сейчас недоступны.")
        }
    }
}
