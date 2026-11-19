import XCTest
@testable import Sonar

/// Порядок поиска текста и правила — те же случаи, что `lyrics/search_tests.rs` и тесты `lyrics/rules.rs`
/// (docs/TITLE_SPLIT.md «Порядок поиска текста», docs/POLISH_PROMPT.md п. 7).
final class LyricsSearchTests: XCTestCase {
    static let uploader = "juchen"
    static let title = "gothviolence – не могу уснуть"
    static let key = "sc:1"
    static let variant = TitlePair("gothviolence", "не могу уснуть")

    /// Подмена сети: какие пары lrclib знает (синхронный текст), на каких падает; NetEase и Genius молчат.
    final class Net: @unchecked Sendable {
        let transport: FakeLyricsTransport

        init(synced: [TitlePair] = [], broken: [TitlePair] = []) {
            transport = FakeLyricsTransport { request in
                let pair = TitlePair(queryValue(request, "artist_name") ?? "", queryValue(request, "track_name") ?? "")
                switch (request.url?.host, request.url?.path) {
                case ("lrclib.net", "/api/get"):
                    guard synced.contains(pair) else { return nil }
                    let record: [String: Any] = ["trackName": pair.title, "duration": 120, "syncedLyrics": "[00:01.00]Строка\n[00:03.00]Ещё строка"]
                    return LyricsResponse(status: 200, body: try JSONSerialization.data(withJSONObject: record))
                case ("lrclib.net", "/api/search"):
                    return broken.contains(pair) ? json("", status: 503) : json("[]")
                case ("music.163.com", _):
                    return json(#"{"result":{"songs":[]}}"#)
                case ("genius.com", _):
                    return json(#"{"response":{"sections":[]}}"#)
                default:
                    return nil
                }
            }
        }

        /// Пары, о которых спросили lrclib, по порядку первого запроса.
        var lrclib: [TitlePair] {
            var out: [TitlePair] = []
            for request in transport.requests where request.url?.host == "lrclib.net" {
                let pair = TitlePair(queryValue(request, "artist_name") ?? "", queryValue(request, "track_name") ?? "")
                if !out.contains(pair) { out.append(pair) }
            }
            return out
        }

        /// Первый запрос к Genius и к NetEase (`исполнитель название`).
        var genius: String? { transport.requests.first { $0.url?.path == "/api/search/multi" }.flatMap { queryValue($0, "q") } }
        var netease: String? { transport.requests.first { $0.url?.host == "music.163.com" }.flatMap { queryValue($0, "s") } }
    }

    private func find(_ net: Net, artist: String = uploader, title: String = title, rules: LyricsRules,
                      now: ContinuousClock.Instant = .now) async throws -> Lyrics? {
        try await LyricsFinder(transport: net.transport, rules: rules)
            .find(LyricsQuery(artist: artist, title: title, duration: 120, key: Self.key), now: now)
    }

    private func rules(_ json: String? = nil) -> LyricsRules {
        LyricsRules(remote: nil, rules: json.flatMap(LyricsRuleSet.parse) ?? LyricsRuleSet())
    }

    // MARK: порядок поиска

    func testFirstPairFoundVariantsNotTried() async throws {
        let net = Net(synced: [TitlePair(Self.uploader, Self.title)])
        let found = try await find(net, rules: rules())
        XCTAssertEqual(found?.synced, true)
        XCTAssertEqual(net.lrclib, [TitlePair(Self.uploader, Self.title)])
    }

    func testNotFoundTriesReuploadVariant() async throws {
        let net = Net(synced: [Self.variant])
        let found = try await find(net, rules: rules())
        XCTAssertEqual(found?.synced, true)
        XCTAssertEqual(net.lrclib.first, TitlePair(Self.uploader, Self.title), "сначала обычная пара")
        XCTAssertEqual(net.lrclib.last, Self.variant)
        XCTAssertNil(net.genius)
    }

    func testNoVariantsOneRequest() async throws {
        let net = Net()
        let found = try await find(net, artist: "Bones", title: "Sodium", rules: rules())
        XCTAssertNil(found)
        XCTAssertEqual(net.lrclib, [TitlePair("Bones", "Sodium")])
        XCTAssertEqual(net.genius, "Bones Sodium")
    }

    func testNetworkFailureOnVariantStopsWithoutMiss() async throws {
        let net = Net(broken: [Self.variant])
        let rules = rules()
        let now = ContinuousClock.now
        do {
            _ = try await find(net, rules: rules, now: now)
            XCTFail("ожидалась ошибка сети")
        } catch {}
        XCTAssertEqual(net.lrclib.last, Self.variant, "после сбоя lrclib больше не спрашиваем")
        let fresh = await rules.missIsFresh(Self.key, now: now)
        XCTAssertFalse(fresh, "сбой сети — не промах")
    }

    func testMissIsRememberedAndExpires() async throws {
        let rules = rules()
        let now = ContinuousClock.now
        let first = Net()
        let none = try await find(first, rules: rules, now: now)
        XCTAssertNil(none)
        XCTAssertTrue(first.lrclib.contains(Self.variant))

        let second = Net()
        _ = try await find(second, rules: rules, now: now + .seconds(60))
        XCTAssertTrue(second.lrclib.allSatisfy { $0.artist == Self.uploader }, "промах помнится — только обычный поиск")

        let later = Net()
        _ = try await find(later, rules: rules, now: now + LyricsRules.variantRecheck)
        XCTAssertTrue(later.lrclib.contains(Self.variant), "промах истёк")
    }

    func testManualRecheckResetsMiss() async throws {
        let rules = rules()
        let now = ContinuousClock.now
        _ = try await find(Net(), rules: rules, now: now)
        await LyricsFinder(transport: Net().transport, rules: rules).recheck(Self.key)
        let again = Net()
        _ = try await find(again, rules: rules, now: now)
        XCTAssertTrue(again.lrclib.contains(Self.variant))
    }

    func testReuploaderVariantsFirst() async throws {
        let net = Net()
        _ = try await find(net, rules: rules(#"{"reuploaders":["Juchen"]}"#))
        XCTAssertEqual(net.lrclib.first, Self.variant)
    }

    func testManualPairReplacesSteps() async throws {
        let net = Net()
        _ = try await find(net, artist: "Kleyy", title: "cowboyclicker - doesnt matter (prod. gloro)",
                           rules: rules(#"{"pairs":{"sc:1":{"artist":"cowboyclicker","title":"doesnt matter"}}}"#))
        XCTAssertEqual(net.lrclib, [TitlePair("cowboyclicker", "doesnt matter")])
        XCTAssertEqual(net.genius, "cowboyclicker doesnt matter")
    }

    func testIgnoredTrackNotSearched() async throws {
        let net = Net()
        let found = try await find(net, rules: rules(#"{"ignore":["sc:1"]}"#))
        XCTAssertNil(found)
        XCTAssertTrue(net.transport.requests.isEmpty)
    }

    func testGeniusAndNetEaseUseSearchPair() async throws {
        let net = Net()
        _ = try await find(net, artist: "Kleyy", title: "cowboyclicker - doesnt matter (prod. gloro)", rules: rules())
        XCTAssertEqual(net.genius, "cowboyclicker doesnt matter")
        XCTAssertEqual(net.netease, "cowboyclicker doesnt matter")
    }

    func testPlanAttemptsHaveNoDuplicates() {
        let plan = LyricsFinder.plan(LyricsQuery(artist: "Bones", title: "Sodium", duration: 0, key: ""), rules: LyricsRuleSet(), missFresh: false)
        XCTAssertEqual(plan.normal, [TitlePair("Bones", "Sodium")])
        XCTAssertTrue(plan.variants.isEmpty)
        XCTAssertFalse(plan.variantsFirst)
    }

    // MARK: правила

    func testDefaultRulesKnowDashArtist() {
        XCTAssertTrue(LyricsRuleSet().dash.names.contains("cowboyclicker"))
    }

    func testParseRules() throws {
        let r = try XCTUnwrap(LyricsRuleSet.parse(#"""
            {"dash_artists":["jay-z"],"reuploaders":["Kleyy"],"ignore":["sc:1"],
             "pairs":{"sc:2":{"artist":"cowboyclicker","title":"doesnt matter","display":true},"sc:3":{"artist":"","title":"x"}}}
            """#))
        XCTAssertTrue(r.isReuploader("kleyy"))
        XCTAssertFalse(r.isReuploader("Bones"))
        XCTAssertTrue(r.isIgnored("sc:1"))
        XCTAssertEqual(r.pair("sc:2"), ManualPair(artist: "cowboyclicker", title: "doesnt matter", display: true))
        XCTAssertNil(r.pair("sc:3"), "пустой артист — пары нет")
        XCTAssertNil(LyricsRuleSet.parse("not json"))
        XCTAssertNotNil(LyricsRuleSet.parse("{}"))
    }

    func testParseRejectsHugeLists() {
        let list = Array(repeating: #""x""#, count: LyricsRuleSet.maxEntries + 1).joined(separator: ",")
        XCTAssertNil(LyricsRuleSet.parse(#"{"ignore":[\#(list)]}"#))
    }

    func testMissesExpireAndForget() async {
        let rules = rules()
        let t0 = ContinuousClock.now
        var fresh = await rules.missIsFresh("sc:1", now: t0)
        XCTAssertFalse(fresh)
        await rules.rememberMiss("sc:1", now: t0)
        fresh = await rules.missIsFresh("sc:1", now: t0 + .seconds(60))
        XCTAssertTrue(fresh)
        fresh = await rules.missIsFresh("sc:1", now: t0 + LyricsRules.variantRecheck)
        XCTAssertFalse(fresh)
        await rules.rememberMiss("sc:1", now: t0)
        await rules.forgetMiss("sc:1")
        fresh = await rules.missIsFresh("sc:1", now: t0)
        XCTAssertFalse(fresh)
    }

    func testRemoteRulesReplaceAndFailureKeeps() async {
        let url = URL(string: "https://example.invalid/lyrics-rules.json")!
        let good = FakeLyricsTransport { _ in json(#"{"reuploaders":["juchen"]}"#) }
        let rules = LyricsRules(remote: url, rules: LyricsRuleSet())
        await rules.refreshIfDue(transport: good)
        var current = await rules.current
        XCTAssertTrue(current.isReuploader("Juchen"))

        // битый файл — прежние правила
        let broken = FakeLyricsTransport { _ in json("not json") }
        let other = LyricsRules(remote: url, rules: current)
        await other.refreshIfDue(transport: broken)
        current = await other.current
        XCTAssertTrue(current.isReuploader("Juchen"))

        // второй раз в те же сутки файл не читаем
        await rules.refreshIfDue(transport: good)
        XCTAssertEqual(good.requests.count, 1)
    }
}
