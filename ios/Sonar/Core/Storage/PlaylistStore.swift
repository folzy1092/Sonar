import Foundation
import Observation

/// Свой плейлист Sonar — смешанный (`sc:` и `ym:` вместе), как на ПК (`store/mod.rs` «плейлисты», DB.md
/// `playlists` + `playlist_items`). Треки лежат целиком, чтобы список открывался без сети.
struct SonarPlaylist: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var tracks: [Track]
    /// Скрыт из «Все» в Медиатеке (во вкладке «Плейлисты» виден).
    var hidden: Bool
    /// `scpl:…` / `ympl:…`, если перенесён из сервиса.
    var sourceRef: String?
    /// Миллисекунды с 1970 — как `created_at` / `updated_at` в DB.md.
    var createdAt: Int
    var updatedAt: Int

    enum CodingKeys: String, CodingKey {
        case id, name, tracks, hidden
        case sourceRef = "source_ref"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var durationMs: Int { tracks.reduce(0) { $0 + $1.durationMs } }

    /// Коллаж без повторов (`Covers`): 4 разные обложки или одна первая, как на ПК.
    var covers: [String] { Self.covers(of: tracks) }

    /// Коллаж из списка треков — и для умного плейлиста.
    static func covers(of tracks: [Track]) -> [String] { Covers.collage(tracks) }
}

/// Сохранённый альбом и исполнитель, на которого подписан, — `likes` с `kind = album | artist` (DB.md).
struct SavedAlbum: Codable, Hashable, Sendable {
    var album: Album
    var addedAt: Int

    enum CodingKeys: String, CodingKey {
        case album
        case addedAt = "added_at"
    }
}

struct FollowedArtist: Codable, Hashable, Sendable {
    var artist: Artist
    var addedAt: Int

    enum CodingKeys: String, CodingKey {
        case artist
        case addedAt = "added_at"
    }
}

/// Правила плейлистов без хранения — их гоняют тесты.
enum PlaylistMath {
    static let maxName = 100

    /// Название без пробелов по краям, не длиннее 100 знаков; пустое — nil.
    static func cleanName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxName))
    }

    /// Добавить треки в начало или в конец (`general.add_position`). Уже лежащие в списке и повторы внутри
    /// добавляемых пропускаются. Возвращает новый список и сколько добавилось.
    static func add(_ new: [Track], to list: [Track], atStart: Bool) -> (list: [Track], added: Int) {
        var refs = Set(list.map(\.ref))
        var fresh: [Track] = []
        for track in new where !refs.contains(track.ref) {
            refs.insert(track.ref)
            fresh.append(track)
        }
        guard !fresh.isEmpty else { return (list, 0) }
        return (atStart ? fresh + list : list + fresh, fresh.count)
    }

    /// Новый порядок по ref: чего нет в order — убрано, неизвестные ref — пропущены.
    static func reorder(_ list: [Track], to order: [String]) -> [Track] {
        let byRef = Dictionary(list.map { ($0.ref, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        return order.compactMap { ref in
            guard !seen.contains(ref), let track = byRef[ref] else { return nil }
            seen.insert(ref)
            return track
        }
    }

    /// «Новый плейлист», «Новый плейлист 2», … — первое свободное название.
    static func freeName(_ base: String, taken: [String]) -> String {
        let names = Set(taken.map { $0.lowercased() })
        guard names.contains(base.lowercased()) else { return base }
        var n = 2
        while names.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}

/// Своя медиатека Sonar на телефоне, пока нет сервера: плейлисты (смешанные, перенесённые из сервисов),
/// сохранённые альбомы и исполнители с подпиской — как на ПК (W3). JSON в Application Support
/// (`Sonar/collections.json`); с SQLite по DB.md переедут туда с теми же полями, с сервером — в синк.
@MainActor
@Observable
final class PlaylistStore {
    static let shared = PlaylistStore()

    /// Новые сверху.
    private(set) var playlists: [SonarPlaylist] = []
    private(set) var albums: [SavedAlbum] = []
    private(set) var artists: [FollowedArtist] = []

    private struct Snapshot: Codable {
        var playlists: [SonarPlaylist]
        var albums: [SavedAlbum]?
        var artists: [FollowedArtist]?
    }

    @ObservationIgnored private let file: URL
    /// Часы — тесты подставляют свои.
    @ObservationIgnored var now: () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }

    init(file: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.file = file ?? base.appendingPathComponent("Sonar/collections.json")
        if let data = try? Data(contentsOf: self.file), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            playlists = snapshot.playlists
            albums = snapshot.albums ?? []
            artists = snapshot.artists ?? []
        }
    }

    // MARK: - Плейлисты

    func playlist(_ id: String) -> SonarPlaylist? {
        playlists.first { $0.id == id }
    }

    /// Перенесённый из сервиса (`scpl:…` / `ympl:…`), если он уже есть.
    func playlist(source ref: String) -> SonarPlaylist? {
        playlists.first { $0.sourceRef == ref }
    }

    func contains(_ ref: String, in id: String) -> Bool {
        playlist(id)?.tracks.contains { $0.ref == ref } ?? false
    }

    /// Новый плейлист; пустое название — nil. Возвращает id.
    @discardableResult
    func create(name: String, tracks: [Track] = [], sourceRef: String? = nil) -> String? {
        guard let clean = PlaylistMath.cleanName(name) else { return nil }
        let stamp = now()
        let id = "pl_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).lowercased()
        let list = PlaylistMath.add(tracks, to: [], atStart: false).list
        playlists.insert(SonarPlaylist(id: id, name: clean, tracks: list, hidden: false, sourceRef: sourceRef,
                                       createdAt: stamp, updatedAt: stamp), at: 0)
        save()
        return id
    }

    func rename(_ id: String, to name: String) {
        guard let clean = PlaylistMath.cleanName(name) else { return }
        edit(id) { $0.name = clean }
    }

    func setHidden(_ id: String, _ hidden: Bool) {
        edit(id) { $0.hidden = hidden }
    }

    func delete(_ id: String) {
        guard playlists.contains(where: { $0.id == id }) else { return }
        playlists.removeAll { $0.id == id }
        save()
    }

    /// Добавить треки; возвращает, сколько добавилось (уже лежащие пропускаются).
    @discardableResult
    func add(_ tracks: [Track], to id: String, atStart: Bool) -> Int {
        guard let current = playlist(id) else { return 0 }
        let result = PlaylistMath.add(tracks, to: current.tracks, atStart: atStart)
        guard result.added > 0 else { return 0 }
        edit(id) { $0.tracks = result.list }
        return result.added
    }

    func remove(_ refs: Set<String>, from id: String) {
        guard !refs.isEmpty, let current = playlist(id), current.tracks.contains(where: { refs.contains($0.ref) }) else { return }
        edit(id) { playlist in playlist.tracks.removeAll { track in refs.contains(track.ref) } }
    }

    /// Новый порядок (режим выбора): чего нет в order — убрано.
    func setOrder(_ order: [String], in id: String) {
        guard let current = playlist(id) else { return }
        let list = PlaylistMath.reorder(current.tracks, to: order)
        guard list != current.tracks else { return }
        edit(id) { $0.tracks = list }
    }

    private func edit(_ id: String, _ change: (inout SonarPlaylist) -> Void) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        change(&playlists[index])
        playlists[index].updatedAt = now()
        save()
    }

    // MARK: - Альбомы и исполнители

    func isSaved(album ref: String) -> Bool {
        albums.contains { $0.album.ref == ref }
    }

    /// «Сохранить в медиатеку» / «Убрать из медиатеки». Возвращает, сохранён ли теперь.
    @discardableResult
    func toggleSave(_ album: Album) -> Bool {
        if isSaved(album: album.ref) {
            albums.removeAll { $0.album.ref == album.ref }
            save()
            return false
        }
        albums.insert(SavedAlbum(album: album, addedAt: now()), at: 0)
        save()
        return true
    }

    func isFollowed(artist ref: String) -> Bool {
        artists.contains { $0.artist.ref == ref }
    }

    /// «Подписаться» / «Вы подписаны». Возвращает, подписан ли теперь.
    @discardableResult
    func toggleFollow(_ artist: Artist) -> Bool {
        if isFollowed(artist: artist.ref) {
            artists.removeAll { $0.artist.ref == artist.ref }
            save()
            return false
        }
        artists.insert(FollowedArtist(artist: artist, addedAt: now()), at: 0)
        save()
        return true
    }

    // MARK: - Файл

    private func save() {
        let snapshot = Snapshot(playlists: playlists, albums: albums, artists: artists)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// Длительность списка, как `durationText` на ПК (`lib/format.ts`): «51 мин», «6 часов 51 мин».
enum PlaylistDuration {
    /// Часы и минуты из миллисекунд (минуты округлены).
    static func parts(ms: Int) -> (hours: Int, minutes: Int) {
        let total = Int((Double(max(0, ms)) / 60_000).rounded())
        return (total / 60, total % 60)
    }

    @MainActor
    static func text(ms: Int) -> String {
        let (h, m) = parts(ms: ms)
        let minutes = t("{m} мин", ["m": String(m)])
        guard h > 0 else { return minutes }
        let hours = "\(h) " + tn(h, "час", "часа", "часов")
        return m > 0 ? hours + " " + minutes : hours
    }
}
