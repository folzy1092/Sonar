import XCTest
@testable import Sonar

/// «Итоги месяца и года»: подсчёт по журналу (`RecapEngine`) — те же правила, что Windows
/// `store/recap.rs` и `lib/recap-core.ts`.
final class RecapTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: 1))!
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.startOfDay(for: at(y, m, d))
    }

    private func row(_ ref: String, _ artist: String, _ date: Date, ms: Int) -> PlayRow {
        PlayRow(ref: ref, artist: artist, at: date, ms: ms)
    }

    private let tracks = [
        "sc:1": makeTrack("sc:1", "Alpha"),
        "sc:2": makeTrack("sc:2", "Beta"),
        "ym:3": makeTrack("ym:3", "alpha"),
    ]

    /// Ноябрь 2026: sc:9 (Gamma) слушали больше всех, но трека нет среди сохранённых — в топ и
    /// «на повторе» он не попадает. В октябре — только Beta, это история до периода.
    private var november: [PlayRow] {
        var rows = [row("sc:2", "Beta", at(2026, 10, 10, 10), ms: 300_000)]
        rows += (0 ..< 3).map { _ in row("sc:1", "Alpha", at(2026, 11, 3, 22), ms: 200_000) }
        rows.append(row("ym:3", "alpha", at(2026, 11, 5, 22), ms: 100_000))
        rows.append(row("sc:2", "Beta", at(2026, 11, 5, 9), ms: 60_000))
        rows += (0 ..< 4).map { _ in row("sc:9", "Gamma", at(2026, 11, 6, 9), ms: 150_000) }
        return rows
    }

    func testRefIdsPreviousAndBounds() {
        XCTAssertEqual(RecapRef.month(2026, 1).id, "month-2026-01")
        XCTAssertEqual(RecapRef.month(2026, 11).id, "month-2026-11")
        XCTAssertEqual(RecapRef.year(2026).id, "year-2026")
        XCTAssertEqual(RecapRef.month(2026, 1).previous, .month(2025, 12))
        XCTAssertEqual(RecapRef.month(2026, 7).previous, .month(2026, 6))
        XCTAssertEqual(RecapRef.year(2026).previous, .year(2025))
        let dec = RecapRef.month(2026, 12).interval(in: utc)
        XCTAssertEqual(dec?.start, day(2026, 12, 1))
        XCTAssertEqual(dec?.end, day(2027, 1, 1))
        let year = RecapRef.year(2024).interval(in: utc)
        XCTAssertEqual(year?.start, day(2024, 1, 1))
        XCTAssertEqual(year?.end, day(2025, 1, 1))
    }

    func testPercentsAlwaysSumTo100() {
        XCTAssertEqual(RecapEngine.percents([1, 1, 1]), [34, 33, 33])
        XCTAssertEqual(RecapEngine.percents([2, 1]), [67, 33])
        XCTAssertEqual(RecapEngine.percents([0, 0]), [0, 0])
        XCTAssertEqual(RecapEngine.percents([]), [])
        XCTAssertEqual(RecapEngine.percents([1_260_000, 100_000]), [93, 7])
    }

    func testMonthTotalsAndTops() {
        let r = RecapEngine.compute(rows: november, tracks: tracks, ref: .month(2026, 11), calendar: utc)
        XCTAssertEqual(r.totalMs, 1_360_000)
        XCTAssertEqual(r.plays, 9)
        XCTAssertEqual(r.tracks, 4)
        XCTAssertEqual(r.artists, 3) // Alpha и alpha — один артист
        XCTAssertEqual(r.activeDays, 3)
        XCTAssertEqual(r.deltaPct, 353) // 1360 к 300 в октябре
        XCTAssertEqual(r.topTracks.map(\.track.ref), ["sc:1", "ym:3", "sc:2"])
        XCTAssertEqual(r.topTracks.first?.plays, 3)
        XCTAssertEqual(r.topArtists.map(\.name), ["Alpha", "Gamma", "Beta"])
        XCTAssertEqual(r.topArtists.first?.ms, 700_000)
        XCTAssertNotNil(r.topArtists.first?.ref) // лицо артиста — из сохранённых треков
        XCTAssertNil(r.topArtists[1].ref) // Gamma нет среди сохранённых
    }

    func testMonthHourDayRepeatAndServices() {
        let r = RecapEngine.compute(rows: november, tracks: tracks, ref: .month(2026, 11), calendar: utc)
        XCTAssertEqual(r.hours[22], 700_000)
        XCTAssertEqual(r.hours[9], 660_000)
        XCTAssertEqual(r.peakHour, 22)
        // 3 и 6 ноября — по 600 000 мс: при равенстве — более ранний день
        XCTAssertEqual(r.longestDay, RecapDay(date: day(2026, 11, 3), ms: 600_000, plays: 3))
        XCTAssertEqual(r.repeatTrack?.track.track.ref, "sc:1")
        XCTAssertEqual(r.repeatTrack?.count, 3)
        XCTAssertEqual(r.repeatTrack?.date, day(2026, 11, 3))
        XCTAssertEqual(r.services.map(\.service), [.sc, .ym])
        XCTAssertEqual(r.services.map(\.pct), [93, 7])
        XCTAssertEqual(r.newArtist?.artist.name, "Alpha")
        XCTAssertEqual(r.newArtist?.firstPlayed, day(2026, 11, 3))
    }

    func testCardsInOrder() {
        let r = RecapEngine.compute(rows: november, tracks: tracks, ref: .month(2026, 11), calendar: utc)
        let cards = RecapEngine.cards(r)
        XCTAssertEqual(cards.map(\.id), ["intro", "minutes", "tracks", "artists", "new_artist", "hour", "day", "repeat", "services"])
        XCTAssertEqual(cards[1], .minutes(minutes: 23, delta: 353, days: 3, plays: 9))
        XCTAssertEqual(RecapEngine.coverURL(r), nil) // у тестовых треков обложек нет
    }

    func testNewArtistNeedsHistoryBeforePeriod() {
        let rows = november.filter { $0.at >= day(2026, 11, 1) }
        let r = RecapEngine.compute(rows: rows, tracks: tracks, ref: .month(2026, 11), calendar: utc)
        XCTAssertNil(r.newArtist)
        XCTAssertNil(r.deltaPct)
        XCTAssertFalse(RecapEngine.cards(r).map(\.id).contains("new_artist"))
    }

    func testEmptyPeriodHasNoCards() {
        let r = RecapEngine.compute(rows: november, tracks: tracks, ref: .month(2026, 12), calendar: utc)
        XCTAssertEqual(r.totalMs, 0)
        XCTAssertNil(r.peakHour)
        XCTAssertNil(r.longestDay)
        XCTAssertNil(r.repeatTrack)
        XCTAssertEqual(r.deltaPct, -100)
        XCTAssertEqual(RecapEngine.cards(r), [])
    }

    func testYearSpansAllMonths() {
        let rows = november + [row("sc:1", "Alpha", at(2025, 12, 31, 23), ms: 50_000)]
        let r = RecapEngine.compute(rows: rows, tracks: tracks, ref: .year(2026), calendar: utc)
        XCTAssertEqual(r.totalMs, 1_660_000)
        XCTAssertEqual(r.deltaPct, Int((1_610_000.0 / 50_000.0 * 100).rounded()))
        XCTAssertEqual(r.newArtist?.artist.name, "Gamma") // Alpha слушал ещё в 2025
    }

    func testPeriodsNewestFirst() {
        let rows = [
            row("sc:1", "A", at(2025, 12, 5), ms: 1000),
            row("sc:1", "A", at(2026, 1, 5), ms: 2000),
            row("sc:1", "A", at(2026, 11, 5), ms: 3000),
            row("sc:1", "A", at(2026, 11, 6), ms: 4000),
            row("sc:1", "A", at(2027, 3, 1), ms: 9000), // в будущем — не считаем
        ]
        let p = RecapEngine.periods(rows: rows, now: at(2026, 11, 20), calendar: utc)
        XCTAssertEqual(p.months.map(\.ref), [.month(2026, 11), .month(2026, 1), .month(2025, 12)])
        XCTAssertEqual(p.months.map(\.totalMs), [7000, 2000, 1000])
        XCTAssertEqual(p.years.map(\.ref), [.year(2026), .year(2025)])
        XCTAssertEqual(p.years.map(\.totalMs), [9000, 1000])
        XCTAssertTrue(RecapEngine.periods(rows: [], now: at(2026, 11, 20), calendar: utc).isEmpty)
    }

    func testInviteTiming() {
        let big = RecapEngine.minInviteMs
        let periods = RecapPeriods(
            months: [RecapPeriod(ref: .month(2026, 11), totalMs: big), RecapPeriod(ref: .month(2026, 10), totalMs: big)],
            years: [RecapPeriod(ref: .year(2026), totalMs: big * 10)]
        )
        let invite = { (now: Date, seen: String?) in RecapEngine.invite(now: now, periods: periods, seen: seen, calendar: self.utc) }
        XCTAssertEqual(invite(at(2026, 11, 3), nil), .month(2026, 10))
        XCTAssertEqual(invite(at(2026, 11, 7), nil), .month(2026, 10))
        XCTAssertNil(invite(at(2026, 11, 8), nil))
        XCTAssertNil(invite(at(2026, 11, 3), "month-2026-10"))
        XCTAssertEqual(invite(at(2026, 12, 20), nil), .year(2026))
        XCTAssertEqual(invite(at(2027, 1, 2), nil), .year(2026))
        XCTAssertNil(invite(at(2027, 1, 2), "year-2026"))
        XCTAssertNil(invite(at(2026, 10, 3), nil)) // за сентябрь ничего нет
    }

    func testInviteRemembersSeveralSeenRecaps() {
        let big = RecapEngine.minInviteMs
        let periods = RecapPeriods(
            months: [RecapPeriod(ref: .month(2026, 11), totalMs: big), RecapPeriod(ref: .month(2026, 10), totalMs: big),
                     RecapPeriod(ref: .month(2025, 12), totalMs: big)],
            years: [RecapPeriod(ref: .year(2026), totalMs: big * 10), RecapPeriod(ref: .year(2025), totalMs: big)]
        )
        let invite = { (now: Date, seen: String?) in RecapEngine.invite(now: now, periods: periods, seen: seen, calendar: self.utc) }
        // открыл старые итоги из Статистики — приглашение на текущие не возвращается
        let seen = RecapEngine.markSeen(RecapEngine.markSeen("", "month-2026-10"), "month-2025-12")
        XCTAssertNil(invite(at(2026, 11, 2), seen))
        // начало декабря: сначала год, потом ноябрь
        XCTAssertEqual(invite(at(2026, 12, 2), nil), .year(2026))
        XCTAssertEqual(invite(at(2026, 12, 2), "year-2026"), .month(2026, 11))
        XCTAssertNil(invite(at(2026, 12, 2), "year-2026,month-2026-11"))
        XCTAssertNil(invite(at(2026, 12, 20), "year-2026"))
        // начало января: прошлый год, потом декабрь
        XCTAssertEqual(invite(at(2026, 1, 3), "year-2025"), .month(2025, 12))
    }

    func testSeenListIsBoundedWithoutDuplicates() {
        XCTAssertEqual(RecapEngine.seenIDs("month-2026-10"), ["month-2026-10"])
        XCTAssertEqual(RecapEngine.seenIDs(""), [])
        XCTAssertEqual(RecapEngine.seenIDs(nil), [])
        XCTAssertEqual(RecapEngine.seenIDs(" a , ,b "), ["a", "b"])
        XCTAssertEqual(RecapEngine.markSeen("a,b", "a"), "b,a")
        var raw = ""
        for i in 0..<(RecapEngine.maxSeen + 5) { raw = RecapEngine.markSeen(raw, "id-\(i)") }
        let ids = RecapEngine.seenIDs(raw)
        XCTAssertEqual(ids.count, RecapEngine.maxSeen)
        XCTAssertEqual(ids.first, "id-5")
        XCTAssertEqual(ids.last, "id-\(RecapEngine.maxSeen + 4)")
    }

    func testInviteNeedsEnoughListening() {
        let periods = RecapPeriods(months: [RecapPeriod(ref: .month(2026, 10), totalMs: RecapEngine.minInviteMs - 1)], years: [])
        XCTAssertNil(RecapEngine.invite(now: at(2026, 11, 2), periods: periods, seen: nil, calendar: utc))
    }

    func testPartOfDay() {
        XCTAssertEqual([0, 5, 6, 11, 12, 17, 18, 23, 24, -1].map(RecapEngine.partOfDay), [0, 0, 1, 1, 2, 2, 3, 3, 0, 3])
    }

    func testColorsFromCover() {
        let neutral = RecapColors.from(cover: nil)
        XCTAssertEqual(RecapColors.from(cover: RGB(128, 128, 128)), neutral) // серая — как без обложки
        let red = RecapColors.from(cover: RGB(220, 40, 40))
        XCTAssertNotEqual(red, neutral)
        XCTAssertLessThan(Palette.oklch(red.bg).l, 0.35)
        XCTAssertLessThan(Palette.oklch(red.bg2).l, Palette.oklch(red.bg).l)
        XCTAssertGreaterThan(Palette.oklch(red.accent).l, 0.7)
        XCTAssertLessThan(Palette.oklch(red.accentInk).l, 0.35)
        XCTAssertEqual(red.ink, RGB(246, 246, 248))
    }

    func testHexColors() {
        XCTAssertEqual(RGB(hex: "#FF5500"), RGB(255, 85, 0))
        XCTAssertEqual(RGB(hex: "ffcc00"), RGB(255, 204, 0))
        XCTAssertNil(RGB(hex: "#FFF"))
        XCTAssertNil(RGB(hex: "#GG0000"))
    }
}
