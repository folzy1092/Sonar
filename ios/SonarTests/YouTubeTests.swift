import XCTest
@testable import Sonar

/// YouTube Music без сети — те же случаи, что в Rust-тестах (`providers/youtube/parse.rs`, `auth.rs`),
/// на тех же сохранённых ответах (`Fixtures/yt_*.json`, адреса потоков в них тестовые).
final class YouTubeTests: XCTestCase {
    private func fixture(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "yt_\(name)", withExtension: "json"), "нет фикстуры \(name)")
        return try JSONValue(data: Data(contentsOf: url))
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONValue(data: Data(text.utf8))
    }

    func testSearchSongsParseTrackFields() throws {
        let tracks = YTParse.searchTracks(try fixture("search_songs"))
        XCTAssertEqual(tracks.count, 4)
        let t = tracks[0]
        XCTAssertEqual(t.ref, "yt:q7mwXbOw58g")
        XCTAssertEqual(t.title, "Star Shopping")
        XCTAssertEqual(t.artist, "Cut-Off")
        XCTAssertEqual(t.artists.first?.ref, "yta:UCIzdQrjdn8XVyWI4p7N55SA")
        XCTAssertEqual(t.album?.ref, "ytalb:MPREb_2EPG9Eh31Fr")
        XCTAssertEqual(t.durationMs, 146_000)
        XCTAssertEqual(t.plays, 1200)
        XCTAssertEqual(t.url, "https://music.youtube.com/watch?v=q7mwXbOw58g")
        XCTAssertTrue(t.coverURL?.contains("=w544-h544") == true)
        XCTAssertEqual(t.service, .youtube)
        let peep = tracks[1]
        XCTAssertEqual(peep.artist, "Lil Peep")
        XCTAssertEqual(peep.durationMs, 245_000)
        XCTAssertEqual(peep.plays, 251_000_000)
        XCTAssertEqual(peep.album?.title, "Come Over When You're Sober, Pt. 2")
    }

    func testSearchArtistsAlbumsPlaylists() throws {
        let artists = YTParse.searchArtists(try fixture("search_artists"))
        XCTAssertEqual(artists.count, 3)
        XCTAssertEqual(artists[0].ref, "yta:UCxcyWcW0kZFGRyetDHr3UuA")
        XCTAssertEqual(artists[0].name, "LiL PEEP")
        let albums = YTParse.searchAlbums(try fixture("search_albums"))
        XCTAssertEqual(albums[0].ref, "ytalb:MPREb_onqktzsmdxw")
        XCTAssertEqual(albums[0].artist, "Lil Peep")
        XCTAssertEqual(albums[0].year, 2015)
        XCTAssertEqual(albums[1].artist, "Lil Peep и ILOVEMAKONNEN")
        XCTAssertTrue(albums[0].coverURL?.contains("544") == true)
        let lists = YTParse.searchPlaylists(try fixture("search_playlists"))
        XCTAssertEqual(lists[0].ref, "ytpl:PLFQ6IvlXwKtgvr-BripRdnRS2cediaKA6")
        XCTAssertEqual(lists[0].owner, "metlast")
        XCTAssertTrue(lists[0].coverURL?.hasPrefix("https://i.ytimg.com/") == true)
    }

    func testArtistPageHeaderTopAlbums() throws {
        let page = try YTParse.artistPage(try fixture("artist"), channelID: "UCxcyWcW0kZFGRyetDHr3UuA")
        XCTAssertEqual(page.artist.name, "LiL PEEP")
        XCTAssertEqual(page.artist.ref, "yta:UCxcyWcW0kZFGRyetDHr3UuA")
        XCTAssertTrue(page.artist.avatarURL?.contains("=w544-h544") == true)
        XCTAssertEqual(page.top.count, 3)
        XCTAssertEqual(page.top[0].ref, "yt:DmhdcDQt7Dk")
        XCTAssertEqual(page.top[0].artist, "Lil Peep и XXXTENTACION")
        XCTAssertEqual(page.top[0].album?.ref, "ytalb:MPREb_K4OwytHjekv")
        XCTAssertEqual(page.allTracks, "OLAK5uy_m2QvXUMCoZqqmp1JMnlY_dncmcaLj2ehM")
        let diamonds = try XCTUnwrap(page.albums.first { $0.ref == "ytalb:MPREb_nEhq7bxafxu" })
        XCTAssertEqual(diamonds.title, "DIAMONDS")
        XCTAssertEqual(diamonds.year, 2023)
        XCTAssertEqual(diamonds.artist, "LiL PEEP")
        XCTAssertThrowsError(try YTParse.artistPage(try json("{}"), channelID: "UC1"))
    }

    func testAlbumPageFillsTracksFromHeader() throws {
        let (album, tracks) = try YTParse.albumPage(try fixture("album"), browseID: "MPREb_onqktzsmdxw")
        XCTAssertEqual(album.title, "The Way I See Things")
        XCTAssertEqual(album.artist, "Lil Peep")
        XCTAssertEqual(album.year, 2015)
        XCTAssertEqual(album.trackCount, 1)
        XCTAssertEqual(album.artists.first?.ref, "yta:UCxcyWcW0kZFGRyetDHr3UuA")
        let t = try XCTUnwrap(tracks.first)
        XCTAssertEqual(t.ref, "yt:C4gVlt46voo")
        XCTAssertEqual(t.durationMs, 131_000)
        XCTAssertEqual(t.artist, "Lil Peep")
        XCTAssertEqual(t.album?.ref, "ytalb:MPREb_onqktzsmdxw")
        XCTAssertEqual(t.coverURL, album.coverURL)
    }

    func testPlaylistPageAndContinuation() throws {
        let page = try YTParse.playlistPage(try fixture("playlist"), listID: "PLwNv9Hhd8gZjNoQdpd2kBa3fwXNeJjzDX")
        XCTAssertEqual(page.playlist.title, "500 Greatest Love Songs Of All Time")
        XCTAssertEqual(page.playlist.owner, "Inko Infinity2")
        XCTAssertEqual(page.playlist.trackCount, 500)
        XCTAssertTrue(page.playlist.coverURL?.hasSuffix("=s544") == true)
        XCTAssertEqual(page.tracks.count, 3)
        XCTAssertEqual(page.tracks[0].title, "I Will Always Love You")
        XCTAssertEqual(page.tracks[0].artist, "Whitney Houston")
        XCTAssertEqual(page.tracks[0].durationMs, 274_000)
        XCTAssertNotNil(page.next)
        let more = YTParse.continuationPage(try fixture("playlist_cont"))
        XCTAssertEqual(more.tracks.count, 3)
        XCTAssertEqual(more.tracks[0].ref, "yt:qxZInIyOBXk")
        XCTAssertNotNil(more.next)
        XCTAssertThrowsError(try YTParse.playlistPage(try json("{}"), listID: "PL1"))
    }

    func testNextSkipsSeed() throws {
        let tracks = YTParse.nextTracks(try fixture("next"), seed: "q7mwXbOw58g")
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertTrue(tracks.allSatisfy { $0.ref != "yt:q7mwXbOw58g" })
        XCTAssertEqual(tracks[0].ref, "yt:8aaoYbPXOPs")
        XCTAssertEqual(tracks[0].title, "Fuck Love")
        XCTAssertEqual(tracks[0].durationMs, 147_000)
        XCTAssertEqual(tracks[0].artist, "XXXTENTACION и Trippie Redd")
        XCTAssertEqual(tracks[0].album?.ref, "ytalb:MPREb_Tr9YVfRfip1")
    }

    func testPlayerPicksAACOnly() throws {
        let formats = try YTParse.playerFormats(try fixture("player_ios"))
        XCTAssertEqual(formats.map(\.itag), [139, 140, 249, 250, 251])
        XCTAssertTrue(formats.allSatisfy { $0.mime.hasPrefix("audio/") })
        // AVPlayer не играет Opus: и «Высокое», и «Обычное» без 141 — AAC 128
        XCTAssertEqual(YTParse.pickFormat(formats, high: true)?.itag, 140)
        XCTAssertEqual(YTParse.pickFormat(formats, high: false)?.itag, 140)
        XCTAssertEqual(YTParse.qualityLabel(try XCTUnwrap(YTParse.pickFormat(formats, high: true))), "AAC 128")
        let premium = formats + [YTParse.Format(itag: 141, url: "u", mime: "audio/mp4; codecs=\"mp4a.40.2\"", bitrate: 256_000)]
        XCTAssertEqual(YTParse.pickFormat(premium, high: true)?.itag, 141)
        XCTAssertEqual(YTParse.pickFormat(premium, high: false)?.itag, 140)
        XCTAssertEqual(YTParse.qualityLabel(premium.last!), "AAC 256")
        let opusOnly = [YTParse.Format(itag: 251, url: "u", mime: "audio/webm; codecs=\"opus\"", bitrate: 160_000)]
        XCTAssertNil(YTParse.pickFormat(opusOnly, high: true))
        let otherAAC = [YTParse.Format(itag: 139, url: "u", mime: "audio/mp4", bitrate: 48_000)]
        XCTAssertEqual(YTParse.pickFormat(otherAAC, high: false).map(YTParse.qualityLabel), "AAC 48")
    }

    func testPlayerErrorHasReason() throws {
        let blocked = try json(#"{"playabilityStatus": {"status": "LOGIN_REQUIRED", "reason": "Sign in to confirm you're not a bot"}}"#)
        XCTAssertThrowsError(try YTParse.playerFormats(blocked)) { error in
            XCTAssertEqual(error.localizedDescription, "YouTube Music: трек не играется (Sign in to confirm you're not a bot)")
        }
        let empty = try json(#"{"playabilityStatus": {"status": "OK"}, "streamingData": {"adaptiveFormats": []}}"#)
        XCTAssertThrowsError(try YTParse.playerFormats(empty))
    }

    func testAccountAndPremium() throws {
        let value = try json(#"""
        {"responseContext": {"serviceTrackingParams": [{"service": "GFEEDBACK", "params": [{"key": "has_unlimited_entitlement", "value": "True"}]}]},
         "actions": [{"openPopupAction": {"popup": {"multiPageMenuRenderer": {"header": {"activeAccountHeaderRenderer": {
           "accountName": {"runs": [{"text": "Folzy"}]},
           "accountPhoto": {"thumbnails": [{"url": "https://yt3.ggpht.com/a=s48", "width": 48}, {"url": "https://yt3.ggpht.com/a=s88", "width": 88}]}
         }}}}}}]}
        """#)
        let account = try YTParse.account(value)
        XCTAssertEqual(account.name, "Folzy")
        XCTAssertEqual(account.premium, true)
        XCTAssertEqual(account.avatarURL, "https://yt3.ggpht.com/a=s544")
        XCTAssertThrowsError(try YTParse.account(try json("{}")))
        XCTAssertNil(YTParse.premium(try json("{}")))
    }

    func testLibrarySkipsLikesAndDupes() throws {
        func item(_ id: String, _ title: String) -> String {
            #"{"musicTwoRowItemRenderer": {"title": {"runs": [{"text": "\#(title)"}]}, "subtitle": {"runs": [{"text": "Плейлист"}, {"text": " • "}, {"text": "Folzy", "navigationEndpoint": {"browseEndpoint": {"browseId": "UC1", "browseEndpointContextSupportedConfigs": {"browseEndpointContextMusicConfig": {"pageType": "MUSIC_PAGE_TYPE_USER_CHANNEL"}}}}}, {"text": " • "}, {"text": "12 треков"}]}, "navigationEndpoint": {"browseEndpoint": {"browseId": "\#(id)"}}}}"#
        }
        let items = [item("VLLM", "Понравившиеся"), item("VLPL1", "Мой"), item("VLPL1", "Мой"), item("FEmusic_x", "не плейлист")]
        let got = YTParse.libraryPlaylists(try json(#"{"items": [\#(items.joined(separator: ","))]}"#))
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first?.ref, "ytpl:PL1")
        XCTAssertEqual(got.first?.owner, "Folzy")
        XCTAssertEqual(got.first?.trackCount, 12)
    }

    func testHelpers() {
        XCTAssertEqual(YTParse.parseDuration("1:02:03"), 3_723_000)
        XCTAssertNil(YTParse.parseDuration("abc"))
        XCTAssertEqual(YTParse.parseCount("61,5\u{a0}млн слушателей"), 61_500_000)
        XCTAssertEqual(YTParse.parseCount("422 тыс. просмотров"), 422_000)
        XCTAssertEqual(YTParse.parseCount("1,234 plays"), 1234)
        XCTAssertEqual(YTParse.parseCount("1.2K plays"), 1200)
        XCTAssertNil(YTParse.parseCount("нет"))
        XCTAssertEqual(YTParse.lastYear("Сингл • 2015"), 2015)
        XCTAssertNil(YTParse.lastYear("12 треков"))
        XCTAssertEqual(YTParse.upscale("https://lh3.googleusercontent.com/x=w60-h60-l90-rj"), "https://lh3.googleusercontent.com/x=w544-h544-l90-rj")
        XCTAssertEqual(YTParse.upscale("https://i.ytimg.com/vi/x/hq.jpg?a=w60-h60"), "https://i.ytimg.com/vi/x/hq.jpg?a=w60-h60")
        XCTAssertEqual(YTParse.stripVL("VLPL1"), "PL1")
        XCTAssertEqual(YTParse.stripVL("OLAK5"), "OLAK5")
    }

    // MARK: вход по cookie

    func testCookieValueAndSapisid() {
        let cookie = "HSID=a; SAPISID=abcSAPISID; __Secure-3PAPISID=other"
        XCTAssertEqual(YouTubeAuth.cookieValue(cookie, "HSID"), "a")
        XCTAssertNil(YouTubeAuth.cookieValue(cookie, "SID"))
        XCTAssertEqual(YouTubeAuth.sapisid(cookie), "abcSAPISID")
        XCTAssertEqual(YouTubeAuth.sapisid("__Secure-3PAPISID=x; SID=1"), "x")
        XCTAssertNil(YouTubeAuth.sapisid("SAPISID=; SID=1"))
    }

    func testSapisidHashMatchesRust() {
        XCTAssertEqual(YouTubeAuth.sapisidHash("abcSAPISID", timestamp: 1_700_000_000), "SAPISIDHASH 1700000000_958be2d45afc2262a8777d73de623e5ba13eed75")
    }

    func testNormalizeCookieAcceptsHeaderAndHidesSecret() throws {
        XCTAssertEqual(try YouTubeAuth.normalize("Cookie: SID=1;  SAPISID=x ;\n\nHSID=2;;"), "SID=1; SAPISID=x; HSID=2")
        XCTAssertEqual(try YouTubeAuth.normalize("  cookie: =bad; SAPISID=y "), "SAPISID=y")
        XCTAssertThrowsError(try YouTubeAuth.normalize("   ")) { error in
            XCTAssertEqual(error.localizedDescription, "Вставь cookie YouTube Music")
        }
        XCTAssertThrowsError(try YouTubeAuth.normalize("SID=secret-value")) { error in
            XCTAssertFalse(error.localizedDescription.contains("secret-value"))
        }
        XCTAssertFalse(String(describing: YouTubeCreds(cookie: "SAPISID=secret-value")).contains("secret-value"))
    }

    /// Те же случаи, что `yt_cookie_header` в `login.rs`.
    func testCookieHeaderFromLoginWindow() {
        XCTAssertEqual(YouTubeAuth.cookieHeader([("SID", "1"), ("SAPISID", "a"), ("", "x"), ("HSID", "")]), "SID=1; SAPISID=a")
        XCTAssertEqual(YouTubeAuth.cookieHeader([("__Secure-3PAPISID", "b")]), "__Secure-3PAPISID=b")
        XCTAssertNil(YouTubeAuth.cookieHeader([("SID", "1"), ("VISITOR_INFO1_LIVE", "v")]))
        XCTAssertNil(YouTubeAuth.cookieHeader([]))
        XCTAssertEqual(YouTubeAuth.loginURL.host, "accounts.google.com")
        XCTAssertTrue(YouTubeAuth.loginURL.absoluteString.contains("music.youtube.com"))
    }

    func testPlayerBodyShape() {
        let body = YouTube.playerBody(videoID: "abc", visitor: "vd")
        XCTAssertEqual(body["videoId"].string, "abc")
        XCTAssertEqual(body["context"]["client"]["clientName"].string, "VISIONOS")
        XCTAssertEqual(body["context"]["client"]["visitorData"].string, "vd")
        XCTAssertEqual(body["contentCheckOk"].bool, true)
    }

    func testDownloadQualityAndQuickPlaylist() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a"))
        XCTAssertEqual(DownloadSource.from(.file(url: url, quality: "AAC 256"))?.fileExtension, "m4a")
        XCTAssertEqual(DownloadSource.from(.file(url: url, quality: "FLAC · Яндекс"))?.fileExtension, "flac")
        XCTAssertEqual(DownloadSource.from(.file(url: url, quality: "MP3 320"))?.fileExtension, "mp3")
        XCTAssertNil(DownloadSource.from(.hls(url: url, quality: "AAC 160")))
        XCTAssertTrue(MusicCore.youTubeHigh(nil))
        XCTAssertTrue(MusicCore.youTubeHigh("high"))
        XCTAssertFalse(MusicCore.youTubeHigh("normal"))
        XCTAssertEqual(MusicCore.youTubeLikesRef, "ytpl:likes")
        XCTAssertEqual(QuickPlaylist(setting: "ytpl:likes"), .service("ytpl:likes"))
        XCTAssertEqual(QuickPlaylist(setting: "ytpl:PL123"), .service("ytpl:PL123"))
        XCTAssertEqual(QuickPlaylist(setting: "ytpl:"), .liked)
    }

    /// `audio.yt_quality` — тот же ключ и значения, что на ПК; незнакомое (например, Opus с ПК) — «Высокое».
    func testQualitySettingMatchesWindows() {
        XCTAssertEqual(YouTubeQuality.key, "audio.yt_quality")
        XCTAssertEqual(YouTubeQuality.allCases.map(\.rawValue), ["normal", "high"])
        XCTAssertEqual(YouTubeQuality.from("normal"), .normal)
        XCTAssertEqual(YouTubeQuality.from("opus"), .high)
        XCTAssertEqual(SettingsDefaults.player[YouTubeQuality.key], .string("high"))
        for choice in YouTubeQuality.allCases {
            XCTAssertEqual(MusicCore.youTubeHigh(choice.rawValue), choice == .high)
        }
    }

    /// Строки YouTube Music: en и uk — одни ключи, контекст `YouTube::` по-русски не виден.
    func testStringsTranslated() {
        XCTAssertEqual(Set(I18n.youtubeEN.keys), Set(I18n.youtubeUK.keys))
        XCTAssertEqual(I18n.translate("YouTube::Обычное", lang: .ru), "Обычное")
        XCTAssertEqual(I18n.translate("YouTube::Обычное", lang: .en), "Normal")
        XCTAssertEqual(I18n.translate("Войти в YouTube Music", lang: .uk), "Увійти в YouTube Music")
        for choice in YouTubeQuality.allCases {
            XCTAssertNotNil(I18n.dictionaries[.en]?[choice.title], choice.title)
            XCTAssertNotNil(I18n.dictionaries[.uk]?[choice.subtitle], choice.subtitle)
        }
    }
}
