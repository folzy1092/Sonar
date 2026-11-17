import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Sonar

/// Last.fm: md5 и подпись (как Windows `lastfm.rs`), правила скроббла, очередь и запросы.
final class LastfmTests: XCTestCase {
    func testMD5Vectors() {
        // RFC 1321, приложение A.5
        XCTAssertEqual(MD5.hex(""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(MD5.hex("a"), "0cc175b9c0f1b6a831c399e269772661")
        XCTAssertEqual(MD5.hex("abc"), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(MD5.hex("message digest"), "f96b697d7cb7938d525a2f31aaf161d0")
        XCTAssertEqual(MD5.hex("12345678901234567890123456789012345678901234567890123456789012345678901234567890"),
                       "57edf4a22be3c955ac49da2e2107b67a")
        XCTAssertEqual(MD5.hex("Кириллица"), MD5.hex(Array("Кириллица".utf8)))
    }

    func testSignatureSortsParamsAndSkipsFormat() {
        // пример из документации Last.fm (тот же, что в тесте Windows)
        let params = ["method": "auth.getSession", "token": "yyyyyy", "api_key": "xxxx", "format": "json"]
        XCTAssertEqual(LastfmSign.signature(params, secret: "secret"),
                       MD5.hex("api_keyxxxxmethodauth.getSessiontokenyyyyyysecret"))
    }

    func testScrobbleRules() {
        XCTAssertNil(LastfmRules.threshold(durationMs: 30_000)) // не длиннее 30 с — не скробблится
        XCTAssertEqual(LastfmRules.threshold(durationMs: 100_000), 50_000) // половина
        XCTAssertEqual(LastfmRules.threshold(durationMs: 600_000), 240_000) // но не больше 4 минут
        XCTAssertEqual(LastfmRules.threshold(durationMs: 0), 240_000) // длительность неизвестна
        XCTAssertFalse(LastfmRules.shouldScrobble(listenedMs: 49_999, durationMs: 100_000))
        XCTAssertTrue(LastfmRules.shouldScrobble(listenedMs: 50_000, durationMs: 100_000))
        XCTAssertFalse(LastfmRules.shouldScrobble(listenedMs: 25_000, durationMs: 25_000))
    }

    func testKeysFromInfoPlist() {
        XCTAssertNil(LastfmKeys.from(info: nil))
        XCTAssertNil(LastfmKeys.from(info: ["SonarLastfmKey": "", "SonarLastfmSecret": "s"]))
        XCTAssertNil(LastfmKeys.from(info: ["SonarLastfmKey": "$(SONAR_LASTFM_KEY)", "SonarLastfmSecret": "s"]))
        XCTAssertEqual(LastfmKeys.from(info: ["SonarLastfmKey": " k ", "SonarLastfmSecret": "s"]), LastfmKeys(key: "k", secret: "s"))
    }

    func testTrackFromSonarTrack() {
        var track = makeTrack("sc:1", "Main", title: "Song", durationMs: 185_400)
        track.artist = "Main, Guest"
        track.album = AlbumRef(ref: "scalb:1", title: "LP")
        let item = LastfmTrack(track, startedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(item, LastfmTrack(artist: "Main", title: "Song", album: "LP", durationS: 185, startedAt: 1000))
        let batch = LastfmAPI.trackParams(item, index: 2, timestamp: true)
        XCTAssertEqual(batch["artist[2]"], "Main")
        XCTAssertEqual(batch["timestamp[2]"], "1000")
        XCTAssertNil(LastfmAPI.trackParams(item, timestamp: false)["timestamp"])
    }

    func testRequestIsSignedFormPost() throws {
        let api = LastfmAPI(keys: LastfmKeys(key: "KEY", secret: "SEC"))
        let request = api.request(["method": "track.scrobble", "artist": "Мот & Co", "sk": "S"], signed: true, post: true)
        XCTAssertEqual(request.httpMethod, "POST")
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8) ?? ""
        let sig = LastfmSign.signature(["method": "track.scrobble", "artist": "Мот & Co", "sk": "S", "api_key": "KEY"], secret: "SEC")
        XCTAssertTrue(body.contains("api_sig=\(sig)"))
        XCTAssertTrue(body.contains("format=json"))
        XCTAssertTrue(body.contains("artist=%D0%9C%D0%BE%D1%82%20%26%20Co"))
        let get = api.request(["method": "auth.getToken"], signed: true, post: false)
        XCTAssertEqual(get.httpMethod ?? "GET", "GET")
        XCTAssertTrue(get.url?.absoluteString.contains("api_key=KEY") == true)
    }

    func testAuthURL() {
        let api = LastfmAPI(keys: LastfmKeys(key: "KEY", secret: "SEC"))
        let url = api.authURL(token: "T", callback: "sonar://lastfm").absoluteString
        XCTAssertTrue(url.hasPrefix("https://www.last.fm/api/auth/?"))
        XCTAssertTrue(url.contains("api_key=KEY"))
        XCTAssertTrue(url.contains("token=T"))
        XCTAssertTrue(url.contains("cb=sonar://lastfm"))
    }

    func testErrorsAreParsed() async {
        let api = LastfmAPI(keys: LastfmKeys(key: "K", secret: "S"),
                            transport: FakeLastfm(reply: #"{"error": 9, "message": "Invalid session key"}"#, status: 403))
        do {
            _ = try await api.getToken()
            XCTFail("ожидалась ошибка")
        } catch let error as LastfmError {
            XCTAssertTrue(error.isInvalidSession)
        } catch {
            XCTFail("\(error)")
        }
        let ok = LastfmAPI(keys: LastfmKeys(key: "K", secret: "S"), transport: FakeLastfm(reply: #"{"session": {"name": "folzy", "key": "SK"}}"#))
        let session = try? await ok.getSession(token: "T")
        XCTAssertEqual(session, LastfmSession(name: "folzy", key: "SK", avatarURL: nil))
    }

    @MainActor
    func testScrobblerScrobblesOnceAtThreshold() async throws {
        let fake = FakeLastfm(reply: "{}")
        let scrobbler = makeScrobbler(fake, session: LastfmSession(name: "u", key: "SK"))
        let track = makeTrack("sc:1", "A", durationMs: 100_000)
        scrobbler.trackStarted(track)
        await settle()
        XCTAssertEqual(fake.methods, ["track.updateNowPlaying"])
        scrobbler.progress(listenedMs: 20_000)
        scrobbler.progress(listenedMs: 50_000)
        scrobbler.progress(listenedMs: 90_000)
        await settle()
        XCTAssertEqual(fake.methods, ["track.updateNowPlaying", "track.scrobble"])
        XCTAssertTrue(scrobbler.pending.isEmpty)
        XCTAssertNotNil(scrobbler.lastSent)
        // тот же трек заново — новое прослушивание
        scrobbler.trackStarted(track)
        scrobbler.progress(listenedMs: 60_000)
        await settle()
        XCTAssertEqual(fake.methods.filter { $0 == "track.scrobble" }.count, 2)
    }

    @MainActor
    func testScrobblerRespectsSettingsAndLogin() async {
        let fake = FakeLastfm(reply: "{}")
        let settings = SettingsStore(storage: UserDefaults(suiteName: "lastfm-\(UUID().uuidString)")!)
        settings.set(LastfmScrobbler.nowPlayingKey, false)
        settings.set(LastfmScrobbler.scrobbleKey, false)
        let scrobbler = makeScrobbler(fake, session: LastfmSession(name: "u", key: "SK"), settings: settings)
        scrobbler.trackStarted(makeTrack("sc:1", "A"))
        scrobbler.progress(listenedMs: 300_000)
        await settle()
        XCTAssertTrue(fake.methods.isEmpty)

        let offline = makeScrobbler(fake, session: nil)
        offline.trackStarted(makeTrack("sc:1", "A"))
        offline.progress(listenedMs: 300_000)
        await settle()
        XCTAssertTrue(fake.methods.isEmpty)
        XCTAssertFalse(offline.isConnected)
    }

    @MainActor
    func testFailedScrobbleWaitsAndInvalidSessionLogsOut() async {
        let fake = FakeLastfm(reply: #"{"error": 11, "message": "Service Offline"}"#, status: 503)
        let defaults = UserDefaults(suiteName: "lastfm-\(UUID().uuidString)")!
        let store = MemoryLastfmStore(LastfmSession(name: "u", key: "SK"))
        let scrobbler = makeScrobbler(fake, store: store, defaults: defaults)
        scrobbler.trackStarted(makeTrack("sc:1", "A"))
        scrobbler.progress(listenedMs: 300_000)
        await settle()
        XCTAssertEqual(scrobbler.pending.count, 1) // Last.fm недоступен — ждёт
        XCTAssertNotNil(scrobbler.lastError)
        // очередь переживает перезапуск
        let reopened = makeScrobbler(fake, store: store, defaults: defaults)
        XCTAssertEqual(reopened.pending.count, 1)

        fake.reply = #"{"error": 9, "message": "Invalid session key"}"#
        reopened.flush()
        await settle()
        XCTAssertFalse(reopened.isConnected)
        XCTAssertNil(store.load())
        XCTAssertTrue(reopened.pending.isEmpty)
    }

    @MainActor
    func testWithoutKeysNothingHappens() async {
        let fake = FakeLastfm(reply: "{}")
        let scrobbler = LastfmScrobbler(keys: nil, transport: fake, store: MemoryLastfmStore(LastfmSession(name: "u", key: "SK")),
                                        settings: SettingsStore(storage: UserDefaults(suiteName: "lastfm-\(UUID().uuidString)")!),
                                        defaults: UserDefaults(suiteName: "lastfm-\(UUID().uuidString)")!)
        XCTAssertFalse(scrobbler.available)
        scrobbler.trackStarted(makeTrack("sc:1", "A"))
        scrobbler.progress(listenedMs: 300_000)
        await settle()
        XCTAssertTrue(fake.methods.isEmpty)
    }

    // MARK: - Помощники

    @MainActor
    private func makeScrobbler(_ fake: FakeLastfm, session: LastfmSession?, settings: SettingsStore? = nil) -> LastfmScrobbler {
        makeScrobbler(fake, store: MemoryLastfmStore(session), settings: settings,
                      defaults: UserDefaults(suiteName: "lastfm-\(UUID().uuidString)")!)
    }

    @MainActor
    private func makeScrobbler(_ fake: FakeLastfm, store: MemoryLastfmStore, settings: SettingsStore? = nil,
                               defaults: UserDefaults) -> LastfmScrobbler {
        LastfmScrobbler(keys: LastfmKeys(key: "K", secret: "S"), transport: fake, store: store,
                        settings: settings ?? SettingsStore(storage: UserDefaults(suiteName: "lastfm-\(UUID().uuidString)")!),
                        defaults: defaults)
    }

    /// Дать отработать задачам скробблера (сеть подменена — отвечает сразу).
    @MainActor
    private func settle() async {
        for _ in 0 ..< 20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(30))
        for _ in 0 ..< 20 { await Task.yield() }
    }
}

/// Last.fm без сети: один ответ на всё, запоминает методы.
final class FakeLastfm: LastfmTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _reply: String
    private var _methods: [String] = []
    let status: Int

    init(reply: String, status: Int = 200) {
        _reply = reply
        self.status = status
    }

    var reply: String {
        get { lock.lock(); defer { lock.unlock() }; return _reply }
        set { lock.lock(); _reply = newValue; lock.unlock() }
    }

    var methods: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _methods
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let text = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? request.url?.query ?? ""
        let method = text.split(separator: "&").first { $0.hasPrefix("method=") }.map { String($0.dropFirst(7)) } ?? ""
        return (Data(record(method).utf8), status)
    }

    private func record(_ method: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        _methods.append(method)
        return _reply
    }
}
