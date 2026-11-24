import XCTest
@testable import Sonar

/// Spotify без сети — токен, TOTP и ключ, как Rust-тесты `providers/spotify.rs` (разбор ответов — `SpotifyGQLTests`);
/// живая проверка — только с
/// `SP_DC` в окружении схемы тестов (ключ не печатается).
final class SpotifyTests: XCTestCase {
    func testTotpRFC6238Vectors() {
        let key = Data("12345678901234567890".utf8)
        XCTAssertEqual(Spotify.totp(key: key, unixSeconds: 59), "287082")
        XCTAssertEqual(Spotify.totp(key: key, unixSeconds: 1_111_111_109), "081804")
    }

    func testTotpKeyFromCipher() {
        let key = Spotify.totpKey(Spotify.TotpSecret.default.cipher)
        XCTAssertEqual(String(decoding: key, as: UTF8.self), "376136387538459893883312310911992847112448894410210511297108")
        XCTAssertEqual(Spotify.totp(key: key, unixSeconds: 1_700_000_000), "371599")
    }

    func testRemoteTotpOnlyNewerAndSane() {
        func parse(_ text: String) -> Spotify.TotpSecret? { SpotifyTotp.parseRemote(Data(text.utf8), current: 61) }
        XCTAssertEqual(parse(#"{"version":62,"cipher":[1,2,3]}"#), Spotify.TotpSecret(version: 62, cipher: [1, 2, 3]))
        XCTAssertNil(parse(#"{"version":61,"cipher":[1]}"#), "та же версия — мимо")
        XCTAssertNil(parse(#"{"version":5,"cipher":[1]}"#), "старая — мимо")
        XCTAssertNil(parse(#"{"version":70,"cipher":[]}"#), "пустой шифр")
        XCTAssertNil(parse(#"{"version":70,"cipher":[300]}"#), "не байт")
        XCTAssertNil(parse("<html>404</html>"))
        XCTAssertNil(parse(#"{"version":70,"cipher":[\#(Array(repeating: "1", count: 200).joined(separator: ","))]}"#), "слишком длинный")
    }

    func testTotpStoreAdoptsNewerFile() async {
        let store = SpotifyTotp()
        let builtin = await store.current
        XCTAssertEqual(builtin, .default)
        let same = await store.adopt(Data(#"{"version":61,"cipher":[9]}"#.utf8))
        XCTAssertFalse(same)
        let newer = await store.adopt(Data(#"{"version":64,"cipher":[9,8]}"#.utf8))
        XCTAssertTrue(newer)
        let adopted = await store.current.version
        XCTAssertEqual(adopted, 64)
        let older = await store.adopt(Data(#"{"version":63,"cipher":[7]}"#.utf8))
        XCTAssertFalse(older, "назад не откатываемся")
    }

    func testTokenQueryShape() {
        let query = Dictionary(uniqueKeysWithValues: Spotify.tokenQuery(.default, unixSeconds: 1_700_000_000))
        XCTAssertEqual(query["totp"], "371599")
        XCTAssertEqual(query["totpServer"], "371599")
        XCTAssertEqual(query["totpVer"], "61")
        XCTAssertEqual(query["productType"], "web-player")
        XCTAssertEqual(query["reason"], "init")
    }

    func testNormalizeAcceptsPrefixAndCookieHeader() {
        let value = "AQBxyz-_0123456789abcdefABCDEF"
        XCTAssertEqual(Spotify.normalizeSpDc(value), value)
        XCTAssertEqual(Spotify.normalizeSpDc("  sp_dc=\(value);  "), value)
        XCTAssertEqual(Spotify.normalizeSpDc("sp_t=1; sp_dc=\(value); sp_key=2"), value)
        XCTAssertEqual(Spotify.normalizeSpDc("\"\(value)\""), value)
        XCTAssertNil(Spotify.normalizeSpDc(""))
        XCTAssertNil(Spotify.normalizeSpDc("short"))
        XCTAssertNil(Spotify.normalizeSpDc("has space inside the cookie value ok"))
    }

    func testParseTokenOkAndErrors() throws {
        func parse(_ status: Int, _ body: String) throws -> Spotify.WebToken {
            try Spotify.parseToken(status: status, body: Data(body.utf8), nowMs: 0)
        }
        func message(_ status: Int, _ body: String) -> String? {
            do {
                _ = try parse(status, body)
                return nil
            } catch {
                return (error as? ServiceError)?.message
            }
        }
        let ok = try parse(200, #"{"clientId":"c","accessToken":"BQ1","accessTokenExpirationTimestampMs":1700000000000,"isAnonymous":false}"#)
        XCTAssertEqual(ok, Spotify.WebToken(accessToken: "BQ1", expiresAtMs: 1_700_000_000_000))
        XCTAssertTrue(ok.isFresh(atMs: 1_700_000_000_000 - 61_000))
        XCTAssertFalse(ok.isFresh(atMs: 1_700_000_000_000 - 59_000))
        XCTAssertEqual(message(200, #"{"accessToken":"BQ2","isAnonymous":true}"#), Spotify.spDcBad)
        XCTAssertEqual(message(400, "{}"), Spotify.totpStale)
        XCTAssertEqual(message(403, #"{"error":"Invalid TOTP"}"#), Spotify.totpStale)
        XCTAssertEqual(message(429, ""), "Spotify: слишком много запросов, подожди минуту (HTTP 429)")
        XCTAssertEqual(message(200, "not json"), "Spotify: непонятный ответ веб-плеера")
        // удачный ответ, где в случайном токене попалось «TOTP», — не «ключ устарел»
        XCTAssertEqual(try parse(200, #"{"accessToken":"BQxTOTPy","isAnonymous":false}"#).accessToken, "BQxTOTPy")
        // срок не пришёл — полчаса от «сейчас»
        XCTAssertEqual(try parse(200, #"{"accessToken":"BQ3"}"#).expiresAtMs, Spotify.defaultTokenLifeMs)
    }

    func testSearchSourceCycleIncludesSpotifyOnlyWhenConnected() {
        typealias Source = SearchView.Source
        XCTAssertEqual(Source.soundcloud.next(spotifyConnected: false), .yandex)
        XCTAssertEqual(Source.yandex.next(spotifyConnected: false), .youtube)
        XCTAssertEqual(Source.youtube.next(spotifyConnected: false), .vk)
        XCTAssertEqual(Source.vk.next(spotifyConnected: false), .soundcloud)
        XCTAssertEqual(Source.vk.next(spotifyConnected: true), .spotify)
        XCTAssertEqual(Source.spotify.next(spotifyConnected: true), .soundcloud)
        // сырые значения SoundCloud и Яндекса — как у Service: старая настройка search.source читается
        XCTAssertEqual(Source(rawValue: Service.yandex.rawValue), .yandex)
        XCTAssertEqual(Source(rawValue: Service.soundcloud.rawValue), .soundcloud)
    }

    func testCredsKeepRustFieldName() throws {
        let data = try JSONEncoder().encode(SpotifyCreds(spDc: "x"))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"sp_dc":"x"}"#)
    }

    /// Токен кэшируется до конца срока; renew — всегда заново.
    func testTokenCache() async throws {
        let tokens = SpotifyTokens()
        let calls = Counter()
        let fetch: @Sendable () async throws -> Spotify.WebToken = {
            let n = await calls.next()
            return Spotify.WebToken(accessToken: "T\(n)", expiresAtMs: Spotify.nowMs + 3_600_000)
        }
        let first = try await tokens.token(renew: false, fetch: fetch)
        let cached = try await tokens.token(renew: false, fetch: fetch)
        let renewed = try await tokens.token(renew: true, fetch: fetch)
        XCTAssertEqual([first, cached, renewed], ["T1", "T1", "T2"])
    }

    /// Живая проверка: `SP_DC` в окружении — токен, `/me` и поиск. Без ключа — пропуск.
    func testLiveTokenSearchAccount() async throws {
        guard let raw = ProcessInfo.processInfo.environment["SP_DC"], let spDc = Spotify.normalizeSpDc(raw) else {
            throw XCTSkip("SP_DC не задан")
        }
        let client = Spotify(creds: SpotifyCreds(spDc: spDc), tokens: SpotifyTokens())
        let account = try await client.account()
        XCTAssertNotNil(account.uid)
        let found = try await client.search("Daft Punk", limit: 5)
        XCTAssertFalse(found.isEmpty)
        XCTAssertTrue(found.allSatisfy { $0.ref.hasPrefix("sp:") })
    }
}

private actor Counter {
    private var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}
