import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // тесты логики на Linux
#endif

/// Ошибка сервера Sonar — всегда `{"error": {"code", "message"}}` (API.md, начало).
struct APIError: LocalizedError, Equatable, Sendable {
    var status: Int
    var code: String
    var message: String
    /// Только у `account_banned`: до какого момента (мс Unix), `nil` — навсегда.
    var until: Int64?
    var reason: String?
    /// Только у `network`: что именно не вышло («таймаут», «DNS», «ошибка TLS» …) — чтобы «Нет связи» не прятало причину.
    var detail: String?

    var errorDescription: String? { message }

    /// Сервер ещё не подключён (флаг выключен или нет адреса).
    static let serverOff = APIError(status: 0, code: "server_off", message: "Сервер Sonar ещё не подключён")
    /// Своя сессия моложе 24 ч — другие завершать рано (`DELETE /me/devices/{id}`).
    static let sessionTooNewCode = "session_too_new"

    var isUnauthorized: Bool { status == 401 }
    /// `403 account_banned` — аккаунт заблокирован (API.md §1 «Блокировка»).
    var isBanned: Bool { status == 403 && code == Self.bannedCode }
    /// Сессии больше нет: её отозвали (401) или аккаунт заблокирован (403) — приложение выходит само.
    var endsSession: Bool { isUnauthorized || isBanned }

    static let bannedCode = "account_banned"
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

    /// Отвечает ли сервер (`GET /health`, без сессии). Ворота входа встают только когда да: упавший сервер не запирает приложение.
    func ping() async -> Bool {
        guard let req = try? request("GET", "health"), let (_, status) = try? await fetch(req) else { return false }
        return (200 ..< 300).contains(status)
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
            throw APIError(status: 0, code: "network", message: "Нет связи с сервером Sonar", detail: Self.reason(of: error))
        }
        guard (200 ..< 300).contains(status) else { throw Self.error(status: status, data: data) }
        return data
    }

    /// Короткая причина сетевого сбоя для экрана входа: слово и код `URLError` (-1001 …).
    static func reason(of error: Error) -> String {
        guard let url = error as? URLError else { return String(describing: type(of: error)) }
        let word: String = switch url.code {
        case .timedOut: "таймаут"
        case .cannotFindHost, .dnsLookupFailed: "DNS"
        case .cannotConnectToHost: "нет соединения с узлом"
        case .networkConnectionLost: "связь оборвалась"
        case .notConnectedToInternet: "нет интернета"
        case .secureConnectionFailed, .serverCertificateUntrusted: "ошибка TLS"
        default: "сбой сети"
        }
        return "\(word), \(url.code.rawValue)"
    }

    static func error(status: Int, data: Data) -> APIError {
        struct Envelope: Decodable {
            struct Body: Decodable { var code: String; var message: String; var until: Int64?; var reason: String? }
            var error: Body
        }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            return APIError(status: status, code: envelope.error.code, message: envelope.error.message,
                            until: envelope.error.until, reason: envelope.error.reason)
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
