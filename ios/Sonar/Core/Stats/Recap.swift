import Foundation

// Итоги месяца и года (NEXT_PROMPT «Этап 11») — порт Windows `store/recap.rs` и `lib/recap-core.ts` по
// журналу на телефоне (`PlayLog`): минуты, топ-5 треков и артистов, новый артист, любимый час, самый
// длинный день, трек на повторе, доли сервисов; какие карточки показать и когда звать на Главной.
// Границы периода — по местному календарю (тесты передают UTC). Без UIKit — гоняется XCTest
// (`SonarTests/RecapTests.swift`).

enum RecapKind: String, Codable, Sendable {
    case month, year
}

/// Какие итоги: месяц (`month` 1–12) или год (`month` = nil).
struct RecapRef: Hashable, Sendable, Identifiable {
    var kind: RecapKind
    var year: Int
    var month: Int?

    static func month(_ year: Int, _ month: Int) -> RecapRef { RecapRef(kind: .month, year: year, month: month) }
    static func year(_ year: Int) -> RecapRef { RecapRef(kind: .year, year: year, month: nil) }

    /// Ключ итогов — для `stats.recap_seen` и имени картинки, как на ПК: `month-2026-11`, `year-2026`.
    var id: String {
        guard kind == .month, let month else { return "year-\(year)" }
        return "month-\(year)-\(month < 10 ? "0" : "")\(month)"
    }

    /// Прошлый такой же период — для «к прошлому разу».
    var previous: RecapRef {
        guard kind == .month, let month else { return .year(year - 1) }
        return month == 1 ? .month(year - 1, 12) : .month(year, month - 1)
    }

    /// С местной полуночи первого дня до местной полуночи после последнего.
    func interval(in calendar: Calendar) -> DateInterval? {
        let start = DateComponents(year: year, month: kind == .month ? month : 1, day: 1)
        guard let from = calendar.date(from: start),
              let to = calendar.date(byAdding: kind == .month ? .month : .year, value: 1, to: from) else { return nil }
        return DateInterval(start: from, end: to)
    }
}

/// Период, за который есть прослушивания.
struct RecapPeriod: Equatable, Sendable {
    var ref: RecapRef
    var totalMs: Int
}

struct RecapPeriods: Equatable, Sendable {
    /// Новые сверху.
    var months: [RecapPeriod] = []
    var years: [RecapPeriod] = []

    var isEmpty: Bool { months.isEmpty && years.isEmpty }
}

struct RecapNewArtist: Equatable, Sendable {
    var artist: ArtistStat
    /// Местная полночь дня первого прослушивания.
    var firstPlayed: Date
}

struct RecapDay: Equatable, Sendable {
    var date: Date
    var ms: Int
    var plays: Int
}

struct RecapRepeat: Equatable, Sendable {
    var track: TrackStat
    /// Сколько раз за день.
    var count: Int
    var date: Date
}

struct RecapServiceShare: Equatable, Sendable {
    var service: ServiceID
    var ms: Int
    /// Целые проценты, в сумме ровно 100.
    var pct: Int
}

struct Recap: Equatable, Sendable {
    var ref: RecapRef
    var totalMs = 0
    var plays = 0
    var tracks = 0
    var artists = 0
    /// Дней, когда слушал.
    var activeDays = 0
    /// К прошлому такому же периоду, % (nil — сравнивать не с чем).
    var deltaPct: Int?
    var topTracks: [TrackStat] = []
    var topArtists: [ArtistStat] = []
    var newArtist: RecapNewArtist?
    /// Время по часам суток (24 значения, мс).
    var hours = [Int](repeating: 0, count: 24)
    var peakHour: Int?
    var longestDay: RecapDay?
    var repeatTrack: RecapRepeat?
    var services: [RecapServiceShare] = []
}

/// Карточка итогов; без данных карточки нет.
enum RecapCard: Equatable, Sendable, Identifiable {
    case intro
    case minutes(minutes: Int, delta: Int?, days: Int, plays: Int)
    case tracks([TrackStat])
    case artists([ArtistStat])
    case newArtist(ArtistStat, firstPlayed: Date)
    case hour(Int, hours: [Int])
    case day(Date, minutes: Int, plays: Int)
    case onRepeat(TrackStat, count: Int, date: Date)
    case services([RecapServiceShare])

    /// Вид карточки — как `kind` на ПК (имя картинки, ключ листания).
    var id: String {
        switch self {
        case .intro: "intro"
        case .minutes: "minutes"
        case .tracks: "tracks"
        case .artists: "artists"
        case .newArtist: "new_artist"
        case .hour: "hour"
        case .day: "day"
        case .onRepeat: "repeat"
        case .services: "services"
        }
    }
}

enum RecapEngine {
    /// Сколько позиций в топах карточек.
    static let topN = 5
    /// Кандидатов в топ треков с запасом: трека без сохранённых данных нет в карточке.
    static let topCandidates = 10
    /// «Трек на повторе» — не меньше стольких прослушиваний за один день.
    static let minRepeat = 3
    /// На Главной зовём, только если за период наслушано хотя бы столько.
    static let minInviteMs = 30 * 60_000
    /// Первые дни месяца, когда на Главной приглашение на итоги прошлого месяца.
    static let inviteDays = 7
    private static let december = 12

    // MARK: - Подсчёт

    /// Итоги периода по журналу. `tracks` — сохранённые треки (название, обложка, артисты).
    static func compute(rows: [PlayRow], tracks: [String: Track], ref: RecapRef, calendar: Calendar = .current) -> Recap {
        var recap = Recap(ref: ref)
        guard let span = ref.interval(in: calendar) else { return recap }
        let inPeriod = rows.filter { span.start <= $0.at && $0.at < span.end }.sorted { $0.at < $1.at }
        recap.totalMs = inPeriod.reduce(0) { $0 + $1.ms }
        let prev = ref.previous.interval(in: calendar).map { p in
            rows.lazy.filter { p.start <= $0.at && $0.at < p.end }.reduce(0) { $0 + $1.ms }
        } ?? 0
        if prev > 0 { recap.deltaPct = Int((Double(recap.totalMs - prev) / Double(prev) * 100).rounded()) }

        for row in inPeriod { recap.hours[calendar.component(.hour, from: row.at)] += row.ms }
        let trackList = trackTotals(inPeriod)
        let artistList = artistTotals(inPeriod)
        let faces = StatsEngine.artistFaces(tracks)
        let face = { (a: (name: String, ms: Int, plays: Int)) -> ArtistStat in
            let f = faces[a.name.lowercased()]
            return ArtistStat(name: a.name, ref: f?.ref, avatarURL: f?.avatarURL, ms: a.ms, plays: a.plays)
        }

        recap.plays = inPeriod.count
        recap.tracks = trackList.count
        recap.artists = artistList.count
        recap.activeDays = Set(inPeriod.map { calendar.startOfDay(for: $0.at) }).count
        recap.topTracks = Array(trackList.prefix(topCandidates).compactMap { item in
            tracks[item.ref].map { TrackStat(track: $0, plays: item.plays, ms: item.ms) }
        }.prefix(topN))
        recap.topArtists = artistList.prefix(topN).map(face)
        recap.newArtist = newArtist(inPeriod, artists: artistList, rows: rows, before: span.start, calendar: calendar).map {
            RecapNewArtist(artist: face($0.artist), firstPlayed: $0.first)
        }
        recap.peakHour = peakHour(recap.hours)
        recap.longestDay = longestDay(inPeriod, calendar: calendar)
        recap.repeatTrack = repeatTrack(inPeriod, tracks: tracks, calendar: calendar)
        recap.services = serviceShares(inPeriod)
        return recap
    }

    /// Треки периода по числу прослушиваний (при равенстве — по времени, потом по ref).
    static func trackTotals(_ rows: [PlayRow]) -> [(ref: String, plays: Int, ms: Int)] {
        var by: [String: (plays: Int, ms: Int)] = [:]
        for row in rows {
            let e = by[row.ref] ?? (0, 0)
            by[row.ref] = (e.plays + 1, e.ms + row.ms)
        }
        return by.map { (ref: $0.key, plays: $0.value.plays, ms: $0.value.ms) }
            .sorted { ($1.plays, $1.ms, $0.ref) < ($0.plays, $0.ms, $1.ref) }
    }

    /// Артисты периода по времени; без учёта регистра, имя — как в первой записи. Пустые имена не считаем.
    static func artistTotals(_ rows: [PlayRow]) -> [(name: String, ms: Int, plays: Int)] {
        var by: [String: (name: String, ms: Int, plays: Int)] = [:]
        for row in rows where !row.artist.trimmingCharacters(in: .whitespaces).isEmpty {
            let key = row.artist.lowercased()
            let e = by[key] ?? (row.artist, 0, 0)
            by[key] = (e.name, e.ms + row.ms, e.plays + 1)
        }
        return by.values.sorted { ($1.ms, $1.plays, $0.name) < ($0.ms, $0.plays, $1.name) }
    }

    /// Любимый час — больше всего времени (при равенстве — более ранний); тишина — nil.
    static func peakHour(_ hours: [Int]) -> Int? {
        guard let top = hours.max(), top > 0 else { return nil }
        return hours.firstIndex(of: top)
    }

    /// Самый длинный день по времени (при равенстве — более ранний).
    static func longestDay(_ rows: [PlayRow], calendar: Calendar) -> RecapDay? {
        var by: [Date: (ms: Int, plays: Int)] = [:]
        for row in rows {
            let day = calendar.startOfDay(for: row.at)
            let e = by[day] ?? (0, 0)
            by[day] = (e.ms + row.ms, e.plays + 1)
        }
        return by.filter { $0.value.ms > 0 }
            .max { $0.value.ms != $1.value.ms ? $0.value.ms < $1.value.ms : $0.key > $1.key }
            .map { RecapDay(date: $0.key, ms: $0.value.ms, plays: $0.value.plays) }
    }

    /// Трек на повторе: больше всего прослушиваний за один день (не меньше `minRepeat`), лучший из
    /// тех, что сохранены. При равенстве — больше времени, раньше день, меньше ref.
    static func repeatTrack(_ rows: [PlayRow], tracks: [String: Track], calendar: Calendar) -> RecapRepeat? {
        struct Key: Hashable { var ref: String; var day: Date }
        var by: [Key: (count: Int, ms: Int)] = [:]
        for row in rows {
            let key = Key(ref: row.ref, day: calendar.startOfDay(for: row.at))
            let e = by[key] ?? (0, 0)
            by[key] = (e.count + 1, e.ms + row.ms)
        }
        let best = by.filter { $0.value.count >= minRepeat }.sorted { a, b in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            if a.value.ms != b.value.ms { return a.value.ms > b.value.ms }
            return a.key.day != b.key.day ? a.key.day < b.key.day : a.key.ref < b.key.ref
        }
        return best.lazy.compactMap { item in
            tracks[item.key.ref].map {
                RecapRepeat(track: TrackStat(track: $0, plays: item.value.count, ms: item.value.ms),
                            count: item.value.count, date: item.key.day)
            }
        }.first
    }

    /// Новый артист: больше всего времени среди тех, кого до периода не слушал. Без истории до
    /// периода — nil (иначе «новыми» были бы все).
    static func newArtist(_ inPeriod: [PlayRow], artists: [(name: String, ms: Int, plays: Int)], rows: [PlayRow],
                          before: Date, calendar: Calendar) -> (artist: (name: String, ms: Int, plays: Int), first: Date)? {
        let known = Set(rows.lazy.filter { $0.at < before }.map { $0.artist.lowercased() })
        guard !known.isEmpty, let found = artists.first(where: { !known.contains($0.name.lowercased()) }) else { return nil }
        let key = found.name.lowercased()
        guard let first = inPeriod.first(where: { $0.artist.lowercased() == key }) else { return nil }
        return (found, calendar.startOfDay(for: first.at))
    }

    /// Доли сервисов по времени — id из реестра; ref без сервиса не считаем.
    static func serviceShares(_ rows: [PlayRow]) -> [RecapServiceShare] {
        var by: [ServiceID: Int] = [:]
        for row in rows {
            if let id = ServiceRegistry.service(of: row.ref) { by[id, default: 0] += row.ms }
        }
        let list = by.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
        let pct = percents(list.map(\.value))
        return zip(list, pct).map { RecapServiceShare(service: $0.key, ms: $0.value, pct: $1) }
    }

    /// Проценты методом наибольшего остатка: целые, в сумме ровно 100.
    static func percents(_ values: [Int]) -> [Int] {
        let total = values.reduce(0, +)
        guard total > 0 else { return values.map { _ in 0 } }
        var out = values.map { $0 * 100 / total }
        var rest = 100 - out.reduce(0, +)
        let order = values.indices.sorted { a, b in
            let ra = values[a] * 100 % total, rb = values[b] * 100 % total
            return ra != rb ? ra > rb : a < b
        }
        for i in order where rest > 0 {
            out[i] += 1
            rest -= 1
        }
        return out
    }

    // MARK: - Периоды и приглашение

    /// Месяцы и годы, за которые есть прослушивания (новые сверху), — для «Итогов» в Статистике и Главной.
    static func periods(rows: [PlayRow], now: Date, calendar: Calendar = .current) -> RecapPeriods {
        var months: [RecapRef: Int] = [:]
        var years: [Int: Int] = [:]
        for row in rows where row.at <= now {
            let c = calendar.dateComponents([.year, .month], from: row.at)
            guard let y = c.year, let m = c.month else { continue }
            months[.month(y, m), default: 0] += row.ms
            years[y, default: 0] += row.ms
        }
        return RecapPeriods(
            months: months.map { RecapPeriod(ref: $0.key, totalMs: $0.value) }
                .sorted { ($0.ref.year, $0.ref.month ?? 0) > ($1.ref.year, $1.ref.month ?? 0) },
            years: years.map { RecapPeriod(ref: .year($0.key), totalMs: $0.value) }.sorted { $0.ref.year > $1.ref.year }
        )
    }

    /// Какие итоги звать на Главной: весь декабрь — итоги года; первые `inviteDays` дней месяца —
    /// прошлый месяц (в начале января — прошлый год). Мало слушал или уже открывал — nil.
    static func invite(now: Date, periods: RecapPeriods, seen: String?, calendar: Calendar = .current) -> RecapRef? {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        let ref: RecapRef
        if m == december {
            ref = .year(y)
        } else if d <= inviteDays {
            ref = m == 1 ? .year(y - 1) : .month(y, m - 1)
        } else {
            return nil
        }
        guard ref.id != seen else { return nil }
        let list = ref.kind == .year ? periods.years : periods.months
        guard let found = list.first(where: { $0.ref == ref }), found.totalMs >= minInviteMs else { return nil }
        return ref
    }

    // MARK: - Карточки

    /// Карточки по порядку; без данных карточки нет. Совсем пусто — пустой список.
    static func cards(_ r: Recap) -> [RecapCard] {
        guard r.totalMs > 0 else { return [] }
        let minutes = { (ms: Int) in Int((Double(ms) / 60_000).rounded()) }
        let all: [RecapCard?] = [
            .intro,
            .minutes(minutes: minutes(r.totalMs), delta: r.deltaPct, days: r.activeDays, plays: r.plays),
            r.topTracks.isEmpty ? nil : .tracks(r.topTracks),
            r.topArtists.isEmpty ? nil : .artists(r.topArtists),
            r.newArtist.map { .newArtist($0.artist, firstPlayed: $0.firstPlayed) },
            r.peakHour.map { .hour($0, hours: r.hours) },
            r.longestDay.map { .day($0.date, minutes: minutes($0.ms), plays: $0.plays) },
            r.repeatTrack.map { .onRepeat($0.track, count: $0.count, date: $0.date) },
            r.services.isEmpty ? nil : .services(r.services),
        ]
        return all.compactMap { $0 }
    }

    /// Обложка, от которой берутся цвета итогов: первый трек топа, иначе трек на повторе.
    static func coverURL(_ r: Recap) -> String? {
        r.topTracks.lazy.compactMap(\.track.coverURL).first ?? r.repeatTrack?.track.track.coverURL
    }

    /// Часть суток по часу: 0 — ночь (0–5), 1 — утро (6–11), 2 — день (12–17), 3 — вечер (18–23).
    static func partOfDay(_ hour: Int) -> Int {
        ((hour % 24) + 24) % 24 / 6
    }
}

/// Цвета итогов: фон — градиент от `bg` к `bg2`, акцент, текст на акценте и основной текст.
struct RecapColors: Equatable, Sendable {
    var bg: RGB
    var bg2: RGB
    var accent: RGB
    var accentInk: RGB
    var ink: RGB

    /// Нет обложки или она серая — спокойный сине-фиолетовый.
    private static let neutral = (c: 0.05, h: 280.0)
    private static let grey = 0.02
    private static let maxBgChroma = 0.11
    private static let minAccentChroma = 0.09
    private static let maxAccentChroma = 0.17
    private static let bg2HueShift = 30.0

    /// Как ПК `recapColors`: тёмный фон оттенка обложки, светлый акцент, белый текст.
    static func from(cover: RGB?) -> RecapColors {
        let src = cover.map(Palette.oklch).flatMap { $0.c > grey ? $0 : nil }
        let h = src?.h ?? neutral.h
        let c = src?.c ?? neutral.c
        let bgC = min(c, maxBgChroma)
        let accentC = max(minAccentChroma, min(c, maxAccentChroma))
        return RecapColors(
            bg: Palette.rgb(Lch(l: 0.27, c: bgC, h: h)),
            bg2: Palette.rgb(Lch(l: 0.15, c: bgC * 0.7, h: (h + bg2HueShift).truncatingRemainder(dividingBy: 360))),
            accent: Palette.rgb(Lch(l: 0.8, c: accentC, h: h)),
            accentInk: Palette.rgb(Lch(l: 0.22, c: min(accentC, 0.06), h: h)),
            ink: RGB(246, 246, 248)
        )
    }
}

extension RGB {
    /// `#RRGGBB` из реестра сервисов; не разобрали — nil.
    init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(Double(v >> 16 & 0xFF), Double(v >> 8 & 0xFF), Double(v & 0xFF))
    }
}
