import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Вход в Яндекс Музыку «в один клик» по коду — как в Windows (`login.rs` `yandex_device`, решение владельца
/// 2026-11-16): OAuth device flow клиента Яндекс Музыки. Sonar показывает короткий код и открывает
/// `ya.ru/device` в Safari, человек подтверждает — Sonar сам забирает токен `y0_…`.
enum YandexLogin {
    /// client_id приложения Яндекс Музыки (так входят официальный клиент и yandex-music-api).
    static let clientId = "23cabbbdc6cd418abb4b39c32c41195d"
    /// Его публичный секрет (тот же, что в yandex-music-api) — для обмена кода устройства на токен.
    static let clientSecret = "53bc75238f0c4d08a118e51fe9203300"

    struct DeviceCode: Sendable, Equatable {
        var deviceCode: String
        var userCode: String
        var url: URL
        var expiresIn: Int
        var interval: Int
    }

    /// Ответ `/device/code` → код; нет кода — nil.
    static func parseDeviceCode(_ json: JSONValue) -> DeviceCode? {
        guard let device = json["device_code"].string, let user = json["user_code"].string else { return nil }
        return DeviceCode(
            deviceCode: device,
            userCode: user,
            url: json["verification_url"].string.flatMap(URL.init(string:)) ?? URL(string: "https://ya.ru/device")!,
            expiresIn: json["expires_in"].int ?? 300,
            interval: max(2, json["interval"].int ?? 5)
        )
    }

    enum Poll: Equatable {
        case token(String)
        case pending
        case slowDown
        case failed(String)
    }

    /// Ответ `/token` при ожидании подтверждения.
    static func parsePoll(_ json: JSONValue) -> Poll {
        if let token = json["access_token"].string, !token.isEmpty { return .token(token) }
        switch json["error"].string {
        case nil, "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "expired_token": return .failed("Код устарел — нажми «Войти через Яндекс» ещё раз")
        case "access_denied": return .failed("Вход отменён")
        case let error?: return .failed("Яндекс не пустил: \(error)")
        }
    }

    private static func post(_ url: String, _ form: [(String, String)]) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.form(form)
        // ошибки ожидания приходят с кодом 400 — читаем тело в любом случае
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONValue(data: data)
    }

    static func start(deviceId: String) async throws -> DeviceCode {
        let json = try await post("https://oauth.yandex.ru/device/code",
                                  [("client_id", clientId), ("device_id", deviceId), ("device_name", "Sonar (iPhone)")])
        guard let code = parseDeviceCode(json) else {
            throw ServiceError(message: "Яндекс: вход по коду сейчас недоступен — вставь токен")
        }
        return code
    }

    /// Ждёт подтверждения на ya.ru/device и возвращает токен. Отмена задачи — отмена входа.
    static func waitToken(_ code: DeviceCode) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
        var interval = code.interval
        while true {
            try await Task.sleep(for: .seconds(interval))
            guard Date() < deadline else { throw ServiceError(message: "Код устарел — нажми «Войти через Яндекс» ещё раз") }
            guard let json = try? await post("https://oauth.yandex.ru/token", [
                ("grant_type", "device_code"), ("code", code.deviceCode), ("client_id", clientId), ("client_secret", clientSecret),
            ]) else { continue }
            switch parsePoll(json) {
            case let .token(token): return token
            case .pending: continue
            case .slowDown: interval += 2
            case let .failed(message): throw ServiceError(message: message)
            }
        }
    }
}
