import XCTest
@testable import Sonar

/// Умные плейлисты (NEXT_PROMPT, этап 6): движок правил — те же случаи, что `smart.test.ts` и
/// `store/smart_rules.rs` на ПК, — JSON как у ПК, источники и хранилище.
final class SmartRulesTests: XCTestCase {
    private let day = SmartEngine.day
    private let now = 1_000 * 86_400_000

    private func cands(_ tracks: [Track], added: [Int]? = nil) -> [SmartCandidate] {
        tracks.enumerated().map { SmartCandidate(track: $0.element, addedAt: added?[$0.offset] ?? 0) }
    }

    private func history(_ rows: [(String, Int)]) -> SmartHistory {
        SmartHistory(rows: rows.map { (ref: $0.0, at: $0.1) })
    }

    private func refs(_ rules: SmartRules, _ list: [SmartCandidate], _ h: SmartHistory = SmartHistory(rows: [])) -> [String] {
        SmartEngine.evaluate(rules, candidates: list, history: h, now: now).map(\.ref)
    }

    // MARK: - Условия

    func testPlaysCountsOnlyInsideWindow() {
        let list = cands([makeTrack("sc:1", "A"), makeTrack("sc:2", "B")])
        let h = history([("sc:1", now - 1 * day), ("sc:1", now - 2 * day), ("sc:1", now - 40 * day), ("sc:2", now - 40 * day)])
        let month = SmartRules(source: .liked, conditions: [.plays(days: 30, op: .gte, value: 2)])
        XCTAssertEqual(refs(month, list, h), ["sc:1"])
        let ever = SmartRules(source: .liked, conditions: [.plays(days: nil, op: .gte, value: 1)])
        XCTAssertEqual(refs(ever, list, h), ["sc:1", "sc:2"], "без окна — за всё время")
        let zero = SmartRules(source: .liked, conditions: [.plays(days: 0, op: .lte, value: 1)])
        XCTAssertEqual(refs(zero, list, h), ["sc:2"], "0 дней — тоже за всё время")
    }

    func testNeverPlayedCountsAsLongAgo() {
        let list = cands([makeTrack("sc:1", "A"), makeTrack("sc:2", "B"), makeTrack("sc:3", "C")])
        let h = history([("sc:1", now - 90 * day), ("sc:2", now - 5 * day)])
        let before = SmartRules(source: .liked, conditions: [.lastPlayed(op: .before, days: 60)])
        XCTAssertEqual(refs(before, list, h), ["sc:1", "sc:3"])
        let after = SmartRules(source: .liked, conditions: [.lastPlayed(op: .after, days: 60)])
        XCTAssertEqual(refs(after, list, h), ["sc:2"])
    }

    func testAddedServiceArtistAndDuration() {
        let a = makeTrack("sc:1", "Daft Punk", durationMs: 100_000)
        let b = makeTrack("ym:2", "Punk Rockers", durationMs: 300_000)
        let c = makeTrack("ym:3", "Other", durationMs: 200_000)
        let list = cands([a, b, c], added: [now - 3 * day, now - 20 * day, now])

        XCTAssertEqual(refs(SmartRules(source: .liked, conditions: [.added(days: 14)]), list), ["sc:1", "ym:3"])
        XCTAssertEqual(refs(SmartRules(source: .liked, conditions: [.service(op: .is, value: "ym")]), list), ["ym:2", "ym:3"])
        XCTAssertEqual(refs(SmartRules(source: .liked, conditions: [.service(op: .not, value: "ym")]), list), ["sc:1"])
        XCTAssertEqual(refs(SmartRules(source: .liked, conditions: [.artist(op: .is, value: " punk ")]), list), ["sc:1", "ym:2"],
                       "без учёта регистра, часть имени")
        XCTAssertEqual(refs(SmartRules(source: .liked, conditions: [.artist(op: .not, value: "punk")]), list), ["ym:3"])
        XCTAssertEqual(refs(SmartRules(source: .liked, conditions: [.duration(op: .gte, value: 200)]), list), ["ym:2", "ym:3"],
                       "длительность — в секундах")
        XCTAssertEqual(refs(SmartRules(source: .liked, conditions: [.duration(op: .lte, value: 100)]), list), ["sc:1"])
    }

    func testMatchAllOrAnyAndEmptyConditions() {
        let list = cands([makeTrack("sc:1", "A"), makeTrack("ym:2", "B"), makeTrack("ym:3", "A")])
        let conditions: [SmartCondition] = [.service(op: .is, value: "ym"), .artist(op: .is, value: "A")]
        XCTAssertEqual(refs(SmartRules(source: .liked, match: .all, conditions: conditions), list), ["ym:3"])
        XCTAssertEqual(refs(SmartRules(source: .liked, match: .any, conditions: conditions), list), ["sc:1", "ym:2", "ym:3"])
        XCTAssertEqual(refs(SmartRules(source: .liked), list), ["sc:1", "ym:2", "ym:3"], "без условий — весь источник")
    }

    func testDuplicatesDroppedFirstWins() {
        let list = cands([makeTrack("sc:1", "A"), makeTrack("sc:1", "A"), makeTrack("sc:2", "B")])
        XCTAssertEqual(refs(SmartRules(source: .liked), list), ["sc:1", "sc:2"])
    }

    // MARK: - Порядок и лимит

    func testSortIsStableBothWays() {
        let list = cands([makeTrack("sc:1", "A"), makeTrack("sc:2", "B"), makeTrack("sc:3", "C"), makeTrack("sc:4", "D")])
        let h = history([("sc:2", now - day), ("sc:2", now - 2 * day), ("sc:4", now - day), ("sc:4", now - 3 * day)])
        let desc = SmartRules(source: .liked, sort: SmartSort(by: .plays))
        XCTAssertEqual(refs(desc, list, h), ["sc:2", "sc:4", "sc:1", "sc:3"], "при равенстве — порядок источника")
        let asc = SmartRules(source: .liked, sort: SmartSort(by: .plays, desc: false))
        XCTAssertEqual(refs(asc, list, h), ["sc:1", "sc:3", "sc:2", "sc:4"])
    }

    func testSortByTextLastPlayedAndWindow() {
        let list = cands([makeTrack("sc:1", "b", title: "Zeta"), makeTrack("sc:2", "A", title: "alpha"), makeTrack("sc:3", "c", title: "Mid")])
        XCTAssertEqual(refs(SmartRules(source: .liked, sort: SmartSort(by: .title, desc: false)), list), ["sc:2", "sc:3", "sc:1"])
        XCTAssertEqual(refs(SmartRules(source: .liked, sort: SmartSort(by: .artist, desc: false)), list), ["sc:2", "sc:1", "sc:3"])

        let h = history([("sc:1", now - 50 * day), ("sc:1", now - 51 * day), ("sc:1", now - 52 * day), ("sc:3", now - day)])
        let lastAsc = SmartRules(source: .liked, sort: SmartSort(by: .lastPlayed, desc: false))
        XCTAssertEqual(refs(lastAsc, list, h), ["sc:2", "sc:1", "sc:3"], "не слушал — раньше всех")
        let month = SmartRules(source: .liked, sort: SmartSort(by: .plays, days: 30))
        XCTAssertEqual(refs(month, list, h), ["sc:3", "sc:1", "sc:2"], "старые прослушивания вне окна не считаются")
    }

    func testLimitIsClamped() {
        let list = cands((1...5).map { makeTrack("sc:\($0)", "A") })
        XCTAssertEqual(refs(SmartRules(source: .liked, limit: 2), list), ["sc:1", "sc:2"])
        XCTAssertEqual(refs(SmartRules(source: .liked, limit: 0), list), ["sc:1"], "меньше 1 — 1")
        XCTAssertEqual(refs(SmartRules(source: .liked, limit: 5000), list).count, 5)
    }

    // MARK: - Проверка правил

    func testProblems() {
        XCTAssertNil(SmartEngine.problem(.blank))
        var newer = SmartRules.blank
        newer.v = 2
        XCTAssertEqual(SmartEngine.problem(newer), "Правила из новой версии Sonar")
        XCTAssertEqual(SmartEngine.problem(SmartRules(source: .playlist(id: " "))), "Выбери плейлист")
        XCTAssertEqual(SmartEngine.problem(SmartRules(source: .liked, conditions: [.artist(op: .is, value: "  ")])), "Впиши исполнителя")
        XCTAssertEqual(SmartEngine.problem(SmartRules(source: .liked, conditions: [.service(op: .is, value: "nope")])), "Выбери сервис")
        XCTAssertNil(SmartEngine.problem(SmartRules(source: .liked, conditions: [.service(op: .is, value: "ym")])))
        let many = SmartRules(source: .liked, conditions: Array(repeating: .added(days: 1), count: SmartRules.maxConditions + 1))
        XCTAssertEqual(SmartEngine.problem(many), "Слишком много условий")
    }

    func testNormalizedClampsWithoutChangingOriginal() {
        let raw = SmartRules(source: .liked, conditions: [
            .plays(days: 0, op: .gte, value: -3), .lastPlayed(op: .before, days: 99_999), .added(days: 0),
            .artist(op: .is, value: "  Muse "), .duration(op: .lte, value: 999_999),
        ], sort: SmartSort(by: .title, days: 30), limit: 0)
        let clean = raw.normalized
        XCTAssertEqual(clean.conditions, [
            .plays(days: nil, op: .gte, value: 0), .lastPlayed(op: .before, days: SmartRules.maxDays), .added(days: 1),
            .artist(op: .is, value: "Muse"), .duration(op: .lte, value: 24 * 3600),
        ])
        XCTAssertNil(clean.sort?.days, "окно — только у сортировки по прослушиваниям")
        XCTAssertNil(clean.limit, "0 — без лимита")
        XCTAssertEqual(raw.limit, 0, "исходник не меняется")
        XCTAssertEqual(SmartRules(source: .liked, limit: 9_999).normalized.limit, SmartRules.maxLimit)
    }

    // MARK: - JSON

    func testJSONMatchesPC() throws {
        let pc = """
        {"v":1,"source":{"kind":"playlist","id":"pl_1"},"match":"any","conditions":[
          {"field":"plays","days":30,"op":"gte","value":5},{"field":"last_played","op":"before","days":60},
          {"field":"added","days":14},{"field":"service","op":"not","value":"sc"},
          {"field":"artist","op":"is","value":"Muse"},{"field":"duration","op":"lte","value":180}],
          "sort":{"by":"last_played","desc":false},"limit":50}
        """
        let rules = try JSONDecoder().decode(SmartRules.self, from: Data(pc.utf8))
        XCTAssertEqual(rules.source, .playlist(id: "pl_1"))
        XCTAssertEqual(rules.match, .any)
        XCTAssertEqual(rules.conditions, [
            .plays(days: 30, op: .gte, value: 5), .lastPlayed(op: .before, days: 60), .added(days: 14),
            .service(op: .not, value: "sc"), .artist(op: .is, value: "Muse"), .duration(op: .lte, value: 180),
        ])
        XCTAssertEqual(rules.sort, SmartSort(by: .lastPlayed, desc: false))
        XCTAssertEqual(rules.limit, 50)

        let again = try JSONDecoder().decode(SmartRules.self, from: try JSONEncoder().encode(rules))
        XCTAssertEqual(again, rules)
    }

    func testJSONDefaultsAndUnknownField() throws {
        let short = try JSONDecoder().decode(SmartRules.self, from: Data(#"{"v":1,"source":{"kind":"liked"},"sort":{"by":"plays"}}"#.utf8))
        XCTAssertEqual(short.match, .all)
        XCTAssertTrue(short.conditions.isEmpty)
        XCTAssertEqual(short.sort?.desc, true, "по умолчанию — сначала больше")

        let unknown = #"{"v":1,"source":{"kind":"liked"},"conditions":[{"field":"mood","value":"sad"}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(SmartRules.self, from: Data(unknown.utf8)))
    }

    func testTemplatesAreValidAndMatchSpec() {
        XCTAssertEqual(SmartTemplate.all.map(\.id), ["forgotten", "month_top", "barely", "worn_out", "new_liked"])
        for template in SmartTemplate.all {
            XCTAssertNil(SmartEngine.problem(template.rules), template.id)
            XCTAssertEqual(template.rules.normalized, template.rules, "шаблон \(template.id) уже в границах")
        }
        let list = cands([makeTrack("sc:1", "A"), makeTrack("sc:2", "B")], added: [now - 100 * day, now - 2 * day])
        let h = history([("sc:1", now - 70 * day)] + (0 ..< 10).map { ("sc:2", now - $0 * day) })
        let byID = Dictionary(uniqueKeysWithValues: SmartTemplate.all.map { ($0.id, $0.rules) })
        XCTAssertEqual(refs(byID["forgotten"]!, list, h), ["sc:1"], "60+ дней не слушал")
        XCTAssertEqual(refs(byID["barely"]!, list, h), ["sc:1"], "2 раза и меньше")
        XCTAssertEqual(refs(byID["worn_out"]!, list, h), ["sc:2"], "10+ за 30 дней")
        XCTAssertEqual(refs(byID["new_liked"]!, list, h), ["sc:2"], "добавлен за 14 дней")
        XCTAssertEqual(refs(byID["month_top"]!, list, h), ["sc:2"])
    }

    // MARK: - Источники

    func testPlayedSourceOrderAndAddedIsFirstPlay() {
        let tracks = ["sc:1": makeTrack("sc:1", "A"), "sc:2": makeTrack("sc:2", "B"), "sc:3": makeTrack("sc:3", "C")]
        let h = history([("sc:1", now - 10 * day), ("sc:1", now - day), ("sc:2", now - day), ("sc:3", now - 5 * day), ("sc:9", now)])
        let list = SmartSources.candidates(.played, liked: [], likedAt: [:], playlists: [], played: tracks, history: h)
        XCTAssertEqual(list?.map(\.track.ref), ["sc:1", "sc:2", "sc:3"], "последние сверху, равные — по ref; без трека — пропуск")
        XCTAssertEqual(list?.first?.addedAt, now - 10 * day, "добавлен — первое прослушивание")
    }

    func testLikedSourceUsesLikedAt() {
        let liked = [makeTrack("sc:1", "A"), makeTrack("sc:2", "B")]
        let list = SmartSources.candidates(.liked, liked: liked, likedAt: ["sc:1": 42], playlists: [], played: [:],
                                           history: SmartHistory(rows: []))
        XCTAssertEqual(list?.map(\.addedAt), [42, 0], "дата лайка неизвестна — 0")
    }

    func testMissingPlaylistAndUnreadableRules() {
        let def = SmartPlaylistDef(id: "sm_1", name: "X", rules: .encode(SmartRules(source: .playlist(id: "gone"))), createdAt: 0, updatedAt: 0)
        let none = SmartHistory(rows: [])
        XCTAssertEqual(SmartSources.run(def, liked: [], likedAt: [:], playlists: [], played: [:], history: none, now: now), .sourceMissing)

        var newer = SmartRules.blank
        newer.v = 2
        let future = SmartPlaylistDef(id: "sm_2", name: "Y", rules: .encode(newer), createdAt: 0, updatedAt: 0)
        XCTAssertNil(future.parsed)
        XCTAssertEqual(SmartSources.run(future, liked: [], likedAt: [:], playlists: [], played: [:], history: none, now: now), .invalid)
    }
}

/// Хранилище умных плейлистов и даты лайков в `LibraryStore`.
@MainActor
final class SmartStoreTests: XCTestCase {
    func testCreateUpdateDeleteAndPersist() {
        let file = tempDirectory().appendingPathComponent("smart.json")
        let store = SmartPlaylistStore(file: file)
        store.now = { 1_000 }
        XCTAssertNil(store.create(name: "  ", rules: .blank), "пустое имя")
        XCTAssertNil(store.create(name: "X", rules: SmartRules(source: .playlist(id: ""))), "неверные правила")

        let id = store.create(name: " Топ ", rules: SmartTemplate.all[1].rules) ?? ""
        XCTAssertTrue(id.hasPrefix("sm_"))
        XCTAssertEqual(store.list(id)?.name, "Топ")
        XCTAssertEqual(store.list(id)?.parsed, SmartTemplate.all[1].rules)

        store.now = { 2_000 }
        XCTAssertTrue(store.update(id, name: "Новое", rules: .blank))
        XCTAssertFalse(store.update(id, name: "", rules: .blank))
        XCTAssertFalse(store.update("sm_nope", name: "A", rules: .blank))

        let again = SmartPlaylistStore(file: file)
        XCTAssertEqual(again.list(id)?.name, "Новое")
        XCTAssertEqual(again.list(id)?.createdAt, 1_000)
        XCTAssertEqual(again.list(id)?.updatedAt, 2_000)
        XCTAssertEqual(again.list(id)?.parsed, .blank)

        again.delete(id)
        XCTAssertTrue(SmartPlaylistStore(file: file).lists.isEmpty)
    }

    func testLikedAtFollowsLikes() {
        let file = tempDirectory().appendingPathComponent("library.json")
        let library = LibraryStore(file: file)
        library.now = { 7_000 }
        let track = makeTrack("sc:1", "A")
        library.toggleLike(track)
        XCTAssertEqual(library.likedAt["sc:1"], 7_000)
        XCTAssertEqual(LibraryStore(file: file).likedAt["sc:1"], 7_000, "дата лайка сохраняется")

        library.toggleLike(track)
        XCTAssertNil(library.likedAt["sc:1"])

        library.applySynced(liked: [track], likedAt: ["sc:1": 9_000, "sc:2": 1])
        XCTAssertEqual(library.likedAt, ["sc:1": 9_000], "только для того, что в Любимых")
    }

    func testRunnerUsesPlaylistCreation() {
        let playlists = PlaylistStore(file: tempDirectory().appendingPathComponent("collections.json"))
        let pid = playlists.create(name: "Мой", tracks: [makeTrack("sc:1", "A"), makeTrack("sc:2", "B")]) ?? ""
        let created = playlists.playlist(pid)?.createdAt ?? 0
        let rules = SmartRules(source: .playlist(id: pid), sort: SmartSort(by: .title, desc: true))
        let def = SmartPlaylistDef(id: "sm_1", name: "X", rules: .encode(rules), createdAt: 0, updatedAt: 0)
        let list = SmartSources.candidates(rules.source, liked: [], likedAt: [:], playlists: playlists.playlists, played: [:],
                                           history: SmartHistory(rows: []))
        XCTAssertEqual(list?.map(\.addedAt), [created, created])
        let outcome = SmartSources.run(def, liked: [], likedAt: [:], playlists: playlists.playlists, played: [:],
                                       history: SmartHistory(rows: []), now: created)
        XCTAssertEqual(outcome.tracks.map(\.ref), ["sc:2", "sc:1"])
    }
}
