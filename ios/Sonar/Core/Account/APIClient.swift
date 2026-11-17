import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // тесты логики на Linux
#endif

/// Ошибка сервера Sonar — всегда `{"error": {"code", "message"}}` (API.md, начало).
struct APIError: LocalizedError, Equatable, Sendable {
    var status: Int
    var code: String
    var message: String

    var errorDescription: String? { message }

    /// Сервер ещё не подключён (флаг выключен или нет адреса).
    static let serverOff = APIError(status: 0, code: "server_off", message: "Сервер Sonar ещё не подключён")
    /// Своя сессия моложе 24 ч — другие завершать рано (`DELETE /me/devices/{id}`).
    static let sessionTooNewCode = "session_too_new"

    var isUnauthorized: Bool { status == 401 }
}

/// HTTP к серверу Sonar: JSON в обе стороны, `Authorization: Bearer <session>`. Сеть — замыкание
/// `fetch`, чтобы тесты подставляли свой сервер.
struct APIClient: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    let base: URL
    var token: String?
    var fetch: Fetch

    init(base: URL, token: String? = nil, fetch: Fetch? = nil) {
        self.base = base
        self.token = token
        self.fetch = fetch ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func with(token: String?) -> APIClient {
        var copy = self
        copy.token = token
        return copy
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    func request(_ method: String, _ path: String, query: [(String, String)] = [], body: (some Encodable)? = Optional<Empty>.none) throws -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let url = components?.url else { throw APIError(status: 0, code: "bad_url", message: "Неверный адрес сервера") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }
        return request
    }

    /// Запрос с ответом-JSON.
    func send<T: Decodable>(_ method: String, _ path: String, query: [(String, String)] = [], body: (some Encodable)? = Optional<Empty>.none,
                            as type: T.Type = T.self) async throws -> T {
        let data = try await raw(method, path, query: query, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(status: 200, code: "bad_response", message: "Сервер ответил непонятно")
        }
    }

    /// Запрос без тела ответа (`204`).
    func call(_ method: String, _ path: String, body: (some Encodable)? = Optional<Empty>.none) async throws {
        _ = try await raw(method, path, body: body)
    }

    private func raw(_ method: String, _ path: String, query: [(String, String)] = [], body: (some Encodable)?) async throws -> Data {
        let req = try request(method, path, query: query, body: body)
        let (data, status): (Data, Int)
        do {
            (data, status) = try await fetch(req)
        } catch {
            throw APIError(status: 0, code: "network", message: "Нет связи с сервером Sonar")
        }
        guard (200 ..< 300).contains(status) else { throw Self.error(status: status, data: data) }
        return data
    }

    static func error(status: Int, data: Data) -> APIError {
        struct Envelope: Decodable {
            struct Body: Decodable { var code: String; var message: String }
            var error: Body
        }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            return APIError(status: status, code: envelope.error.code, message: envelope.error.message)
        }
        let message: String = switch status {
        case 401: "Сессия закончилась — войди заново"
        case 429: "Слишком много попыток, попробуй позже"
        case 500...: "Сервер Sonar сейчас недоступен"
        default: "Ошибка сервера (\(status))"
        }
        return APIError(status: status, code: "http_\(status)", message: message)
    }

    /// Пустое тело.
    struct Empty: Codable, Sendable {}
}
