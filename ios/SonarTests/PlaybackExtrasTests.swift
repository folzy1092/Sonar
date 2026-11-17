import XCTest
@testable import Sonar

/// Кроссфейд двумя деками, нормализация по R128, таймер сна, офлайн-кэш волны и «Почему этот трек»
/// (`Playback/PlayerExtras.swift`, `MyWave`).
@MainActor
final class PlaybackExtrasTests: XCTestCase {
    // MARK: - Нормализация

    func testLoudnessCutsLoudTracksOnly() {
        // −8 LUFS → на 6 дБ тише цели −14
        XCTAssertEqual(Loudness.gainDb(lufs: -8, enabled: true), -6, accuracy: 1e-9)
        XCTAssertEqual(Loudness.gain(lufs: -8, enabled: true), pow(10, -6.0 / 20), accuracy: 1e-9)
        // тише цели — громкость плеера выше 1 не бывает, остаётся 1
        XCTAssertEqual(Loudness.gain(lufs: -20, enabled: true), 1)
        // выключено, нет данных, мусор — 1
        XCTAssertEqual(Loudness.gain(lufs: -3, enabled: false), 1)
        XCTAssertEqual(Loudness.gain(lufs: nil, enabled: true), 1)
        XCTAssertEqual(Loudness.gain(lufs: .nan, enabled: true), 1)
        XCTAssertEqual(Loudness.gain(lufs: 2, enabled: true), 1, "положительная громкость — ошибка данных")
        // предел −12 дБ
        XCTAssertEqual(Loudness.gainDb(lufs: -0.5, enabled: true), -12, accuracy: 1e-9)
    }

    func testYandexTrackKeepsR128() throws {
        let json = try JSONValue(data: Data(#"""
        {"id": "5", "title": "Loud", "durationMs": 1000, "artists": [{"id": 1, "name": "A"}], "r128": {"i": -7.5, "tp": 0.4}}
        """#.utf8))
        XCTAssertEqual(try XCTUnwrap(Yandex.parseTrack(json)).loudness, -7.5)
        let plain = try JSONValue(data: Data(#"{"id": "6", "title": "Q", "artists": []}"#.utf8))
        XCTAssertNil(try XCTUnwrap(Yandex.parseTrack(plain)).loudness)
    }

    func testTrackDecodesWithoutLoudness() throws {
        // старые снимки очереди и Любимые без поля — читаются
        let data = Data(#"""
        {"ref": "sc:1", "title": "t", "artist": "a", "artists": [], "duration_ms": 1, "explicit": false, "available": true}
        """#.utf8)
        let track = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertNil(track.loudness)
        var loud = track
        loud.loudness = -9
        let back = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(loud))
        XCTAssertEqual(back.loudness, -9)
    }

    // MARK: - Кроссфейд двумя деками

    func testOverlapSpanAndEqualPower() {
        XCTAssertEqual(Fades.overlapSpan(seconds: 6, outgoing: 200, incoming: 180), 6)
        XCTAssertEqual(Fades.overlapSpan(seconds: 12, outgoing: 200, incoming: 15), 5, "короткий следующий — не больше трети")
        XCTAssertEqual(Fades.overlapSpan(seconds: 12, outgoing: 9, incoming: 200), 3)
        XCTAssertEqual(Fades.overlapSpan(seconds: 0, outgoing: 200, incoming: 200), 0, "0 — бесшовно, без наложения")
        XCTAssertEqual(Fades.overlapSpan(seconds: 6, outgoing: 0, incoming: 0), 6, "длительность неизвестна — как задано")

        XCTAssertEqual(Fades.crossIn(0), 0, accuracy: 1e-9)
        XCTAssertEqual(Fades.crossIn(1), 1, accuracy: 1e-9)
        XCTAssertEqual(Fades.crossOut(0), 1, accuracy: 1e-9)
        XCTAssertEqual(Fades.crossOut(1), 0, accuracy: 1e-9)
        XCTAssertEqual(Fades.crossIn(2), 1, accuracy: 1e-9, "за пределами — край")
        // равная мощность: сумма квадратов — 1 на всём переходе
        for t in stride(from: 0.0, through: 1, by: 0.1) {
            XCTAssertEqual(pow(Fades.crossIn(t), 2) + pow(Fades.crossOut(t), 2), 1, accuracy: 1e-9)
        }
    }

    // MARK: - Таймер сна

    func testSleepTimerMinutesFadeAndDue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let timer = SleepTimer(.minutes(15), now: now)
        XCTAssertFalse(timer.isEndOfTrack)
        XCTAssertEqual(timer.remaining(now: now), 900)
        XCTAssertFalse(timer.isDue(now: now))
        XCTAssertEqual(timer.factor(now: now, position: 0, duration: 200), 1)
        // за 15 с до конца — половина пути затухания (30 с), квадрат — 0.25
        XCTAssertEqual(timer.factor(now: now.addingTimeInterval(885), position: 0, duration: 200), 0.25, accuracy: 1e-9)
        XCTAssertEqual(timer.factor(now: now.addingTimeInterval(900), position: 0, duration: 200), 0, accuracy: 1e-9)
        XCTAssertTrue(timer.isDue(now: now.addingTimeInterval(900)))
        XCTAssertEqual(timer.remaining(now: now.addingTimeInterval(1000)), 0, "не уходит в минус")
    }

    func testSleepTimerEndOfTrack() {
        let timer = SleepTimer(.endOfTrack)
        XCTAssertTrue(timer.isEndOfTrack)
        XCTAssertNil(timer.remaining(now: Date()))
        XCTAssertFalse(timer.isDue(now: .distantFuture), "кончается вместе с треком, не по часам")
        XCTAssertEqual(timer.factor(now: Date(), position: 100, duration: 200), 1)
        XCTAssertEqual(timer.factor(now: Date(), position: 194, duration: 200), 0.25, accuracy: 1e-9, "6 из 12 с")
        XCTAssertEqual(timer.factor(now: Date(), position: 200, duration: 200), 0, accuracy: 1e-9)
        // короткий трек: затухание не длиннее трети
        XCTAssertEqual(timer.factor(now: Date(), position: 7, duration: 9), 4.0 / 9, accuracy: 1e-9, "2 из 3 с")
        XCTAssertEqual(timer.factor(now: Date(), position: 0, duration: 0), 1, "длительность неизвестна")
    }

    func testSleepOptionsAndLabel() {
        XCTAssertEqual(SleepOption.all, [.minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfTrack])
        XCTAssertEqual(Set(SleepOption.all.map(\.id)).count, SleepOption.all.count)
        XCTAssertEqual(SleepOption.minutes(30).title, "30 мин")
        XCTAssertEqual(SleepTimer.label(65), "1:05")
        XCTAssertEqual(SleepTimer.label(0.2), "0:01", "округление вверх — ноль только в самом конце")
        XCTAssertEqual(SleepTimer.label(3600), "1:00:00")
    }

    // MARK: - Офлайн-кэш волны

    func testWaveCachePlanFetchesAheadAndEvictsPlayed() {
        let upcoming = (1 ... 20).map { "sc:\($0)" }
        let plan = WaveCachePlan.plan(upcoming: upcoming, current: "sc:0", cached: ["sc:0", "sc:-1", "sc:2"],
                                      downloaded: ["sc:3"], attempted: ["sc:4"], enabled: true)
        XCTAssertEqual(plan.fetch.first, "sc:1")
        XCTAssertFalse(plan.fetch.contains("sc:2"), "уже в кэше")
        XCTAssertFalse(plan.fetch.contains("sc:3"), "скачан вручную — играет из загрузок")
        XCTAssertFalse(plan.fetch.contains("sc:4"), "уже пробовали")
        XCTAssertFalse(plan.fetch.contains("sc:16"), "только 15 вперёд")
        XCTAssertEqual(plan.fetch.count, 12)
        XCTAssertEqual(plan.evict, ["sc:-1"], "сыгранное уходит, текущий и «Далее» остаются")
    }

    func testWaveCachePlanDisabledClearsEverything() {
        let plan = WaveCachePlan.plan(upcoming: ["sc:1"], current: nil, cached: ["sc:1", "sc:2"], downloaded: [],
                                      attempted: [], enabled: false)
        XCTAssertTrue(plan.fetch.isEmpty)
        XCTAssertEqual(plan.evict, ["sc:1", "sc:2"])
        XCTAssertEqual(WaveCachePlan.plan(upcoming: ["sc:1", "sc:1"], current: nil, cached: [], downloaded: [], attempted: [],
                                          enabled: true).fetch, ["sc:1"], "без повторов")
    }

    func testNextPlayableOffline() {
        let refs = ["a", "b", "c", "d"]
        XCTAssertEqual(WaveCachePlan.nextPlayable(from: 0, refs: refs, isLocal: { $0 == "c" }), 2)
        XCTAssertNil(WaveCachePlan.nextPlayable(from: 0, refs: refs, isLocal: { _ in false }))
        XCTAssertNil(WaveCachePlan.nextPlayable(from: 3, refs: refs, isLocal: { _ in true }), "дальше ничего нет")
    }

    // MARK: - «Почему этот трек»

    func testWaveReasonTexts() {
        let liked = makeTrack("sc:l", "Fav", title: "Любимая")
        let live = makeTrack("sc:g", "Now", title: "Зашла")
        let finished = makeTrack("sc:f", "Old", title: "Дослушанная")
        var c = WaveReason.Context(seedOf: ["sc:1": "sc:l", "sc:2": "sc:g", "sc:3": "sc:f", "sc:4": "sca:9"],
                                   likes: ["sc:l", "sc:liked"], forgotten: ["sc:old"], live: ["sc:g"])
        c.tracks = ["sc:l": liked, "sc:g": live, "sc:f": finished]
        c.artistNames = ["sca:9": "Кино"]
        XCTAssertEqual(WaveReason.text(for: makeTrack("sc:1", "X"), known: true, c), "Ты лайкал «Любимая» — этот похож")
        XCTAssertEqual(WaveReason.text(for: makeTrack("sc:2", "X"), known: true, c), "Похож на «Зашла» — он зашёл сейчас")
        XCTAssertEqual(WaveReason.text(for: makeTrack("sc:3", "X"), known: true, c), "Похож на «Дослушанная»")
        XCTAssertEqual(WaveReason.text(for: makeTrack("sc:4", "Кино"), known: true, c), "Популярное у Кино — ты его слушаешь")
        XCTAssertEqual(WaveReason.text(for: makeTrack("sc:old", "Y"), known: true, c), "Из твоих Любимых — давно не звучал")
        XCTAssertEqual(WaveReason.text(for: makeTrack("sc:liked", "Y"), known: true, c), "Из твоих Любимых")
        XCTAssertEqual(WaveReason.text(for: makeTrack("sc:x", "Y"), known: false, c), "Новый для тебя артист")
        XCTAssertEqual(WaveReason.text(for: makeTrack("sc:x", "Y"), known: true, c), "Подобрано по твоему вкусу")

        c.mode = .new
        XCTAssertEqual(WaveReason.text(for: makeTrack("sc:3", "X"), known: false, c), "Новый для тебя артист · похож на «Дослушанная»")
        c.mode = .calm
        let chill = makeTrack("sc:3", "X", title: "lofi chill")
        XCTAssertEqual(WaveReason.text(for: chill, known: true, c), "Спокойная · похож на «Дослушанная»")
        c.waveSeed = "sc:f"
        XCTAssertEqual(WaveReason.text(for: finished, known: true, c), "С него началась волна")
    }

    func testMyWaveExplainsEveryServedTrack() async throws {
        let dir = tempDirectory()
        let library = LibraryStore(file: dir.appendingPathComponent("library.json"))
        let history = PlayHistory(file: dir.appendingPathComponent("history.json"))
        let source = FakeSource()
        let liked = makeTrack("sc:liked", "Fav", title: "Любимая")
        library.toggleLike(liked)
        source.similarByRef["sc:liked"] = (0 ..< 30).map { makeTrack("sc:s\($0)", "Artist\($0 % 15)", plays: 10_000) }
        let wave = MyWave(source: source, library: library, history: history, random: { 0 })
        let first = try await wave.start(seed: nil)
        XCTAssertFalse(first.isEmpty)
        for track in first {
            XCTAssertNotNil(wave.reasons[track.ref], track.ref)
        }
        let similar = try XCTUnwrap(first.first { $0.ref.hasPrefix("sc:s") })
        XCTAssertEqual(wave.reasons[similar.ref], "Ты лайкал «Любимая» — этот похож")

        let seed = makeTrack("ym:seed", "Seed", title: "Старт")
        source.similarByRef["ym:seed"] = (0 ..< 12).map { makeTrack("ym:s\($0)", "A\($0)") }
        let byTrack = try await wave.start(seed: seed)
        XCTAssertEqual(wave.reasons["ym:seed"], "С него началась волна")
        let next = try XCTUnwrap(byTrack.dropFirst().first)
        XCTAssertEqual(wave.reasons[next.ref], "Похож на «Старт»")
    }
}
