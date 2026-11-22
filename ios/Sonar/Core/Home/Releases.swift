import Foundation

/// Новинка исполнителя (как Windows `ReleaseItem`, `commands.rs` `release_feed`): альбом или сингл
/// (`kind == .album`, по тапу — страница альбома) либо трек SoundCloud (`.track`, по тапу играет).
struct ReleaseItem: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case album, track
    }

    let ref: String
    let kind: Kind
    let title: String
    let artist: String
    let coverURL: String?
    /// `YYYY-MM-DD`.
    let released: String
    /// Трек целиком — у `.track`, чтобы его сыграть.
    let track: Track?
}

/// Чистая часть «Новинок» — тесты гоняют на Linux. Зеркало `windows/src/lib/new-releases.svelte.ts`.
enum ReleaseMath {
    static let week: TimeInterval = 7 * 86_400
    /// Длина ленты, как `release_feed` на ПК.
    static let feedLimit = 60
    /// Сколько увиденных ref помнить.
    static let seenLimit = 600

    /// Вышло за последнюю неделю (полночь дня выхода по местному времени; в будущем — не считается).
    static func isFresh(_ released: String, now: Date, timeZone: TimeZone = .current) -> Bool {
        guard let at = dayStart(released, timeZone: timeZone) else { return false }
        return at <= now && now.timeIntervalSince(at) < week
    }

    /// Свежие релизы, которых ещё не видели, — порядок ленты (новые первыми).
    static func unseenFresh(_ items: [ReleaseItem], seen: Set<String>, now: Date,
                            timeZone: TimeZone = .current) -> [ReleaseItem] {
        items.filter { isFresh($0.released, now: now, timeZone: timeZone) && !seen.contains($0.ref) }
    }

    /// Ленты исполнителей → одна: без повторов по ref, новые первыми, до 60.
    static func merge(_ lists: [[ReleaseItem]], limit: Int = feedLimit) -> [ReleaseItem] {
        var refs = Set<String>()
        let unique = lists.flatMap { $0 }.filter { refs.insert($0.ref).inserted }
        return Array(unique.sorted { $0.released > $1.released }.prefix(limit))
    }

    /// Дата SoundCloud-трека: `release_date` → `display_date` → `created_at`, первые 10 символов.
    static func soundCloudDate(_ json: JSONValue) -> String? {
        guard let date = json["release_date"].string ?? json["display_date"].string ?? json["created_at"].string,
              date.count >= 10 else { return nil }
        return String(date.prefix(10))
    }

    /// Увиденные + новые, последние `seenLimit` (порядок — как добавляли).
    static func remember(_ refs: [String], in seen: [String], limit: Int = seenLimit) -> [String] {
        var known = Set(seen)
        let fresh = refs.filter { known.insert($0).inserted }
        return Array((seen + fresh).suffix(limit))
    }

    private static func dayStart(_ day: String, timeZone: TimeZone) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
