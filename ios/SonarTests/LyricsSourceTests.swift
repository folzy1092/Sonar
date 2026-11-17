import Foundation
import XCTest
@testable import Sonar
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Сеть без сети: ответ по адресу запроса, все запросы записываются.
final class FakeLyricsTransport: LyricsTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [URLRequest] = []
    /// Ответ на запрос; nil — 404.
    let respond: @Sendable (URLRequest) throws -> LyricsResponse?

    init(_ respond: @escaping @Sendable (URLRequest) throws -> LyricsResponse?) {
        self.respond = respond
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    var hosts: [String] { requests.compactMap { $0.url?.host } }

    private func record(_ request: URLRequest) {
        lock.lock()
        log.append(request)
        lock.unlock()
    }

    func send(_ request: URLRequest) async throws -> LyricsResponse {
        record(request)
        return try respond(request) ?? LyricsResponse(status: 404, body: Data())
    }
}

func json(_ text: String, status: Int = 200) -> LyricsResponse {
    LyricsResponse(status: status, body: Data(text.utf8))
}

func queryValue(_ request: URLRequest, _ name: String) -> String? {
    request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == name }?.value
}

/// Разбор LRC / YRC / ответов lrclib, NetEase, Genius и переводчика — те же случаи, что в Rust-тестах
/// (`lyrics/mod.rs`, `lrclib.rs`, `netease.rs`, `genius.rs`, `translate.rs`), и порядок поиска.
final class LyricsSourceTests: XCTestCase {
    // MARK: LRC

    func testLRCLinesDurationsAndPauses() {
        let lrc = "[ar:x]\n[00:01.00]Раз\n[00:03.50]Два\n[00:05.00]\n[00:06.00]\n[00:08.00](эхо)\n"
        let l = LyricsParser.parseLRC(lrc, trackLength: 12)
        XCTAssertEqual(l.count, 4)
        XCTAssertEqual(l[0].text, "Раз")
        XCTAssertEqual(l[0].duration, 2.5, accuracy: 1e-9)
        XCTAssertEqual(l[2].text, "")
        XCTAssertTrue(l[2].isPause)
        XCTAssertEqual(l[2].duration, 3, accuracy: 1e-9)
        XCTAssertTrue(l[3].isBackground)
        XCTAssertEqual(l[3].duration, 4, accuracy: 1e-9) // до конца трека
        XCTAssertEqual(l.map(\.id), [0, 1, 2, 3])
    }

    func testLRCMultipleTagsAndOffset() {
        let l = LyricsParser.parseLRC("[offset:+500]\n[00:10.00][00:02.00]Припев\n[00:05.00]Куплет", trackLength: 0)
        XCTAssertEqual(l.map(\.start), [1.5, 4.5, 9.5])
        XCTAssertEqual(l.map(\.text), ["Припев", "Куплет", "Припев"])
        XCTAssertEqual(l[2].duration, 10, accuracy: 1e-9) // трек неизвестен — 10 с
    }

    func testLRCEnhancedWords() {
        let l = LyricsParser.parseLRC("[00:01.00]<00:01.00>Hello <00:01.50>world<00:02.40>\n[00:03.00]<00:03.00>Next", trackLength: 5)
        XCTAssertEqual(l[0].text, "Hello world")
        XCTAssertEqual(l[0].words.count, 2)
        XCTAssertTrue(l[0].words[0].spaceAfter)
        XCTAssertFalse(l[0].words[1].spaceAfter)
        XCTAssertEqual(l[0].words[0].duration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(l[0].words[1].duration, 0.9, accuracy: 1e-9)
        XCTAssertEqual(l[1].words[0].duration, 2, accuracy: 1e-9)
    }

    func testLRCCarriageReturnsAndJunk() {
        let l = LyricsParser.parseLRC("[00:00.50]\r\n[00:01.00]Раз\r\nмусор без тега\r\n[00:02.00]Два [00:03.00] не тег", trackLength: 0)
        XCTAssertEqual(l.map(\.text), ["Раз", "Два [00:03.00] не тег"]) // пустая строка в начале убрана
    }

    func testPlainTextCollapsesBlankLines() {
        XCTAssertEqual(LyricsParser.plainLines("\n\nОдин\n\n\nДва\n\n").map(\.text), ["Один", "", "Два"])
    }

    // MARK: NetEase

    func testYRCWordsAndCredits() {
        let yrc = "{\"t\":0,\"c\":[{\"tx\":\"作词: \"},{\"tx\":\"Someone\"}]}\n[1000,1500](1000,500,0)Hello (1500,1000,0)world\n[3000,900](3000,900,0)again"
        let l = LyricsParser.parseYRC(yrc)
        XCTAssertEqual(l.count, 2)
        XCTAssertEqual(l[0].text, "Hello world")
        XCTAssertEqual(l[0].words[0].start, 1)
        XCTAssertEqual(l[0].words[0].end, 1.5)
        XCTAssertTrue(l[0].words[0].spaceAfter)
        XCTAssertFalse(l[0].words[1].spaceAfter)
        XCTAssertEqual(l[0].end, 2.5)
        XCTAssertEqual(l[1].start, 3)
        XCTAssertEqual(l[1].id, 1)
        XCTAssertTrue(LyricsParser.isCredit("作曲：Someone"))
    }

    func testNetEasePickStrictMatch() throws {
        let songs = try JSONValue(data: Data(#"""
        [{"id":1,"name":"Yellow","duration":266000,"artists":[{"name":"Coldplay"}]},
         {"id":2,"name":"Yellow (Live)","duration":300000,"artists":[{"name":"Coldplay"}]},
         {"id":3,"name":"Yellow","duration":266500,"artists":[{"name":"Someone Else"}]}]
        """#.utf8)).items
        XCTAssertEqual(NetEase.pick(songs, artist: "Coldplay", title: "Yellow", duration: 267), 1)
        XCTAssertNil(NetEase.pick(songs, artist: "Coldplay", title: "Yellow", duration: 200), "длительность не та — не берём")
    }

    func testNetEaseLyricsPrefersYRCAndDropsInstrumental() throws {
        let both = try JSONValue(data: Data(#"""
        {"yrc":{"lyric":"[1000,1000](1000,1000,0)a\n[2000,1000](2000,1000,0)b\n[3000,1000](3000,1000,0)c"},
         "lrc":{"lyric":"[00:01.00]a\n[00:02.00]b\n[00:03.00]c"}}
        """#.utf8))
        let l = try XCTUnwrap(NetEase.lyrics(from: both, duration: 10))
        XCTAssertTrue(l.wordSynced)
        XCTAssertEqual(l.source, "NetEase")
        let lrcOnly = try JSONValue(data: Data(#"{"lrc":{"lyric":"[00:00.00]作词: X\n[00:01.00]a\n[00:02.00]b\n[00:03.00]c"}}"#.utf8))
        let l2 = try XCTUnwrap(NetEase.lyrics(from: lrcOnly, duration: 10))
        XCTAssertFalse(l2.wordSynced)
        XCTAssertEqual(l2.lines.map(\.text), ["a", "b", "c"])
        let instrumental = try JSONValue(data: Data(#"{"lrc":{"lyric":"[00:00.00]纯音乐，请欣赏"}}"#.utf8))
        XCTAssertNil(NetEase.lyrics(from: instrumental, duration: 10))
    }

    // MARK: lrclib

    func testLrclibPick() {
        let records = [
            Lrclib.Record(trackName: "gates (altered)", duration: 120, synced: "[00:01.00]alt", plain: nil),
            Lrclib.Record(trackName: "gates", duration: 121, synced: "[00:01.00]orig", plain: nil),
            Lrclib.Record(trackName: "gates", duration: 200, synced: "[00:01.00]long", plain: nil),
        ]
        XCTAssertEqual(Lrclib.pick(records, duration: 120, title: "gates (prod. x)").synced, "[00:01.00]orig")
        let plain = Lrclib.pick([Lrclib.Record(trackName: "a", duration: 100, synced: nil, plain: "слова")], duration: 100, title: "a")
        XCTAssertNil(plain.synced)
        XCTAssertEqual(plain.plain, "слова")
        XCTAssertNil(Lrclib.pick([Lrclib.Record(trackName: "a", duration: 100, instrumental: true, synced: "x", plain: nil)],
                                 duration: 100, title: "a").synced)
        let record = Lrclib.Record(json: .object(["trackName": .string("x"), "duration": .double(201.5), "syncedLyrics": .string("[00:01.00]y")]))
        XCTAssertEqual(record.duration, 201.5)
        XCTAssertFalse(record.instrumental)
    }

    // MARK: Genius

    func testGeniusHTMLParsingSkipsExcluded() {
        let html = ##"<html><div data-lyrics-container="true"><div data-exclude-from-selection="true">12 Contributors<div>x</div></div>[Припев]<br/>Раз &amp; два<br><a href="#">Три</a></div><script>a<b</script></html>"##
        let t = Genius.lyrics(fromHTML: html)
        XCTAssertEqual(t, "\n[Припев]\nРаз & два\nТри")
        XCTAssertEqual(Genius.stripSections(t), "\n\nРаз & два\nТри")
    }

    func testGeniusUnescape() {
        XCTAssertEqual(Genius.unescape("a&#x27;b &#39; &quot;q&quot; & x"), "a'b ' \"q\" & x")
    }

    func testGeniusPickRequiresArtist() throws {
        let hits = try JSONValue(data: Data(#"""
        [{"type":"song","result":{"url":"u1","title":"Дежавю","artist_names":"Другой","primary_artist":{"name":"Другой"}}},
         {"type":"song","result":{"url":"u2","id":7,"title":"Дежавю (Remix)","artist_names":"Кизару & X","primary_artist":{"name":"Кизару"}}}]
        """#.utf8)).items
        let found = Genius.pick(hits, variants: ["Дежавю"], allowed: [TrackText.norm("Кизару")])
        XCTAssertEqual(found?.url, "u2")
        XCTAssertEqual(found?.id, 7)
        XCTAssertNil(Genius.pick(hits, variants: ["Совсем другое"], allowed: [TrackText.norm("Кизару")]))
    }

    func testGeniusQueriesAreUnique() {
        XCTAssertEqual(Genius.queries(first: "A", clean: "Song", keywords: "Song", core: "Song"), ["A Song", "Song", "A"])
    }

    func testGeniusReferents() throws {
        let v = try JSONValue(data: Data(#"""
        {"response":{"referents":[
          {"fragment":"[Verse 1: X]","annotations":[{"body":{"plain":"про куплет"},"state":"accepted"}]},
          {"fragment":"Жить этот момент\n Трясутся мои руки","annotations":[{"body":{"plain":"Вся строфа…"},"state":"pending"}]},
          {"fragment":"пусто","annotations":[{"body":{"plain":"  "}}]}
        ]}}
        """#.utf8))
        let a = Genius.parseReferents(v)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].lines, ["Жить этот момент", "Трясутся мои руки"])
        XCTAssertFalse(a[0].reviewed)
    }

    func testGeniusCloudflareError() {
        let challenge = LyricsResponse(status: 403, body: Data("<html>challenge-platform</html>".utf8))
        XCTAssertThrowsError(try Genius.check(challenge)) { error in
            XCTAssertTrue((error as? LyricsSourceError)?.message.contains("Cloudflare") == true)
        }
        XCTAssertEqual(try Genius.check(LyricsResponse(status: 200, body: Data("ok".utf8))), "ok")
    }

    // MARK: перевод

    func testTranslateParsers() throws {
        let gtx = try LyricsTranslator.parse(#"[[["Привет\n","Hello\n",null,null,10],["мир","world",null,null,10]],null,"en",null]"#)
        XCTAssertEqual(gtx.lines, ["Привет", "мир"])
        XCTAssertEqual(gtx.source, "en")
        let lines = try LyricsTranslator.parseLines(#"[["Я вижу свет","en"],["в твоих глазах","en"]]"#)
        XCTAssertEqual(lines.lines, ["Я вижу свет", "в твоих глазах"])
        XCTAssertEqual(lines.source, "en")
        XCTAssertEqual(try LyricsTranslator.parseLines(#"["раз","два"]"#).lines, ["раз", "два"])
        XCTAssertThrowsError(try LyricsTranslator.parse("{}"))
    }

    func testTranslateSkipsPausesAndFallsBack() async throws {
        let transport = FakeLyricsTransport { request in
            if request.url?.host == "clients5.google.com" { return json("oops", status: 500) }
            return json(#"[[["раз\nдва","one\ntwo",null,null,10]],null,"en"]"#)
        }
        let result = try await LyricsTranslator(transport: transport).translate(["one", "", "two"], to: "ru")
        XCTAssertEqual(result.lines, ["раз", "", "два"])
        XCTAssertEqual(result.source, "en")
        XCTAssertEqual(transport.hosts, ["clients5.google.com", "translate.googleapis.com"])
        let body = String(decoding: transport.requests[0].httpBody ?? Data(), as: UTF8.self)
        XCTAssertEqual(body, "q=one&q=two")
    }

    // MARK: порядок поиска (fetch_any)

    func testFinderReturnsLrclibSynced() async throws {
        let transport = FakeLyricsTransport { request in
            guard request.url?.host == "lrclib.net" else { return nil }
            if request.url?.path == "/api/get" {
                XCTAssertEqual(queryValue(request, "duration"), "200")
                return json(#"{"trackName":"Song","duration":200,"syncedLyrics":"[00:01.00]Раз\n[00:02.00]Два"}"#)
            }
            return json("[]")
        }
        let lyrics = try await LyricsFinder(transport: transport).find(LyricsQuery(artist: "A", title: "Song", duration: 200))
        XCTAssertEqual(lyrics?.source, "lrclib")
        XCTAssertEqual(lyrics?.synced, true)
        XCTAssertEqual(lyrics?.lines.map(\.text), ["Раз", "Два"])
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testFinderFallsBackToNetEaseWords() async throws {
        let transport = FakeLyricsTransport { request in
            switch (request.url?.host, request.url?.path) {
            case ("lrclib.net", "/api/search"):
                return json(#"[{"trackName":"Song","duration":200,"plainLyrics":"Раз\nДва"}]"#)
            case ("music.163.com", "/api/search/get"):
                XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://music.163.com/")
                return json(#"{"result":{"songs":[{"id":42,"name":"Song","duration":200000,"artists":[{"name":"A"}]}]}}"#)
            case ("music.163.com", "/api/song/lyric/v1"):
                XCTAssertEqual(queryValue(request, "id"), "42")
                return json(#"{"yrc":{"lyric":"[1000,1000](1000,1000,0)a\n[2000,1000](2000,1000,0)b\n[3000,1000](3000,1000,0)c"}}"#)
            default:
                return nil
            }
        }
        let lyrics = try await LyricsFinder(transport: transport).find(LyricsQuery(artist: "A", title: "Song", duration: 200))
        XCTAssertEqual(lyrics?.source, "NetEase")
        XCTAssertEqual(lyrics?.wordSynced, true)
        XCTAssertFalse(transport.hosts.contains("genius.com"))
    }

    func testFinderUsesGeniusThenPlain() async throws {
        let page = #"<div data-lyrics-container="true">[Куплет]<br/>Слово<br/>Другое</div>"#
        let genius = FakeLyricsTransport { request in
            switch (request.url?.host, request.url?.path) {
            case ("lrclib.net", "/api/search"):
                return json(#"[{"trackName":"Song","duration":200,"plainLyrics":"plain"}]"#)
            case ("music.163.com", _):
                return json(#"{"result":{"songs":[]}}"#)
            case ("genius.com", "/api/search/multi"):
                return json(#"{"response":{"sections":[{"hits":[{"type":"song","result":{"url":"https://genius.com/a-song-lyrics","id":1,"title":"Song","artist_names":"A","primary_artist":{"name":"A"}}}]}]}}"#)
            case ("genius.com", "/a-song-lyrics"):
                return LyricsResponse(status: 200, body: Data(page.utf8))
            default:
                return nil
            }
        }
        let fromGenius = try await LyricsFinder(transport: genius).find(LyricsQuery(artist: "A", title: "Song", duration: 200))
        XCTAssertEqual(fromGenius?.source, "Genius")
        XCTAssertEqual(fromGenius?.synced, false)
        XCTAssertEqual(fromGenius?.lines.map(\.text), ["Слово", "Другое"])

        // Genius закрыт Cloudflare — plain из lrclib
        let blocked = FakeLyricsTransport { request in
            switch (request.url?.host, request.url?.path) {
            case ("lrclib.net", "/api/search"):
                return json(#"[{"trackName":"Song","duration":200,"plainLyrics":"plain"}]"#)
            case ("genius.com", _):
                return LyricsResponse(status: 403, body: Data(), headers: ["cf-mitigated": "challenge"])
            default:
                return nil
            }
        }
        let plain = try await LyricsFinder(transport: blocked).find(LyricsQuery(artist: "A", title: "Song", duration: 200))
        XCTAssertEqual(plain?.source, "lrclib")
        XCTAssertEqual(plain?.lines.map(\.text), ["plain"])
    }

    func testFinderNothingAndOutage() async throws {
        let nothing = FakeLyricsTransport { request in
            if request.url?.path == "/api/search" { return json("[]") }
            if request.url?.host == "music.163.com" { return json(#"{"result":{}}"#) }
            if request.url?.path == "/api/search/multi" { return json(#"{"response":{"sections":[]}}"#) }
            return nil
        }
        let none = try await LyricsFinder(transport: nothing).find(LyricsQuery(artist: "A", title: "Song", duration: 200))
        XCTAssertNil(none)

        // lrclib лежит, остальные молчат — ошибка (не кэшировать как «нет»)
        let down = FakeLyricsTransport { request in
            if request.url?.host == "lrclib.net" { return json("", status: 503) }
            if request.url?.host == "music.163.com" { return json(#"{"result":{}}"#) }
            if request.url?.path == "/api/search/multi" { return json(#"{"response":{"sections":[]}}"#) }
            return nil
        }
        do {
            _ = try await LyricsFinder(transport: down).find(LyricsQuery(artist: "A", title: "Song", duration: 200))
            XCTFail("ожидалась ошибка")
        } catch {
            XCTAssertEqual((error as? LyricsSourceError)?.status, 503)
        }
        // после сбоя lrclib не спрашиваем его по остальным вариантам названия
        XCTAssertEqual(down.requests.filter { $0.url?.path == "/api/search" }.count, 1)
    }

    func testFinderTriesSimplifiedTitleAndReupload() async throws {
        let transport = FakeLyricsTransport { request in
            guard request.url?.path == "/api/search" else { return nil }
            if queryValue(request, "artist_name") == "Кизару", queryValue(request, "track_name") == "Дежавю" {
                return json(#"[{"trackName":"Дежавю","duration":180,"syncedLyrics":"[00:01.00]Да"}]"#)
            }
            return json("[]")
        }
        let lyrics = try await LyricsFinder(transport: transport).find(LyricsQuery(artist: "reuploader", title: "Кизару - Дежавю", duration: 180))
        XCTAssertEqual(lyrics?.lines.first?.text, "Да")
    }
}
