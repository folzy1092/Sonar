import Foundation

// Адаптеры синка для того, что уже есть на iPhone. Формат значений — как шлёт Windows (API.md §6):
// `like` {kind, added_at, track}, `dislike` {artist, added_at}, `track_pref` {speed, lyrics_offset_ms},
// `setting` — значение. `DownloadStore` (офлайн-файлы) не синхронизируется: это файлы этого телефона.

/// Порядок Любимых через `added_at`: на ПК они идут по `added_at` убыванию, на iPhone их можно
/// перетаскивать. Чтобы порядок совпал везде, перетаскивание меняет `added_at` только перенесённого
/// трека (середина между соседями), остальные сохраняют свои — «самая длинная убывающая цепочка»
/// известных времён остаётся, прочие встают между ней.
enum LikeOrder {
    /// Шаг между новыми временами (мс): чтобы между соседями оставалось место для переносов.
    static let step: Int64 = 1000

    /// Времена для списка `order` (новые первыми), строго убывающие. `known` — прошлые `added_at`.
    static func addedTimes(order: [String], known: [String: Int64], now: Int64) -> [Int64] {
        let n = order.count
        guard n > 0 else { return [] }
        let anchors = longestDecreasing(order.map { known[$0] })
        var out = [Int64](repeating: 0, count: n)
        for i in anchors { out[i] = known[order[i]] ?? 0 }
        // промежутки между якорями
        var bounds: [Int?] = [nil]
        bounds += anchors.map { Optional($0) }
        bounds.append(nil)
        for b in 0 ..< bounds.count - 1 {
            let upper = bounds[b], lower = bounds[b + 1]
            let start = (upper ?? -1) + 1, end = lower ?? n
            guard start < end else { continue }
            switch (upper, lower) {
            case let (u?, l?):
                let hi = out[u], lo = out[l], span = Int64(l - u)
                for i in start ..< end { out[i] = hi - (hi - lo) * Int64(i - u) / span }
            case let (nil, l?):
                let top = max(now, out[l] + Int64(l) * step)
                for i in start ..< end { out[i] = top - Int64(i) * step }
            case let (u?, nil):
                for i in start ..< end { out[i] = out[u] - Int64(i - u) * step }
            case (nil, nil):
                for i in start ..< end { out[i] = now - Int64(i) * step }
            }
        }
        // тесные промежутки (между соседями нет места) — сдвинуть вниз
        for i in 1 ..< n where out[i] >= out[i - 1] { out[i] = out[i - 1] - 1 }
        return out
    }

    /// Индексы самой длинной строго убывающей подпоследовательности известных значений.
    static func longestDecreasing(_ values: [Int64?]) -> [Int] {
        // LIS по −value: tails[k] — индекс конца цепочки длины k+1 с наибольшим концом
        var tails: [Int] = []
        var prev = [Int](repeating: -1, count: values.count)
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if values[tails[mid]]! > v { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 { prev[i] = tails[lo - 1] }
            if lo == tails.count { tails.append(i) } else { tails[lo] = i }
        }
        var out: [Int] = []
        var k = tails.last ?? -1
        while k >= 0 {
            out.append(k)
            k = prev[k]
        }
        return out.reversed()
    }

    /// Куда вставить пришедший лайк со временем `t` в список с временами `times` (новые первыми).
    static func insertIndex(_ t: Int64, times: [Int64]) -> Int {
        times.firstIndex { $0 < t } ?? times.count
    }
}

/// Любимые треки (`like`). Альбомы и исполнители из лайков ПК телефон пока не хранит — «чужие» строки.
@MainActor
final class LikesSyncAdapter: SyncAdapter {
    let types: Set<String> = ["like"]
    private let library: LibraryStore
    private let now: () -> Int64

    init(library: LibraryStore, now: @escaping () -> Int64) {
        self.library = library
        self.now = now
    }

    private func times(journal: SyncJournal) -> [Int64] {
        var known: [String: Int64] = [:]
        for track in library.liked {
            if let t = journal.value("like", track.ref)?["added_at"].int64 { known[track.ref] = t }
        }
        return LikeOrder.addedTimes(order: library.liked.map(\.ref), known: known, now: now())
    }

    func snapshot(journal: SyncJournal) -> [SyncKey: JSONValue] {
        var out: [SyncKey: JSONValue] = [:]
        for (track, at) in zip(library.liked, times(journal: journal)) {
            out[SyncKey("like", track.ref)] = .object(["kind": .string("track"), "added_at": .int(Int(at)), "track": .encode(track)])
        }
        return out
    }

    func apply(_ change: SyncChange, journal: SyncJournal) -> Bool {
        if change.value.isNull {
            if library.likedRefs.contains(change.key) {
                library.applySynced(liked: library.liked.filter { $0.ref != change.key })
            }
            return true
        }
        let kind = change.value["kind"].string ?? "track"
        guard kind == "track" else { return false }
        let existing = library.liked.first { $0.ref == change.key }
        guard let track = change.value["track"].decode(Track.self) ?? existing else { return false }
        var list = library.liked.filter { $0.ref != change.key }
        var known: [String: Int64] = [:]
        for item in list {
            if let t = journal.value("like", item.ref)?["added_at"].int64 { known[item.ref] = t }
        }
        let current = LikeOrder.addedTimes(order: list.map(\.ref), known: known, now: now())
        let at = change.value["added_at"].int64 ?? now()
        list.insert(track, at: LikeOrder.insertIndex(at, times: current))
        if list != library.liked {
            library.applySynced(liked: list, likedAt: existing == nil ? [track.ref: Int(at)] : [:])
        }
        return true
    }
}

/// 👎 «Не интересно» (`dislike`). Артиста телефон не хранит — берём из прошлого значения или из трека.
@MainActor
final class DislikesSyncAdapter: SyncAdapter {
    let types: Set<String> = ["dislike"]
    private let library: LibraryStore
    private let artist: (String) -> String?
    private let now: () -> Int64

    init(library: LibraryStore, artist: @escaping (String) -> String?, now: @escaping () -> Int64) {
        self.library = library
        self.artist = artist
        self.now = now
    }

    func snapshot(journal: SyncJournal) -> [SyncKey: JSONValue] {
        var out: [SyncKey: JSONValue] = [:]
        for ref in library.disliked {
            let prev = journal.value("dislike", ref)
            let name = prev?["artist"].string ?? artist(ref) ?? ""
            let at = prev?["added_at"].int64 ?? now()
            out[SyncKey("dislike", ref)] = .object(["artist": .string(name), "added_at": .int(Int(at))])
        }
        return out
    }

    func apply(_ change: SyncChange, journal: SyncJournal) -> Bool {
        var set = library.disliked
        if change.value.isNull { set.remove(change.key) } else { set.insert(change.key) }
        if set != library.disliked { library.applySynced(disliked: set) }
        return true
    }
}

/// Настройки трека (`track_pref`): «Запомнить» скорость (`LibraryStore.speeds`) и сдвиг текста
/// (`LyricsStore.offsets`, мс).
@MainActor
final class TrackPrefsSyncAdapter: SyncAdapter {
    let types: Set<String> = ["track_pref"]
    private let library: LibraryStore
    private let offsets: () -> [String: Int]
    private let setOffset: (String, Int?) -> Void

    init(library: LibraryStore, offsets: @escaping () -> [String: Int], setOffset: @escaping (String, Int?) -> Void) {
        self.library = library
        self.offsets = offsets
        self.setOffset = setOffset
    }

    static func speedValue(_ speed: Float?) -> JSONValue {
        guard let speed else { return .null }
        return .double((Double(speed) * 1000).rounded() / 1000)
    }

    func snapshot(journal: SyncJournal) -> [SyncKey: JSONValue] {
        let offsets = offsets().filter { $0.value != 0 }
        let refs = Set(library.speeds.keys).union(offsets.keys)
        var out: [SyncKey: JSONValue] = [:]
        for ref in refs {
            out[SyncKey("track_pref", ref)] = .object([
                "speed": Self.speedValue(library.speeds[ref]),
                "lyrics_offset_ms": offsets[ref].map { .int($0) } ?? .null,
            ])
        }
        return out
    }

    func apply(_ change: SyncChange, journal: SyncJournal) -> Bool {
        var speeds = library.speeds
        speeds[change.key] = change.value["speed"].number.map { Float($0) }
        if speeds != library.speeds { library.applySynced(speeds: speeds) }
        let ms = change.value["lyrics_offset_ms"].int
        if offsets()[change.key] != ms { setOffset(change.key, ms) }
        return true
    }
}

/// Настройки (`setting`) — только синхронизируемые ключи (`SyncPolicy`). Значения-объекты ПК
/// (`player.tempo` и т.п.) телефон не хранит — они остаются «чужими» строками журнала.
@MainActor
final class SettingsSyncAdapter: SyncAdapter {
    let types: Set<String> = ["setting"]
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    static func json(_ value: SettingValue) -> JSONValue {
        switch value {
        case let .bool(v): .bool(v)
        case let .int(v): .int(v)
        case let .double(v): .double(v)
        case let .string(v): .string(v)
        }
    }

    static func setting(_ json: JSONValue) -> SettingValue? {
        switch json {
        case let .bool(v): .bool(v)
        case let .int(v): .int(v)
        case let .double(v): .double(v)
        case let .string(v): .string(v)
        default: nil
        }
    }

    func snapshot(journal: SyncJournal) -> [SyncKey: JSONValue] {
        var out: [SyncKey: JSONValue] = [:]
        for (key, value) in settings.storedValues where SyncPolicy.settingSyncs(key) {
            out[SyncKey("setting", key)] = Self.json(value)
        }
        return out
    }

    func apply(_ change: SyncChange, journal: SyncJournal) -> Bool {
        guard SyncPolicy.settingSyncs(change.key) else { return false }
        if change.value.isNull {
            settings.remove(change.key)
            return true
        }
        guard let value = Self.setting(change.value) else { return false }
        if settings.storedValues[change.key] != value { settings.set(change.key, value) }
        return true
    }
}

extension PlayUpload {
    /// Прослушивания журнала «Статистики» (`PlayLog`) после метки `since` (мс). Последнее, ещё
    /// идущее (моложе часа), не отправляется: его длительность допишется при смене трека.
    @MainActor
    static func from(_ rows: [PlayRow], since: Int64, now: Date) -> [PlayUpload] {
        let ms = { (d: Date) in Int64(d.timeIntervalSince1970 * 1000) }
        var out = rows.filter { ms($0.at) > since }.sorted { $0.at < $1.at }
        if let last = out.last, last.at == rows.map(\.at).max(), now.timeIntervalSince(last.at) < 3600 {
            out.removeLast()
        }
        return out.map { PlayUpload(ref: $0.ref, playedAt: ms($0.at), listenedMs: $0.ms, context: nil) }
    }
}
