import XCTest
@testable import Sonar

/// «Моя волна»: сиды, отбор порции, сигналы сессии и сама волна на заглушке сервисов.
@MainActor
final class WaveTests: XCTestCase {
    private let zero: () -> Double = { 0 }

    private func candidates(_ artists: [String], prefix: String = "sc:c", plays: Int? = 5000) -> [Track] {
        artists.enumerated().map { makeTrack("\(prefix)\($0.offset)", $0.element, plays: plays) }
    }

    // MARK: - Сиды

    func testSeedsByTrackKeepStyleAndLearn() {
        let seed = makeTrack("sc:seed", "S")
        let good = [makeTrack("sc:g1", "A"), makeTrack("sc:g2", "B"), makeTrack("sc:g3", "C")]
        XCTAssertEqual(WaveMath.seeds(seed: seed, good: good, likes: ["sc:l"], finished: [], recent: [], random: zero),
                       ["sc:seed", "sc:g3", "sc:g2"])
    }

    func testSeedsAtStartFromLikesFinishedThenRecent() {
        let likes = (0 ..< 20).map { "sc:l\($0)" }
        let seeds = WaveMath.seeds(seed: nil, good: [], likes: likes, finished: ["sc:f"], recent: [], random: zero)
        XCTAssertEqual(seeds.count, 6, "5 свежих + 1 старый лайк")
        XCTAssertTrue(seeds.contains("sc:l15"), "старый лайк для разведки")
        XCTAssertEqual(Set(seeds).count, seeds.count)
        XCTAssertEqual(WaveMath.seeds(seed: nil, good: [], likes: [], finished: [], recent: ["sc:r1", "sc:r2"], random: zero).sorted(),
                       ["sc:r1", "sc:r2"])
        XCTAssertTrue(WaveMath.seeds(seed: nil, good: [], likes: [], finished: [], recent: [], random: zero).isEmpty)
    }

    func testSeedsDuringSessionStartFromWhatWorked() {
        let good = [makeTrack("sc:g1", "A"), makeTrack("sc:g2", "B")]
        let seeds = WaveMath.seeds(seed: nil, good: good, likes: ["sc:l1", "sc:l2", "sc:l3"], finished: [], recent: [], random: zero)
        XCTAssertEqual(Array(seeds.prefix(2)), ["sc:g2", "sc:g1"])
        XCTAssertEqual(seeds.count, 4)
    }

    // MARK: - Порция

    func testPickRespectsFiltersAndVariety() {
        let artists = ["A", "A", "A", "B", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K"]
        var cands = candidates(artists)
        cands.append(makeTrack("sc:banned", "Z", plays: 5000))
        cands.append(makeTrack("sc:gone", "Y", plays: 5000, available: false))
        cands.append(makeTrack("sc:paused", "P", plays: 5000))
        let filter = WaveFilter(banned: ["sc:banned"], pausedArtists: ["p"])
        let out = WaveMath.pick(cands, taste: Taste(), origin: WaveOrigin(), session: WaveSession(), filter: filter, noise: zero)
        XCTAssertEqual(out.count, 10)
        XCTAssertFalse(out.contains { ["sc:banned", "sc:gone", "sc:paused"].contains($0.ref) })
        XCTAssertLessThanOrEqual(out.filter { $0.artistKey == "a" }.count, 2, "≤ 2 трека артиста в порции")
        for (x, y) in zip(out, out.dropFirst()) { XCTAssertNotEqual(x.artistKey, y.artistKey, "не два подряд") }
    }

    func testPickSkipsRecentUnlessRelaxed() {
        let cands = candidates(["A", "B"])
        let filter = WaveFilter(recent: ["sc:c0"])
        XCTAssertEqual(WaveMath.pick(cands, taste: Taste(), origin: WaveOrigin(), session: WaveSession(), filter: filter, noise: zero).map(\.ref),
                       ["sc:c1"])
        XCTAssertEqual(WaveMath.pick(cands, taste: Taste(), origin: WaveOrigin(), session: WaveSession(), filter: filter, relaxed: true,
                                     noise: zero).count, 2)
    }

    func testSessionArtistCapAndUnknownLimit() {
        var session = WaveSession()
        for i in 0 ..< 4 { session.serve(makeTrack("sc:s\(i)", "A")) }
        let cands = candidates(["A", "B"])
        let out = WaveMath.pick(cands, taste: Taste(), origin: WaveOrigin(), session: session, filter: WaveFilter(), noise: zero)
        XCTAssertEqual(out.map(\.artistKey), ["b"], "четыре за сессию — хватит")

        var taste = Taste()
        taste.likedArtists = ["known"]
        let mixed = candidates(["U1", "U2", "U3", "U4", "Known", "U5"])
        let limited = WaveMath.pick(mixed, taste: taste, origin: WaveOrigin(), session: WaveSession(),
                                    filter: WaveFilter(maxUnknown: 2), noise: zero)
        XCTAssertEqual(limited.filter { !taste.isKnown($0) }.count, 2)
        XCTAssertTrue(limited.contains { $0.artistKey == "known" })
        // знакомого мало — запасной проход снимает лимит
        let open = WaveMath.portion(mixed, taste: taste, origin: WaveOrigin(), session: WaveSession(),
                                    filter: WaveFilter(maxUnknown: 2), noise: zero)
        XCTAssertEqual(open.count, 6)
    }

    func testUnknownSoundCloudWithFewPlaysDropped() {
        let cands = [makeTrack("sc:few", "U", plays: 50), makeTrack("sc:many", "V", plays: 50_000), makeTrack("ym:1", "W", plays: nil)]
        let out = WaveMath.pick(cands, taste: Taste(), origin: WaveOrigin(), session: WaveSession(),
                                filter: WaveFilter(minPlaysUnknown: 1000), noise: zero)
        XCTAssertEqual(Set(out.map(\.ref)), ["sc:many", "ym:1"])
    }

    func testScorePrefersLikedArtistAndPenalizesSkips() {
        var taste = Taste()
        taste.likedArtists = ["fav"]
        taste.trackSkips = ["sc:bad": 2]
        let session = WaveSession()
        let fav = makeTrack("sc:1", "Fav")
        let other = makeTrack("sc:2", "Other")
        let bad = makeTrack("sc:bad", "Other2")
        XCTAssertGreaterThan(WaveMath.score(fav, taste: taste, origin: WaveOrigin(), session: session),
                             WaveMath.score(other, taste: taste, origin: WaveOrigin(), session: session))
        XCTAssertLessThan(WaveMath.score(bad, taste: taste, origin: WaveOrigin(), session: session),
                          WaveMath.score(other, taste: taste, origin: WaveOrigin(), session: session))
        var origin = WaveOrigin()
        origin.add(seed: "s1", list: [other], live: false)
        origin.add(seed: "s2", list: [other], live: false)
        XCTAssertGreaterThan(WaveMath.score(other, taste: taste, origin: origin, session: session),
                             WaveMath.score(other, taste: taste, origin: WaveOrigin(), session: session), "голоса сидов")
    }

    func testSeedCapIsSoft() {
        var origin = WaveOrigin()
        let fromOne = candidates(["A", "B", "C", "D", "E", "F"])
        origin.add(seed: "s1", list: fromOne, live: false)
        let out = WaveMath.pick(fromOne, taste: Taste(), origin: origin, session: WaveSession(), filter: WaveFilter(), n: 6, noise: zero)
        XCTAssertEqual(out.count, 6, "один сид — второй проход добирает без лимита")
    }

    func testInsertLikedAtSlots() {
        let portion = candidates(["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"])
        let liked = [makeTrack("sc:l1", "L1"), makeTrack("sc:l2", "L2"), makeTrack("sc:l3", "L3")]
        let out = WaveMath.insertLiked(portion, liked: liked)
        XCTAssertEqual(out.count, 10)
        XCTAssertEqual(out[2].ref, "sc:l1")
        XCTAssertEqual(out[5].ref, "sc:l2")
        XCTAssertEqual(out[8].ref, "sc:l3")
        // тот же артист рядом — место сдвигается
        let same = WaveMath.insertLiked(portion, liked: [makeTrack("sc:l", "C")])
        XCTAssertNotEqual(same[2].ref, "sc:l")
        XCTAssertTrue(same.contains { $0.ref == "sc:l" })
    }

    func testPickLikedForgottenOnly() {
        let liked = [makeTrack("sc:1", "A"), makeTrack("sc:2", "A"), makeTrack("sc:3", "B"), makeTrack("sc:4", "C")]
        let out = WaveMath.pickLiked(liked, taste: Taste(), session: WaveSession(), filter: WaveFilter(banned: ["sc:4"]),
                                     playedMonth: ["sc:3"], k: 3, noise: zero)
        XCTAssertEqual(out.map(\.artistKey), ["a"], "слушанный за месяц, 👎 и второй трек артиста — мимо")
    }

    // MARK: - Сессия

    func testTwoEarlySkipsPauseArtistAndSeriesRebuilds() {
        var session = WaveSession()
        let now = Date()
        let a1 = makeTrack("sc:1", "A")
        let a2 = makeTrack("sc:2", "A")
        XCTAssertFalse(session.ended(a1, reward: -1, manualSkip: true, now: now))
        XCTAssertTrue(session.ended(a2, reward: -1, manualSkip: true, now: now), "две ранних подряд — пересобрать")
        XCTAssertTrue(session.paused.contains("a"))
        XCTAssertTrue(session.skippedArtists.contains("a"))
        // кулдаун минута
        XCTAssertFalse(session.ended(makeTrack("sc:3", "B"), reward: -1, manualSkip: true, now: now))
        XCTAssertFalse(session.ended(makeTrack("sc:4", "C"), reward: -1, manualSkip: true, now: now + 10))
        XCTAssertTrue(session.ended(makeTrack("sc:5", "D"), reward: -1, manualSkip: true, now: now + 61))
        // зашло — сид и снят минус
        _ = session.ended(makeTrack("sc:6", "A"), reward: 1, manualSkip: false, now: now)
        XCTAssertEqual(session.good.map(\.ref), ["sc:6"])
        XCTAssertFalse(session.skippedArtists.contains("a"))
    }

    func testSoftSkipBreaksSeries() {
        var series = SkipSeries()
        let now = Date()
        XCTAssertFalse(series.push(-1, skipped: true, now: now))
        XCTAssertFalse(series.push(-0.4, skipped: true, now: now))
        XCTAssertFalse(series.push(-1, skipped: true, now: now))
        XCTAssertTrue(series.push(-2, skipped: true, now: now), "👎 — тоже ранний")
    }

    func testServeUnserve() {
        var session = WaveSession()
        let track = makeTrack("sc:1", "A")
        session.serve(track)
        XCTAssertEqual(session.servedCount["a"], 1)
        session.unserve(track)
        XCTAssertTrue(session.served.isEmpty)
        XCTAssertNil(session.servedCount["a"])
    }

    // MARK: - Волна целиком (заглушка сервисов)

    private func setup() -> (FakeSource, LibraryStore, PlayHistory) {
        let dir = tempDirectory()
        let library = LibraryStore(file: dir.appendingPathComponent("library.json"))
        let history = PlayHistory(file: dir.appendingPathComponent("history.json"))
        return (FakeSource(), library, history)
    }

    func testMyWaveStartsFromLikesWithoutDislikes() async throws {
        let (source, library, history) = setup()
        let liked = makeTrack("sc:liked", "Fav")
        library.toggleLike(liked)
        let similar = (0 ..< 30).map { makeTrack("sc:s\($0)", "Artist\($0 % 15)", plays: 10_000) }
        source.similarByRef["sc:liked"] = similar
        library.toggleDislike(similar[0])
        let wave = MyWave(source: source, library: library, history: history, random: { 0 })
        let first = try await wave.start(seed: nil)
        XCTAssertEqual(first.count, 10)
        XCTAssertFalse(first.contains { $0.ref == "sc:s0" }, "👎 не попадает")
        XCTAssertEqual(Set(first.map(\.ref)).count, first.count)
        let more = try await wave.more()
        XCTAssertTrue(Set(more.map(\.ref)).isDisjoint(with: first.map(\.ref)), "следующая порция без выданного")
    }

    func testWaveByTrackPlaysSeedFirst() async throws {
        let (source, library, history) = setup()
        let seed = makeTrack("ym:seed", "Seed")
        source.similarByRef["ym:seed"] = (0 ..< 12).map { makeTrack("ym:s\($0)", "A\($0)") }
        let wave = MyWave(source: source, library: library, history: history, random: { 0 })
        let list = try await wave.start(seed: seed)
        XCTAssertEqual(list.first?.ref, "ym:seed")
        XCTAssertEqual(list.filter { $0.ref == "ym:seed" }.count, 1)
        XCTAssertGreaterThan(list.count, 5)
    }

    func testWaveWithNothingToStartFromIsAnError() async {
        let (source, library, history) = setup()
        let wave = MyWave(source: source, library: library, history: history)
        do {
            _ = try await wave.start(seed: nil)
            XCTFail("без Любимых и истории волне не от чего оттолкнуться")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("не от чего"))
        }
    }

    func testWaveOfflineIsAnError() async {
        let (source, library, history) = setup()
        library.toggleLike(makeTrack("sc:1", "A"))
        source.failAll = true
        let wave = MyWave(source: source, library: library, history: history)
        do {
            _ = try await wave.start(seed: nil)
            XCTFail("сеть не ответила")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testFavoriteArtistRefs() {
        let liked = [makeTrack("sc:1", "A", artistRef: "sca:1"), makeTrack("sc:2", "A", artistRef: "sca:1"),
                     makeTrack("sc:3", "Z", artistRef: "sca:0")]
        let recent = [makeTrack("ym:1", "B", artistRef: "yma:2")]
        XCTAssertEqual(WaveMath.favoriteArtistRefs(liked: liked, recent: recent, limit: 5), ["sca:1", "yma:2"])
    }

    // MARK: - Режимы

    private func tagged(_ ref: String, _ tags: String?, title: String = "Song") -> Track {
        var track = makeTrack(ref, "A", title: title)
        track.tags = tags
        return track
    }

    func testModesListLikeWindows() {
        XCTAssertEqual(WaveMode.allCases.map(\.rawValue), ["own", "hard", "calm", "sad", "fun", "new"])
        XCTAssertEqual(WaveMode.allCases.map(\.title), ["Своя", "Жёсткая", "Спокойная", "Грустная", "Весёлая", "Незнакомое"])
        XCTAssertEqual(WaveMode.hard.subtitle, "фонк, рэйдж, рок")
        XCTAssertEqual(WaveMode.new.next, .own)
        XCTAssertEqual(SettingsStore.defaults["wave.mode"], .string("own"))
    }

    func testMoodFit() {
        let phonk = tagged("sc:1", "phonk drift")
        let lofi = tagged("sc:2", "lofi chill")
        let plain = tagged("sc:3", nil, title: "Untitled")
        let sadTitle = tagged("sc:4", nil, title: "грустная песня (slowed + reverb)")
        XCTAssertGreaterThan(WaveMath.moodFit(.hard, phonk), 0)
        XCTAssertEqual(WaveMath.moodFit(.hard, phonk), 1.9, accuracy: 1e-9, "два совпадения: 1.6 + 0.3")
        XCTAssertLessThan(WaveMath.moodFit(.hard, lofi), 0, "похож на другое настроение")
        XCTAssertGreaterThan(WaveMath.moodFit(.calm, lofi), 0)
        XCTAssertEqual(WaveMath.moodFit(.sad, plain), 0, "ничего не известно")
        XCTAssertGreaterThan(WaveMath.moodFit(.sad, sadTitle), 0, "по названию тоже")
        XCTAssertLessThan(WaveMath.moodFit(.fun, sadTitle), 0)
        XCTAssertEqual(WaveMath.moodFit(.own, phonk), 0, "«Своя» — без настроения")
        XCTAssertEqual(WaveMath.moodFit(.new, phonk), 0)
    }

    func testMoodModePrefersFittingTracks() {
        var session = WaveSession()
        session.mode = .calm
        let calm = tagged("sc:1", "ambient piano")
        let hard = tagged("sc:2", "phonk")
        XCTAssertGreaterThan(WaveMath.score(calm, taste: Taste(), origin: WaveOrigin(), session: session),
                             WaveMath.score(hard, taste: Taste(), origin: WaveOrigin(), session: session))
        // подходящих хватает — неподходящие мимо совсем
        var cands = (0 ..< 30).map { i -> Track in
            var t = makeTrack("sc:c\(i)", "Artist\(i)", plays: 5000)
            t.tags = "chill"
            return t
        }
        var loud = makeTrack("sc:loud", "Loud", plays: 5000)
        loud.tags = "metal"
        cands.insert(loud, at: 0)
        let out = WaveMath.pick(cands, taste: Taste(), origin: WaveOrigin(), session: session, filter: WaveFilter(), noise: zero)
        XCTAssertFalse(out.contains { $0.ref == "sc:loud" })
    }

    func testNewModeAvoidsKnownArtists() {
        var taste = Taste()
        taste.likedArtists = ["fav"]
        var session = WaveSession()
        session.mode = .new
        let fav = makeTrack("sc:1", "Fav")
        let stranger = makeTrack("sc:2", "Stranger")
        XCTAssertGreaterThan(WaveMath.score(stranger, taste: taste, origin: WaveOrigin(), session: session),
                             WaveMath.score(fav, taste: taste, origin: WaveOrigin(), session: session))
        session.mode = .own
        XCTAssertGreaterThan(WaveMath.score(fav, taste: taste, origin: WaveOrigin(), session: session),
                             WaveMath.score(stranger, taste: taste, origin: WaveOrigin(), session: session))
        XCTAssertNil(WaveMath.familiarity(.new, bySeed: false).maxUnknown)
        XCTAssertEqual(WaveMath.familiarity(.own, bySeed: false).maxUnknown, 3)
        XCTAssertEqual(WaveMath.familiarity(.sad, bySeed: false).maxUnknown, 4)
        XCTAssertEqual(WaveMath.familiarity(.own, bySeed: true).maxUnknown, 5)
        XCTAssertEqual(WaveMath.likedShare(.own, bySeed: false), 3)
        XCTAssertEqual(WaveMath.likedShare(.fun, bySeed: false), 2)
        XCTAssertEqual(WaveMath.likedShare(.new, bySeed: false), 0)
        XCTAssertEqual(WaveMath.likedShare(.own, bySeed: true), 0)
    }

    func testNewModeExploresSecondHop() async throws {
        let dir = tempDirectory()
        let library = LibraryStore(file: dir.appendingPathComponent("library.json"))
        let history = PlayHistory(file: dir.appendingPathComponent("history.json"))
        let source = FakeSource()
        library.toggleLike(makeTrack("sc:liked", "Fav"))
        source.similarByRef["sc:liked"] = [makeTrack("sc:u1", "Stranger1"), makeTrack("sc:f2", "Fav")]
        source.similarByRef["sc:u1"] = (0 ..< 12).map { makeTrack("sc:h\($0)", "Hop\($0)") }
        let wave = MyWave(source: source, library: library, history: history, random: { 0 })
        let list = try await wave.start(seed: nil, mode: .new)
        XCTAssertTrue(list.contains { $0.ref.hasPrefix("sc:h") }, "второй шаг от незнакомого")
        XCTAssertEqual(list.first?.artistKey == "fav", false, "знакомое — в конце, если вообще")
        XCTAssertFalse(list.contains { $0.ref == "sc:liked" }, "в «Незнакомом» своих лайков нет")
    }
}
