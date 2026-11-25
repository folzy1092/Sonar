import Foundation

/// «Авто похожие», как в SoundCloud: любая очередь не обрывается — когда до конца меньше трёх треков,
/// в конец дописываются похожие (от последнего трека и от случайного из твоей части очереди, чтобы
/// продолжение держалось темы). Порт `windows/src/player/autoplay.svelte.ts`; тумблер —
/// `general.similar_autoplay`.
enum Autoplay {
    /// Догружать, когда до конца очереди осталось меньше стольких треков.
    static let left = 3
    /// Сколько похожих дописывать за раз.
    static let batch = 10

    /// Похожие для продолжения: списки от разных сидов чередуются; без треков из очереди, 👎, артистов
    /// «Никогда» (`never`), недоступных и повторов; не больше n.
    static func freshSimilar(_ lists: [[Track]], inQueue: Set<String>, disliked: (String) -> Bool, limit n: Int,
                             never: (Track) -> Bool = { _ in false }) -> [Track] {
        var seen = inQueue
        var out: [Track] = []
        let longest = lists.map(\.count).max() ?? 0
        for i in 0 ..< longest where out.count < n {
            for list in lists where i < list.count {
                let track = list[i]
                if !track.available || disliked(track.ref) || seen.contains(track.ref) || never(track) { continue }
                seen.insert(track.ref)
                out.append(track)
                if out.count >= n { break }
            }
        }
        return out
    }

    /// Сиды: последний трек очереди и случайный из твоей (не автоплейной) части.
    static func seeds(_ queue: [Track], auto: Set<String>, random: () -> Double = { Double.random(in: 0 ..< 1) }) -> [Track] {
        guard let last = queue.last else { return [] }
        let own = queue.filter { !auto.contains($0.ref) && $0.ref != last.ref }
        guard !own.isEmpty else { return [last] }
        return [last, own[Int(random() * Double(own.count))]]
    }

    /// Где в «Далее» кончается твоя очередь и начинаются похожие автоплея: номер первого похожего
    /// (нет похожих — `upcoming.count`). Порт `queueView` ПК: похожие идут сплошным хвостом.
    static func autoStart(_ upcoming: [Track], auto: Set<String>) -> Int {
        upcoming.firstIndex { auto.contains($0.ref) } ?? upcoming.count
    }

    /// Где в уже сыгранном (`history` и текущий последним) пошли похожие: номер первого похожего, но
    /// только если до него есть что-то твоё — иначе чертой отделять не от чего.
    static func playedBoundary(_ played: [Track], auto: Set<String>) -> Int? {
        guard let first = played.firstIndex(where: { auto.contains($0.ref) }), first > 0 else { return nil }
        return first
    }
}
