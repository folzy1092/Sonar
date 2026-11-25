import XCTest
@testable import Sonar

/// Ссылка «Поделиться» (Core/Share/ShareLinkCodec.swift): та же строка, что у сайта и ПК.
final class ShareLinkTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Case: Decodable {
            struct Payload: Decodable {
                let t: String
                let a: String
                let d: Int?
                let c: String?
                let src: String
                let ids: [String: String]
                let sl: String?
                let play: String?
                let by: String?
            }
            let name: String
            let data: Payload
            let lang: String
            let encoded: String
            let url: String
        }
        let cases: [Case]
    }

    /// `site/src/lib/share-link.fixture.json` рядом с репо (на CI — тот же чекаут).
    private func fixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("site/src/lib/share-link.fixture.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "нет общего примера рядом с тестами")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testFixtureMatchesSiteAndPC() throws {
        for c in try fixture().cases {
            let d = c.data
            let share = ShareData(t: d.t, a: d.a, d: d.d, c: d.c, src: d.src, ids: d.ids, sl: d.sl, play: d.play, by: d.by)
            XCTAssertEqual(ShareLinkCodec.encode(share), c.encoded, c.name)
            XCTAssertEqual(ShareLinkCodec.url(share, lang: c.lang)?.absoluteString, c.url, c.name)
        }
    }

    func testFromTrackWithTwins() throws {
        var track = makeTrack("sc:247755542", "Lil Peep", title: "Star Shopping", durationMs: 142_300)
        track.coverURL = "https://i1.sndcdn.com/artworks-000-t500x500.jpg"
        track.url = "https://soundcloud.com/lil_peep/star-shopping?si=tracker"
        let data = ShareLinkCodec.data(track, refs: ["yt": "yt:m8QQR-wQA0I", "ym": "ym:41245581"], scFull: true)
        XCTAssertEqual(data.flatMap(ShareLinkCodec.encode), try fixture().cases[0].encoded)
    }

    func testPickPlay() {
        XCTAssertEqual(ShareLinkCodec.pickPlay(["yt": "m8QQR-wQA0I", "sc": "1"], scFull: false), "yt")
        XCTAssertEqual(ShareLinkCodec.pickPlay(["sc": "1"], scFull: true), "sc")
        XCTAssertNil(ShareLinkCodec.pickPlay(["sc": "1"], scFull: false))
        XCTAssertNil(ShareLinkCodec.pickPlay(["ym": "1"], scFull: true))
    }

    func testNoPrivateData() {
        var track = makeTrack("ym:1695", "Кино", title: "Группа крови")
        track.coverURL = "https://evil.example/a.jpg"
        let data = ShareLinkCodec.data(track)
        XCTAssertNil(data?.c)
        XCTAssertNil(ShareLinkCodec.data(makeTrack("local:abc", "x")))
        XCTAssertEqual(ShareLinkCodec.scPath("https://soundcloud.com/a/b?si=1"), "a/b")
        XCTAssertNil(ShareLinkCodec.scPath("https://soundcloud.com/a/sets/b"))
    }

    func testJSONEscapesLikeJavaScript() {
        XCTAssertEqual(ShareLinkCodec.jsonString("a\"b\\c\nd/é"), "\"a\\\"b\\\\c\\nd/é\"")
    }

    func testLongLinkDropsCover() {
        let share = ShareData(t: String(repeating: "а", count: 150), a: String(repeating: "б", count: 150),
                              c: "https://i1.sndcdn.com/\(String(repeating: "x", count: 300)).jpg",
                              src: "sc", ids: ["sc": "1"])
        var noCover = share
        noCover.c = nil
        XCTAssertNotNil(ShareLinkCodec.encode(share))
        XCTAssertEqual(ShareLinkCodec.encode(share), ShareLinkCodec.encode(noCover))
    }
}
