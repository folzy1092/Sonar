import Foundation
import Observation

/// Аккаунт Sonar на телефоне: вход логином и паролем, регистрация, вход быстрой ссылкой (бот или другое
/// устройство), подтверждение чужого входа, профиль и устройства.
///
/// `serverEnabled` = задан адрес (Info.plist `SonarAPIBaseURL` = `https://try-sonar.ru/api` или настройка
/// `server.url`) **и** флаг `server.enabled` (с 2026-11-25 умолчание true). Вход обязателен, как на ПК (решение владельца
/// 2026-11-26): `needsGate` — сервер включён, отвечает на `/health`, а входа нет; тогда `RootView` закрывает приложение
/// воротами `AuthGateView`. Сервер лёг или офлайн-режим — ворот нет. Выключить флаг — ни одного запроса, синк не стартует.
///
/// Заблокированный аккаунт (`403 account_banned`): сессия стирается, `banned` хранит срок и причину — ворота показывают их
/// вместо обычного приглашения, а `onBanned` останавливает музыку.
@MainActor
@Observable
final class AccountStore {
    static let shared = AccountStore()

    /// Ключ флага в настройках (не синхронизируется — префикс `server.`).
    static let enabledKey = "server.enabled"
    /// Свой адрес сервера поверх Info.plist (для проверки на тестовом сервере).
    static let urlKey = "server.url"
    static let plistKey = "SonarAPIBaseURL"

    /// Включён ли сервер — всё аккаунтное и синк только при true.
    static var serverEnabled: Bool { isEnabled(settings: .shared, plistURL: plistURL) }

    static var plistURL: String? { Bundle.main.object(forInfoDictionaryKey: plistKey) as? String }

    static func isEnabled(settings: SettingsStore, plistURL: String?) -> Bool {
        settings.bool(enabledKey) && baseURL(settings: settings, plistURL: plistURL) != nil
    }

    /// Адрес API: настройка `server.url`, иначе Info.plist. Пусто / не https — nil.
    static func baseURL(settings: SettingsStore, plistURL: String?) -> URL? {
        let custom = settings.string(urlKey).trimmingCharacters(in: .whitespaces)
        let raw = custom.isEmpty ? (plistURL ?? "") : custom
        guard let url = URL(string: raw.hasSuffix("/") ? String(raw.dropLast()) : raw),
              let scheme = url.scheme, scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    // MARK: состояние

    private(set) var user: AccountUser?
    private(set) var devices: [AccountDevice] = []
    /// Код быстрой ссылки, открытой на этом устройстве (`sonar://auth/<code>`) — показать `ApproveLoginSheet`.
    var pendingApproval: String?
    /// Сообщение для тоста.
    var message: String?

    var signedIn: Bool { user != nil && vault.token != nil }
    /// Сервер ответил на `/health` при последней проверке (`checkServer`).
    private(set) var reachable = false
    /// Аккаунт заблокирован: срок и причина для ворот. Входом в другой аккаунт сбрасывается.
    private(set) var banned: BanInfo?
    /// Ворота входа: сервер включён и отвечает, а входа нет. Офлайн-режим учитывает `RootView` (он наблюдаемый).
    var needsGate: Bool { enabled() && reachable && !signedIn }
    /// Блокировка пришла — остановить музыку (`SonarApp`).
    @ObservationIgnored var onBanned: (@MainActor () -> Void)?

    /// Это устройство в списке (после `loadDevices`).
    var currentDevice: AccountDevice? { devices.first(where: \.current) }

    /// Можно ли сейчас выходить на других устройствах (своя сессия старше 24 ч).
    func canRevokeOthers(now: Date = Date()) -> Bool {
        guard let current = currentDevice else { return false }
        return DeviceRules.canRevokeOthers(currentSessionCreatedAt: current.createdAt, now: Int64(now.timeIntervalSince1970 * 1000))
    }

    /// Вошли / вышли — `SyncService` запускается или останавливается.
    @ObservationIgnored var onSessionChange: (@MainActor (Bool) -> Void)?

    @ObservationIgnored let vault: SessionVault
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let plistURL: String?
    @ObservationIgnored private let fetch: APIClient.Fetch?
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let device: (String) -> DeviceDescriptor

    init(settings: SettingsStore? = nil, secrets: SecretStore? = nil, plistURL: String?? = nil,
         fetch: APIClient.Fetch? = nil, pollInterval: Duration = .seconds(2),
         device: ((String) -> DeviceDescriptor)? = nil) {
        self.settings = settings ?? .shared
        self.vault = SessionVault(secrets: secrets ?? Self.defaultSecrets())
        self.plistURL = plistURL ?? Self.plistURL
        self.fetch = fetch
        self.pollInterval = pollInterval
        self.device = device ?? { DeviceInfo.descriptor(id: $0) }
        user = vault.token == nil ? nil : vault.user
    }

    private static func defaultSecrets() -> SecretStore {
        #if canImport(Security)
        KeychainSecrets()
        #else
        MemorySecrets()
        #endif
    }

    func enabled() -> Bool {
        Self.isEnabled(settings: settings, plistURL: plistURL)
    }

    /// Описание этого устройства для сервера.
    var deviceDescriptor: DeviceDescriptor { device(vault.deviceId) }

    /// Клиент с текущей сессией. Сервер выключен — `APIError.serverOff`, без единого запроса.
    func api() throws -> AccountAPI {
        guard enabled(), let base = Self.baseURL(settings: settings, plistURL: plistURL) else { throw APIError.serverOff }
        return AccountAPI(client: APIClient(base: base, token: vault.token, fetch: fetch))
    }

    /// Токен для синка и других клиентов API (nil — не вошли или сервер выключен).
    var sessionToken: String? { enabled() ? vault.token : nil }

    var apiBaseURL: URL? { Self.baseURL(settings: settings, plistURL: plistURL) }

    // MARK: вход

    /// Спросить сервер, жив ли он: ворота входа встают только тогда (при запуске, на возврате в приложение, после офлайна).
    func checkServer() async {
        guard enabled(), let base = Self.baseURL(settings: settings, plistURL: plistURL) else {
            reachable = false
            return
        }
        reachable = await APIClient(base: base, fetch: fetch).ping()
    }

    func login(_ login: String, password: String) async throws {
        try await entering { try await api().login(login: login, password: password, device: deviceDescriptor) }
    }

    func register(_ login: String, password: String) async throws {
        if let problem = AccountValidation.loginProblem(login) ?? AccountValidation.passwordProblem(password) {
            throw APIError(status: 400, code: "invalid", message: problem)
        }
        try await entering { try await api().register(login: login, password: password, device: deviceDescriptor) }
    }

    /// Вход или регистрация: заблокированному сервер отвечает `account_banned` — запоминаем срок и причину для ворот.
    private func entering(_ work: () async throws -> AuthResult) async throws {
        do {
            signedIn(try await work())
        } catch let error as APIError where error.isBanned {
            banned = BanInfo(error)
            throw APIError(status: error.status, code: error.code, message: t("Учётная запись заблокирована"),
                           until: error.until, reason: error.reason)
        }
    }

    /// Быстрая ссылка для входа этого устройства: показать её (бот / QR), потом `waitForLink`.
    func createLoginLink() async throws -> AuthLink {
        try await api().createLink(device: deviceDescriptor)
    }

    /// Ждать, пока ссылку подтвердят в боте или на другом устройстве. Вернёт итог: `approved` — уже вошли.
    func waitForLink(_ link: AuthLink, now: @escaping () -> Date = Date.init) async throws -> AuthLinkPoll.Status {
        let api = try api()
        while !Task.isCancelled {
            if Int64(now().timeIntervalSince1970 * 1000) > link.expiresAt { return .expired }
            // Мобильная сеть теряет ответы: таймаут одного опроса не конец ожидания — пробуем снова, пока не истечёт ссылка
            guard let poll = try await lenient({ try await api.pollLink(link.code) }) else {
                try await Task.sleep(for: pollInterval)
                continue
            }
            switch poll.status {
            case .pending:
                try await Task.sleep(for: pollInterval)
            case .approved:
                guard let session = poll.session, let user = poll.user else {
                    throw APIError(status: 200, code: "bad_response", message: "Сервер ответил непонятно")
                }
                signedIn(AuthResult(session: session, user: user))
                return .approved
            case .rejected, .expired:
                return poll.status
            }
        }
        throw CancellationError()
    }

    /// Один опрос по ненадёжной сети: сбой сети (`network`) — `nil`, «повтори позже»; всё остальное (отказ сервера, 401, бан) — ошибка.
    private func lenient<T>(_ work: () async throws -> T) async throws -> T? {
        do {
            return try await work()
        } catch let error as APIError where error.code == "network" {
            return nil
        }
    }

    func logout() async {
        // сервер мог быть недоступен — локально выходим всё равно
        try? await api().logout()
        signedOut()
    }

    private func signedIn(_ result: AuthResult) {
        vault.save(result)
        banned = nil
        user = result.user
        onSessionChange?(true)
    }

    /// Сессия закончилась (выход, 401, завершили с другого устройства).
    func signedOut() {
        vault.clear()
        user = nil
        devices = []
        onSessionChange?(false)
    }

    /// Сервер сказал, что сессии больше нет: 401 — отозвана, 403 `account_banned` — аккаунт заблокирован (тогда ещё
    /// запоминаем срок и причину и останавливаем музыку). Зовут и `SyncService`.
    func sessionEnded(_ error: APIError) {
        if let ban = BanInfo(error) {
            banned = ban
            onBanned?()
        }
        signedOut()
    }

    /// 401 / 403 `account_banned` — сессии больше нет.
    private func guarded<T: Sendable>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as APIError where error.endsSession {
            sessionEnded(error)
            throw error
        }
    }

    // MARK: подтверждение чужого входа (BOT.md §3)

    /// `sonar://auth/<code>` открыт здесь: показать окно подтверждения (только если вошли).
    func handleAuthLink(_ code: String) {
        let code = code.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard enabled(), !code.isEmpty else { return }
        if signedIn {
            pendingApproval = code
        } else {
            message = "Войди в Sonar, чтобы подтвердить вход"
        }
    }

    func linkInfo(_ code: String) async throws -> AuthLinkInfo {
        try await guarded { try await api().linkInfo(code) }
    }

    func approve(_ code: String) async throws {
        try await guarded { try await api().approveLink(code) }
        pendingApproval = nil
    }

    func reject(_ code: String) async throws {
        try await guarded { try await api().rejectLink(code) }
        pendingApproval = nil
    }

    // MARK: профиль, безопасность

    func refreshMe() async throws {
        let me = try await guarded { try await api().me() }
        user = me
        vault.saveUser(me)
    }

    func changePassword(old: String?, new: String) async throws {
        if let problem = AccountValidation.passwordProblem(new) { throw APIError(status: 400, code: "invalid", message: problem) }
        try await guarded { try await api().changePassword(old: old, new: new) }
        if user?.hasPassword == false {
            user?.hasPassword = true
            if let user { vault.saveUser(user) }
        }
    }

    /// Привязать Telegram: ссылка в бота (открыть), затем ждать подтверждения. true — привязан.
    func linkTelegram(open: @MainActor (URL) -> Void) async throws -> Bool {
        let api = try api()
        let start = try await guarded { try await api.startTelegramLink() }
        if let url = URL(string: start.link) { open(url) }
        while !Task.isCancelled {
            if Int64(Date().timeIntervalSince1970 * 1000) > start.expiresAt { return false }
            guard let poll = try await lenient({ try await guarded { try await api.telegramPoll(start.requestId) } }) else {
                try await Task.sleep(for: pollInterval)
                continue
            }
            switch poll.status {
            case .pending: try await Task.sleep(for: pollInterval)
            case .approved:
                try await refreshMe()
                return true
            case .rejected, .expired: return false
            }
        }
        throw CancellationError()
    }

    func unlinkTelegram() async throws {
        try await guarded { try await api().unlinkTelegram() }
        user?.telegram = nil
        if let user { vault.saveUser(user) }
    }

    // MARK: устройства

    func loadDevices() async throws {
        devices = DeviceRules.sorted(try await guarded { try await api().devices() })
    }

    func renameDevice(_ id: String, name: String) async throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let updated = try await guarded { try await api().renameDevice(id, name: String(name.prefix(48))) }
        if let i = devices.firstIndex(where: { $0.id == id }) { devices[i] = updated }
    }

    /// Выйти на устройстве. Своё — это обычный выход.
    func revokeDevice(_ id: String) async throws {
        if devices.first(where: { $0.id == id })?.current == true {
            await logout()
            return
        }
        try await guarded { try await api().revokeDevice(id) }
        devices.removeAll { $0.id == id }
    }

    // MARK: ключ API (Интеграции)

    func apiKey() async throws -> ApiKeyInfo {
        try await guarded { try await api().apiKey() }
    }

    func newApiKey() async throws -> ApiKeyInfo {
        try await guarded { try await api().newApiKey() }
    }

    func deleteApiKey() async throws {
        try await guarded { try await api().deleteApiKey() }
    }

    /// При каждом запуске (если вошли): сообщить серверу версию Sonar, ОС и имя устройства.
    func reportLaunch() async {
        guard signedIn, enabled() else { return }
        do {
            let me = try await guarded { try await api().reportDevice(deviceDescriptor) }
            if let i = devices.firstIndex(where: { $0.id == me.id }) { devices[i] = me }
        } catch {
            // не вышло — сообщим при следующем запуске
        }
    }
}
