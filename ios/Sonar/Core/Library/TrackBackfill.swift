import Foundation

/// Добивка обложки и длины у треков, где их нет (перенос из Dotify, старый синк) — `docs/NOW_ACCURACY_PROMPT.md` §2.
/// Чистые правила — зеркало ПК `windows/src/lib/track-backfill.ts`, **правила менять в обоих местах**.
enum TrackBackfill {
    /// Сколько ref спрашивать за раз и пауза между пачками — сервисы не любят очереди запросов подряд.
    static let batchSize = 20
    static let pauseMs = 1500
    /// Добивать умеем только у сервисов, у которых есть «трек по id».
    static let prefixes = ["sc:", "ym:"]

    static func supported(_ ref: String) -> Bool {
        prefixes.contains { ref.hasPrefix($0) }
    }

    /// Нет обложки или длины — и сервис умеет отдать трек по id.
    static func needs(_ track: Track) -> Bool {
        supported(track.ref) && ((track.coverURL ?? "").isEmpty || track.durationMs <= 0)
    }

    /// Из свежего берём только недостающее: название, артист и остальное у старого не трогаем.
    static func merge(_ old: Track, _ fresh: Track) -> Track {
        var out = old
        if (old.coverURL ?? "").isEmpty, let cover = fresh.coverURL, !cover.isEmpty { out.coverURL = cover }
        if old.durationMs <= 0, fresh.durationMs > 0 { out.durationMs = fresh.durationMs }
        return out
    }

    /// Очередь следующей пачки: текущий трек первым, дальше по списку, без повторов и без уже спрошенных.
    static func plan(_ tracks: [Track], first: String?, tried: Set<String>, limit: Int = batchSize) -> [String] {
        let wanted = tracks.filter { needs($0) && !tried.contains($0.ref) }.map(\.ref)
        let head = first.map { ref in wanted.contains(ref) ? [ref] : [] } ?? []
        var seen = Set<String>()
        var out: [String] = []
        for ref in head + wanted where out.count < limit && seen.insert(ref).inserted {
            out.append(ref)
        }
        return out
    }
}

/// Сама добивка: спрашивает сервис по ref (`MusicCore.track(ref:)` — в офлайне ни байта), пишет найденное в Любимые
/// (уходит синком на ПК и сервер). Каждый ref спрашивается один раз до перезапуска — промах больше не дёргаем.
@MainActor
final class TrackBackfiller {
    static let shared = TrackBackfiller()

    /// Трек по ref; тесты подставляют свой.
    var fetch: @MainActor (String) async -> Track? = { await MusicCore.shared.track(ref: $0) }
    var library: LibraryStore = .shared
    /// Пауза между пачками (мс); тесты ставят 0.
    var pauseMs = TrackBackfill.pauseMs
    private(set) var tried: Set<String> = []
    private var running: Task<Void, Never>?

    /// Один трек вне очереди (текущий в плеере). nil — добивать нечего или сервис не помог.
    func fill(_ track: Track) async -> Track? {
        guard TrackBackfill.needs(track), !OfflineFlag.isOn, tried.insert(track.ref).inserted,
              let fresh = await fetch(track.ref) else { return nil }
        let merged = TrackBackfill.merge(track, fresh)
        guard merged != track else { return nil }
        library.fillMeta([merged])
        return merged
    }

    /// Любимые лениво: пачками по 20 с паузой, текущий трек первым. Уже идёт — второй раз не запускаем.
    func fillLiked(first: String?) {
        guard running == nil else { return }
        running = Task {
            await runLiked(first: first)
            running = nil
        }
    }

    func runLiked(first: String?) async {
        while !Task.isCancelled, !OfflineFlag.isOn {
            let batch = TrackBackfill.plan(library.liked, first: first, tried: tried)
            if batch.isEmpty { return }
            var filled: [Track] = []
            for ref in batch where !OfflineFlag.isOn {
                tried.insert(ref)
                guard let old = library.liked.first(where: { $0.ref == ref }), let fresh = await fetch(ref) else { continue }
                let merged = TrackBackfill.merge(old, fresh)
                if merged != old { filled.append(merged) }
            }
            library.fillMeta(filled)
            if pauseMs > 0 { try? await Task.sleep(for: .milliseconds(pauseMs)) }
        }
    }
}
