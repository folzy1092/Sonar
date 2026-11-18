import Foundation
import Observation

/// Умный плейлист — название и правила (`smart_playlists` в docs/DB.md). Треков в нём нет: они считаются
/// заново при каждом открытии (`SmartRunner`). Правила лежат сырым JSON, чтобы правила из более новой версии
/// Sonar не терялись при сохранении — такой плейлист показывается «правила не читаются».
struct SmartPlaylistDef: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var rules: JSONValue
    /// Миллисекунды с 1970.
    var createdAt: Int
    var updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id, name, rules
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Правила, если эта версия Sonar их понимает.
    var parsed: SmartRules? {
        guard let rules = rules.decode(SmartRules.self), SmartEngine.problem(rules) == nil else { return nil }
        return rules
    }
}

/// Итог пересчёта умного плейлиста.
enum SmartOutcome: Equatable, Sendable {
    case tracks([Track])
    /// Правила не читаются (новая версия, битый JSON).
    case invalid
    /// Источник — свой плейлист, которого больше нет.
    case sourceMissing

    var tracks: [Track] {
        if case let .tracks(list) = self { return list }
        return []
    }
}

/// Кандидаты из источника правил — без хранилищ, их гоняют тесты.
enum SmartSources {
    /// Любимые: в их порядке, «добавлен» — когда лайкнут (0 — неизвестно, лайк старше этого поля).
    /// Свой плейлист: в его порядке, «добавлен» — создание плейлиста (дат по трекам iPhone не хранит).
    /// Всё прослушанное: последние сверху, «добавлен» — первое прослушивание. nil — плейлиста нет.
    static func candidates(_ source: SmartSource, liked: [Track], likedAt: [String: Int], playlists: [SonarPlaylist],
                           played: [String: Track], history: SmartHistory) -> [SmartCandidate]? {
        switch source {
        case .liked:
            return liked.map { SmartCandidate(track: $0, addedAt: likedAt[$0.ref] ?? 0) }
        case let .playlist(id):
            guard let playlist = playlists.first(where: { $0.id == id }) else { return nil }
            return playlist.tracks.map { SmartCandidate(track: $0, addedAt: playlist.createdAt) }
        case .played:
            return history.refs
                .sorted { $0.last != $1.last ? $0.last > $1.last : $0.ref < $1.ref }
                .compactMap { row in played[row.ref].map { SmartCandidate(track: $0, addedAt: row.first) } }
        }
    }

    static func run(_ def: SmartPlaylistDef, liked: [Track], likedAt: [String: Int], playlists: [SonarPlaylist],
                    played: [String: Track], history: SmartHistory, now: Int) -> SmartOutcome {
        guard let rules = def.parsed else { return .invalid }
        guard let list = candidates(rules.source, liked: liked, likedAt: likedAt, playlists: playlists, played: played, history: history) else {
            return .sourceMissing
        }
        return .tracks(SmartEngine.evaluate(rules, candidates: list, history: history, now: now))
    }
}

/// Пересчёт над данными телефона: Любимые (`LibraryStore`), свои плейлисты (`PlaylistStore`) и журнал
/// прослушиваний (`PlayLog`).
@MainActor
enum SmartRunner {
    static func history(_ log: PlayLog = .shared) -> SmartHistory {
        SmartHistory(rows: log.rows.map { (ref: $0.ref, at: Int($0.at.timeIntervalSince1970 * 1000)) })
    }

    static func run(_ def: SmartPlaylistDef, library: LibraryStore = .shared, playlists: PlaylistStore = .shared,
                    log: PlayLog = .shared, now: Int = Int(Date().timeIntervalSince1970 * 1000)) -> SmartOutcome {
        SmartSources.run(def, liked: library.liked, likedAt: library.likedAt, playlists: playlists.playlists,
                         played: log.tracks, history: history(log), now: now)
    }
}

/// Умные плейлисты на телефоне, пока нет SQLite и сервера: JSON в Application Support (`Sonar/smart.json`),
/// поля — как у `smart_playlists` в DB.md; с сервером уедут в синк.
@MainActor
@Observable
final class SmartPlaylistStore {
    static let shared = SmartPlaylistStore()

    /// Новые сверху.
    private(set) var lists: [SmartPlaylistDef] = []

    @ObservationIgnored private let file: URL
    /// Часы — тесты подставляют свои.
    @ObservationIgnored var now: () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }

    init(file: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.file = file ?? base.appendingPathComponent("Sonar/smart.json")
        if let data = try? Data(contentsOf: self.file), let saved = try? JSONDecoder().decode([SmartPlaylistDef].self, from: data) {
            lists = saved
        }
    }

    func list(_ id: String) -> SmartPlaylistDef? {
        lists.first { $0.id == id }
    }

    /// Новый умный плейлист; пустое название или неверные правила — nil. Возвращает id (`sm_…`, как на ПК).
    @discardableResult
    func create(name: String, rules: SmartRules) -> String? {
        guard let clean = PlaylistMath.cleanName(name), SmartEngine.problem(rules) == nil else { return nil }
        let stamp = now()
        let id = "sm_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).lowercased()
        lists.insert(SmartPlaylistDef(id: id, name: clean, rules: .encode(rules), createdAt: stamp, updatedAt: stamp), at: 0)
        save()
        return id
    }

    /// Новое название и правила; неверные — false, ничего не меняется.
    @discardableResult
    func update(_ id: String, name: String, rules: SmartRules) -> Bool {
        guard let index = lists.firstIndex(where: { $0.id == id }), let clean = PlaylistMath.cleanName(name),
              SmartEngine.problem(rules) == nil else { return false }
        var def = lists[index]
        def.name = clean
        def.rules = .encode(rules)
        def.updatedAt = now()
        lists[index] = def
        save()
        return true
    }

    func delete(_ id: String) {
        guard lists.contains(where: { $0.id == id }) else { return }
        lists.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
