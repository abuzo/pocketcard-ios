import Foundation
import CryptoKit
import PocketCardCore

struct IssueEnvelope: Encodable, Sendable {
    let metadata: String
    let imageBase64: String?
    let contentHash: String
}

struct PreparedIssue: Sendable {
    let cardID: UUID
    let revision: Int
    let envelope: IssueEnvelope
    init(card: Card, image: Data?) throws {
        let metadata = try card.exportMetadata()
        guard metadata.includesImage == (image != nil), image?.isEmpty != true else { throw PocketCardError.missingImage }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(metadata)
        guard bytes.count <= 64*1024, let text = String(data:bytes,encoding:.utf8) else {
            throw PocketCardError.validation("В карточке слишком много данных для выпуска.")
        }
        var hashed = bytes; hashed.append(0); if let image { hashed.append(image) }
        let hash = SHA256.hash(data:hashed).map { String(format:"%02x",$0) }.joined()
        envelope = IssueEnvelope(metadata:text,imageBase64:image?.base64EncodedString(),contentHash:hash)
        guard try encoder.encode(envelope).count <= 5*1024*1024 else {
            throw PocketCardError.validation("Размер выпуска превышает 5 MiB. Выберите другое фото.")
        }
        cardID = card.id; revision = card.revision
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward the installation token or content to a redirect target.
        completionHandler(nil)
    }
}

enum WalletClient {
    static let maximumResponseBytes = 12*1024*1024
    static let expectedMIME = "application/vnd.apple.pkpass"

    static func issue(_ prepared: PreparedIssue, configuration: SignerConfiguration) async throws -> Data {
        try configuration.validate()
        let endpoint = try SignerEndpoint(configuration.baseURL)
        var request = URLRequest(url:endpoint.issueURL)
        request.httpMethod = "POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue(expectedMIME,forHTTPHeaderField:"Accept")
        request.setValue("Bearer " + configuration.token,forHTTPHeaderField:"Authorization")
        request.httpBody = try JSONEncoder().encode(prepared.envelope)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        let session = URLSession(configuration:config,delegate:NoRedirectDelegate(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        do {
            let (stream,response) = try await session.bytes(for:request)
            guard let http = response as? HTTPURLResponse else { throw serviceError() }
            guard http.statusCode == 200 else { throw statusError(http.statusCode) }
            guard http.mimeType?.lowercased() == expectedMIME,
                  http.expectedContentLength <= Int64(maximumResponseBytes),
                  http.url == endpoint.issueURL else { throw serviceError() }
            var data = Data()
            if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
            for try await byte in stream {
                guard data.count < maximumResponseBytes else { throw serviceError() }
                data.append(byte)
                if data.count % 16384 == 0 { try Task.checkCancellation() }
            }
            guard !data.isEmpty else { throw serviceError() }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as PocketCardError { throw error }
        catch { throw serviceError() }
    }
    private static func serviceError() -> PocketCardError {
        .validation("Карточка сохранена. Выпуск в Wallet сейчас недоступен. Проверьте адрес сервиса и соединение.")
    }
    private static func statusError(_ code: Int) -> PocketCardError {
        switch code {
        case 401,403: return .validation("Проверьте токен сервиса в настройках PocketCard.")
        case 413: return .validation("Карточка слишком большая для выпуска. Уменьшите объём данных.")
        case 422: return .validation("Сервис отклонил содержимое карточки. Проверьте поля и фотографию.")
        case 429: return .validation("Сервис занят или достигнут лимит выпуска. Повторите попытку позже.")
        case 503: return .validation("Сервис выпуска требует настройки сертификата. Карточка сохранена в приложении.")
        default: return serviceError()
        }
    }
}
