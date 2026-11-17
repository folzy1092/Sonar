import XCTest
@testable import Sonar

/// «Статистика»: журнал прослушиваний (`PlayLog`) и подсчёт (`StatsEngine`) — те же правила, что
/// Windows `store/stats.rs`.
final class StatsTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    /// 2026-11-17 12:00 UTC — вторник.
    private let now = Date(timeIntervalSince1970: 1_794_916_800)

    private func row(_ ref: String, _ artist: String, daysAgo: Double, hour: Int? = nil, ms: Int = 180_000) -> PlayRow {
        var date = now.addingTimeInterval(-daysAgo * 86_400)
        if let hour {
            let day = utc.startOfDay(for: date)
            date = day.addingTimeInterval(Double(hour) * 3600 + 60)
        }
        return PlayRow(ref: ref, artist: artist, at: date, ms: ms)
    }

    func testCalendarHelpers() {
        XCTAssertEqual(utc.component(.weekday, from: now), 3) // вторник
        XCTAssertEqual(StatsEngine.mondayIndex(3), 1)
        XCTAssertEqual(StatsEngine.mondayIndex(1), 6) // воскресенье
        XCTAssertEqual(StatsEngine.mondayIndex(2), 0)
        XCTAssertNil(StatsEngine.argmax([0, 0]))
        XCTAssertEqual(StatsEngine.argmax([1, 3, 3]), 1)
    }

    func testStreakCountsBackFromTodayOrYesterday() {
        let today = utc.startOfDay(for: now)
        let day = { (n: Int) in self.utc.date(byAdding: .day, value: -n, to: today)! }
        let days: Set<Date> = [day(0), day(1), day(2), day(4)]
        XCTAssertEqual(StatsEngine.streak(days, today: today, calendar: utc), 3)
        XCTAssertEqual(StatsEngine.streak([day(1), day(2)], today: today, calendar: utc), 2)
        XCTAssertEqual(StatsEngine.streak([day(2)], today: today, calendar: utc), 0)
    }

    func testTotalsTopsAndDelta() {
        let tracks = ["sc:1": makeTrack("sc:1", "Alpha"), "sc:2": makeTrack("sc:2", "Beta"), "sc:3": makeTrack("sc:3", "alpha")]
        let rows = [
            row("sc:1", "Alpha", daysAgo: 1, hour: 22),
            row("sc:1", "Alpha", daysAgo: 2, hour: 22),
            row("sc:2", "Beta", daysAgo: 2, hour: 9, ms: 60_000),
            row("sc:3", "alpha", daysAgo: 3, hour: 22),
            // прошлая неделя — только для «к прошлому периоду»
            row("sc:2", "Beta", daysAgo: 10, ms: 300_000),
        ]
        let s = StatsEngine.compute(rows: rows, tracks: tracks, period: .week, now: now, calendar: utc)
        XCTAssertEqual(s.plays, 4)
        XCTAssertEqual(s.trackCount, 3)
        XCTAssertEqual(s.artistCount, 2) // Alpha и alpha — один артист
        XCTAssertEqual(s.totalMs, 600_000)
        XCTAssertEqual(s.totalMinutes, 10)
        XCTAssertEqual(s.deltaPct, 100) // 600 к 300
        XCTAssertEqual(s.artists.first?.name, "Alpha")
        XCTAssertEqual(s.artists.first?.plays, 3)
        XCTAssertEqual(s.artists.first?.ref, "sca:alpha")
        XCTAssertEqual(s.tracks.first?.track.ref, "sc:1")
        XCTAssertEqual(s.tracks.first?.plays, 2)
        XCTAssertEqual(s.peakHour, 22)
        XCTAssertEqual(s.hours[9], 1)
        XCTAssertEqual(s.perDay, 1) // 4 прослушивания за 3 дня
        XCTAssertEqual(s.streakDays, 3) // сегодня не слушал — серия от вчера: 3 дня
        XCTAssertEqual(s.buckets.count, 7)
        XCTAssertEqual(s.buckets.last?.start, utc.startOfDay(for: now))
        XCTAssertEqual(s.buckets.reduce(0) { $0 + $1.ms }, 600_000)
    }

    func testStreakUsesAllTimeEvenForShortPeriod() {
        let rows = [row("sc:1", "A", daysAgo: 0), row("sc:1", "A", daysAgo: 1), row("sc:1", "A", daysAgo: 2)]
        let s = StatsEngine.compute(rows: rows, tracks: [:], period: .week, now: now, calendar: utc)
        XCTAssertEqual(s.streakDays, 3)
        XCTAssertTrue(s.tracks.isEmpty) // трека нет в журнале — в топ не попадает
        XCTAssertEqual(s.trackCount, 1)
    }

    func testFutureAndOldRowsOutsidePeriod() {
        let rows = [row("sc:1", "A", daysAgo: 40), row("sc:1", "A", daysAgo: -1)]
        let month = StatsEngine.compute(rows: rows, tracks: [:], period: .month, now: now, calendar: utc)
        XCTAssertTrue(month.isEmpty)
        XCTAssertEqual(month.deltaPct, -100) // в прошлом месяце слушал, в этом — нет
        let all = StatsEngine.compute(rows: rows, tracks: [:], period: .all, now: now, calendar: utc)
        XCTAssertEqual(all.plays, 1)
        XCTAssertNil(all.deltaPct) // за всё время сравнивать не с чем
    }

    func testMonthlyBucketsTrimLeadingEmptyButKeepHalfYear() {
        let rows = [row("sc:1", "A", daysAgo: 0, ms: 1000), row("sc:1", "A", daysAgo: 60, ms: 2000)]
        let all = StatsEngine.compute(rows: rows, tracks: [:], period: .all, now: now, calendar: utc)
        XCTAssertEqual(all.buckets.count, 6)
        XCTAssertEqual(all.buckets.last?.ms, 1000)
        XCTAssertEqual(all.buckets.last?.unit, .month)
        let year = StatsEngine.compute(rows: rows, tracks: [:], period: .year, now: now, calendar: utc)
        XCTAssertEqual(year.buckets.count, 12)
        XCTAssertEqual(year.buckets.reduce(0) { $0 + $1.ms }, 3000)
        let longAgo = (0 ..< 20).map { row("sc:1", "A", daysAgo: Double($0) * 30, ms: 1) }
        XCTAssertEqual(StatsEngine.compute(rows: longAgo, tracks: [:], period: .all, now: now, calendar: utc).buckets.count, 20) // апрель 2025 … ноябрь 2026
    }

    func testWeekdayAndPerDay() {
        let rows = [row("sc:1", "A", daysAgo: 0), row("sc:2", "A", daysAgo: 0), row("sc:3", "A", daysAgo: 7)]
        let s = StatsEngine.compute(rows: rows, tracks: [:], period: .month, now: now, calendar: utc)
        XCTAssertEqual(s.favWeekday, 1) // вторник
        XCTAssertEqual(s.weekdays[1], 3)
        XCTAssertEqual(s.perDay, 2) // 3 за 2 дня → 1.5 → 2
    }

    @MainActor
    func testPlayLogStartedEndedAndPersists() {
        let file = tempDirectory().appendingPathComponent("plays.json")
        let log = PlayLog(file: file)
        let track = makeTrack("sc:1", "Alpha", durationMs: 200_000)
        log.started(track, at: now, listenedMs: 30_000)
        log.ended(track, listenedMs: 150_000, now: now.addingTimeInterval(200))
        log.ended(track, listenedMs: 10_000, now: now.addingTimeInterval(300)) // меньше — не трогаем
        XCTAssertEqual(log.rows.count, 1)
        XCTAssertEqual(log.rows[0].ms, 150_000)
        XCTAssertEqual(log.rows[0].artist, "Alpha")
        let again = PlayLog(file: file)
        XCTAssertEqual(again.rows, log.rows)
        XCTAssertEqual(again.tracks["sc:1"]?.title, track.title)
        XCTAssertGreaterThan(again.fileBytes, 0)
        again.clear()
        XCTAssertTrue(PlayLog(file: file).rows.isEmpty)
    }

    @MainActor
    func testPlayHistoryFeedsLog() {
        let dir = tempDirectory()
        let history = PlayHistory(file: dir.appendingPathComponent("history.json"), now: { self.now })
        let log = PlayLog(file: dir.appendingPathComponent("plays.json"))
        history.log = log
        let track = makeTrack("ym:5", "Gamma", durationMs: 40_000)
        history.record(track)
        XCTAssertEqual(log.rows.first?.ms, 20_000) // порог — половина короткого трека
        history.ended(track, listenedMs: 40_000, manualSkip: false)
        XCTAssertEqual(log.rows.first?.ms, 40_000)
        history.clear()
        XCTAssertTrue(log.rows.isEmpty)
    }

    @MainActor
    func testBackfillFromOldHistoryOnce() {
        let file = tempDirectory().appendingPathComponent("plays.json")
        let log = PlayLog(file: file)
        let track = makeTrack("sc:9", "Delta", durationMs: 100_000)
        let signals = [
            PlaySignal(ref: "sc:9", artists: ["delta"], kind: .play, weight: 1, at: now),
            PlaySignal(ref: "sc:9", artists: ["delta"], kind: .finish, weight: 1, at: now.addingTimeInterval(90)),
            PlaySignal(ref: "sc:8", artists: ["omega"], kind: .play, weight: 1, at: now.addingTimeInterval(-500)),
        ]
        log.backfill(signals: signals, recent: [track])
        XCTAssertEqual(log.rows.map(\.ref), ["sc:8", "sc:9"])
        XCTAssertEqual(log.rows.last?.ms, 100_000) // дослушан — вся длительность
        XCTAssertEqual(log.rows.first?.artist, "omega")
        log.backfill(signals: signals, recent: [track])
        XCTAssertEqual(log.rows.count, 2)
        XCTAssertEqual(PlayLog(file: file).rows.count, 2)
    }
}
