import Foundation

// Правила умного плейлиста и движок — порт `windows/src-tauri/src/store/smart_rules.rs`. JSON правил общий
// для ПК и iPhone (docs/PLATFORMS.md «Умные плейлисты»): те же ключи, те же значения по умолчанию, тот же
// смысл. Чистая логика без хранилищ — её гоняют XCTest (`SmartRulesTests`).

/// Откуда берутся треки: Любимые, свой плейлист или всё, что слушал.
enum SmartSource: Hashable, Sendable {
    case liked
    case playlist(id: String)
    case played
}

enum SmartMatch: String, Codable, Hashable, Sendable {
    case all, any
}

enum SmartCmp: String, Codable, Hashable, Sendable {
    case gte, lte
}

enum SmartWhen: String, Codable, Hashable, Sendable {
    case before, after
}

enum SmartIs: String, Codable, Hashable, Sendable {
    case `is`, not
}

/// Одно условие. `days` = 0 или нет — за всё время.
enum SmartCondition: Hashable, Sendable {
    /// Прослушиваний за последние `days` дней не меньше / не больше `value`.
    case plays(days: Int?, op: SmartCmp, value: Int)
    /// Последнее прослушивание раньше / позже, чем `days` дней назад. Ни разу не слушал — «раньше».
    case lastPlayed(op: SmartWhen, days: Int)
    /// Добавлен за последние `days` дней.
    case added(days: Int)
    /// Сервис по префиксу ref (`sc`, `ym`, …).
    case service(op: SmartIs, value: String)
    /// Исполнитель: вхождение без учёта регистра в строку артиста или имя любого из артистов.
    case artist(op: SmartIs, value: String)
    /// Длительность в секундах не меньше / не больше `value`.
    case duration(op: SmartCmp, value: Int)
}

enum SmartSortBy: String, Codable, Hashable, Sendable {
    case plays
    case lastPlayed = "last_played"
    case added, title, artist, duration
}

struct SmartSort: Hashable, Sendable {
    var by: SmartSortBy
    /// Для `plays`: окно в днях (0 или нет — за всё время).
    var days: Int?
    var desc: Bool = true
}

struct SmartRules: Hashable, Sendable {
    static let version = 1
    static let maxDays = 3650
    static let maxLimit = 1000
    static let maxConditions = 20

    var v: Int = SmartRules.version
    var source: SmartSource
    var match: SmartMatch = .all
    var conditions: [SmartCondition] = []
    var sort: SmartSort?
    var limit: Int?

    /// «С нуля»: все Любимые, новые сверху.
    static var blank: SmartRules {
        SmartRules(source: .liked, sort: SmartSort(by: .added))
    }
}

// MARK: - JSON (тот же, что у ПК)

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private func corrupt(_ c: KeyedDecodingContainer<AnyKey>, _ what: String) -> DecodingError {
    DecodingError.dataCorruptedError(forKey: AnyKey("kind"), in: c, debugDescription: what)
}

extension SmartSource: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        switch try c.decode(String.self, forKey: AnyKey("kind")) {
        case "liked": self = .liked
        case "played": self = .played
        case "playlist": self = .playlist(id: try c.decode(String.self, forKey: AnyKey("id")))
        case let other: throw corrupt(c, "неизвестный источник: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        switch self {
        case .liked: try c.encode("liked", forKey: AnyKey("kind"))
        case .played: try c.encode("played", forKey: AnyKey("kind"))
        case let .playlist(id):
            try c.encode("playlist", forKey: AnyKey("kind"))
            try c.encode(id, forKey: AnyKey("id"))
        }
    }
}

extension SmartCondition: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func int(_ k: String) throws -> Int { try c.decode(Int.self, forKey: AnyKey(k)) }
        func str(_ k: String) throws -> String { try c.decode(String.self, forKey: AnyKey(k)) }
        switch try str("field") {
        case "plays":
            self = .plays(days: try c.decodeIfPresent(Int.self, forKey: AnyKey("days")),
                          op: try c.decode(SmartCmp.self, forKey: AnyKey("op")), value: try int("value"))
        case "last_played":
            self = .lastPlayed(op: try c.decode(SmartWhen.self, forKey: AnyKey("op")), days: try int("days"))
        case "added": self = .added(days: try int("days"))
        case "service": self = .service(op: try c.decode(SmartIs.self, forKey: AnyKey("op")), value: try str("value"))
        case "artist": self = .artist(op: try c.decode(SmartIs.self, forKey: AnyKey("op")), value: try str("value"))
        case "duration": self = .duration(op: try c.decode(SmartCmp.self, forKey: AnyKey("op")), value: try int("value"))
        case let other: throw corrupt(c, "неизвестное условие: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        switch self {
        case let .plays(days, op, value):
            try c.encode("plays", forKey: AnyKey("field"))
            try c.encode(days, forKey: AnyKey("days"))
            try c.encode(op, forKey: AnyKey("op"))
            try c.encode(value, forKey: AnyKey("value"))
        case let .lastPlayed(op, days):
            try c.encode("last_played", forKey: AnyKey("field"))
            try c.encode(op, forKey: AnyKey("op"))
            try c.encode(days, forKey: AnyKey("days"))
        case let .added(days):
            try c.encode("added", forKey: AnyKey("field"))
            try c.encode(days, forKey: AnyKey("days"))
        case let .service(op, value), let .artist(op, value):
            try c.encode(field, forKey: AnyKey("field"))
            try c.encode(op, forKey: AnyKey("op"))
            try c.encode(value, forKey: AnyKey("value"))
        case let .duration(op, value):
            try c.encode("duration", forKey: AnyKey("field"))
            try c.encode(op, forKey: AnyKey("op"))
            try c.encode(value, forKey: AnyKey("value"))
        }
    }

    /// Имя поля в JSON.
    var field: String {
        switch self {
        case .plays: "plays"
        case .lastPlayed: "last_played"
        case .added: "added"
        case .service: "service"
        case .artist: "artist"
        case .duration: "duration"
        }
    }
}

extension SmartSort: Codable {
    enum CodingKeys: String, CodingKey { case by, days, desc }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        by = try c.decode(SmartSortBy.self, forKey: .by)
        days = try c.decodeIfPresent(Int.self, forKey: .days)
        desc = try c.decodeIfPresent(Bool.self, forKey: .desc) ?? true
    }
}

extension SmartRules: Codable {
    enum CodingKeys: String, CodingKey { case v, source, match, conditions, sort, limit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decode(Int.self, forKey: .v)
        source = try c.decode(SmartSource.self, forKey: .source)
        match = try c.decodeIfPresent(SmartMatch.self, forKey: .match) ?? .all
        conditions = try c.decodeIfPresent([SmartCondition].self, forKey: .conditions) ?? []
        sort = try c.decodeIfPresent(SmartSort.self, forKey: .sort)
        limit = try c.decodeIfPresent(Int.self, forKey: .limit)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(source, forKey: .source)
        try c.encode(match, forKey: .match)
        try c.encode(conditions, forKey: .conditions)
        try c.encode(sort, forKey: .sort)
        try c.encode(limit, forKey: .limit)
    }
}

// MARK: - Движок

/// Трек-кандидат из источника и когда он туда попал (мс с 1970).
struct SmartCandidate: Sendable {
    var track: Track
    var addedAt: Int
}

/// История прослушиваний: ref → моменты прослушиваний (мс), по возрастанию.
struct SmartHistory: Sendable {
    private var plays: [String: [Int]] = [:]

    init(rows: [(ref: String, at: Int)]) {
        for row in rows { plays[row.ref, default: []].append(row.at) }
        for key in plays.keys { plays[key]?.sort() }
    }

    /// Прослушиваний начиная с `since` (включительно); nil — за всё время.
    func count(_ ref: String, since: Int?) -> Int {
        guard let list = plays[ref] else { return 0 }
        guard let since else { return list.count }
        return list.count - (list.firstIndex { $0 >= since } ?? list.count)
    }

    func last(_ ref: String) -> Int? {
        plays[ref]?.last
    }

    /// Все прослушанные ref: первое и последнее прослушивание.
    var refs: [(ref: String, first: Int, last: Int)] {
        plays.compactMap { ref, list in
            guard let first = list.first, let last = list.last else { return nil }
            return (ref, first, last)
        }
    }
}

enum SmartEngine {
    static let day = 86_400_000

    /// Что не так с правилами — ключ строки для `t()` (те же, что у ПК в lib/smart.ts); nil — всё хорошо.
    static func problem(_ rules: SmartRules) -> String? {
        if rules.v != SmartRules.version { return "Правила из новой версии Sonar" }
        if case let .playlist(id) = rules.source, id.trimmingCharacters(in: .whitespaces).isEmpty { return "Выбери плейлист" }
        if rules.conditions.count > SmartRules.maxConditions { return "Слишком много условий" }
        for condition in rules.conditions {
            switch condition {
            case let .artist(_, value) where value.trimmingCharacters(in: .whitespaces).isEmpty: return "Впиши исполнителя"
            case let .service(_, value) where !isService(value): return "Выбери сервис"
            default: continue
            }
        }
        return nil
    }

    /// Id сервиса из реестра — это префикс его трека.
    static func isService(_ id: String) -> Bool {
        ServiceRegistry.parse(ref: "\(id.trimmingCharacters(in: .whitespaces)):x")?.kind == .track
    }

    /// Отбор: без повторов (первый ref побеждает) → условия → устойчивая сортировка → лимит 1…1000.
    static func evaluate(_ rules: SmartRules, candidates: [SmartCandidate], history: SmartHistory, now: Int) -> [Track] {
        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0.track.ref).inserted }
        let passed = unique.filter { passes(rules, $0, history, now) }
        var sorted = passed
        if let sort = rules.sort { sorted = sortStable(passed, sort, history, now) }
        if let limit = rules.limit { sorted = Array(sorted.prefix(min(max(limit, 1), SmartRules.maxLimit))) }
        return sorted.map(\.track)
    }

    private static func since(_ now: Int, _ days: Int?) -> Int? {
        guard let days, days > 0 else { return nil }
        return now - min(days, SmartRules.maxDays) * day
    }

    private static func compare(_ op: SmartCmp, _ left: Int, _ right: Int) -> Bool {
        op == .gte ? left >= right : left <= right
    }

    private static func artistMatches(_ track: Track, _ needle: String) -> Bool {
        let n = needle.trimmingCharacters(in: .whitespaces).lowercased()
        return track.artist.lowercased().contains(n) || track.artists.contains { $0.name.lowercased().contains(n) }
    }

    private static func check(_ condition: SmartCondition, _ cand: SmartCandidate, _ history: SmartHistory, _ now: Int) -> Bool {
        let ref = cand.track.ref
        switch condition {
        case let .plays(days, op, value):
            return compare(op, history.count(ref, since: since(now, days)), value)
        case let .lastPlayed(op, days):
            let edge = now - min(max(days, 0), SmartRules.maxDays) * day
            guard let at = history.last(ref) else { return op == .before }
            return op == .before ? at < edge : at >= edge
        case let .added(days):
            guard let from = since(now, days) else { return true }
            return cand.addedAt >= from
        case let .service(op, value):
            let same = ServiceRegistry.service(of: ref)?.rawValue == value.trimmingCharacters(in: .whitespaces)
            return same == (op == .is)
        case let .artist(op, value):
            return artistMatches(cand.track, value) == (op == .is)
        case let .duration(op, value):
            return compare(op, cand.track.durationMs / 1000, value)
        }
    }

    private static func passes(_ rules: SmartRules, _ cand: SmartCandidate, _ history: SmartHistory, _ now: Int) -> Bool {
        guard !rules.conditions.isEmpty else { return true }
        switch rules.match {
        case .all: return rules.conditions.allSatisfy { check($0, cand, history, now) }
        case .any: return rules.conditions.contains { check($0, cand, history, now) }
        }
    }

    /// Ключ сортировки: число (счёт, время, длительность) или текст (название, артист).
    private static func key(_ cand: SmartCandidate, _ by: SmartSortBy, _ history: SmartHistory, _ from: Int?) -> (Int, String) {
        switch by {
        case .plays: (history.count(cand.track.ref, since: from), "")
        case .lastPlayed: (history.last(cand.track.ref) ?? Int.min, "")
        case .added: (cand.addedAt, "")
        case .title: (0, cand.track.title.lowercased())
        case .artist: (0, cand.track.artist.lowercased())
        case .duration: (cand.track.durationMs, "")
        }
    }

    /// Устойчивая сортировка: при равных ключах остаётся порядок источника (и при убывании тоже).
    private static func sortStable(_ list: [SmartCandidate], _ sort: SmartSort, _ history: SmartHistory, _ now: Int) -> [SmartCandidate] {
        let from = sort.by == .plays ? since(now, sort.days) : nil
        let keyed = list.enumerated().map { (index: $0.offset, key: key($0.element, sort.by, history, from), cand: $0.element) }
        return keyed.sorted { a, b in
            if a.key != b.key {
                let less = a.key.0 != b.key.0 ? a.key.0 < b.key.0 : a.key.1 < b.key.1
                return sort.desc ? !less : less
            }
            return a.index < b.index
        }.map(\.cand)
    }
}

// MARK: - Шаблоны (те же, что у ПК в lib/smart.ts)

struct SmartTemplate: Identifiable, Sendable {
    let id: String
    /// Русское название — ключ `t()`.
    let name: String
    let rules: SmartRules

    static let all: [SmartTemplate] = [
        SmartTemplate(id: "forgotten", name: "Давно не слушал", rules: SmartRules(
            source: .liked, conditions: [.lastPlayed(op: .before, days: 60)], sort: SmartSort(by: .lastPlayed, desc: false))),
        SmartTemplate(id: "month_top", name: "Топ месяца", rules: SmartRules(
            source: .played, conditions: [.plays(days: 30, op: .gte, value: 1)], sort: SmartSort(by: .plays, days: 30), limit: 50)),
        SmartTemplate(id: "barely", name: "Лайкнул, но почти не слушаю", rules: SmartRules(
            source: .liked, conditions: [.plays(days: nil, op: .lte, value: 2)], sort: SmartSort(by: .added))),
        SmartTemplate(id: "worn_out", name: "Заслушанное", rules: SmartRules(
            source: .played, conditions: [.plays(days: 30, op: .gte, value: 10)], sort: SmartSort(by: .plays, days: 30))),
        SmartTemplate(id: "new_liked", name: "Новое в Любимых", rules: SmartRules(
            source: .liked, conditions: [.added(days: 14)], sort: SmartSort(by: .added))),
    ]
}

// MARK: - Конструктор (как `defaultCondition` / `normalizeRules` в lib/smart.ts)

/// Поле условия — пункт «Добавить условие».
enum SmartField: String, CaseIterable, Sendable {
    case plays
    case lastPlayed = "last_played"
    case added, service, artist, duration

    /// Новое условие со значениями по умолчанию.
    func makeDefault(service: String = ServiceID.sc.rawValue) -> SmartCondition {
        switch self {
        case .plays: .plays(days: 30, op: .gte, value: 5)
        case .lastPlayed: .lastPlayed(op: .before, days: 60)
        case .added: .added(days: 14)
        case .service: .service(op: .is, value: service)
        case .artist: .artist(op: .is, value: "")
        case .duration: .duration(op: .gte, value: 180)
        }
    }
}

extension SmartRules {
    private static func clamp(_ n: Int, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, n)) }

    /// Числа в границах, пробелы по краям убраны, `days` и `limit` 0 — «нет». Новая копия, исходник не меняется.
    var normalized: SmartRules {
        var out = SmartRules(source: source, match: match)
        out.conditions = conditions.map { condition in
            switch condition {
            case let .plays(days, op, value):
                let d = Self.clamp(days ?? 0, 0, Self.maxDays)
                return .plays(days: d == 0 ? nil : d, op: op, value: Self.clamp(value, 0, 100_000))
            case let .lastPlayed(op, days): return .lastPlayed(op: op, days: Self.clamp(days, 1, Self.maxDays))
            case let .added(days): return .added(days: Self.clamp(days, 1, Self.maxDays))
            case let .service(op, value): return .service(op: op, value: value.trimmingCharacters(in: .whitespaces))
            case let .artist(op, value): return .artist(op: op, value: value.trimmingCharacters(in: .whitespaces))
            case let .duration(op, value): return .duration(op: op, value: Self.clamp(value, 0, 24 * 3600))
            }
        }
        out.sort = sort.map { s in
            let days = s.by == .plays ? Self.clamp(s.days ?? 0, 0, Self.maxDays) : 0
            return SmartSort(by: s.by, days: days == 0 ? nil : days, desc: s.desc)
        }
        out.limit = limit.flatMap { $0 == 0 ? nil : Self.clamp($0, 1, Self.maxLimit) }
        return out
    }
}
