import Foundation

// Модели аккаунта Sonar — тот же JSON, что в docs/API.md §1 (snake_case, время — мс Unix). Сервера пока
// нет: всё это включается флагом `AccountStore.serverEnabled`.

/// Пользователь (`GET /me`, ответ входа и регистрации).
struct AccountUser: Codable, Equatable, Sendable {
    struct Telegram: Codable, Equatable, Sendable {
        var id: Int64
        var username: String?
    }

    var id: String
    var login: String
    var username: String
    var displayName: String
    var number: Int?
    var avatarURL: String?
    var createdAt: Int64?
    var telegram: Telegram?
    var hasPassword: Bool

    enum CodingKeys: String, CodingKey {
        case id, login, username, number, telegram
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case hasPassword = "has_password"
    }

    init(id: String, login: String, username: String, displayName: String, number: Int? = nil, avatarURL: String? = nil,
         createdAt: Int64? = nil, telegram: Telegram? = nil, hasPassword: Bool = true) {
        self.id = id
        self.login = login
        self.username = username
        self.displayName = displayName
        self.number = number
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.telegram = telegram
        self.hasPassword = hasPassword
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        login = try c.decode(String.self, forKey: .login)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? login
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? login
        number = try c.decodeIfPresent(Int.self, forKey: .number)
        avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL)
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt)
        telegram = try c.decodeIfPresent(Telegram.self, forKey: .telegram)
        hasPassword = try c.decodeIfPresent(Bool.self, forKey: .hasPassword) ?? true
    }
}

/// Платформа устройства (`device.platform`, `sessions.platform`).
enum DevicePlatform: String, Codable, Sendable, CaseIterable {
    case ios, windows, android
    /// Неизвестное значение с сервера новее клиента.
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DevicePlatform(rawValue: raw) ?? .other
    }
}

/// Что устройство сообщает о себе при входе и при каждом запуске (`device` в API.md §1).
/// `id` — постоянный: на iPhone UUID в Keychain (переживает переустановку), на ПК — HWID.
struct DeviceDescriptor: Codable, Equatable, Sendable {
    var id: String
    /// «iPhone 15 Pro», «Windows 10 (Folzy)».
    var name: String
    var platform: DevicePlatform
    /// «iOS 18.1», «Windows 10 22H2».
    var os: String
    var appVersion: String
    var build: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, platform, os, build
        case appVersion = "app_version"
    }
}

/// Строка списка устройств (`GET /me/devices`).
struct AccountDevice: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var platform: DevicePlatform
    var os: String?
    /// Последняя версия Sonar, о которой сообщило устройство.
    var appVersion: String?
    var build: Int?
    /// Когда на устройстве вошли (начало сессии).
    var createdAt: Int64
    var lastSeenAt: Int64
    /// Это устройство (сессия запроса).
    var current: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, platform, os, build, current
        case appVersion = "app_version"
        case createdAt = "created_at"
        case lastSeenAt = "last_seen_at"
    }

    init(id: String, name: String, platform: DevicePlatform, os: String? = nil, appVersion: String? = nil, build: Int? = nil,
         createdAt: Int64, lastSeenAt: Int64, current: Bool = false) {
        self.id = id
        self.name = name
        self.platform = platform
        self.os = os
        self.appVersion = appVersion
        self.build = build
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.current = current
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        platform = try c.decodeIfPresent(DevicePlatform.self, forKey: .platform) ?? .other
        os = try c.decodeIfPresent(String.self, forKey: .os)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        build = try c.decodeIfPresent(Int.self, forKey: .build)
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        lastSeenAt = try c.decodeIfPresent(Int64.self, forKey: .lastSeenAt) ?? createdAt
        current = try c.decodeIfPresent(Bool.self, forKey: .current) ?? false
    }
}

/// Правило сервера: завершать **другие** сессии можно, только если своя старше 24 ч (защита от того,
/// кто только что вошёл чужим паролем). Сервер отвечает 403 `session_too_new`; клиент заранее гасит кнопку.
enum DeviceRules {
    static let revokeDelayMs: Int64 = 24 * 3600 * 1000

    /// С какого момента (мс) этой сессии можно выходить на других устройствах.
    static func revokeAvailableAt(currentSessionCreatedAt: Int64) -> Int64 {
        currentSessionCreatedAt + revokeDelayMs
    }

    static func canRevokeOthers(currentSessionCreatedAt: Int64, now: Int64) -> Bool {
        now >= revokeAvailableAt(currentSessionCreatedAt: currentSessionCreatedAt)
    }

    /// Сначала это устройство, дальше — кто был в сети позже.
    static func sorted(_ devices: [AccountDevice]) -> [AccountDevice] {
        devices.sorted { a, b in
            if a.current != b.current { return a.current }
            return a.lastSeenAt > b.lastSeenAt
        }
    }
}

/// Сессия: токен (только в Keychain) и пользователь.
struct AuthResult: Codable, Equatable, Sendable {
    var session: String
    var user: AccountUser
}

/// Быстрая ссылка входа (`POST /auth/link`, BOT.md §3): живёт 5 минут.
struct AuthLink: Codable, Equatable, Sendable {
    var code: String
    /// `https://try-sonar.ru/auth/<code>` — открыть там, где уже вошли (ПК или iPhone).
    var url: String
    /// `https://t.me/SonarMusicApp?start=link_<code>` — подтвердить в боте. Нет в ответе — собираем сами.
    var botURL: String?
    var expiresAt: Int64

    enum CodingKeys: String, CodingKey {
        case code, url
        case botURL = "bot_url"
        case expiresAt = "expires_at"
    }

    static let botName = "SonarMusicApp"

    /// Ссылка в бота: из ответа или по коду.
    var telegramURL: URL? {
        URL(string: botURL ?? "https://t.me/\(Self.botName)?start=link_\(code)")
    }

    /// `sonar://auth/<code>` — для QR и «Скопировать».
    var appURL: URL? { URL(string: "sonar://auth/\(code)") }
}

/// Ответ опроса быстрой ссылки (`GET /auth/link/{code}/poll`).
struct AuthLinkPoll: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending, approved, rejected, expired
    }

    var status: Status
    var session: String?
    var user: AccountUser?
}

/// Кто просит доступ (`GET /auth/link/{code}`) — для окна подтверждения.
struct AuthLinkInfo: Codable, Equatable, Sendable {
    struct Requester: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case telegram, device }
        var kind: Kind
        /// «Telegram @cocainemodel», «iPhone 15 Pro · Sonar 1.0».
        var name: String
        var platform: DevicePlatform?
    }

    var requester: Requester
    var createdAt: Int64
    var expiresAt: Int64

    enum CodingKeys: String, CodingKey {
        case requester = "for"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

/// Привязка Telegram из приложения (`POST /auth/telegram/start`, `purpose: link`).
struct TelegramStart: Codable, Equatable, Sendable {
    var requestId: String
    var link: String
    var expiresAt: Int64

    enum CodingKeys: String, CodingKey {
        case link
        case requestId = "request_id"
        case expiresAt = "expires_at"
    }
}

/// Проверки форм входа — как в боте (BOT.md §2.3): логин 3–24 символа `a-z 0-9 _ .`, пароль от 8.
enum AccountValidation {
    static func normalizedLogin(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// nil — подходит; иначе текст ошибки (ключ перевода).
    static func loginProblem(_ raw: String) -> String? {
        let login = normalizedLogin(raw)
        if login.count < 3 || login.count > 24 { return "Логин — от 3 до 24 символов" }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")
        if !login.allSatisfy({ allowed.contains($0) }) { return "Только латиница, цифры, «_» и «.»" }
        return nil
    }

    static func passwordProblem(_ password: String) -> String? {
        password.count < 8 ? "Пароль — от 8 символов" : nil
    }
}

/// Ключ API (`GET /me/integration`, `POST /integrations/api-key`): по нему selfbot и другие сервисы читают «сейчас играет».
struct ApiKeyInfo: Codable, Equatable, Sendable {
    var key: String?
    var createdAt: Int64?

    enum CodingKeys: String, CodingKey {
        case key
        case createdAt = "created_at"
    }
}
