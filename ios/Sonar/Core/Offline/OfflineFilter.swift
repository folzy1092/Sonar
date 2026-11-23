import Foundation

/// Чистые правила офлайна (`docs/OFFLINE.md` §6): что показывать и как подписать. Доступен — есть на
/// телефоне файлом (скачан, в кэше волны). Недоступное скрыто, не серое.
@MainActor
struct OfflineFilter {
    let isAvailable: @MainActor (String) -> Bool

    func tracks(_ list: [Track]) -> [Track] {
        list.filter { isAvailable($0.ref) }
    }

    func count(_ list: [Track]) -> Int {
        list.reduce(0) { $0 + (isAvailable($1.ref) ? 1 : 0) }
    }

    /// «12 из 40 · офлайн»; доступно всё — просто число треков.
    static func countText(available: Int, total: Int) -> String {
        available == total ? tracksCount(total) : t("{n} из {m} · офлайн", ["n": "\(available)", "m": "\(total)"])
    }
}

/// Очередь при включении офлайна (§9): из «Далее» и «Было» уходит недоступное, текущий трек остаётся
/// на месте (недоступный затихает и встаёт на паузу в `PlaybackEngine.offlineChanged`).
enum OfflineQueue {
    /// Затухание недоступного трека: 12 шагов по 50 мс ≈ 0,6 с.
    static let fadeSteps = 12
    static let fadeStepMs = 50

    static func prune(order: [Int], pos: Int, isAvailable: (Int) -> Bool) -> (order: [Int], pos: Int) {
        guard order.indices.contains(pos) else { return (order.filter(isAvailable), 0) }
        let before = order[..<pos].filter(isAvailable)
        let after = order[(pos + 1)...].filter(isAvailable)
        return (before + [order[pos]] + after, before.count)
    }
}

/// Предложить офлайн-режим, когда пропала сеть (`general.offline_suggest`, как ПК `suggestOnNetwork`):
/// одна плашка на одну пропажу (`shown` — уже предлагали), сеть вернулась — счёт сначала.
enum OfflineSuggest {
    static let key = "general.offline_suggest"

    static func next(shown: Bool, online: Bool, modeOn: Bool, enabled: Bool) -> (shown: Bool, show: Bool) {
        if online { return (false, false) }
        if shown || modeOn || !enabled { return (shown, false) }
        return (true, true)
    }
}

/// Поиск в офлайне (§6): только среди того, что есть на телефоне, по названию, артисту и альбому —
/// каждое слово запроса должно найтись. Порядок — как в списке (скачанное сверху).
enum OfflineSearch {
    static func match(_ list: [Track], query: String) -> [Track] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        return list.filter { track in
            let text = [track.title, track.artist, track.album?.title ?? ""].joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }
}
