import Foundation

// «Схожесть» вкуса в профиле друга (docs/NEXT_FRIEND.md §2) — порт `windows/src/lib/taste-match.ts`, та же
// формула на сервере (`GET /users/{username}/taste`, docs/API.md): менять — во всех трёх местах и в тестах.
//
// Процент = √(0.7 · исполнители + 0.3 · лайки) · 100, где
//  • исполнители — Σ min(доля у меня, доля у друга) по общим, доля — прослушивания / все прослушивания топа;
//  • лайки — общие / max(меньший список, 20).
// Нет лайков у кого-то — только исполнители; нет топа — только лайки; нет ничего — nil.
// Имена сравниваются без регистра, ё = е: у друга тот же артист может быть с другого сервиса.
// Экрана на iPhone пока нет — профили друзей появятся с сервером; тесты гоняют на Linux.

/// Что умеет сравниваться как трек: ref и «артист — название».
protocol TasteTrack {
    var ref: String { get }
    var title: String { get }
    var artist: String { get }
}

extension Track: TasteTrack {}

struct TasteArtist: Codable, Hashable, Sendable {
    var name: String
    var ref: String?
    var avatarURL: String?
    var plays: Int

    enum CodingKeys: String, CodingKey {
        case name, ref, plays
        case avatarURL = "avatar_url"
    }
}

struct TasteSide<T: TasteTrack> {
    var artists: [TasteArtist]
    var likes: [T]
}

/// ≥ 85 — «Очень похожие вкусы», ≥ 60 — «Похожие вкусы», ниже — «Разные вкусы».
enum TasteLevel: String, Sendable {
    case very, similar, different
}

struct TasteResult<T: TasteTrack> {
    /// 0…100.
    let percent: Int
    let level: TasteLevel
    /// Общие исполнители: сначала те, кого оба слушают больше всего.
    let artists: [TasteArtist]
    /// Общие лайки — мои экземпляры (их можно сыграть), в порядке моих Любимых.
    let tracks: [T]
}

enum TasteMath {
    static let artistWeight = 0.7
    static let likesWeight = 0.3
    /// Меньше этого числа лайков знаменатель не опускается.
    static let likesFloor = 20
    static let veryFrom = 85
    static let similarFrom = 60
    /// Сколько общих треков отдаёт расчёт.
    static let tracksShown = 5
    /// Сколько исполнителей и лайков берёт демо-друг.
    private static let demoStep = 3

    /// Ключ сравнения имён: без регистра, лишних пробелов, ё = е.
    static func key(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func level(_ percent: Int) -> TasteLevel {
        if percent >= veryFrom { return .very }
        if percent >= similarFrom { return .similar }
        return .different
    }

    /// Схожесть меня и друга; не с чем сравнивать (ни топа, ни лайков у кого-то) — nil.
    static func match<T: TasteTrack, F: TasteTrack>(me: TasteSide<T>, friend: TasteSide<F>) -> TasteResult<T>? {
        let artists = sharedArtists(me.artists, friend.artists)
        let likes = sharedLikes(me.likes, friend.likes)
        let raw: Double
        if artists.known && likes.known {
            raw = artistWeight * artists.overlap + likesWeight * likes.overlap
        } else if artists.known {
            raw = artists.overlap
        } else if likes.known {
            raw = likes.overlap
        } else {
            return nil
        }
        let percent = Int((min(1, max(0, raw)).squareRoot() * 100).rounded())
        return TasteResult(percent: percent, level: level(percent), artists: artists.list,
                           tracks: Array(likes.list.prefix(tracksShown)))
    }

    /// Демо-друг для предпросмотра, пока друзей нет: часть моих исполнителей с другим порядком
    /// прослушиваний, свой исполнитель, которого у меня нет, и каждый третий мой лайк. Как `demoFriendTaste` на ПК.
    static func demoFriend<T: TasteTrack>(_ me: TasteSide<T>) -> TasteSide<T> {
        let kept = me.artists.enumerated().filter { $0.offset % demoStep != demoStep - 1 }.map(\.element)
        let artists = kept.enumerated().map { index, artist in
            TasteArtist(name: artist.name, ref: artist.ref, avatarURL: artist.avatarURL,
                        plays: kept[kept.count - 1 - index].plays)
        }
        let stranger = TasteArtist(name: "\u{0}demo", ref: nil, avatarURL: nil, plays: me.artists.first?.plays ?? 1)
        let likes = me.likes.enumerated().filter { $0.offset % demoStep == 0 }.map(\.element)
        return TasteSide(artists: artists + [stranger], likes: likes)
    }

    // MARK: - Внутри

    private static func trackKey(_ track: some TasteTrack) -> String {
        "\(key(track.artist))\u{0}\(key(track.title))"
    }

    /// Доли прослушиваний по ключу имени (повторы одного имени складываются).
    private static func shares(_ artists: [TasteArtist]) -> [String: Double] {
        let total = artists.reduce(0) { $0 + max(0, $1.plays) }
        guard total > 0 else { return [:] }
        var out: [String: Double] = [:]
        for artist in artists where artist.plays > 0 {
            let name = key(artist.name)
            guard !name.isEmpty else { continue }
            out[name, default: 0] += Double(artist.plays) / Double(total)
        }
        return out
    }

    /// Один исполнитель на имя: ref и аватар — мои, чего нет у меня — у друга.
    private static func artistsByKey(_ all: [TasteArtist]) -> [String: TasteArtist] {
        var out: [String: TasteArtist] = [:]
        for artist in all {
            let name = key(artist.name)
            if let known = out[name] {
                out[name] = TasteArtist(name: known.name, ref: known.ref ?? artist.ref,
                                        avatarURL: known.avatarURL ?? artist.avatarURL, plays: known.plays)
            } else {
                out[name] = artist
            }
        }
        return out
    }

    private static func sharedArtists(_ mine: [TasteArtist], _ theirs: [TasteArtist])
        -> (overlap: Double, list: [TasteArtist], known: Bool) {
        let a = shares(mine)
        let b = shares(theirs)
        let byKey = artistsByKey(mine + theirs)
        let common = a.compactMap { name, share in b[name].map { (name: name, weight: min(share, $0)) } }
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.name < $1.name }
        return (common.reduce(0) { $0 + $1.weight }, common.compactMap { byKey[$0.name] }, !a.isEmpty && !b.isEmpty)
    }

    private static func sharedLikes<T: TasteTrack, F: TasteTrack>(_ mine: [T], _ theirs: [F])
        -> (overlap: Double, list: [T], known: Bool) {
        let refs = Set(theirs.map(\.ref))
        let keys = Set(theirs.map { trackKey($0) })
        var seen = Set<String>()
        let common = mine.filter { track in
            let key = trackKey(track)
            guard !seen.contains(key), refs.contains(track.ref) || keys.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        let smaller = min(Set(mine.map { trackKey($0) }).count, keys.count)
        let overlap = smaller > 0 ? min(1, Double(common.count) / Double(max(smaller, likesFloor))) : 0
        return (overlap, common, !mine.isEmpty && !theirs.isEmpty)
    }
}
