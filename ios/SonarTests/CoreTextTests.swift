import XCTest
@testable import Sonar

/// Названия, ссылки и сопоставление SoundCloud → Яндекс — те же случаи, что в Rust-тестах
/// (`lyrics/mod.rs`, `providers/links.rs`, `providers/matching.rs`).
final class CoreTextTests: XCTestCase {
    func testTitlesAndArtists() {
        XCTAssertEqual(TrackText.cleanTitle("gates (prod. nepuhz)"), "gates")
        XCTAssertEqual(TrackText.cleanTitle("Song feat. X"), "Song")
        XCTAssertEqual(TrackText.artistVariants("Big Baby Tape, Kizaru"), ["Big Baby Tape, Kizaru", "Big Baby Tape"])
        XCTAssertEqual(TrackText.artistVariants("Solo"), ["Solo"])
        let keyword = TrackText.keywordTitle("+ elox1m PAGER =( #2016")
        XCTAssertEqual(keyword.keywords, "elox1m PAGER")
        XCTAssertEqual(keyword.core, "PAGER")
        XCTAssertEqual(keyword.feats, ["elox1m"])
        XCTAssertEqual(TrackText.reuploadVariant("Кизару - Дежавю")?.artist, "Кизару")
        XCTAssertEqual(TrackText.reuploadVariant("Кизару - Дежавю")?.title, "Дежавю")
        XCTAssertNil(TrackText.reuploadVariant("no dash"))
        XCTAssertEqual(TrackText.firstArtist("A feat. B"), "A")
        XCTAssertEqual(TrackText.keywordTitle("Song (feat. Guest) 🔥").feats, ["Guest"])
        XCTAssertEqual(TrackText.keywordTitle("Song (feat. Guest) 🔥").core, "Song")
    }

    func testSimilarity() {
        XCTAssertEqual(TrackText.similarity("abc", "abc"), 1, accuracy: 1e-9)
        XCTAssertLessThan(TrackText.similarity("gates", "gatesaltered"), 0.8)
        XCTAssertGreaterThan(TrackText.similarity(TrackText.norm("Дежавю!"), TrackText.norm("дежавю")), 0.99)
        XCTAssertEqual(TrackText.norm("Ёлка, 2!"), "елка2")
    }

    func testYandexLinks() {
        XCTAssertEqual(ServiceLink.parse("https://music.yandex.ru/album/123/track/456?utm_source=x"), .ref("ym:456"))
        XCTAssertEqual(ServiceLink.parse("https://music.yandex.com/track/789"), .ref("ym:789"))
        XCTAssertEqual(ServiceLink.parse("music.yandex.ru/album/123"), .ref("ymalb:123"))
        XCTAssertEqual(ServiceLink.parse("https://music.yandex.by/artist/42/tracks"), .ref("yma:42"))
        XCTAssertEqual(ServiceLink.parse("https://music.yandex.ru/users/folzy/playlists/1003"), .ref("ympl:folzy:1003"))
        XCTAssertNil(ServiceLink.parse("https://music.yandex.ru/home"))
        XCTAssertNil(ServiceLink.parse("https://music.yandex.ru/album/abc"))
    }

    func testSoundCloudLinks() {
        XCTAssertEqual(ServiceLink.parse("https://soundcloud.com/lil-peep/star-shopping?si=abc&utm_medium=text"),
                       .soundCloud("https://soundcloud.com/lil-peep/star-shopping"))
        XCTAssertEqual(ServiceLink.parse("https://m.soundcloud.com/x/sets/y"), .soundCloud("https://m.soundcloud.com/x/sets/y"))
        guard case .soundCloud = ServiceLink.parse("https://on.soundcloud.com/AbC123") else {
            return XCTFail("короткая ссылка SoundCloud")
        }
        XCTAssertNil(ServiceLink.parse("https://soundcloud.com/"))
        XCTAssertNil(ServiceLink.parse("https://youtube.com/watch?v=1"))
    }

    func testLinkDetection() {
        XCTAssertTrue(ServiceLink.looksLikeLink("https://soundcloud.com/a/b"))
        XCTAssertTrue(ServiceLink.looksLikeLink("music.yandex.ru/album/1"))
        XCTAssertFalse(ServiceLink.looksLikeLink("lil peep star shopping"))
    }

    private func ym(_ id: String, _ artist: String, _ title: String, _ ms: Int) -> Track {
        Track(ref: "ym:\(id)", title: title, artist: artist, artists: [ArtistRef(ref: "yma:1", name: artist)],
              album: nil, durationMs: ms, coverURL: nil, url: nil, explicit: false, available: true)
    }

    func testMatchesSameTrack() {
        let wanted = TrackMatch.soundCloud(uploader: "EsDeeKid", metaArtist: nil, title: "4 Raws", durationMs: 146_000)
        XCTAssertEqual(wanted.best([ym("1", "EsDeeKid", "4 Raws", 146_500)])?.ref, "ym:1")
    }

    func testRejectsOtherDurationArtistAndVersions() {
        let wanted = TrackMatch.soundCloud(uploader: "EsDeeKid", metaArtist: nil, title: "4 Raws", durationMs: 146_000)
        XCTAssertNil(wanted.best([
            ym("1", "EsDeeKid", "4 Raws", 160_000),
            ym("2", "Someone", "4 Raws", 146_000),
            ym("3", "EsDeeKid", "4 Raws (Sped Up)", 146_000),
        ]))
    }

    func testReuploadAndProdTags() {
        let wanted = TrackMatch.soundCloud(uploader: "random uploader", metaArtist: nil, title: "Кизару - Дежавю (prod. x)", durationMs: 180_000)
        XCTAssertTrue(wanted.queries[0].hasPrefix("Кизару"))
        let found = wanted.best([ym("7", "Kizaru, Другой", "Дежавю", 181_000), ym("8", "Кизару", "Дежавю", 181_000)])
        XCTAssertEqual(found?.ref, "ym:8")
    }

    func testKeepsRemixOnlyForRemix() {
        let wanted = TrackMatch.soundCloud(uploader: "A", metaArtist: nil, title: "Song (Remix)", durationMs: 100_000)
        XCTAssertEqual(wanted.best([ym("1", "A", "Song", 100_000), ym("2", "A", "Song (Remix)", 100_000)])?.ref, "ym:2")
    }

    func testTrackJSONMatchesAPI() throws {
        let json = #"{"ref":"sc:1","title":"T","artist":"A","artists":[{"ref":"sca:2","name":"A","avatar_url":null}],"album":null,"duration_ms":1000,"cover_url":"https://x/c.jpg","url":null,"explicit":false,"available":true,"plays":5}"#
        let track = try JSONDecoder().decode(Track.self, from: Data(json.utf8))
        XCTAssertEqual(track.durationMs, 1000)
        XCTAssertEqual(track.coverURL, "https://x/c.jpg")
        XCTAssertEqual(track.service, .soundcloud)
        XCTAssertNil(track.tags)
        let back = try JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any]
        XCTAssertEqual(back?["duration_ms"] as? Int, 1000)
        XCTAssertEqual(Service(ref: "ympl:u:3"), .yandex)
        XCTAssertEqual(ServiceError.http("Яндекс", 451).message, "Яндекс: недоступно в твоей стране (HTTP 451)")
    }
}
