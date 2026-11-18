import Foundation

// Реестр сервисов — одно место со списком (docs/API.md «Префиксы ref», docs/NEXT_PROMPT.md §2). Та же таблица —
// Windows `providers/registry.rs` и `lib/services.ts`; порядок строк — порядок показа везде.
// Две записи имени: короткий id (`sc`, корень префиксов ref) и длинный key (`soundcloud`, имя в Keychain и
// в `general.platform`). Сервисы с implemented = false пока только описаны: интерфейс их не показывает.

/// Короткий id сервиса — корень префиксов ref и источник поиска.
enum ServiceID: String, Codable, Sendable, CaseIterable {
    case sc, ym, yt, vk, sp, local
}

/// Что за объект у ref: трек, альбом, исполнитель или плейлист сервиса.
enum RefKind: String, Sendable {
    case track, album, artist, playlist
}

/// Что сервис умеет (у неподключённых к коду сервисов — цель, ничего по ней не делается).
struct ServiceCaps: Sendable, Equatable {
    let search, stream, library, playlists, similar, login, key: Bool
}

/// Префиксы ref сервиса: `sc` → `sc:<id>`, `scalb:<id>`, `sca:<id>`, `scpl:<id>`.
struct ServicePrefixes: Sendable, Equatable {
    let track: String
    let album: String?
    let artist: String?
    let playlist: String?
}

struct ServiceInfo: Sendable, Equatable {
    let id: ServiceID
    /// Длинное имя: `soundcloud`, `yandex`… — Keychain, `service_accounts.service`, `general.platform`.
    let key: String
    /// Название по-русски (исходная строка для `t()`).
    let name: String
    /// Цвет знака, `#RRGGBB`.
    let color: String
    /// Файл цветного знака в `brand/icon/`.
    let icon: String?
    /// Файл одноцветного знака в `brand/icon/`.
    let iconMono: String?
    let prefixes: ServicePrefixes
    let caps: ServiceCaps
    /// Сервис уже работает в приложении. Остальные скрыты в интерфейсе.
    let implemented: Bool

    /// Все префиксы сервиса с видом объекта.
    fileprivate var kinds: [(prefix: String, kind: RefKind)] {
        var out: [(prefix: String, kind: RefKind)] = [(prefixes.track, .track)]
        if let album = prefixes.album { out.append((album, .album)) }
        if let artist = prefixes.artist { out.append((artist, .artist)) }
        if let playlist = prefixes.playlist { out.append((playlist, .playlist)) }
        return out
    }
}

enum ServiceRegistry {
    /// Шесть сервисов в порядке показа.
    static let all: [ServiceInfo] = [
        ServiceInfo(
            id: .sc, key: "soundcloud", name: "SoundCloud", color: "#FF5500",
            icon: "SoundCloud.svg", iconMono: "soundcloud-mono.svg",
            prefixes: ServicePrefixes(track: "sc", album: "scalb", artist: "sca", playlist: "scpl"),
            caps: ServiceCaps(search: true, stream: true, library: true, playlists: true, similar: true, login: true, key: true),
            implemented: true
        ),
        ServiceInfo(
            id: .ym, key: "yandex", name: "Яндекс Музыка", color: "#FFBC0D",
            icon: "Yandex-Music.svg", iconMono: "yandex-music-mono.svg",
            prefixes: ServicePrefixes(track: "ym", album: "ymalb", artist: "yma", playlist: "ympl"),
            caps: ServiceCaps(search: true, stream: true, library: true, playlists: true, similar: true, login: true, key: true),
            implemented: true
        ),
        ServiceInfo(
            id: .yt, key: "youtube", name: "YouTube Music", color: "#FF0033",
            icon: "youtube-music.svg", iconMono: "youtube-music-mono.svg",
            prefixes: ServicePrefixes(track: "yt", album: "ytalb", artist: "yta", playlist: "ytpl"),
            // key — cookie music.youtube.com вручную, если окно входа не пустило
            caps: ServiceCaps(search: true, stream: true, library: true, playlists: true, similar: true, login: true, key: true),
            implemented: true
        ),
        ServiceInfo(
            id: .vk, key: "vk", name: "VK Музыка", color: "#0077FF",
            icon: "vk.svg", iconMono: "vk-mono.svg",
            prefixes: ServicePrefixes(track: "vk", album: "vkalb", artist: "vka", playlist: "vkpl"),
            caps: ServiceCaps(search: true, stream: true, library: true, playlists: true, similar: true, login: true, key: true),
            implemented: true
        ),
        ServiceInfo(
            id: .sp, key: "spotify", name: "Spotify", color: "#1ED760",
            icon: "spotify.svg", iconMono: "spotify-mono.svg",
            prefixes: ServicePrefixes(track: "sp", album: "spalb", artist: "spa", playlist: "sppl"),
            // играет только на ПК с Premium (librespot); на iPhone — метаданные, трек играет резервный сервис.
            // Рекомендаций Spotify не берём
            caps: ServiceCaps(search: true, stream: false, library: true, playlists: true, similar: false, login: true, key: true),
            implemented: true
        ),
        ServiceInfo(
            id: .local, key: "local", name: "Локальные файлы", color: "#8E8E93",
            icon: nil, iconMono: nil,
            prefixes: ServicePrefixes(track: "local", album: nil, artist: nil, playlist: nil),
            caps: ServiceCaps(search: false, stream: true, library: true, playlists: false, similar: false, login: false, key: false),
            implemented: false
        ),
    ]

    /// Строка реестра по id (есть у каждого id).
    static func info(_ id: ServiceID) -> ServiceInfo {
        all.first { $0.id == id }!
    }

    /// По короткому id или длинному key: `sc` и `soundcloud` — SoundCloud.
    static func byKey(_ s: String) -> ServiceInfo? {
        all.first { $0.id.rawValue == s || $0.key == s }
    }

    /// Сервис и вид объекта по ref. Префикс — текст до первого `:`, сравнивается целиком (не «начинается с»):
    /// `scpl:likes` — плейлист SoundCloud, `ympl:42:1003` — плейлист Яндекса. Без `:`, с пустым префиксом,
    /// `pl_…` (свои плейлисты), `similar:<ref>` и прочее — nil.
    static func parse(ref: String) -> (info: ServiceInfo, kind: RefKind)? {
        guard let colon = ref.firstIndex(of: ":") else { return nil }
        let prefix = ref[..<colon]
        guard !prefix.isEmpty else { return nil }
        for info in all {
            if let match = info.kinds.first(where: { $0.prefix == prefix }) { return (info, match.kind) }
        }
        return nil
    }

    /// Сервис по ref (любой вид объекта).
    static func service(of ref: String) -> ServiceID? {
        parse(ref: ref)?.info.id
    }

    /// Работающие сервисы в порядке показа: SoundCloud, Яндекс, YouTube Music, VK.
    static var implemented: [ServiceInfo] {
        all.filter(\.implemented)
    }

    /// Лучший звук — первым: кого оставить среди дублей (`DupeFinder`). Тот же порядок — `QUALITY_ORDER`
    /// в `providers/registry.rs`: Яндекс (FLAC) > свой файл > Spotify > VK > YouTube Music > SoundCloud.
    static let qualityOrder: [ServiceID] = [.ym, .local, .sp, .vk, .yt, .sc]

    /// Место трека по качеству звука: меньше — лучше; ref без сервиса — последним.
    static func qualityRank(_ ref: String) -> Int {
        service(of: ref).flatMap { qualityOrder.firstIndex(of: $0) } ?? qualityOrder.count
    }
}
