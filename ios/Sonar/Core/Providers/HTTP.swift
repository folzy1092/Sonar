import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // тесты логики на Linux
#endif

/// Запросы к сервисам прямо с телефона (сервера пока нет, SPEC §9): GET с параметрами и заголовками,
/// не-2xx → понятная ошибка сервиса.
enum HTTP {
    static let browserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    /// Десктопный браузер: сайты вроде soundcloud.com с айфонным агентом уводят на мобильную версию без нужных скриптов.
    static let desktopAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

    static func url(_ base: String, query: [(String, String)]) throws -> URL {
        guard var components = URLComponents(string: base) else { throw ServiceError(message: "Неверный адрес: \(base)") }
        if !query.isEmpty {
            var items = components.queryItems ?? []
            items.append(contentsOf: query.map { URLQueryItem(name: $0.0, value: $0.1) })
            components.queryItems = items
            // «+» в значениях URLComponents не кодирует, а сервер прочитает его как пробел
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw ServiceError(message: "Неверный адрес: \(base)") }
        return url
    }

    static func data(_ request: URLRequest, service: String, session: URLSession = .shared) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else { throw ServiceError.http(service, status) }
        return data
    }

    /// Тело `application/x-www-form-urlencoded`.
    static func form(_ fields: [(String, String)]) -> Data {
        // только ASCII unreserved: alphanumerics пропустил бы кириллицу как есть
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = fields.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
        return Data(body.utf8)
    }
}
