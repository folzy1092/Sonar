import Foundation

// Модели — тот же JSON, что в docs/API.md §3 и Windows-клиенте (`windows/src-tauri/src/providers/mod.rs`):
// когда появится сервер, клиент получит их же. ref: `sc:<id>` / `ym:<id>` — трек, `sca:` / `yma:` —
// исполнитель, `scalb:` / `ymalb:` — альбом, `scpl:<id>` / `ympl:<uid>:<kind>` — плейлист сервиса;
// YouTube Music — `yt:` / `yta:` / `ytalb:` / `ytpl:`;
// Старые треки убранного VK (`vk:` …) разбираются реестром, но клиента у них нет.
// Все префиксы — в реестре `ServiceRegistry.swift` (docs/API.md «Префиксы ref»).

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
    /// Громкость EBU R128, LUFS (Яндекс `r128.i`) — для нормализации (`Loudness`); SoundCloud не отдаёт.
    var loudness: Double? = nil

    var id: String { ref }

    enum CodingKeys: String, CodingKey {
        case ref, title, artist, artists, album, explicit, available, plays, tags, url, loudness
        case durationMs = "duration_ms"
        case coverURL = "cover_url"
    }

    /// Источник по ref: SoundCloud, Яндекс или YouTube Music.
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

/// Подключаемые сервисы приложения. Сырые значения хранятся в настройках и Keychain — не менять.
/// Остальные сервисы реестра (`ServiceID`) появятся здесь, когда заработают.
enum Service: String, Codable, Sendable, CaseIterable {
    case soundcloud
    case yandex
    case youtube

    /// Короткий id в реестре.
    var id: ServiceID {
        switch self {
        case .soundcloud: .sc
        case .yandex: .ym
        case .youtube: .yt
        }
    }

    var info: ServiceInfo { ServiceRegistry.info(id) }

    /// `.sc` — SoundCloud, `.ym` — Яндекс, `.yt` — YouTube Music; у остальных сервисов реестра (и убранного VK) клиента нет.
    init?(id: ServiceID) {
        switch id {
        case .sc: self = .soundcloud
        case .ym: self = .yandex
        case .yt: self = .youtube
        case .vk, .sp, .local: return nil
        }
    }

    /// По префиксу ref из реестра: `sc:`, `sca:`, `scalb:`, `scpl:` — SoundCloud, `ym…:` — Яндекс, `yt…:` — YouTube Music.
    init?(ref: String) {
        guard let service = ServiceRegistry.service(of: ref).flatMap(Service.init(id:)) else { return nil }
        self = service
    }

    var title: String { info.name }

    /// Следующий сервис по кругу — кнопка сервиса в Поиске (SoundCloud → Яндекс → YouTube Music → …).
    var next: Service {
        let all = Service.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    /// Знак сервиса (бейдж источника, кнопка сервиса в Поиске) — у каждого свой контур, без букв.
    var icon: IconName {
        switch self {
        case .soundcloud: .soundcloud
        case .yandex: .yandexMusic
        case .youtube: .youtubeMusic
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

extension Track {
    /// Артисты трека для вкуса и волны (как `wave.rs` `artist_keys`): имена из `artists` в нижнем
    /// регистре без крайних пробелов, а если списка нет — строка `artist` целиком. Первый — главный.
    /// По запятым и `&` не режем («Tyler, The Creator», «Simon & Garfunkel»).
    var artistKeys: [String] {
        var out: [String] = []
        for artist in artists {
            let key = artist.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty, !out.contains(key) { out.append(key) }
        }
        if out.isEmpty { out.append(artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        return out
    }

    /// Главный артист — по нему лимиты разнообразия волны, пауза, подборки.
    var artistKey: String { artistKeys[0] }

    /// Префиксы исполнителей работающих сервисов: `sca:`, `yma:`, `yta:`.
    private static let artistPrefixes = Service.allCases.map { $0.info.prefixes.artist! + ":" }
    /// У SoundCloud без id пользователя приходит `sca:0` — такого исполнителя нет.
    private static let missingArtist = Service.soundcloud.info.prefixes.artist! + ":0"

    /// ref главного артиста (`sca:` / `yma:`) — для его страницы, популярных треков и релизов.
    var mainArtistRef: String? {
        artists.lazy.map(\.ref).first { ref in
            Self.artistPrefixes.contains { ref.hasPrefix($0) } && ref != Self.missingArtist
        }
    }

    /// Имя главного артиста для подписи.
    var mainArtistName: String {
        let name = artists.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? artist : name
    }
}

/// Оценка исхода трека — одна шкала для всех сигналов (docs/WAVE.md 1.3; та же функция — Windows
/// `src/player/reward.ts` и `wave.rs` `reward`).
///
/// | исход (f = прослушано / длительность)        | оценка |
/// |----------------------------------------------|--------|
/// | 👎                                           | −2     |
/// | лайк во время трека или трек уже в Любимых   | +1.5   |
/// | ручной пропуск, f < 0.25 или < 30 с — ранний  | −1     |
/// | ручной пропуск, 0.25 ≤ f < 0.5               | −0.4   |
/// | ручной пропуск, 0.5 ≤ f < 0.8                | 0      |
/// | f ≥ 0.8 (как угодно закончился)              | +1     |
/// | сменился не пропуском, f < 0.8               | 0      |
///
/// Длительность 0 — по секундам: < 30 с — ранний пропуск, ≥ 150 с — дослушан.
enum Outcome {
    static func reward(listenedMs: Int, durationMs: Int, manualSkip: Bool, liked: Bool = false, disliked: Bool = false) -> Double {
        if disliked { return -2 }
        if liked { return 1.5 }
        let early = listenedMs < 30_000
        guard durationMs > 0 else {
            if listenedMs >= 150_000 { return 1 }
            return manualSkip && early ? -1 : 0
        }
        let f = Double(listenedMs) / Double(durationMs)
        if f >= 0.8 { return 1 }
        if !manualSkip { return 0 }
        if f < 0.25 || early { return -1 }
        if f < 0.5 { return -0.4 }
        return 0
    }
}
