import Foundation

// Модели — тот же JSON, что в docs/API.md §3 и Windows-клиенте (`windows/src-tauri/src/providers/mod.rs`):
// когда появится сервер, клиент получит их же. ref: `sc:<id>` / `ym:<id>` — трек, `sca:` / `yma:` —
// исполнитель, `scalb:` / `ymalb:` — альбом, `scpl:<id>` / `ympl:<uid>:<kind>` — плейлист сервиса.

struct Track: Codable, Hashable, Sendable, Identifiable {
    var ref: String
    var title: String
    var artist: String
    var artists: [ArtistRef]
    var album: AlbumRef?
    var durationMs: Int
    var coverURL: String?
    var url: String?
    var explicit: Bool
    var available: Bool
    /// Сколько раз слушали на сервисе (SoundCloud `playback_count`; Яндекс не отдаёт).
    var plays: Int?
    /// Жанр и теги — для режимов волны.
    var tags: String?

    var id: String { ref }

    enum CodingKeys: String, CodingKey {
        case ref, title, artist, artists, album, explicit, available, plays, tags, url
        case durationMs = "duration_ms"
        case coverURL = "cover_url"
    }

    /// Источник по ref: SoundCloud или Яндекс.
    var service: Service? { Service(ref: ref) }
}

struct ArtistRef: Codable, Hashable, Sendable {
    var ref: String
    var name: String
    var avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case ref, name
        case avatarURL = "avatar_url"
    }
}

struct AlbumRef: Codable, Hashable, Sendable {
    var ref: String
    var title: String
}

struct Album: Codable, Hashable, Sendable {
    var ref: String
    var title: String
    var artist: String
    var artists: [ArtistRef]
    var coverURL: String?
    var year: Int?
    /// `YYYY-MM-DD`, если сервис знает.
    var released: String?
    var trackCount: Int
    var url: String?

    enum CodingKeys: String, CodingKey {
        case ref, title, artist, artists, year, released, url
        case coverURL = "cover_url"
        case trackCount = "track_count"
    }
}

struct Artist: Codable, Hashable, Sendable {
    var ref: String
    var name: String
    var avatarURL: String?
    var followers: Int?
    var url: String?

    enum CodingKeys: String, CodingKey {
        case ref, name, followers, url
        case avatarURL = "avatar_url"
    }
}

/// Плейлист сервиса — «фантомный», виден, пока не перенесён в Sonar.
struct ServicePlaylist: Codable, Hashable, Sendable {
    var ref: String
    var title: String
    var owner: String
    var coverURL: String?
    var trackCount: Int

    enum CodingKeys: String, CodingKey {
        case ref, title, owner
        case coverURL = "cover_url"
        case trackCount = "track_count"
    }
}

struct SearchResults: Codable, Sendable {
    var tracks: [Track] = []
    var artists: [Artist] = []
    var albums: [Album] = []
    var playlists: [ServicePlaylist] = []
}

/// Откуда играть: прямой файл или HLS. quality — что реально играет, для плашки: «AAC 160», «MP3 320», «FLAC».
enum StreamSource: Equatable, Sendable {
    case file(url: URL, quality: String)
    case hls(url: URL, quality: String)
}

enum Service: String, Codable, Sendable, CaseIterable {
    case soundcloud
    case yandex

    /// По префиксу ref: `sc…` — SoundCloud, `ym…` — Яндекс.
    init?(ref: String) {
        if ref.hasPrefix("sc") { self = .soundcloud }
        else if ref.hasPrefix("ym") { self = .yandex }
        else { return nil }
    }

    var title: String {
        switch self {
        case .soundcloud: "SoundCloud"
        case .yandex: "Яндекс Музыка"
        }
    }
}

/// Ошибка сервиса — понятным текстом для пользователя (как `http_error` в Rust).
struct ServiceError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }

    static func http(_ service: String, _ status: Int) -> ServiceError {
        let why = switch status {
        case 401, 403: "токен не подошёл или устарел"
        case 404: "не найдено"
        case 429: "слишком много запросов, подожди минуту"
        case 451: "недоступно в твоей стране"
        default: "сервис ответил ошибкой"
        }
        return ServiceError(message: "\(service): \(why) (HTTP \(status))")
    }
}
