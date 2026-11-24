import XCTest
@testable import Sonar

/// Внутренний GraphQL веб-плеера Spotify — те же случаи, что Rust-тесты `providers/spotify_gql.rs`, на тех же
/// образцах ответов (`Fixtures/sp_*.json`: публичные сняты вживую 2026-11-24, ответы аккаунта — по коду веб-плеера).
final class SpotifyGQLTests: XCTestCase {
    private func fixture(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sp_\(name)", withExtension: "json"), "нет фикстуры \(name)")
        return try JSONValue(data: Data(contentsOf: url))["data"]
    }

    func testIdsFromURIs() {
        XCTAssertEqual(SpotifyGQL.id("spotify:track:5Z01UMMf7V1o0MzF86s6WJ", "track"), "5Z01UMMf7V1o0MzF86s6WJ")
        XCTAssertNil(SpotifyGQL.id("spotify:album:x", "track"))
        XCTAssertNil(SpotifyGQL.id("spotify:track:", "track"))
        XCTAssertNil(SpotifyGQL.id("spotify:trackx:1", "track"))
    }

    func testBiggestImageEvenWithoutSizes() throws {
        let sized = try JSONValue(data: Data(#"[{"url": "a", "width": 300}, {"url": "b", "width": 64}, {"url": "c", "width": 640}]"#.utf8))
        XCTAssertEqual(SpotifyGQL.bestSource(sized), "c")
        let bare = try JSONValue(data: Data(#"[{"url": "300"}, {"url": "64"}, {"url": "640"}]"#.utf8))
        XCTAssertEqual(SpotifyGQL.bestSource(bare), "640")
        XCTAssertNil(SpotifyGQL.bestSource(.array([])))
    }

    func testSearchTracksLiveShape() throws {
        let tracks = SpotifyGQL.searchTracks(try fixture("search_tracks"))
        XCTAssertEqual(tracks.count, 2)
        let t = tracks[0]
        XCTAssertTrue(t.ref.hasPrefix("sp:") && t.ref.count > 10)
        XCTAssertFalse(t.title.isEmpty || t.artist.isEmpty)
        XCTAssertGreaterThan(t.durationMs, 60_000)
        XCTAssertEqual(t.album?.ref.hasPrefix("spalb:"), true)
        XCTAssertEqual(t.coverURL?.contains("b273"), true, "640-я обложка")
        XCTAssertEqual(t.url?.hasPrefix("https://open.spotify.com/track/"), true)
        XCTAssertEqual(ServiceRegistry.service(of: t.ref), .sp)
    }

    func testSearchDesktopAllSections() throws {
        let data = try fixture("search_desktop")
        XCTAssertFalse(SpotifyGQL.searchTracks(data).isEmpty)
        let more = SpotifyGQL.searchMore(data)
        XCTAssertEqual(more.artists.first?.name, "Eminem")
        XCTAssertNotNil(more.artists.first?.avatarURL)
        let album = try XCTUnwrap(more.albums.first)
        XCTAssertTrue(album.ref.hasPrefix("spalb:") && album.year != nil && !album.artist.isEmpty)
        let list = try XCTUnwrap(more.playlists.first)
        XCTAssertTrue(list.ref.hasPrefix("sppl:") && !list.owner.isEmpty && list.coverURL != nil)
    }

    func testArtistOverviewAndTopTracks() throws {
        let overview = try XCTUnwrap(SpotifyGQL.artistOverview(try fixture("artist_overview")))
        XCTAssertEqual(overview.artist.ref, "spa:7dGJo4pcD2V6oG8kP0tJRR")
        XCTAssertGreaterThan(overview.artist.followers ?? 0, 1_000_000)
        XCTAssertEqual(overview.top.count, 2)
        XCTAssertEqual(overview.top[0].coverURL?.contains("b273"), true, "без размеров — последняя, 640")
        XCTAssertTrue(overview.top[0].explicit)
    }

    func testDiscographyReleasesTakeArtist() throws {
        let by = ArtistRef(ref: "spa:7dGJo4pcD2V6oG8kP0tJRR", name: "Eminem")
        let page = SpotifyGQL.discography(try fixture("discography_all"), by: by)
        XCTAssertFalse(page.rows.isEmpty)
        XCTAssertGreaterThan(page.seen, 0)
        XCTAssertNotNil(page.total)
        XCTAssertTrue(page.rows.allSatisfy { $0.artist == "Eminem" && $0.ref.hasPrefix("spalb:") && $0.year != nil })
        XCTAssertEqual(page.rows[0].released, "2026-11-13")
    }

    func testAlbumTracksTakeOuterAlbum() throws {
        let found = try XCTUnwrap(SpotifyGQL.albumPage(try fixture("album")))
        XCTAssertEqual(found.album.title, "The Marshall Mathers LP")
        XCTAssertEqual(found.album.released, "2000-05-23")
        XCTAssertEqual(found.album.trackCount, 18)
        XCTAssertEqual(found.page.seen, 3)
        XCTAssertEqual(found.page.total, 18)
        XCTAssertEqual(found.page.rows[0].album?.title, "The Marshall Mathers LP")
        XCTAssertEqual(found.page.rows[0].coverURL, found.album.coverURL)
    }

    func testPlaylistHeadAndRows() throws {
        let (head, page) = SpotifyGQL.playlistPage(try fixture("playlist"))
        XCTAssertEqual(head?.ref, "sppl:3xqcAMgjHGrv3ElA51zZRj")
        XCTAssertEqual(head?.trackCount, 53)
        XCTAssertEqual(page.rows.count, 2)
        XCTAssertEqual(page.total, 53)
        XCTAssertGreaterThanOrEqual(page.rows[0].artists.count, 2)
    }

    func testLibrarySkipsMissingAndNonPlaylists() throws {
        let likes = SpotifyGQL.libraryTracks(try fixture("library_tracks"))
        XCTAssertEqual([likes.rows.count, likes.seen], [1, 2], "«не найдено» — мимо, но в счёт страницы")
        XCTAssertEqual(likes.total, 2)
        let lists = SpotifyGQL.libraryPlaylists(try fixture("library_v3"))
        XCTAssertEqual([lists.rows.count, lists.seen], [1, 3])
    }

    func testAccountFromProfileAndProduct() throws {
        let account = SpotifyGQL.account(profile: try fixture("profile"), account: try fixture("account"))
        XCTAssertEqual(account.name, "Folzy")
        XCTAssertEqual(account.uid, "31folzy")
        XCTAssertEqual(account.avatarURL, "https://i.scdn.co/image/avatar300")
        XCTAssertEqual(account.premium, true)
        XCTAssertNil(SpotifyGQL.account(profile: try fixture("profile"), account: nil).premium)
    }

    func testScanFindsOpsAndChunks() {
        let js = #"x=new aX.l("fetchLibraryTracks","query","087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240",null),y=new aX.l("addToLibrary","mutation","1111111111111111111111111111111111111111111111111111111111111111",null);u.u=e=>""+(({1872:"xpui-routes-playlist",4241:"xpui-routes-search"})[e]||e)+"."+({1872:"aaaa1111",4241:"b12d67ce",99:"33ddb874"})[e]+".js",u.miniCssF"#
        let found = SpotifyGQL.scan(js)
        XCTAssertEqual(found["fetchLibraryTracks"], SpotifyGQL.Op.libraryTracks.builtin)
        XCTAssertEqual(found.count, 2)
        let main = "https://open.spotifycdn.com/cdn/build/web-player/web-player.e2037ec6.js"
        XCTAssertEqual(SpotifyGQL.chunkURL(mainURL: main, mainJS: js, name: "xpui-routes-search"),
                       "https://open.spotifycdn.com/cdn/build/web-player/xpui-routes-search.b12d67ce.js")
        XCTAssertNil(SpotifyGQL.chunkURL(mainURL: main, mainJS: js, name: "xpui-routes-nope"))
        let html = #"<script src="https://open.spotifycdn.com/cdn/build/web-player/vendor~web-player.eadaf34e.js"></script><script src="https://open.spotifycdn.com/cdn/build/web-player/web-player.e2037ec6.js"></script><link href="https://open.spotifycdn.com/cdn/build/web-player/web-player.e2037ec6.js">"#
        XCTAssertEqual(SpotifyGQL.scriptURLs(html).count, 2)
    }

    func testHashesAdoptOnlyKnownChanges() async {
        let hashes = SpotifyHashes()
        let builtin = await hashes.hash(.album)
        XCTAssertEqual(builtin, SpotifyGQL.Op.album.builtin)
        let same = await hashes.adopt(["getAlbum": SpotifyGQL.Op.album.builtin])
        XCTAssertFalse(same)
        let fresh = await hashes.adopt(["getAlbum": String(repeating: "f", count: 64), "unknownOp": String(repeating: "e", count: 64)])
        XCTAssertTrue(fresh)
        let now = await hashes.hash(.album)
        XCTAssertEqual(now, String(repeating: "f", count: 64))
    }

    func testRequestBodyShape() throws {
        let body = try JSONValue(data: SpotifyGQL.body(.searchTracks, hash: "abc", variables: ["searchTerm": "x"]))
        XCTAssertEqual(body["operationName"].string, "searchTracks")
        XCTAssertEqual(body["extensions"]["persistedQuery"]["sha256Hash"].string, "abc")
        XCTAssertEqual(body["extensions"]["persistedQuery"]["version"].int, 1)
        XCTAssertEqual(body["variables"]["searchTerm"].string, "x")
    }

    func testDataOrClearError() throws {
        XCTAssertTrue(try SpotifyGQL.data(JSONValue(data: Data(#"{"data": {"me": null}}"#.utf8))).isObject)
        let unauthorized = try JSONValue(data: Data(#"{"data": null, "errors": [{"message": "Exception while fetching data (/me) : User is not authorized"}]}"#.utf8))
        XCTAssertThrowsError(try SpotifyGQL.data(unauthorized)) { XCTAssertEqual(($0 as? ServiceError)?.message, Spotify.spDcBad) }
        XCTAssertThrowsError(try SpotifyGQL.data(.string("Invalid query hash")))
    }
}
