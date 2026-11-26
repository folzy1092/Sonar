import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Sonar

/// Заблокированный аккаунт (API.md §1 «Блокировка»), обязательный вход и ключ API на iPhone.
@MainActor
final class BanTests: XCTestCase {
    private static let bannedBody = #"{"error":{"code":"account_banned","message":"Учётная запись заблокирована","until":1795000000000,"reason":"спам"}}"#
    private static let foreverBody = #"{"error":{"code":"account_banned","message":"Учётная запись заблокирована навсегда","until":null,"reason":null}}"#

    private func makeStore(api: FakeAPI = FakeAPI(), secrets: MemorySecrets = MemorySecrets(), fetch: APIClient.Fetch? = nil) -> AccountStore {
        let settings = SettingsStore(storage: UserDefaults(suiteName: "ban-\(UUID().uuidString)")!)
        settings.set(AccountStore.enabledKey, true)
        return AccountStore(settings: settings, secrets: secrets, plistURL: "https://try-sonar.ru/api", fetch: fetch ?? api.fetch,
                            pollInterval: .milliseconds(1),
                            device: { DeviceDescriptor(id: $0, name: "iPhone", platform: .ios, os: "iOS 18", appVersion: "0.2.0", build: 7) })
    }

    // MARK: разбор ответа

    func testErrorCarriesTermAndReason() {
        let error = APIClient.error(status: 403, data: Data(Self.bannedBody.utf8))
        XCTAssertTrue(error.isBanned)
        XCTAssertTrue(error.endsSession)
        XCTAssertFalse(error.isUnauthorized)
        XCTAssertEqual(error.until, 1_795_000_000_000)
        XCTAssertEqual(error.reason, "спам")
        XCTAssertEqual(BanInfo(error), BanInfo(until: 1_795_000_000_000, reason: "спам"))
    }

    func testPermanentBanHasNoTerm() throws {
        let error = APIClient.error(status: 403, data: Data(Self.foreverBody.utf8))
        let ban = try XCTUnwrap(BanInfo(error))
        XCTAssertTrue(ban.isForever)
        XCTAssertNil(ban.reason)
        XCTAssertNil(ban.untilText(locale: Locale(identifier: "ru")))
        XCTAssertFalse(ban.isOver())
    }

    func testOrdinaryErrorsAreNotBans() {
        XCTAssertNil(BanInfo(APIClient.error(status: 403, data: Data(#"{"error":{"code":"registration_closed","message":"Закрыта"}}"#.utf8))))
        let unauthorized = APIClient.error(status: 401, data: Data(#"{"error":{"code":"unauthorized","message":"x"}}"#.utf8))
        XCTAssertTrue(unauthorized.endsSession)
        XCTAssertNil(BanInfo(unauthorized))
        XCTAssertFalse(APIClient.error(status: 500, data: Data()).endsSession)
    }

    func testBanInfoTrimsReasonAndFormatsTerm() throws {
        XCTAssertNil(BanInfo(until: nil, reason: "   ").reason)
        XCTAssertEqual(BanInfo(until: nil, reason: String(repeating: "я", count: 300)).reason?.count, 200)
        let ban = BanInfo(until: 1_795_000_000_000, reason: nil)
        let text = try XCTUnwrap(ban.untilText(locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC")!))
        XCTAssertTrue(text.contains("2026"), text)
        XCTAssertTrue(ban.isOver(now: Date(timeIntervalSince1970: 1_795_000_001)))
        XCTAssertFalse(ban.isOver(now: Date(timeIntervalSince1970: 1_794_999_999)))
    }

    // MARK: ворота входа

    func testGateNeedsLiveServerAndNoSession() async throws {
        let api = FakeAPI()
        api.on("GET /health", 200, "{}")
        api.on("POST /auth/login", 200, #"{"session":"tok","user":\#(userJSON)}"#)
        let store = makeStore(api: api)
        XCTAssertFalse(store.needsGate, "сервер ещё не спрашивали")
        await store.checkServer()
        XCTAssertTrue(store.needsGate)
        try await store.login("folzy", password: "12345678")
        XCTAssertFalse(store.needsGate)
    }

    func testDeadServerDoesNotLockTheApp() async {
        let api = FakeAPI()
        api.on("GET /health", 502, "<html>")
        let store = makeStore(api: api)
        await store.checkServer()
        XCTAssertFalse(store.reachable)
        XCTAssertFalse(store.needsGate, "сервер лёг — пускаем, как на ПК")
    }

    // MARK: бан

    func testBannedLoginKeepsTermAndShowsOnGate() async {
        let api = FakeAPI()
        api.on("POST /auth/login", 403, Self.bannedBody)
        let secrets = MemorySecrets()
        let store = makeStore(api: api, secrets: secrets)
        do {
            try await store.login("folzy", password: "12345678")
            XCTFail("заблокированного не пускаем")
        } catch let error as APIError {
            XCTAssertTrue(error.isBanned)
            XCTAssertEqual(error.reason, "спам")
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertFalse(store.signedIn)
        XCTAssertNil(secrets.string(SessionVault.tokenAccount), "сессия не сохраняется")
        XCTAssertEqual(store.banned, BanInfo(until: 1_795_000_000_000, reason: "спам"))
    }

    func testBanMidSessionSignsOutStopsMusicAndExplains() async throws {
        let api = FakeAPI()
        api.on("POST /auth/login", 200, #"{"session":"tok","user":\#(userJSON)}"#)
        api.on("GET /me", 403, Self.bannedBody)
        let secrets = MemorySecrets()
        let store = makeStore(api: api, secrets: secrets)
        var stopped = 0
        store.onBanned = { stopped += 1 }
        try await store.login("folzy", password: "12345678")
        XCTAssertTrue(store.signedIn)
        do {
            try await store.refreshMe()
            XCTFail("403 должен вылететь")
        } catch let error as APIError {
            XCTAssertTrue(error.isBanned)
        }
        XCTAssertFalse(store.signedIn)
        XCTAssertNil(secrets.string(SessionVault.tokenAccount), "токен стёрт")
        XCTAssertEqual(store.banned?.reason, "спам")
        XCTAssertEqual(stopped, 1, "музыка останавливается")
    }

    func testPlainSessionEndDoesNotClaimABan() async throws {
        let api = FakeAPI()
        api.on("POST /auth/login", 200, #"{"session":"tok","user":\#(userJSON)}"#)
        api.on("GET /me", 401, #"{"error":{"code":"unauthorized","message":"x"}}"#)
        let store = makeStore(api: api)
        var stopped = 0
        store.onBanned = { stopped += 1 }
        try await store.login("folzy", password: "12345678")
        _ = try? await store.refreshMe()
        XCTAssertFalse(store.signedIn)
        XCTAssertNil(store.banned)
        XCTAssertEqual(stopped, 0)
    }

    func testSigningInAgainClearsTheBanNotice() async throws {
        let api = FakeAPI()
        api.on("POST /auth/login", 403, Self.bannedBody)
        api.on("POST /auth/login", 200, #"{"session":"tok","user":\#(userJSON)}"#)
        let store = makeStore(api: api)
        _ = try? await store.login("bad", password: "12345678")
        XCTAssertNotNil(store.banned)
        try await store.login("folzy", password: "12345678")
        XCTAssertNil(store.banned)
        XCTAssertTrue(store.signedIn)
    }

    // MARK: причина сетевого сбоя

    func testNetworkFailureKeepsItsReason() async {
        let cases: [(URLError.Code, String)] = [(.timedOut, "таймаут, -1001"), (.cannotFindHost, "DNS, -1003"),
                                                (.notConnectedToInternet, "нет интернета, -1009"),
                                                (.serverCertificateUntrusted, "ошибка TLS, -1202")]
        for (code, expected) in cases {
            let client = APIClient(base: URL(string: "https://try-sonar.ru/api")!, fetch: { _ in throw URLError(code) })
            do {
                try await client.call("GET", "health")
                XCTFail("ждали ошибку сети")
            } catch let error as APIError {
                XCTAssertEqual(error.code, "network")
                XCTAssertEqual(error.message, "Нет связи с сервером Sonar", "сообщение прежнее — оно переводится")
                XCTAssertEqual(error.detail, expected)
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    func testAccountErrorTextAppendsReasonOnlyForNetwork() {
        let net = APIError(status: 0, code: "network", message: "Нет связи с сервером Sonar", detail: "таймаут, -1001")
        XCTAssertTrue(AccountErrorText.of(net).hasSuffix("(таймаут, -1001)"))
        XCTAssertEqual(AccountErrorText.of(APIError(status: 401, code: "bad_credentials", message: "Неверный логин или пароль")),
                       t("Неверный логин или пароль"))
    }

    // MARK: вход по ссылке в ненадёжной сети

    private final class PollScript: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var polls = 0

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            polls += 1
            return polls
        }
    }

    /// Первый опрос потерялся (таймаут), второй — «ждём», третий — «разрешено»: вход всё равно состоялся.
    func testLinkWaitSurvivesALostPollAnswer() async throws {
        let script = PollScript()
        let expires = Int64(Date().timeIntervalSince1970 * 1000) + 60_000
        let store = makeStore(fetch: { request in
            let route = FakeAPI.route(request)
            if route == "POST /auth/link" {
                return (Data(#"{"code":"abc","url":"https://try-sonar.ru/auth/abc","expires_at":\#(expires)}"#.utf8), 200)
            }
            if route == "GET /auth/link/abc/poll" {
                switch script.next() {
                case 1: throw URLError(.timedOut)
                case 2: return (Data(#"{"status":"pending"}"#.utf8), 200)
                default: return (Data(#"{"status":"approved","session":"tok","user":\#(userJSON)}"#.utf8), 200)
                }
            }
            return (Data(#"{"error":{"code":"not_found","message":"нет"}}"#.utf8), 404)
        })
        let link = try await store.createLoginLink()
        let outcome = try await store.waitForLink(link)
        XCTAssertEqual(outcome, .approved)
        XCTAssertTrue(store.signedIn)
        XCTAssertEqual(script.polls, 3)
    }

    /// Сервер ответил отказом — это не «потерялся ответ», ожидание заканчивается ошибкой, а не крутится вечно.
    func testLinkWaitStopsOnARealServerError() async throws {
        let expires = Int64(Date().timeIntervalSince1970 * 1000) + 60_000
        let store = makeStore(fetch: { request in
            if FakeAPI.route(request) == "POST /auth/link" {
                return (Data(#"{"code":"abc","url":"https://try-sonar.ru/auth/abc","expires_at":\#(expires)}"#.utf8), 200)
            }
            return (Data(#"{"error":{"code":"not_found","message":"Ссылка не найдена"}}"#.utf8), 404)
        })
        let link = try await store.createLoginLink()
        do {
            _ = try await store.waitForLink(link)
            XCTFail("404 должен прервать ожидание")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 404)
        }
    }

    // MARK: карточка синхронизации

    func testSyncCardStateFollowsLoginAndProgress() {
        let when = Date(timeIntervalSince1970: 1_795_000_000)
        XCTAssertEqual(SyncCardState.of(signedIn: false, syncing: true, lastSyncAt: when, lastError: "x"), .signedOut)
        XCTAssertEqual(SyncCardState.of(signedIn: true, syncing: true, lastSyncAt: when, lastError: nil), .syncing)
        XCTAssertEqual(SyncCardState.of(signedIn: true, syncing: false, lastSyncAt: when, lastError: "Нет связи"), .failed("Нет связи"))
        XCTAssertEqual(SyncCardState.of(signedIn: true, syncing: false, lastSyncAt: nil, lastError: nil), .never)
        XCTAssertEqual(SyncCardState.of(signedIn: true, syncing: false, lastSyncAt: when, lastError: ""), .done(when))
    }

    func testSyncNowOnlyWhenThereIsSomeoneToSyncWithAndNothingRuns() {
        XCTAssertFalse(SyncCardState.signedOut.canSyncNow)
        XCTAssertFalse(SyncCardState.syncing.canSyncNow)
        XCTAssertTrue(SyncCardState.never.canSyncNow)
        XCTAssertTrue(SyncCardState.failed("x").canSyncNow)
        XCTAssertTrue(SyncCardState.done(Date()).canSyncNow)
    }

    // MARK: ключ API

    func testApiKeyIsMaskedAndAddressIsBuilt() {
        XCTAssertEqual(ApiKeyView.masked("snr_abcdefghijklmnop"), "snr_ab••••••••mnop")
        XCTAssertEqual(ApiKeyView.masked("abc"), "••••", "короткое прячем целиком")
        XCTAssertEqual(ApiKeyView.nowURL(base: URL(string: "https://try-sonar.ru/api"), key: "snr_x"), "https://try-sonar.ru/api/oauth/now?token=snr_x")
        XCTAssertEqual(ApiKeyView.nowURL(base: URL(string: "https://test.example/api/"), key: "k"), "https://test.example/api/oauth/now?token=k")
        XCTAssertEqual(ApiKeyView.nowURL(base: nil, key: "k"), "https://try-sonar.ru/api/oauth/now?token=k")
    }

    func testApiKeyRoundTrip() async throws {
        let api = FakeAPI()
        api.on("POST /auth/login", 200, #"{"session":"tok","user":\#(userJSON)}"#)
        api.on("GET /me/integration", 200, #"{"key":null,"created_at":null}"#)
        api.on("POST /integrations/api-key", 200, #"{"key":"snr_abc","created_at":1795000000000}"#)
        api.on("DELETE /integrations/api-key", 204, "")
        let store = makeStore(api: api)
        try await store.login("folzy", password: "12345678")
        let empty = try await store.apiKey()
        XCTAssertNil(empty.key)
        let fresh = try await store.newApiKey()
        XCTAssertEqual(fresh.key, "snr_abc")
        XCTAssertEqual(fresh.createdAt, 1_795_000_000_000)
        try await store.deleteApiKey()
        XCTAssertEqual(api.count("DELETE /integrations/api-key"), 1)
        XCTAssertEqual(api.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }
}
