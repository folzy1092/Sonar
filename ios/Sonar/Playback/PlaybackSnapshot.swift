import Foundation

/// Что играло — для «Продолжить с прошлого раза» (`general.restore`, как Windows `player_state`):
/// очередь, порядок, позиция в порядке и секунда трека. JSON в Application Support, пока нет SQLite.
struct PlaybackSnapshot: Codable, Equatable, Sendable {
    var tracks: [Track]
    var order: [Int]
    var pos: Int
    var position: Double
    var context: String
    var shuffle: Bool
    var repeatMode: RepeatMode
    /// Треки «Авто похожих» — в очереди отдельным блоком.
    var autoRefs: [String]

    var current: Track? {
        order.indices.contains(pos) && tracks.indices.contains(order[pos]) ? tracks[order[pos]] : nil
    }

    /// Что вернуть по настройке: `none` — ничего, `track` — только трек (с той же секунды), `queue` — всё.
    /// Битый снимок (индексы мимо списка) — nil.
    func restored(_ mode: RestoreMode) -> PlaybackSnapshot? {
        guard order.allSatisfy({ tracks.indices.contains($0) }), let current else { return nil }
        switch mode {
        case .none:
            return nil
        case .track:
            return PlaybackSnapshot(tracks: [current], order: [0], pos: 0, position: position, context: context,
                                    shuffle: false, repeatMode: repeatMode == .one ? .one : .off, autoRefs: [])
        case .queue:
            return self
        }
    }

    /// Очередь бывает длинной (волна, «Авто похожие»): храним не больше 50 прошлых и 300 следующих.
    func trimmed(past: Int = 50, ahead: Int = 300) -> PlaybackSnapshot {
        guard order.indices.contains(pos) else { return self }
        let from = max(0, pos - past)
        let to = min(order.count, pos + 1 + ahead)
        let kept = Array(order[from ..< to])
        // переиндексируем: в списке только треки, которые остались в порядке (их взаимный порядок прежний)
        var remap: [Int: Int] = [:]
        var list: [Track] = []
        for index in Set(kept).sorted() {
            remap[index] = list.count
            list.append(tracks[index])
        }
        let refs = Set(list.map(\.ref))
        return PlaybackSnapshot(tracks: list, order: kept.map { remap[$0]! }, pos: pos - from, position: position,
                                context: context, shuffle: shuffle, repeatMode: repeatMode,
                                autoRefs: autoRefs.filter(refs.contains))
    }
}

/// Файл снимка: `Application Support/Sonar/player-state.json`.
struct PlaybackSnapshotFile: Sendable {
    let url: URL

    init(url: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.url = url ?? base.appendingPathComponent("Sonar/player-state.json")
    }

    func load() -> PlaybackSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }

    func save(_ snapshot: PlaybackSnapshot?) {
        guard let snapshot else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot.trimmed()) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
