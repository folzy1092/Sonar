import Foundation

/// Группа дублей: первым — кого оставить по умолчанию (`keep`), остальные — по порядку списка.
struct DupeGroup: Sendable, Equatable {
    let tracks: [Track]
    var keep: Track { tracks[0] }
    /// Лишние — все, кроме оставляемого.
    var extra: [Track] { Array(tracks.dropFirst()) }
}

/// Поиск дублей в Любимых и своих плейлистах (этап 7 NEXT_PROMPT) — без сети, по сохранённым метаданным.
/// Порт `windows/src-tauri/src/dupes/mod.rs`. Дубли: тот же ref ещё раз; тот же трек из другого сервиса и
/// почти то же название того же исполнителя с длительностью ±3 с (`TrackMatch`: «версии» — remix, live,
/// sped up… — должны совпасть). Строже, чем `TrackMatch`: числа в названии совпадают («Part 1» ≠ «Part 2»),
/// а если длительность одного из треков неизвестна — название без мусора совпадает целиком.
/// Кого оставить: доступный > лучше звук (`ServiceRegistry.qualityOrder`) > добавлен раньше > выше в списке.
enum DupeFinder {
    private static let number = Pattern(#"\d+"#)

    /// Трек с заранее посчитанным: что искать, название и числа для строгой сверки.
    private struct Entry {
        let track: Track
        let match: TrackMatch
        let titleKey: String
        let numbers: [String]

        init(_ track: Track) {
            self.track = track
            match = TrackMatch.from(track)
            titleKey = TrackText.norm(match.titles.first ?? TrackText.cleanTitle(track.title))
            numbers = DupeFinder.number.findAll(titleKey).map { digits in
                let trimmed = digits.drop { $0 == "0" }
                return String(trimmed)
            }
        }

        /// Имена исполнителей: общее имя — необходимое условие совпадения (порт `artist_keys`).
        var artistKeys: Set<String> {
            let names = match.artists.flatMap(TrackMatch.artistNames)
                + track.artists.map { TrackText.norm($0.name) }
                + TrackMatch.artistNames(track.artist)
            return Set(names.filter { !$0.isEmpty })
        }
    }

    /// Группы дублей по порядку списка (по первому треку группы); треки без пары не попадают.
    /// newestFirst — список идёт от новых к старым (Любимые): «добавлен раньше» — тот, что ниже.
    static func groups(_ tracks: [Track], newestFirst: Bool) -> [DupeGroup] {
        let entries = tracks.map(Entry.init)
        var sets = DisjointSets(count: entries.count)
        var byRef: [String: [Int]] = [:]
        var byArtist: [String: [Int]] = [:]
        for (i, entry) in entries.enumerated() {
            byRef[entry.track.ref, default: []].append(i)
            for key in entry.artistKeys { byArtist[key, default: []].append(i) }
        }
        for same in byRef.values { for i in same.dropFirst() { sets.join(same[0], i) } }
        for bucket in byArtist.values where bucket.count > 1 { scan(bucket, entries, &sets) }

        var members: [Int: [Int]] = [:]
        for i in entries.indices { members[sets.root(i), default: []].append(i) }
        return members
            .filter { $0.value.count > 1 }
            .sorted { $0.key < $1.key }
            .map { group(of: $0.value, tracks, newestFirst: newestFirst) }
    }

    /// Один ли это трек (см. описание).
    private static func twins(_ a: Entry, _ b: Entry) -> Bool {
        if a.track.ref == b.track.ref { return true }
        guard a.numbers == b.numbers else { return false }
        if (a.track.durationMs <= 0 || b.track.durationMs <= 0) && a.titleKey != b.titleKey { return false }
        return a.match.score(b.track, reuploads: b.track.service == .soundcloud) != nil
            || b.match.score(a.track, reuploads: a.track.service == .soundcloud) != nil
    }

    /// Пары внутри «корзины» одного исполнителя: с известной длительностью — соседи в окне ±3 с,
    /// с неизвестной — со всеми.
    private static func scan(_ bucket: [Int], _ entries: [Entry], _ sets: inout DisjointSets) {
        let known = bucket.filter { entries[$0].track.durationMs > 0 }.sorted { entries[$0].track.durationMs < entries[$1].track.durationMs }
        let unknown = bucket.filter { entries[$0].track.durationMs <= 0 }
        for (pos, a) in known.enumerated() {
            for b in known[(pos + 1)...] {
                if entries[b].track.durationMs - entries[a].track.durationMs > TrackMatch.maxDurationDiffMs { break }
                check(a, b, entries, &sets)
            }
        }
        for u in unknown { for b in bucket { check(u, b, entries, &sets) } }
    }

    private static func check(_ a: Int, _ b: Int, _ entries: [Entry], _ sets: inout DisjointSets) {
        guard a != b, sets.root(a) != sets.root(b), twins(entries[a], entries[b]) else { return }
        sets.join(a, b)
    }

    /// Группа из индексов по порядку списка: лучший — первым.
    private static func group(of indices: [Int], _ tracks: [Track], newestFirst: Bool) -> DupeGroup {
        func key(_ i: Int) -> (Int, Int, Int) {
            let track = tracks[i]
            return (track.available ? 0 : 1, ServiceRegistry.qualityRank(track.ref), newestFirst ? -i : i)
        }
        let best = indices.min { key($0) < key($1) } ?? indices[0]
        return DupeGroup(tracks: [tracks[best]] + indices.filter { $0 != best }.map { tracks[$0] })
    }
}

/// Непересекающиеся множества: дубль дубля — тоже дубль. Корень — меньший индекс (место в списке).
private struct DisjointSets {
    private var parent: [Int]

    init(count: Int) { parent = Array(0..<count) }

    mutating func root(_ i: Int) -> Int {
        var i = i
        while parent[i] != i {
            parent[i] = parent[parent[i]]
            i = parent[i]
        }
        return i
    }

    mutating func join(_ a: Int, _ b: Int) {
        let (ra, rb) = (root(a), root(b))
        if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
    }
}
