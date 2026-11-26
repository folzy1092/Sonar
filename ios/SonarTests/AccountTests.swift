import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Sonar

/// Сервер для тестов аккаунта: ответы по «МЕТОД путь», запросы записываются.
final class FakeAPI: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: [(Int, String)]] = [:]
    private(set) var requests: [URLRequest] = []

    /// Ответ на запрос; несколько — по очереди (последний повторяется).
    func on(_ route: String, _ status: Int = 200, _ body: String) {
        lock.lock()
        routes[route, default: []].append((status, body))
        lock.unlock()
    }

    var fetch: APIClient.Fetch {
        { [self] request in handle(request) }
    }

    private func handle(_ request: URLRequest) -> (Data, Int) {
        do {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
            let route = FakeAPI.route(request)
            guard var queue = routes[route], !queue.isEmpty else {
                return (Data(#"{"error":{"code":"not_found","message":"нет"}}"#.utf8), 404)
            }
            let (status, body) = queue.count > 1 ? queue.removeFirst() : queue[0]
            routes[route] = queue
            return (Data(body.utf8), status)
        }
    }

    /// «POST /auth/login»: адрес API — `https://try-sonar.ru/api`, маршруты в тестах — без префикса, как в API.md.
    static func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return "\(request.httpMethod ?? "GET") \(path.hasPrefix("/api/") ? String(path.dropFirst(4)) : path)"
    }

    func count(_ route: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.filter { FakeAPI.route($0) == route }.count
    }

    func body(_ route: String) -> JSONValue? {
        lock.lock()
        defer { lock.unlock() }
        guard let r = requests.last(where: { FakeAPI.route($0) == route }), let data = r.httpBody else { return nil }
        return try? JSONValue(data: data)
    }
}

let userJSON = #"{"id":"u_1","login":"folzy","username":"folzy","display_name":"Folzy","number":104633,"avatar_url":null,"created_at":1791590400000,"telegram":{"id":123,"username":"cocainemodel"},"has_password":true}"#

@MainActor
final class AccountTests: XCTestCase {
    private func settings(enabled: Bool) -> SettingsStore {
        let store = SettingsStore(storage: UserDefaults(suiteName: "acc-\(UUID().uuidString)")!)
        store.set(AccountStore.enabledKey, enabled)
        return store
    }

    private func makeStore(enabled: Bool = true, api: FakeAPI = FakeAPI(), secrets: MemorySecrets = MemorySecrets()) -> AccountStore {
        AccountStore(settings: settings(enabled: enabled), secrets: secrets, plistURL: "https://try-sonar.ru/api",
                     fetch: api.fetch, pollInterval: .milliseconds(1),
                     device: { DeviceDescriptor(id: $0, name: "iPhone 15 Pro", platform: .ios, os: "iOS 18.1", appVersion: "0.1.0", build: 7) })
    }

    func testServerOffByDefault() async {
        let api = FakeAPI()
        let store = makeStore(enabled: false, api: api)
        XCTAssertFalse(store.enabled())
        await store.checkServer()
        XCTAssertFalse(store.needsGate, "без сервера ворот входа нет")
        XCTAssertFalse(store.reachable)
        do {
            try await store.login("folzy", password: "12345678")
            XCTFail("без флага вход невозможен")
        } catch {
            XCTAssertEqual(error as? APIError, .serverOff)
        }
        XCTAssertTrue(api.requests.isEmpty, "ни одного запроса без флага")
        XCTAssertNil(store.sessionToken)
    }

    func testServerOnByDefault() {
        let fresh = SettingsStore(storage: UserDefaults(suiteName: "acc-\(UUID().uuidString)")!)
        XCTAssertTrue(AccountStore.isEnabled(settings: fresh, plistURL: "https://try-sonar.ru/api"), "сервер включён по умолчанию")
    }

    func testEnabledNeedsFlagAndAddress() {
        let on = settings(enabled: true)
        XCTAssertTrue(AccountStore.isEnabled(settings: on, plistURL: "https://try-sonar.ru/api"))
        XCTAssertFalse(AccountStore.isEnabled(settings: on, plistURL: nil), "нет адреса — выключено")
        XCTAssertFalse(AccountStore.isEnabled(settings: on, plistURL: "не адрес"))
        on.set(AccountStore.urlKey, .string("https://test.example/"))
        XCTAssertEqual(AccountStore.baseURL(settings: on, plistURL: "https://try-sonar.ru/api")?.absoluteString, "https://test.example")
        XCTAssertFalse(AccountStore.isEnabled(settings: settings(enabled: false), plistURL: "https://try-sonar.ru/api"))
        XCTAssertFalse(SyncPolicy.settingSyncs(AccountStore.enabledKey), "флаг сервера — только на этом устройстве")
        XCTAssertFalse(SyncPolicy.settingSyncs(AccountStore.urlKey))
    }

    func testLoginStoresSessionInSecretsAndSendsDevice() async throws {
        let api = FakeAPI()
        api.on("POST /auth/login", 200, #"{"session":"tok_1","user":\#(userJSON)}"#)
        api.on("GET /me", 200, userJSON)
        let secrets = MemorySecrets()
        api.on("GET /health", 200, "{}")
        let store = makeStore(api: api, secrets: secrets)
        XCTAssertFalse(store.needsGate, "пока не спросили сервер, ворот нет")
        await store.checkServer()
        XCTAssertTrue(store.needsGate, "сервер отвечает, входа нет — ворота")
        try await store.login(" Folzy ", password: "12345678")
        XCTAssertFalse(store.needsGate, "вошли — ворота ушли")
        XCTAssertTrue(store.signedIn)
        XCTAssertEqual(store.user?.number, 104633)
        XCTAssertEqual(store.user?.telegram?.username, "cocainemodel")
        XCTAssertEqual(secrets.string(SessionVault.tokenAccount), "tok_1")
        let body = try XCTUnwrap(api.body("POST /auth/login"))
        XCTAssertEqual(body["login"].string, "folzy", "логин без пробелов и в нижнем регистре")
        XCTAssertEqual(body["device"]["name"].string, "iPhone 15 Pro")
        XCTAssertEqual(body["device"]["platform"].string, "ios")
        XCTAssertEqual(body["device"]["app_version"].string, "0.1.0")
        XCTAssertEqual(body["device"]["id"].string, store.vault.deviceId)

        try await store.refreshMe()
        XCTAssertEqual(api.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer tok_1")

        // новый запуск — вход сохранился
        let again = makeStore(api: api, secrets: secrets)
        XCTAssertTrue(again.signedIn)
        XCTAssertEqual(again.user?.login, "folzy")
    }

    func testServerErrorMessageAndUnauthorizedSignsOut() async throws {
        let api = FakeAPI()
        api.on("POST /auth/login", 401, #"{"error":{"code":"bad_password","message":"Неверный пароль"}}"#)
        let store = makeStore(api: api)
        do {
            try await store.login("folzy", password: "wrongpass")
            XCTFail()
        } catch let error as APIError {
            XCTAssertEqual(error.code, "bad_password")
            XCTAssertEqual(error.localizedDescription, "Неверный пароль")
        }

        let secrets = MemorySecrets()
        SessionVault(secrets: secrets).save(AuthResult(session: "old", user: AccountUser(id: "u_1", login: "folzy", username: "folzy", displayName: "F")))
        api.on("GET /me", 401, "")
        let signed = makeStore(api: api, secrets: secrets)
        var events: [Bool] = []
        signed.onSessionChange = { events.append($0) }
        XCTAssertTrue(signed.signedIn)
        do { try await signed.refreshMe() } catch {}
        XCTAssertFalse(signed.signedIn, "сессию завершили — выходим")
        XCTAssertNil(secrets.string(SessionVault.tokenAccount))
        XCTAssertEqual(events, [false])
    }

    func testRegisterValidatesLikeBot() async {
        let api = FakeAPI()
        let store = makeStore(api: api)
        XCTAssertNil(AccountValidation.loginProblem("folzy_1.x"))
        XCTAssertNotNil(AccountValidation.loginProblem("ab"))
        XCTAssertNotNil(AccountValidation.loginProblem("фолзи"))
        XCTAssertNotNil(AccountValidation.passwordProblem("1234567"))
        do {
            try await store.register("ab", password: "12345678")
            XCTFail()
        } catch {
            XCTAssertEqual((error as? APIError)?.code, "invalid")
        }
        XCTAssertEqual(api.count("POST /auth/register"), 0, "неверное не уходит на сервер")
    }

    func testQuickLinkLoginPollsUntilApproved() async throws {
        let api = FakeAPI()
        let expires = Int64(Date().timeIntervalSince1970 * 1000) + 300_000
        api.on("POST /auth/link", 200, #"{"code":"abc","url":"https://try-sonar.ru/auth/abc","expires_at":\#(expires)}"#)
        api.on("GET /auth/link/abc/poll", 200, #"{"status":"pending"}"#)
        api.on("GET /auth/link/abc/poll", 200, #"{"status":"pending"}"#)
        api.on("GET /auth/link/abc/poll", 200, #"{"status":"approved","session":"tok_q","user":\#(userJSON)}"#)
        let store = makeStore(api: api)
        let link = try await store.createLoginLink()
        XCTAssertEqual(link.telegramURL?.absoluteString, "https://t.me/SonarMusicApp?start=link_abc")
        XCTAssertEqual(link.appURL?.absoluteString, "sonar://auth/abc")
        XCTAssertNil(api.requests.last?.value(forHTTPHeaderField: "Authorization"), "без авторизации")
        let status = try await store.waitForLink(link)
        XCTAssertEqual(status, .approved)
        XCTAssertTrue(store.signedIn)
        XCTAssertEqual(store.vault.token, "tok_q")
        XCTAssertEqual(api.count("GET /auth/link/abc/poll"), 3)
    }

    func testQuickLinkExpiresAndRejects() async throws {
        let api = FakeAPI()
        let store = makeStore(api: api)
        let old = AuthLink(code: "x", url: "", botURL: nil, expiresAt: 1)
        let expired = try await store.waitForLink(old)
        XCTAssertEqual(expired, .expired)
        XCTAssertEqual(api.count("GET /auth/link/x/poll"), 0)
        api.on("GET /auth/link/y/poll", 200, #"{"status":"rejected"}"#)
        let rejected = try await store.waitForLink(AuthLink(code: "y", url: "", botURL: nil, expiresAt: .max))
        XCTAssertEqual(rejected, .rejected)
        XCTAssertFalse(store.signedIn)
    }

    func testApproveFromDeepLinkOnlyWhenSignedIn() async throws {
        let api = FakeAPI()
        let secrets = MemorySecrets()
        let out = makeStore(api: api, secrets: secrets)
        out.handleAuthLink("abc")
        XCTAssertNil(out.pendingApproval, "не вошли — подтверждать нечем")
        XCTAssertNotNil(out.message)

        SessionVault(secrets: secrets).save(AuthResult(session: "t", user: AccountUser(id: "u_1", login: "folzy", username: "folzy", displayName: "F")))
        let store = makeStore(api: api, secrets: secrets)
        store.handleAuthLink("/abc")
        XCTAssertEqual(store.pendingApproval, "abc")
        api.on("GET /auth/link/abc", 200, #"{"for":{"kind":"telegram","name":"Telegram @cocainemodel"},"created_at":1,"expires_at":2}"#)
        let info = try await store.linkInfo("abc")
        XCTAssertEqual(info.requester.kind, .telegram)
        XCTAssertEqual(info.requester.name, "Telegram @cocainemodel")
        api.on("POST /auth/link/abc/approve", 204, "")
        try await store.approve("abc")
        XCTAssertNil(store.pendingApproval)
        XCTAssertEqual(api.count("POST /auth/link/abc/approve"), 1)
    }

    func testDevicesSortedAndRevokeRules() async throws {
        let api = FakeAPI()
        let secrets = MemorySecrets()
        SessionVault(secrets: secrets).save(AuthResult(session: "t", user: AccountUser(id: "u_1", login: "folzy", username: "folzy", displayName: "F")))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        api.on("GET /me/devices", 200, """
        [{"id":"pc","name":"Windows 10 (Folzy)","platform":"windows","app_version":"0.1.40","created_at":1,"last_seen_at":\(now - 1000),"current":false},
         {"id":"me","name":"iPhone 15 Pro","platform":"ios","app_version":"0.1.0","created_at":\(now - 3_600_000),"last_seen_at":\(now - 5000),"current":true},
         {"id":"old","name":"iPhone 11","platform":"ios","created_at":1,"last_seen_at":5}]
        """)
        let store = makeStore(api: api, secrets: secrets)
        try await store.loadDevices()
        XCTAssertEqual(store.devices.map(\.id), ["me", "pc", "old"], "это устройство первым, дальше — кто был позже")
        XCTAssertEqual(store.devices[1].platform, .windows)
        XCTAssertFalse(store.canRevokeOthers(), "вошли час назад — рано")
        XCTAssertTrue(store.canRevokeOthers(now: Date().addingTimeInterval(24 * 3600)))
        XCTAssertFalse(DeviceRules.canRevokeOthers(currentSessionCreatedAt: 0, now: DeviceRules.revokeDelayMs - 1))
        XCTAssertTrue(DeviceRules.canRevokeOthers(currentSessionCreatedAt: 0, now: DeviceRules.revokeDelayMs))

        api.on("DELETE /me/devices/pc", 403, #"{"error":{"code":"session_too_new","message":"Вход был недавно — завершать другие сессии можно через 24 часа"}}"#)
        do {
            try await store.revokeDevice("pc")
            XCTFail()
        } catch let error as APIError {
            XCTAssertEqual(error.code, APIError.sessionTooNewCode)
        }
        XCTAssertEqual(store.devices.count, 3, "не завершили — строка осталась")
        api.on("DELETE /me/devices/old", 204, "")
        try await store.revokeDevice("old")
        XCTAssertEqual(store.devices.map(\.id), ["me", "pc"])

        api.on("PATCH /me/devices/pc", 200, #"{"id":"pc","name":"Домашний ПК","platform":"windows","created_at":1,"last_seen_at":2}"#)
        try await store.renameDevice("pc", name: "  Домашний ПК ")
        XCTAssertEqual(api.body("PATCH /me/devices/pc")?["name"].string, "Домашний ПК")
        XCTAssertEqual(store.devices.first { $0.id == "pc" }?.name, "Домашний ПК")
    }

    func testLaunchReportsVersion() async {
        let api = FakeAPI()
        let secrets = MemorySecrets()
        SessionVault(secrets: secrets).save(AuthResult(session: "t", user: AccountUser(id: "u_1", login: "folzy", username: "folzy", displayName: "F")))
        api.on("PUT /me/device", 200, #"{"id":"me","name":"iPhone 15 Pro","platform":"ios","app_version":"0.1.0","created_at":1,"last_seen_at":2,"current":true}"#)
        let store = makeStore(api: api, secrets: secrets)
        await store.reportLaunch()
        XCTAssertEqual(api.body("PUT /me/device")?["device"]["app_version"].string, "0.1.0")
        XCTAssertEqual(api.body("PUT /me/device")?["device"]["build"].int, 7)

        let off = makeStore(enabled: false, api: api, secrets: secrets)
        await off.reportLaunch()
        XCTAssertEqual(api.count("PUT /me/device"), 1, "без сервера ничего не шлём")
    }

    func testLogoutClearsEvenIfServerDown() async {
        let api = FakeAPI()
        let secrets = MemorySecrets()
        SessionVault(secrets: secrets).save(AuthResult(session: "t", user: AccountUser(id: "u_1", login: "folzy", username: "folzy", displayName: "F")))
        api.on("POST /auth/logout", 503, "")
        let store = makeStore(api: api, secrets: secrets)
        await store.logout()
        XCTAssertFalse(store.signedIn)
        XCTAssertNil(secrets.string(SessionVault.tokenAccount))
    }
}
