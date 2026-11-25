import Foundation

// Свои плейлисты Sonar в синке (API.md §6): `playlist` `pl_…` {name, hidden, source_ref, created_at, updated_at} и
// `playlist_item` <id элемента> {playlist_id, ref, position, added_at, track}. На ПК это строки SQLite с дробной
// `position`; на телефоне — `PlaylistStore` со списком треков, без id элементов. Id и позиции телефон берёт из
// журнала синка (что пришло или ушло раньше), новым — придумывает: id из плейлиста и ref, позицию между соседями.

/// Порядок элементов через дробную `position`, как на ПК (`add_to_playlist`, `reorder_playlist`): известные позиции
/// по возможности не меняются — остаётся самая длинная возрастающая цепочка, остальные встают между её звеньями.
/// Тогда перенос одного трека на телефоне — одна строка в синке, а не весь плейлист.
enum PlaylistOrder {
    /// Позиции для списка, где `known[i]` — прошлая позиция i-го трека (nil — новый). Строго возрастают.
    static func positions(_ known: [Double?]) -> [Double] {
        let n = known.count
        guard n > 0 else { return [] }
        let anchors = longestIncreasing(known)
        var out = [Double](repeating: 0, count: n)
        for i in anchors { out[i] = known[i] ?? 0 }
        var bounds: [Int?] = [nil]
        bounds += anchors.map { Optional($0) }
        bounds.append(nil)
        for b in 0 ..< bounds.count - 1 {
            let lower = bounds[b], upper = bounds[b + 1]
            let start = (lower ?? -1) + 1, end = upper ?? n
            guard start < end else { continue }
            switch (lower, upper) {
            case let (l?, u?):
                let lo = out[l], hi = out[u], span = Double(u - l)
                for i in start ..< end { out[i] = lo + (hi - lo) * Double(i - l) / span }
            case let (nil, u?):
                for i in start ..< end { out[i] = out[u] - Double(u - i) }
            case let (l?, nil):
                for i in start ..< end { out[i] = out[l] + Double(i - l) }
            case (nil, nil):
                for i in start ..< end { out[i] = Double(i) }
            }
        }
        // промежуток кончился (сотни переносов в одно место) — чуть выше соседа
        for i in 1 ..< n where out[i] <= out[i - 1] { out[i] = out[i - 1].nextUp }
        return out
    }

    /// Индексы самой длинной строго возрастающей подпоследовательности известных значений.
    static func longestIncreasing(_ values: [Double?]) -> [Int] {
        var tails: [Int] = []
        var prev = [Int](repeating: -1, count: values.count)
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if values[tails[mid]]! < v { lo = mid + 1 } else { hi = mid }
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

    /// Число в JSON так, чтобы оно пережило запись журнала в файл: целое — `.int` (JSONDecoder прочтёт `1.0` как 1).
    static func json(_ value: Double) -> JSONValue {
        value.rounded() == value && abs(value) < 9e15 ? .int(Int(value)) : .double(value)
    }

    /// Id элемента, добавленного на телефоне: один и тот же для пары (плейлист, трек), чтобы повторный снимок
    /// не плодил новых строк. FNV-1a, 64 бита — `hashValue` Swift от запуска к запуску другой.
    static func itemId(playlist: String, ref: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(playlist)|\(ref)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "pi_" + String(hash, radix: 16)
    }
}

/// `playlist` и `playlist_item` ↔ `PlaylistStore`. Пришедшее не применяется по одному: `apply` только помечает
/// плейлист, а `finishApply` пересобирает помеченные из журнала разом (элемент может прийти раньше своего
/// плейлиста — он ждёт в журнале «чужим»). Дубль трека в одном плейлисте ПК телефон показывает один раз,
/// лишний элемент остаётся «чужим» и с ПК не удаляется.
@MainActor
final class PlaylistSyncAdapter: SyncAdapter {
    let types: Set<String> = ["playlist", "playlist_item"]
    private let store: PlaylistStore
    private let now: () -> Int64
    private var dirty: Set<String> = []
    /// Карточки треков в формате синка: снимок снимается на каждую правку, а кодировать 400 треков каждый раз дорого.
    private var cards: [Track: JSONValue] = [:]

    init(store: PlaylistStore, now: @escaping () -> Int64) {
        self.store = store
        self.now = now
    }

    private struct Item {
        var key: String
        var value: JSONValue
        var foreign: Bool
        var position: Double { value["position"].number ?? 0 }
    }

    /// Живые элементы журнала по плейлистам.
    private static func items(_ journal: SyncJournal) -> [String: [Item]] {
        var out: [String: [Item]] = [:]
        for (key, row) in journal.rows where key.type == "playlist_item" && !row.value.isNull {
            guard let playlist = row.value["playlist_id"].string, row.value["ref"].string != nil else { continue }
            out[playlist, default: []].append(Item(key: key.key, value: row.value, foreign: row.foreign))
        }
        return out
    }

    func snapshot(journal: SyncJournal) -> [SyncKey: JSONValue] {
        let items = Self.items(journal)
        var out: [SyncKey: JSONValue] = [:]
        for playlist in store.playlists {
            out[SyncKey("playlist", playlist.id)] = .object([
                "name": .string(playlist.name),
                "hidden": .bool(playlist.hidden),
                "source_ref": playlist.sourceRef.map { JSONValue.string($0) } ?? .null,
                "created_at": .int(playlist.createdAt),
                "updated_at": .int(playlist.updatedAt),
            ])
            // id элемента по ref: своё (уже отправленное) важнее «чужого» дубля
            var byRef: [String: Item] = [:]
            for item in (items[playlist.id] ?? []).sorted(by: { $0.key < $1.key }) {
                guard let ref = item.value["ref"].string else { continue }
                if let have = byRef[ref], !have.foreign || item.foreign { continue }
                byRef[ref] = item
            }
            let known = playlist.tracks.map { byRef[$0.ref].map(\.position) }
            let positions = PlaylistOrder.positions(known)
            for (track, position) in zip(playlist.tracks, positions) {
                let prev = byRef[track.ref]
                let id = prev?.key ?? PlaylistOrder.itemId(playlist: playlist.id, ref: track.ref)
                let at = prev?.value["added_at"].int64 ?? journal.value("playlist_item", id)?["added_at"].int64 ?? now()
                out[SyncKey("playlist_item", id)] = .object([
                    "playlist_id": .string(playlist.id),
                    "ref": .string(track.ref),
                    "position": PlaylistOrder.json(position),
                    "added_at": .int(Int(at)),
                    "track": card(track),
                ])
            }
        }
        return out
    }

    private func card(_ track: Track) -> JSONValue {
        if let hit = cards[track] { return hit }
        if cards.count > 20000 { cards.removeAll() }
        let value = JSONValue.encode(track)
        cards[track] = value
        return value
    }

    func apply(_ change: SyncChange, journal: SyncJournal) -> Bool {
        switch change.type {
        case "playlist":
            dirty.insert(change.key)
        default:
            if let playlist = change.value["playlist_id"].string {
                dirty.insert(playlist)
            } else {
                // удалённый элемент: в журнале уже `.null`, из какого он плейлиста — не узнать. Пересобрать все —
                // безвредно (снимок уже в журнале), запись файла всё равно одна
                dirty.formUnion(store.playlists.map(\.id))
            }
        }
        return false // применится в `finishApply`
    }

    func finishApply(journal: SyncJournal) -> Set<SyncKey> {
        guard !dirty.isEmpty else { return [] }
        defer { dirty = [] }
        let items = Self.items(journal)
        var upsert: [SonarPlaylist] = []
        var remove: Set<String> = []
        var adopted: Set<SyncKey> = []
        for id in dirty.sorted() {
            let key = SyncKey("playlist", id)
            guard let value = journal.value(key) else {
                // элементы есть, а самого плейлиста ещё нет — ждём его, элементы остаются «чужими»
                continue
            }
            adopted.insert(key)
            if value.isNull {
                if store.playlist(id) != nil { remove.insert(id) }
                continue
            }
            let existing = store.playlist(id)
            let known = Dictionary((existing?.tracks ?? []).map { ($0.ref, $0) }, uniquingKeysWith: { a, _ in a })
            var tracks: [Track] = []
            var seen = Set<String>()
            let sorted = (items[id] ?? []).sorted {
                ($0.position, $0.value["added_at"].int64 ?? 0, $0.key) < ($1.position, $1.value["added_at"].int64 ?? 0, $1.key)
            }
            for item in sorted {
                guard let ref = item.value["ref"].string, !seen.contains(ref),
                      let track = item.value["track"].decode(Track.self) ?? known[ref] else { continue }
                seen.insert(ref)
                tracks.append(track)
                adopted.insert(SyncKey("playlist_item", item.key))
            }
            let stamp = Int(now())
            upsert.append(SonarPlaylist(
                id: id,
                name: value["name"].string.flatMap(PlaylistMath.cleanName) ?? existing?.name ?? "Плейлист",
                tracks: tracks,
                hidden: value["hidden"].bool ?? existing?.hidden ?? false,
                sourceRef: value["source_ref"].string,
                createdAt: value["created_at"].int ?? existing?.createdAt ?? stamp,
                updatedAt: value["updated_at"].int ?? existing?.updatedAt ?? stamp))
        }
        // удалённые элементы — тоже приняты (их уже нет в пересобранном списке)
        for (key, row) in journal.rows where key.type == "playlist_item" && row.value.isNull && row.foreign {
            adopted.insert(key)
        }
        store.applySynced(upsert: upsert, remove: remove)
        return adopted
    }
}
