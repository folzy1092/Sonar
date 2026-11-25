import XCTest
@testable import Sonar

/// Разбор ответов SoundCloud и Яндекса без сети — те же случаи, что в Rust-тестах
/// (`providers/soundcloud.rs`, `providers/yandex.rs`).
final class ProviderTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONValue(data: Data(text.utf8))
    }

    private func transcoding(_ proto: String, _ mime: String, _ preset: String, snipped: Bool = false) -> String {
        #"{"url": "u-\#(proto)-\#(preset)", "preset": "\#(preset)", "snipped": \#(snipped), "format": {"protocol": "\#(proto)", "mime_type": "\#(mime.replacingOccurrences(of: "\"", with: "\\\""))"}}"#
    }

    func testJSONValue() throws {
        let value = try json(#"{"a": {"b": [1, "x", null, 2.5, true]}, "id": 2296053116}"#)
        XCTAssertEqual(value["a"]["b"][0].int, 1)
        XCTAssertEqual(value["a"]["b"][1].string, "x")
        XCTAssertTrue(value["a"]["b"][2].isNull)
        XCTAssertTrue(value["нет"]["совсем"][3].isNull)
        XCTAssertNil(value["a"]["b"][3].int)
        XCTAssertEqual(value["a"]["b"][4].bool, true)
        XCTAssertEqual(value["id"].idString, "2296053116")
    }

    func testPicksAACHLSAndSkipsDRMAndOpus() throws {
        let track = try json(#"{"media": {"transcodings": ["# + [
            transcoding("hls", "audio/mpeg", "mp3_1_0"),
            transcoding("progressive", "audio/mpeg", "mp3_1_0"),
            transcoding("ctr-encrypted-hls", "audio/mpeg", "mp3_1_0"),
            transcoding("hls", "audio/ogg; codecs=\"opus\"", "opus_0_0"),
            transcoding("hls", "audio/mp4; codecs=\"mp4a.40.2\"", "aac_160k"),
            transcoding("hls", "audio/mp4; codecs=\"mp4a.40.2\"", "aac_96k"),
        ].joined(separator: ",") + "]}}")
        let picked = try XCTUnwrap(SoundCloud.pickTranscoding(track))
        XCTAssertEqual(picked["preset"].string, "aac_160k")
        XCTAssertEqual(SoundCloud.qualityLabel(picked), "AAC 160")
    }

    func testSnippedOnlyIfNothingElse() throws {
        let track = try json(#"{"media": {"transcodings": ["# + [
            transcoding("hls", "audio/mp4; codecs=\"mp4a.40.2\"", "aac_160k", snipped: true),
            transcoding("hls", "audio/mpeg", "mp3_1_0"),
        ].joined(separator: ",") + "]}}")
        let picked = try XCTUnwrap(SoundCloud.pickTranscoding(track))
        XCTAssertEqual(picked["preset"].string, "mp3_1_0")
        XCTAssertEqual(SoundCloud.qualityLabel(picked), "MP3 128")
    }

    func testFindsScriptsAndClientId() {
        let html = #"""
        <script crossorigin src="https://a-v2.sndcdn.com/assets/0-a.js"></script>
          <link href="https://a-v2.sndcdn.com/assets/x.css"><script src="https://a-v2.sndcdn.com/assets/49-b.js"></script>
        """#
        XCTAssertEqual(SoundCloud.scriptURLs(html), ["https://a-v2.sndcdn.com/assets/0-a.js", "https://a-v2.sndcdn.com/assets/49-b.js"])
        let js = #"a={client_id:"short"},b={client_id:"AbCdEfGhIjKlMnOpQrStUvWxYz012345",env:"production"}"#
        XCTAssertEqual(SoundCloud.findClientId(js), "AbCdEfGhIjKlMnOpQrStUvWxYz012345")
        XCTAssertNil(SoundCloud.findClientId("client_id:\"short\""))
    }

    /// С айфонным агентом soundcloud.com отдаёт m.soundcloud.com без скриптов — client_id ищем десктопным.
    func testClientIdUsesDesktopAgent() {
        XCTAssertFalse(SoundCloud.clientIdAgent.contains("iPhone"))
        XCTAssertFalse(SoundCloud.clientIdAgent.contains("Mobile"))
    }

    func testSoundCloudPlaylistToAlbumAndPhantom() throws {
        let playlist = try json(#"""
        {"id": 77, "title": "suffocate reality", "track_count": 9, "release_date": "2024-03-01T00:00:00Z",
         "artwork_url": null, "tracks": [{"id": 1, "artwork_url": "https://i1.sndcdn.com/a-large.jpg"}],
         "user": {"id": 5, "username": "extra"}, "permalink_url": "https://soundcloud.com/extra/sets/s"}
        """#)
        let album = try XCTUnwrap(SoundCloud.parseAlbum(playlist))
        XCTAssertEqual(album.ref, "scalb:77")
        XCTAssertEqual(album.year, 2024)
        XCTAssertEqual(album.released, "2024-03-01")
        XCTAssertEqual(album.coverURL, "https://i1.sndcdn.com/a-t500x500.jpg")
        XCTAssertEqual(album.artists.first?.ref, "sca:5")
        let phantom = try XCTUnwrap(SoundCloud.parsePlaylist(playlist))
        XCTAssertEqual(phantom.ref, "scpl:77")
        XCTAssertEqual(phantom.owner, "extra")
        XCTAssertEqual(phantom.trackCount, 9)
    }

    func testSoundCloudRepostsKeepOnlyTracksOnce() throws {
        // лента репостов: репост плейлиста мимо, повтор того же трека и пустой трек — тоже
        let page = try json(#"""
        {"collection": [
            {"type": "track-repost", "track": {"id": 1, "title": "секундант"}},
            {"type": "playlist-repost", "playlist": {"id": 9}, "track": {"id": 9}},
            {"type": "track-repost", "track": {"id": 2, "title": "330"}},
            {"type": "track-repost", "track": {"id": 1, "title": "секундант"}},
            {"type": "track-repost", "track": null},
            {"track": {"id": 3, "title": "high"}}
        ]}
        """#)
        XCTAssertEqual(SoundCloud.repostTracks(page).compactMap { $0["id"].int }, [1, 2, 3])
        XCTAssertTrue(SoundCloud.repostTracks(try json("{}")).isEmpty)
    }

    func testSoundCloudTrack() throws {
        let track = try XCTUnwrap(SoundCloud.parseTrack(json(#"""
        {"id": 2296053116, "title": "море стало моим домом.", "duration": 123000, "genre": "Hip-hop", "tag_list": "Rap Sad",
         "artwork_url": "https://i1.sndcdn.com/artworks-x-large.jpg", "permalink_url": "https://soundcloud.com/o/m",
         "policy": "ALLOW", "playback_count": 42, "user": {"id": 5, "username": "одиссея", "avatar_url": "a"}}
        """#)))
        XCTAssertEqual(track.ref, "sc:2296053116")
        XCTAssertEqual(track.coverURL, "https://i1.sndcdn.com/artworks-x-t500x500.jpg")
        XCTAssertEqual(track.artists.first?.ref, "sca:5")
        XCTAssertEqual(track.durationMs, 123_000)
        XCTAssertEqual(track.plays, 42)
        XCTAssertEqual(track.tags, "hip-hop rap sad")
        XCTAssertTrue(track.available)
        XCTAssertFalse(try XCTUnwrap(SoundCloud.parseTrack(json(#"{"id": 1, "title": "t", "policy": "BLOCK", "user": {}}"#))).available)
    }

    func testYandexSignedLink() {
        let xml = "<?xml version=\"1.0\"?><download-info><host>s1.storage.yandex.net</host><path>/rmusic/abc</path><ts>0005f</ts><region>-1</region><s>deadbeef</s></download-info>"
        // md5(SALT + "rmusic/abc" + "deadbeef") — посчитано отдельно
        XCTAssertEqual(Yandex.signedLink(xml), "https://s1.storage.yandex.net/get-mp3/95cd5ceba72fed3875fc62d06e9a219e/0005f/rmusic/abc")
        XCTAssertNil(Yandex.signedLink("<host>x</host>"))
    }

    func testYandexFileInfoSign() {
        // base64(HMAC-SHA256) без последнего символа — посчитано отдельно (python hmac)
        XCTAssertEqual(Yandex.fileInfoSign(ts: "1700000000", id: "123", quality: "lossless", codecs: "flac,flac-mp4,aac,he-aac,mp3", transports: "raw"),
                       "eNqHRjJGHXTKYjEuBH12k8P+/NJNzMddvv9Is4ieE6I")
    }

    func testPicksBestMP3UnderCap() throws {
        let infos = try json(#"[{"codec": "mp3", "bitrateInKbps": 320}, {"codec": "mp3", "bitrateInKbps": 192}, {"codec": "aac", "bitrateInKbps": 256}, {"codec": "mp3", "bitrateInKbps": 128}]"#)
        XCTAssertEqual(Yandex.pickMP3(infos, maxKbps: 320)?["bitrateInKbps"].int, 320)
        XCTAssertEqual(Yandex.pickMP3(infos, maxKbps: 256)?["bitrateInKbps"].int, 192)
        XCTAssertEqual(Yandex.pickMP3(infos, maxKbps: 64)?["bitrateInKbps"].int, 128)
    }

    func testYandexPlaylistAlbumArtist() throws {
        let playlist = try XCTUnwrap(Yandex.parsePlaylist(json(#"""
        {"uid": 42, "kind": 3, "title": "Мне нравится", "trackCount": 217, "owner": {"uid": 42, "login": "folzy", "name": "Folzy"},
         "cover": {"itemsUri": ["avatars.yandex.net/a/%%"]}}
        """#)))
        XCTAssertEqual(playlist.ref, "ympl:42:3")
        XCTAssertEqual(playlist.owner, "Folzy")
        XCTAssertEqual(playlist.coverURL, "https://avatars.yandex.net/a/400x400")
        let album = try XCTUnwrap(Yandex.parseAlbum(json(#"{"id": 9, "title": "Come Over", "year": 2016, "trackCount": 7, "artists": [{"id": 7, "name": "Lil Peep"}], "coverUri": "x/%%"}"#)))
        XCTAssertEqual(album.ref, "ymalb:9")
        XCTAssertEqual(album.artist, "Lil Peep")
        XCTAssertEqual(album.year, 2016)
        let artist = try XCTUnwrap(Yandex.parseArtist(json(#"{"id": 7, "name": "Lil Peep", "likesCount": 100}"#)))
        XCTAssertEqual(artist.ref, "yma:7")
        XCTAssertEqual(artist.followers, 100)
    }

    func testYandexTrack() throws {
        let track = try XCTUnwrap(Yandex.parseTrack(json(#"""
        {"id": "123", "title": "Benz Truck", "version": "Remix", "durationMs": 160000,
         "coverUri": "avatars.yandex.net/get-music-content/1/%%", "available": true, "contentWarning": "explicit",
         "artists": [{"id": 7, "name": "Lil Peep"}], "albums": [{"id": 99, "title": "Come Over", "genre": "Rap"}]}
        """#)))
        XCTAssertEqual(track.ref, "ym:123")
        XCTAssertEqual(track.title, "Benz Truck (Remix)")
        XCTAssertEqual(track.artist, "Lil Peep")
        XCTAssertEqual(track.coverURL, "https://avatars.yandex.net/get-music-content/1/400x400")
        XCTAssertEqual(track.url, "https://music.yandex.ru/album/99/track/123")
        XCTAssertEqual(track.album?.ref, "ymalb:99")
        XCTAssertTrue(track.explicit)
        XCTAssertEqual(track.tags, "rap")
    }

    func testQueryEncoding() throws {
        let url = try HTTP.url("https://api.example/search", query: [("q", "a+b & ё"), ("limit", "5")])
        XCTAssertEqual(url.absoluteString, "https://api.example/search?q=a%2Bb%20%26%20%D1%91&limit=5")
        XCTAssertEqual(String(decoding: HTTP.form([("track-ids", "1:2,3")]), as: UTF8.self), "track-ids=1%3A2%2C3")
    }

    func testCoreHelpers() {
        XCTAssertTrue(MusicCore.isAuthError(ServiceError.http("SoundCloud", 401)))
        XCTAssertTrue(MusicCore.isAuthError(ServiceError.http("SoundCloud", 403)))
        XCTAssertFalse(MusicCore.isAuthError(ServiceError.http("SoundCloud", 404)))
        XCTAssertEqual(MusicCore.qualityKbps("low"), 192)
        XCTAssertEqual(MusicCore.qualityKbps("medium"), 256)
        XCTAssertEqual(MusicCore.qualityKbps("high"), 320)
        XCTAssertEqual(MusicCore.qualityKbps(nil), 1411)
        XCTAssertEqual(MusicCore.qualityKbps("lossless"), 1411)
    }
}

/// Очередь — те же случаи, что `windows/src/player/queue.test.ts`.
final class QueueTests: XCTestCase {
    func testMakeOrder() {
        XCTAssertEqual(QueueMath.makeOrder(length: 4, current: 2, shuffle: false), [0, 1, 2, 3])
        let order = QueueMath.makeOrder(length: 6, current: 3, shuffle: true, random: { 0.42 })
        XCTAssertEqual(order.first, 3)
        XCTAssertEqual(order.sorted(), [0, 1, 2, 3, 4, 5])
    }

    func testNextPos() {
        XCTAssertEqual(QueueMath.nextPos(0, length: 3, repeat: .off, manual: false), 1)
        XCTAssertNil(QueueMath.nextPos(2, length: 3, repeat: .off, manual: false))
        XCTAssertEqual(QueueMath.nextPos(2, length: 3, repeat: .all, manual: false), 0)
        XCTAssertEqual(QueueMath.nextPos(1, length: 3, repeat: .one, manual: false), 1)
        XCTAssertEqual(QueueMath.nextPos(1, length: 3, repeat: .one, manual: true), 2)
        XCTAssertNil(QueueMath.nextPos(0, length: 0, repeat: .all, manual: true))
    }

    func testPrevPos() {
        XCTAssertEqual(QueueMath.prevPos(2, length: 3, repeat: .off), 1)
        XCTAssertEqual(QueueMath.prevPos(0, length: 3, repeat: .off), 0)
        XCTAssertEqual(QueueMath.prevPos(0, length: 3, repeat: .all), 2)
    }

    func testCountsAsPlayAndEnqueue() {
        XCTAssertTrue(QueueMath.countsAsPlay(listenedMs: 30_000, durationMs: 200_000))
        XCTAssertFalse(QueueMath.countsAsPlay(listenedMs: 29_000, durationMs: 200_000))
        XCTAssertTrue(QueueMath.countsAsPlay(listenedMs: 20_000, durationMs: 40_000))
        XCTAssertEqual(QueueMath.enqueue(order: [0, 1, 2], pos: 0, newIndex: 3, next: true), [0, 3, 1, 2])
        XCTAssertEqual(QueueMath.enqueue(order: [0, 1, 2], pos: 0, newIndex: 3, next: false), [0, 1, 2, 3])
        XCTAssertEqual(QueueMath.enqueue(order: [], pos: 0, newIndex: 0, next: true), [0])
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.one.next, .off)
    }
}

/// «Авто похожие» — те же случаи, что `windows/src/player/autoplay.test.ts`.
final class AutoplayTests: XCTestCase {
    private func track(_ ref: String, available: Bool = true) -> Track {
        Track(ref: ref, title: ref, artist: "a", artists: [], album: nil, durationMs: 1, coverURL: nil, url: nil,
              explicit: false, available: available)
    }

    func testFreshSimilarAlternatesSeeds() {
        let a = [track("s1"), track("q1"), track("s3"), track("s4", available: false)]
        let b = [track("s1"), track("d1"), track("s5"), track("s6")]
        let out = Autoplay.freshSimilar([a, b], inQueue: ["q1"], disliked: { $0 == "d1" }, limit: 3)
        XCTAssertEqual(out.map(\.ref), ["s1", "s3", "s5"])
    }

    func testSeeds() {
        let queue = [track("a"), track("b"), track("x"), track("y")]
        XCTAssertEqual(Autoplay.seeds(queue, auto: ["x", "y"], random: { 0.99 }).map(\.ref), ["y", "b"])
        XCTAssertEqual(Autoplay.seeds([track("a")], auto: []).map(\.ref), ["a"])
        XCTAssertTrue(Autoplay.seeds([], auto: []).isEmpty)
    }

    func testAutoStartSplitsOwnQueueFromSimilar() {
        let upcoming = ["a", "b", "x", "y"].map { track($0) }
        XCTAssertEqual(Autoplay.autoStart(upcoming, auto: ["x", "y"]), 2)
        // похожих нет — вся очередь своя
        XCTAssertEqual(Autoplay.autoStart(upcoming, auto: []), 4)
        // очередь целиком из похожих — своей части нет
        XCTAssertEqual(Autoplay.autoStart(upcoming, auto: ["a", "b", "x", "y"]), 0)
        XCTAssertEqual(Autoplay.autoStart([], auto: ["x"]), 0)
    }

    func testPlayedBoundaryMarksWhereSimilarStarted() {
        let played = ["a", "b", "x", "y"].map { track($0) }
        XCTAssertEqual(Autoplay.playedBoundary(played, auto: ["x", "y"]), 2)
        // пока играет своя очередь — черты нет
        XCTAssertNil(Autoplay.playedBoundary(played, auto: []))
        // сыгранное целиком из похожих — отделять не от чего
        XCTAssertNil(Autoplay.playedBoundary(played, auto: ["a", "b", "x", "y"]))
        // первый похожий — текущий (последний в списке)
        XCTAssertEqual(Autoplay.playedBoundary(played, auto: ["y"]), 3)
    }
}

/// Вход в Яндекс по коду — разбор ответов OAuth.
final class YandexLoginTests: XCTestCase {
    func testDeviceCodeAndPoll() throws {
        let code = try XCTUnwrap(YandexLogin.parseDeviceCode(JSONValue(data: Data(#"{"device_code": "d1", "user_code": "ABC123", "verification_url": "https://ya.ru/device", "expires_in": 300, "interval": 1}"#.utf8))))
        XCTAssertEqual(code.userCode, "ABC123")
        XCTAssertEqual(code.interval, 2, "не чаще раза в 2 с")
        XCTAssertNil(YandexLogin.parseDeviceCode(try JSONValue(data: Data(#"{"error": "invalid_client"}"#.utf8))))
        XCTAssertEqual(YandexLogin.parsePoll(try JSONValue(data: Data(#"{"error": "authorization_pending"}"#.utf8))), .pending)
        XCTAssertEqual(YandexLogin.parsePoll(try JSONValue(data: Data(#"{"error": "slow_down"}"#.utf8))), .slowDown)
        XCTAssertEqual(YandexLogin.parsePoll(try JSONValue(data: Data(#"{"access_token": "y0_x", "token_type": "bearer"}"#.utf8))), .token("y0_x"))
        guard case .failed = YandexLogin.parsePoll(try JSONValue(data: Data(#"{"error": "expired_token"}"#.utf8))) else {
            return XCTFail("устаревший код — ошибка")
        }
    }
}
