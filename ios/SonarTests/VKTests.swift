import XCTest
@testable import Sonar

/// VK Музыка без сети — те же случаи, что в Rust-тестах (`providers/vk.rs`, `login.rs`).
final class VKTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONValue(data: Data(text.utf8))
    }

    private let audio = #"""
    {"artist": "Земфира", "id": 456239017, "owner_id": -2001234567, "title": "Хочешь?", "subtitle": "Live",
     "duration": 214, "access_key": "a1b2c3", "url": "https://cs1-2v4.vkuseraudio.net/s/v1/ac/abc/index.m3u8?siren=1",
     "is_explicit": true, "genre_id": 2,
     "album": {"id": 77, "title": "Прости меня моя любовь", "owner_id": -2000111, "access_key": "k9",
               "thumb": {"photo_300": "https://sun9-1.userapi.com/a300.jpg", "photo_600": "https://sun9-1.userapi.com/a600.jpg"}},
     "main_artists": [{"name": "Земфира", "domain": "zemfira", "id": "123456789"}],
     "featured_artists": [{"name": "Гость", "id": "42"}]}
    """#

    private let playlist = #"""
    {"id": 15, "owner_id": 1, "type": 0, "title": "Дорога", "count": 31, "access_key": "ff00",
     "thumbs": [{"photo_300": "https://sun9-3.userapi.com/t300.jpg"}]}
    """#

    func testAudioFields() throws {
        let parsed = try XCTUnwrap(VK.parseAudio(try json(audio)))
        let track = parsed.track
        XCTAssertEqual(track.ref, "vk:-2001234567_456239017")
        XCTAssertEqual(track.title, "Хочешь? (Live)")
        XCTAssertEqual(track.artist, "Земфира")
        XCTAssertEqual(track.artists.map(\.ref), ["vka:123456789", "vka:42"])
        XCTAssertEqual(track.album?.ref, "vkalb:-2000111_77_k9")
        XCTAssertEqual(track.durationMs, 214_000)
        XCTAssertEqual(track.coverURL, "https://sun9-1.userapi.com/a600.jpg")
        XCTAssertEqual(track.url, "https://vk.com/audio-2001234567_456239017")
        XCTAssertTrue(track.explicit)
        XCTAssertTrue(track.available)
        XCTAssertEqual(track.tags, "pop")
        XCTAssertEqual(parsed.accessKey, "a1b2c3")
        XCTAssertTrue(parsed.streamURL?.hasSuffix("index.m3u8?siren=1") == true)
        XCTAssertEqual(Service(ref: track.ref), .vk)
    }

    func testAudioMinimalAndRestricted() throws {
        let parsed = try XCTUnwrap(VK.parseAudio(try json(#"{"id": 1, "owner_id": 5, "title": "x", "url": "", "content_restricted": 1}"#)))
        XCTAssertEqual(parsed.track.ref, "vk:5_1")
        XCTAssertNil(parsed.track.album)
        XCTAssertNil(parsed.track.coverURL)
        XCTAssertNil(parsed.streamURL)
        XCTAssertNil(parsed.accessKey)
        XCTAssertFalse(parsed.track.available)
        XCTAssertTrue(parsed.track.artists.isEmpty)
        XCTAssertNil(VK.parseAudio(try json(#"{"id": 1, "title": "без владельца"}"#)))
    }

    func testListResponses() throws {
        let list = try json(#"{"count": 2, "items": [\#(audio), {"bad": 1}, \#(audio)]}"#)
        XCTAssertEqual(VK.audios(list["items"]).count, 2)
        // audio.getById отдаёт массив без items
        XCTAssertEqual(VK.audios(try json("[\(audio)]")).count, 1)
        XCTAssertEqual(VK.items(try json("[1, 2]")).count, 2)
        XCTAssertTrue(VK.items(try json(#"{"count": 0}"#)).isEmpty)
    }

    func testStreamSources() throws {
        guard case .hls = try VK.source("https://cs1.vkuseraudio.net/s/v1/ac/x/index.m3u8?siren=1") else {
            return XCTFail("m3u8 — это HLS")
        }
        guard case .file = try VK.source("https://cs1.vkuseraudio.net/s/v1/acmp3/x.mp3?extra=1") else {
            return XCTFail("mp3 — это файл")
        }
        for bad in ["", "https://vk.com/mp3/audio_api_unavailable.mp3", "not a url"] {
            XCTAssertThrowsError(try VK.source(bad), bad) { error in
                XCTAssertEqual(error.localizedDescription, VK.noStream)
                XCTAssertEqual(Unplayable.reason(of: error), .unavailable)
            }
        }
    }

    func testCDNNeedsKateAgent() {
        XCTAssertTrue(VK.isCDN(URL(string: "https://cs1-2v4.vkuseraudio.net/s/v1/ac/x/index.m3u8")!))
        XCTAssertTrue(VK.isCDN(URL(string: "https://psv4.userapi.com/c1/x.mp3")!))
        XCTAssertFalse(VK.isCDN(URL(string: "https://evil-vkuseraudio.net.example/x.mp3")!))
        XCTAssertFalse(VK.isCDN(URL(string: "https://strm.yandex.ru/x.mp3")!))
        XCTAssertTrue(VK.userAgent.hasPrefix("KateMobileAndroid/"))
    }

    func testAPIErrorsAreFriendly() throws {
        func message(_ code: Int) throws -> String? {
            let body = #"{"error": {"error_code": \#(code), "error_msg": "User authorization failed: access_token vk1.a.SECRET", "request_params": []}}"#
            return VK.apiError(try json(body))?.message
        }
        for code in [5, 15, 25, 201, 1117] {
            XCTAssertEqual(try message(code), VK.authExpired, "\(code)")
        }
        XCTAssertEqual(try message(6), VK.tooMany)
        XCTAssertEqual(try message(14), VK.captcha)
        XCTAssertEqual(try message(100), VK.failed)
        XCTAssertFalse(try message(5)?.contains("SECRET") ?? true)
        XCTAssertNil(VK.apiError(try json(#"{"response": []}"#)))
    }

    func testAccountFields() throws {
        let account = try XCTUnwrap(VK.parseAccount(try json(
            #"{"id": 1, "first_name": "Иван", "last_name": "Петров", "photo_200": "https://sun9-2.userapi.com/p.jpg"}"#)))
        XCTAssertEqual(account.name, "Иван Петров")
        XCTAssertEqual(account.uid, "1")
        XCTAssertNil(account.premium)
        XCTAssertEqual(account.avatarURL, "https://sun9-2.userapi.com/p.jpg")
        XCTAssertNil(try XCTUnwrap(VK.parseAccount(try json(#"{"id": 2}"#))).name)
        XCTAssertNil(VK.parseAccount(try json("{}")))
    }

    func testPlaylistsAndAlbums() throws {
        let parsed = try XCTUnwrap(VK.parsePlaylist(try json(playlist)))
        XCTAssertEqual(parsed.ref, "vkpl:1_15_ff00")
        XCTAssertEqual(parsed.title, "Дорога")
        XCTAssertEqual(parsed.trackCount, 31)
        XCTAssertEqual(parsed.coverURL, "https://sun9-3.userapi.com/t300.jpg")
        // добавленный к себе чужой — по оригиналу
        let followed = String(playlist.dropLast()) + #", "original": {"owner_id": -2000, "playlist_id": 9, "access_key": "zz"}}"#
        XCTAssertEqual(VK.parsePlaylist(try json(followed))?.ref, "vkpl:-2000_9_zz")

        let album = try XCTUnwrap(VK.parseAlbum(try json(#"""
        {"id": 5, "owner_id": -2000222, "type": 1, "title": "Альбом", "count": 10, "year": 2004,
         "photo": {"photo_600": "https://sun9-4.userapi.com/c600.jpg"}, "main_artists": [{"name": "Земфира", "id": "123"}]}
        """#)))
        XCTAssertEqual(album.ref, "vkalb:-2000222_5")
        XCTAssertEqual(album.artist, "Земфира")
        XCTAssertEqual(album.year, 2004)
        XCTAssertEqual(album.trackCount, 10)
        XCTAssertEqual(album.url, "https://vk.com/music/album/-2000222_5")
        XCTAssertEqual(album.coverURL, "https://sun9-4.userapi.com/c600.jpg")
    }

    func testArtistFields() throws {
        let artist = try XCTUnwrap(VK.parseArtist(try json(#"""
        {"id": "123", "name": "Земфира", "domain": "zemfira",
         "photo": [{"url": "https://sun9-5.userapi.com/s.jpg", "width": 100}, {"url": "https://sun9-5.userapi.com/l.jpg", "width": 1200}]}
        """#)))
        XCTAssertEqual(artist.ref, "vka:123")
        XCTAssertEqual(artist.name, "Земфира")
        XCTAssertEqual(artist.avatarURL, "https://sun9-5.userapi.com/l.jpg")
        XCTAssertEqual(artist.url, "https://vk.com/artist/zemfira")
        XCTAssertNil(VK.parseArtist(try json(#"{"name": "без id"}"#)))
    }

    func testPlaylistIDs() {
        XCTAssertEqual(VKPlaylistID.parse("-2000_9_ab12"), VKPlaylistID(owner: "-2000", id: "9", key: "ab12"))
        XCTAssertNil(VKPlaylistID.parse("1_15")?.key)
        XCTAssertNil(VKPlaylistID.parse("x_1"))
        XCTAssertNil(VKPlaylistID.parse("1"))
        XCTAssertNotNil(VKPlaylistID.parse("1_2_a&b"))
        XCTAssertNil(VKPlaylistID.parse("1_2_a&b")?.key, "в ключе только буквы и цифры")
        XCTAssertTrue(VK.isAudioID("-1_2") && VK.isAudioID("5_1"))
        XCTAssertFalse(VK.isAudioID("5_1_key") || VK.isAudioID("likes") || VK.isAudioID("5"))
    }

    func testThrottleSpacesCalls() {
        let now = Date(timeIntervalSince1970: 1_000)
        let first = VKThrottle.takeSlot(next: nil, now: now)
        XCTAssertEqual(first.wait, 0)
        let second = VKThrottle.takeSlot(next: first.next, now: now)
        XCTAssertEqual(second.wait, VK.gap, accuracy: 0.0001)
        let third = VKThrottle.takeSlot(next: second.next, now: now)
        XCTAssertEqual(third.wait, VK.gap * 2, accuracy: 0.0001)
        // после паузы ждать не нужно
        XCTAssertEqual(VKThrottle.takeSlot(next: third.next, now: now.addingTimeInterval(VK.gap * 10)).wait, 0)
    }

    func testLoginOutcome() throws {
        XCTAssertEqual(VKLogin.outcome(URL(string: "https://oauth.vk.com/blank.html#access_token=vk1.a.Xy-Z&expires_in=0&user_id=1")!),
                       .token("vk1.a.Xy-Z"))
        XCTAssertEqual(VKLogin.outcome(URL(string: "https://oauth.vk.com/blank.html#error=access_denied&error_reason=user_denied")!),
                       .denied)
        XCTAssertEqual(VKLogin.outcome(URL(string: "https://oauth.vk.com/blank.html?error=invalid_request")!), .denied)
        XCTAssertEqual(VKLogin.outcome(URL(string: "https://oauth.vk.ru/blank.html#access_token=vk1.a.Ru&expires_in=0")!), .token("vk1.a.Ru"))
        // вход ещё идёт или адрес чужой
        for link in ["https://oauth.vk.com/authorize?client_id=1", "https://id.vk.com/auth?x=1",
                     "https://evil.example/blank.html#access_token=x", "https://oauth.vk.com/blank.html",
                     "http://oauth.vk.com/blank.html#access_token=x"] {
            XCTAssertNil(VKLogin.outcome(URL(string: link)!), link)
        }
    }

    func testLoginURLIsKateImplicit() throws {
        let components = try XCTUnwrap(URLComponents(url: VKLogin.authURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "oauth.vk.com")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["client_id"], VK.clientId)
        XCTAssertEqual(query["redirect_uri"], VKLogin.redirect)
        XCTAssertEqual(query["response_type"], "token")
        XCTAssertEqual(query["scope"], "audio,offline")
        XCTAssertEqual(query["v"], VK.version)
    }

    func testCredsKeepOnlyToken() throws {
        let data = try JSONEncoder().encode(VKCreds(token: "vk1.a.test"))
        XCTAssertEqual(try JSONDecoder().decode(VKCreds.self, from: data), VKCreds(token: "vk1.a.test"))
        XCTAssertEqual(Service.vk.info.key, "vk")
        XCTAssertEqual(Service.vk.icon, .vk)
        XCTAssertEqual(Service.yandex.icon, .yandexMusic)
        XCTAssertEqual(Service.soundcloud.icon, .soundcloud)
        XCTAssertEqual(Service.youtube.icon, .youtubeMusic)
    }

    /// Ответ без `count` не обрывает страницы на первой: идём дальше, пока страница полная.
    func testPagesWithoutCount() {
        XCTAssertFalse(VK.lastPage(got: 200, asked: 200, offset: 200, total: nil))
        XCTAssertTrue(VK.lastPage(got: 37, asked: 200, offset: 237, total: nil))
        XCTAssertTrue(VK.lastPage(got: 0, asked: 200, offset: 400, total: nil))
        // с count — по нему, даже если страница короче
        XCTAssertFalse(VK.lastPage(got: 150, asked: 200, offset: 150, total: 500))
        XCTAssertTrue(VK.lastPage(got: 200, asked: 200, offset: 500, total: 500))
        XCTAssertTrue(VK.lastPage(got: 0, asked: 200, offset: 0, total: 10))
    }

    /// access_key трека переживает перезапуск: новый `VKKeyStore` читает тот же файл.
    func testKeyStoreSurvivesReopen() {
        let file = tempDirectory().appendingPathComponent("vk-keys.json")
        var before = VKKeyStore(file: file)
        before.remember([(ref: "vk:-1_2", key: "k1"), (ref: "vk:5_6", key: "k2")])
        let after = VKKeyStore(file: file)
        XCTAssertEqual(after.key(for: "vk:-1_2"), "k1")
        XCTAssertEqual(after.key(for: "vk:5_6"), "k2")
        XCTAssertNil(after.key(for: "vk:7_8"))
    }

    func testKeyStoreBrokenFileIsEmpty() throws {
        let file = tempDirectory().appendingPathComponent("vk-keys.json")
        try Data("{not json".utf8).write(to: file)
        XCTAssertEqual(VKKeyStore(file: file).count, 0)
    }

    /// Переполнение выкидывает самые давние, свежие и недавно виденные остаются.
    func testKeyStoreOverflowDropsOldestOnly() {
        var store = VKKeyStore()
        store.remember((0..<VKKeyStore.maxKeys).map { (ref: "vk:1_\($0)", key: "k") })
        store.remember([(ref: "vk:1_0", key: "k")])
        store.remember([(ref: "vk:2_1", key: "new")])
        XCTAssertEqual(store.count, VKKeyStore.keepAfterTrim)
        XCTAssertEqual(store.key(for: "vk:2_1"), "new")
        XCTAssertEqual(store.key(for: "vk:1_0"), "k")
        XCTAssertNil(store.key(for: "vk:1_1"))
        XCTAssertEqual(store.key(for: "vk:1_\(VKKeyStore.maxKeys - 1)"), "k")
    }
}
