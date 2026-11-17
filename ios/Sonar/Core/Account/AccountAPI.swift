import Foundation

/// Аккаунт по API.md §1 и BOT.md §3/§6: вход, регистрация, быстрая ссылка, подтверждение входа,
/// `me`, устройства. Только запросы — состояние держит `AccountStore`.
struct AccountAPI: Sendable {
    var client: APIClient

    private struct Credentials: Encodable {
        var login: String
        var password: String
        var device: DeviceDescriptor
    }

    func register(login: String, password: String, device: DeviceDescriptor) async throws -> AuthResult {
        try await client.send("POST", "auth/register", body: Credentials(login: AccountValidation.normalizedLogin(login), password: password, device: device))
    }

    func login(login: String, password: String, device: DeviceDescriptor) async throws -> AuthResult {
        try await client.send("POST", "auth/login", body: Credentials(login: AccountValidation.normalizedLogin(login), password: password, device: device))
    }

    func logout() async throws {
        try await client.call("POST", "auth/logout")
    }

    // MARK: быстрая ссылка (BOT.md §3)

    private struct LinkBody: Encodable { var device: DeviceDescriptor }

    /// Новое устройство просит вход: ссылку открывают в боте или там, где уже вошли.
    func createLink(device: DeviceDescriptor) async throws -> AuthLink {
        try await client.with(token: nil).send("POST", "auth/link", body: LinkBody(device: device))
    }

    func pollLink(_ code: String) async throws -> AuthLinkPoll {
        try await client.with(token: nil).send("GET", "auth/link/\(code)/poll")
    }

    /// (вошедший) кто просит доступ — для `ApproveLoginSheet`.
    func linkInfo(_ code: String) async throws -> AuthLinkInfo {
        try await client.send("GET", "auth/link/\(code)")
    }

    func approveLink(_ code: String) async throws {
        try await client.call("POST", "auth/link/\(code)/approve")
    }

    func rejectLink(_ code: String) async throws {
        try await client.call("POST", "auth/link/\(code)/reject")
    }

    // MARK: профиль и безопасность

    func me() async throws -> AccountUser {
        try await client.send("GET", "me")
    }

    private struct PasswordBody: Encodable {
        var oldPassword: String?
        var newPassword: String
        enum CodingKeys: String, CodingKey {
            case oldPassword = "old_password"
            case newPassword = "new_password"
        }
    }

    func changePassword(old: String?, new: String) async throws {
        try await client.call("PUT", "me/password", body: PasswordBody(oldPassword: old, newPassword: new))
    }

    private struct TelegramStartBody: Encodable { var purpose: String }

    /// Привязать Telegram: ссылка в бота, дальше опрос `telegramPoll`.
    func startTelegramLink() async throws -> TelegramStart {
        try await client.send("POST", "auth/telegram/start", body: TelegramStartBody(purpose: "link"))
    }

    func telegramPoll(_ requestId: String) async throws -> AuthLinkPoll {
        try await client.send("GET", "auth/telegram/poll/\(requestId)")
    }

    /// Отвязать (только если есть пароль).
    func unlinkTelegram() async throws {
        try await client.call("DELETE", "auth/telegram")
    }

    // MARK: устройства

    func devices() async throws -> [AccountDevice] {
        try await client.send("GET", "me/devices")
    }

    private struct RenameBody: Encodable { var name: String }

    func renameDevice(_ id: String, name: String) async throws -> AccountDevice {
        try await client.send("PATCH", "me/devices/\(id)", body: RenameBody(name: name))
    }

    /// Завершить сессию устройства. Своя сессия моложе 24 ч — 403 `session_too_new`.
    func revokeDevice(_ id: String) async throws {
        try await client.call("DELETE", "me/devices/\(id)")
    }

    /// При каждом запуске: «это устройство» — имя, ОС, версия Sonar (сервер помнит последнюю версию
    /// каждого устройства и `last_seen_at`).
    func reportDevice(_ device: DeviceDescriptor) async throws -> AccountDevice {
        try await client.send("PUT", "me/device", body: LinkBody(device: device))
    }
}
