import Foundation

/// Период «Статистики» (как `Stats.svelte` / `store/stats.rs`, без «дня» и «полугода» на iPhone).
enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week, month, year, all

    var id: String { rawValue }

    /// Длина периода, дней (nil — всё время).
    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        case .all: nil
        }
    }
}

/// Столбик графика: день (неделя, месяц) или месяц (год, всё время).
struct StatsBucket: Equatable, Sendable, Identifiable {
    enum Unit: Sendable { case day, month }
    /// Начало дня / месяца (местное время).
    var start: Date
    var unit: Unit
    var ms: Int
    var id: Date { start }
}

struct ArtistStat: Equatable, Sendable, Identifiable {
    var name: String
    var ref: String?
    var avatarURL: String?
    var ms: Int
    var plays: Int
    var id: String { name.lowercased() }
}

struct TrackStat: Equatable, Sendable, Identifiable {
    var track: Track
    var plays: Int
    var ms: Int
    var id: String { track.ref }
}

/// Итоги за период — те же поля, что `Stats` в docs/API.md §5 / `store/stats.rs`, плюс раскладка по
/// часам и дням недели для колец и столбиков.
struct ListeningStats: Equatable, Sendable {
    var period: StatsPeriod
    var totalMs = 0
    /// Изменение времени к прошлому такому же периоду, % (nil — сравнивать не с чем).
    var deltaPct: Int?
    var buckets: [StatsBucket] = []
    /// Прослушиваний по часу суток (0–23, местное время).
    var hours = [Int](repeating: 0, count: 24)
    /// Прослушиваний по дню недели: 0 — пн … 6 — вс.
    var weekdays = [Int](repeating: 0, count: 7)
    var artists: [ArtistStat] = []
    var tracks: [TrackStat] = []
    /// Прослушиваний, разных треков, разных артистов.
    var plays = 0
    var trackCount = 0
    var artistCount = 0
    /// Дней подряд со слушанием (по сегодня или вчера) — за всё время.
    var streakDays = 0
    var peakHour: Int?
    /// Треков в день — в среднем по дням, когда слушал.
    var perDay = 0
    var favWeekday: Int?

    var isEmpty: Bool { plays == 0 }
    var totalMinutes: Int { Int((Double(totalMs) / 60_000).rounded()) }
    var totalHours: Int { totalMs / 3_600_000 }
}

enum StatsEngine {
    static let topArtists = 10
    static let topTracks = 10

    /// Посчитать статистику за период. calendar — местное время (тесты передают UTC).
    static func compute(rows: [PlayRow], tracks: [String: Track], period: StatsPeriod, now: Date,
                        calendar: Calendar = .current) -> ListeningStats {
        var stats = ListeningStats(period: period)
        let from = period.days.map { now.addingTimeInterval(-Double($0) * 86_400) }
        let inPeriod = rows.filter { row in row.at <= now && from.map { row.at >= $0 } ?? true }
        let today = calendar.startOfDay(for: now)

        stats.totalMs = inPeriod.reduce(0) { $0 + $1.ms }
        if let from, let days = period.days {
            let prevFrom = from.addingTimeInterval(-Double(days) * 86_400)
            let prev = rows.lazy.filter { $0.at >= prevFrom && $0.at < from }.reduce(0) { $0 + $1.ms }
            if prev > 0 { stats.deltaPct = Int(((Double(stats.totalMs - prev) / Double(prev)) * 100).rounded()) }
        }

        var byArtist: [String: (name: String, ms: Int, plays: Int)] = [:]
        var byTrack: [String: (plays: Int, ms: Int, last: Date)] = [:]
        var days = Set<Date>()
        for row in inPeriod {
            let key = row.artist.lowercased()
            var a = byArtist[key] ?? (row.artist, 0, 0)
            a.ms += row.ms
            a.plays += 1
            byArtist[key] = a
            var tr = byTrack[row.ref] ?? (0, 0, row.at)
            tr.plays += 1
            tr.ms += row.ms
            tr.last = max(tr.last, row.at)
            byTrack[row.ref] = tr
            stats.hours[calendar.component(.hour, from: row.at)] += 1
            stats.weekdays[mondayIndex(calendar.component(.weekday, from: row.at))] += 1
            days.insert(calendar.startOfDay(for: row.at))
        }

        stats.plays = inPeriod.count
        stats.trackCount = byTrack.count
        stats.artistCount = byArtist.count
        stats.perDay = days.isEmpty ? 0 : Int((Double(inPeriod.count) / Double(days.count)).rounded())
        stats.peakHour = argmax(stats.hours)
        stats.favWeekday = argmax(stats.weekdays)

        let artistList = byArtist.values.sorted { $0.ms != $1.ms ? $0.ms > $1.ms : ($0.plays != $1.plays ? $0.plays > $1.plays : $0.name < $1.name) }
        let faces = artistFaces(tracks)
        stats.artists = artistList.prefix(topArtists).map { a in
            let face = faces[a.name.lowercased()]
            return ArtistStat(name: a.name, ref: face?.ref, avatarURL: face?.avatarURL, ms: a.ms, plays: a.plays)
        }
        stats.tracks = byTrack
            .sorted { $0.value.plays != $1.value.plays ? $0.value.plays > $1.value.plays
                : ($0.value.ms != $1.value.ms ? $0.value.ms > $1.value.ms : $0.value.last > $1.value.last) }
            .compactMap { ref, v in tracks[ref].map { TrackStat(track: $0, plays: v.plays, ms: v.ms) } }
            .prefix(topTracks)
            .map { $0 }

        let allDays = period == .all ? days : Set(rows.map { calendar.startOfDay(for: $0.at) })
        stats.streakDays = streak(allDays, today: today, calendar: calendar)
        stats.buckets = buckets(period, rows: inPeriod, today: today, calendar: calendar)
        return stats
    }

    /// weekday Calendar (1 — вс … 7 — сб) → 0 — пн … 6 — вс.
    static func mondayIndex(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    /// Индекс наибольшего (первый при равенстве), nil — всё нули.
    static func argmax(_ values: [Int]) -> Int? {
        guard let top = values.max(), top > 0 else { return nil }
        return values.firstIndex(of: top)
    }

    /// Дни подряд со слушанием, заканчивая сегодня (или вчера — сегодня ещё не слушал).
    static func streak(_ days: Set<Date>, today: Date, calendar: Calendar) -> Int {
        var day = days.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var n = 0
        while days.contains(day) {
            n += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    /// Столбики: неделя — 7 дней, месяц — 30 дней, год — 12 месяцев, всё время — до 24 месяцев без
    /// пустых в начале, но не меньше полугода.
    static func buckets(_ period: StatsPeriod, rows: [PlayRow], today: Date, calendar: Calendar) -> [StatsBucket] {
        switch period {
        case .week, .month:
            let n = period == .week ? 7 : 30
            let starts = (0 ..< n).compactMap { calendar.date(byAdding: .day, value: $0 - (n - 1), to: today) }
            var ms = [Int](repeating: 0, count: starts.count)
            let index = Dictionary(uniqueKeysWithValues: starts.enumerated().map { ($1, $0) })
            for row in rows {
                if let i = index[calendar.startOfDay(for: row.at)] { ms[i] += row.ms }
            }
            return zip(starts, ms).map { StatsBucket(start: $0, unit: .day, ms: $1) }
        case .year, .all:
            let n = period == .year ? 12 : 24
            let month = calendar.dateInterval(of: .month, for: today)?.start ?? today
            let starts = (0 ..< n).compactMap { calendar.date(byAdding: .month, value: $0 - (n - 1), to: month) }
            var ms = [Int](repeating: 0, count: starts.count)
            let index = Dictionary(uniqueKeysWithValues: starts.enumerated().map { ($1, $0) })
            for row in rows {
                if let start = calendar.dateInterval(of: .month, for: row.at)?.start, let i = index[start] { ms[i] += row.ms }
            }
            var out = zip(starts, ms).map { StatsBucket(start: $0, unit: .month, ms: $1) }
            if period == .all {
                let first = min(out.firstIndex { $0.ms > 0 } ?? out.count, max(0, out.count - 6))
                out.removeFirst(first)
            }
            return out
        }
    }

    /// Артист → ref и аватар — из сохранённых треков (первый с аватаром).
    static func artistFaces(_ tracks: [String: Track]) -> [String: (ref: String, avatarURL: String?)] {
        var out: [String: (ref: String, avatarURL: String?)] = [:]
        for track in tracks.values {
            for artist in track.artists {
                let key = artist.name.lowercased()
                if let known = out[key], known.avatarURL != nil { continue }
                if out[key] == nil || artist.avatarURL != nil { out[key] = (artist.ref, artist.avatarURL) }
            }
        }
        return out
    }
}
