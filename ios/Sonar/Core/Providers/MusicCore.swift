import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ключи SoundCloud: client_id и необязательный OAuth-токен (без него играют только открытые треки).
struct SoundCloudCreds: Codable, Sendable, Equatable {
    var clientId: String
    var oauthToken: String?
}

/// Токен Яндекс Музыки `y0_…`.
struct YandexCreds: Codable, Sendable, Equatable {
    var token: String
}

/// Подключённый сервис: ключи и аккаунт.
struct StoredService<Creds: Codable & Sendable>: Codable, Sendable {
    var creds: Creds
    var account: ServiceAccount
}

/// Что нашлось по ссылке из строки поиска.
enum LinkItem: Sendable {
    case track(Track)
    case album(Album)
    case artist(Artist)
    case playlist(ServicePlaylist)
}

/// Общее ядро сервисов (порт `windows/src-tauri/src/services.rs`): ключи (Keychain), поиск, ссылки на
/// поток с кэшем, трек SoundCloud → тот же на Яндексе ради FLAC / 320. Экраны и плеер ходят в сервисы
/// только через него. Сервера пока нет — всё прямо с телефона (SPEC §9).
actor MusicCore {
    static let shared = MusicCore()

    /// Ссылки SoundCloud и Яндекса живут минуты — держим чуть меньше, при 403 берём заново.
    static let streamTTL: TimeInterval = 240

    private var soundCloud: StoredService<SoundCloudCreds>?
    private var yandex: StoredService<YandexCreds>?
    /// VK и что он отдал вместе с треками — в `MusicCore+VK.swift` (поэтому не private).
    var vk: StoredService<VKCreds>?
    /// Ссылки на поток, которые VK отдал вместе с треками, и когда (живут `streamTTL`).
    var vkSeen: [String: (url: String, at: Date)] = [:]
    /// access_key треков VK — на диске, переживают перезапуск (`VKKeyStore`).
    var vkKeys = VKKeyStore(file: VKKeyStore.defaultFile)
    /// Публичный client_id с soundcloud.com — когда своих ключей нет (поиск и открытые треки).
    private var publicClientId: String?
    /// Сырой JSON треков SoundCloud — в нём варианты потока.
    private var soundCloudRaw: [String: JSONValue] = [:]
    var streams: [String: (source: StreamSource, at: Date)] = [:]
    /// Найденные пары `sc:…` → id Яндекса (nil — на Яндексе нет), чтобы не искать каждый раз.
    private var yandexTwins: [String: String?] = [:]
    /// Потолок битрейта Яндекса (`audio.quality`): 192 / 256 / 320 / 1411 (FLAC).
    private var maxKbps = Yandex.losslessKbps
    /// Трек SoundCloud играть с Яндекса, если там есть тот же (`audio.sc_via_yandex`).
    private var soundCloudViaYandex = false
    /// Cookie YouTube Music: без него каталог и поток работают гостем, нужен для «Лайков» и плейлистов.
    private var youtube: StoredService<YouTubeCreds>?
    /// `visitorData` гостя YouTube на сеанс (без неё `player` чаще просит «подтверди, что ты не бот»).
    private var youTubeVisitor: String?
    /// `audio.yt_quality`: «Высокое» — AAC 256, если есть, иначе 128.
    private var youTubeHigh = true

    init() {
        soundCloud = ServiceVault.load(Service.soundcloud.info.key)
        yandex = ServiceVault.load(Service.yandex.info.key)
        youtube = ServiceVault.load(Service.youtube.info.key)
        vk = ServiceVault.load(Service.vk.info.key)
    }

    // MARK: - Подключение

    struct Status: Sendable, Equatable {
        var soundCloud: ServiceAccount?
        var yandex: ServiceAccount?
        var youtube: ServiceAccount?
        var vk: ServiceAccount? = nil
    }

    func status() -> Status {
        Status(soundCloud: soundCloud?.account, yandex: yandex?.account, youtube: youtube?.account, vk: vk?.account)
    }

    func configure(maxKbps: Int, soundCloudViaYandex: Bool, youTubeHigh: Bool? = nil) {
        let youTubeHigh = youTubeHigh ?? self.youTubeHigh
        if maxKbps != self.maxKbps || youTubeHigh != self.youTubeHigh { streams.removeAll() }
        self.maxKbps = maxKbps
        self.soundCloudViaYandex = soundCloudViaYandex
        self.youTubeHigh = youTubeHigh
    }

    /// `audio.yt_quality` → брать ли AAC 256. По умолчанию — да («Высокое»).
    static func youTubeHigh(_ value: String?) -> Bool { value != "normal" }

    func connectSoundCloud(_ creds: SoundCloudCreds) async throws -> ServiceAccount {
        let creds = SoundCloudCreds(clientId: creds.clientId.trimmingCharacters(in: .whitespacesAndNewlines),
                                    oauthToken: creds.oauthToken?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty)
        guard creds.clientId.count >= 20 else { throw ServiceError(message: "client_id SoundCloud — строка из 32 символов") }
        let account = try await SoundCloud(clientId: creds.clientId, oauthToken: creds.oauthToken).account()
        let stored = StoredService(creds: creds, account: account)
        ServiceVault.save("soundcloud", stored)
        soundCloud = stored
        streams.removeAll()
        return account
    }

    func connectYandex(token: String) async throws -> ServiceAccount {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ServiceError(message: "Вставь токен Яндекс Музыки") }
        let account = try await Yandex(token: token).account()
        let stored = StoredService(creds: YandexCreds(token: token), account: account)
        ServiceVault.save("yandex", stored)
        yandex = stored
        streams.removeAll()
        return account
    }

    /// Cookie music.youtube.com (из окна входа или вставленный) → проверка аккаунтом → Keychain.
    func connectYouTube(cookie: String) async throws -> ServiceAccount {
        let creds = YouTubeCreds(cookie: try YouTubeAuth.normalize(cookie))
        let account = try await YouTube(creds: creds).account()
        let stored = StoredService(creds: creds, account: account)
        ServiceVault.save(Service.youtube.info.key, stored)
        youtube = stored
        streams.removeAll()
        return account
    }

    func disconnect(_ service: Service) {
        switch service {
        case .soundcloud: soundCloud = nil
        case .yandex: yandex = nil
        case .youtube: youtube = nil
        case .vk:
            vk = nil
            vkSeen.removeAll()
        }
        ServiceVault.delete(service.info.key)
        streams.removeAll()
        yandexTwins.removeAll()
    }

    // MARK: - Клиенты

    /// Ключи SoundCloud: свои, иначе публичный client_id с сайта. public — их можно взять заново при 401/403.
    private func soundCloudClient(renew: Bool = false) async throws -> (client: SoundCloud, isPublic: Bool) {
        if let soundCloud {
            return (SoundCloud(clientId: soundCloud.creds.clientId, oauthToken: soundCloud.creds.oauthToken), false)
        }
        if !renew, let publicClientId {
            return (SoundCloud(clientId: publicClientId), true)
        }
        let id = try await SoundCloud.publicClientId()
        publicClientId = id
        return (SoundCloud(clientId: id), true)
    }

    /// Вызов SoundCloud с повтором на свежем публичном client_id при 401/403.
    private func withSoundCloud<T: Sendable>(_ call: @Sendable (SoundCloud) async throws -> T) async throws -> T {
        let (client, isPublic) = try await soundCloudClient()
        do {
            return try await call(client)
        } catch let error where isPublic && Self.isAuthError(error) {
            return try await call(try await soundCloudClient(renew: true).client)
        }
    }

    private func yandexClient() throws -> Yandex {
        guard let yandex else { throw ServiceError(message: "Яндекс Музыка не подключена — открой Профиль → Сервисы") }
        return Yandex(token: yandex.creds.token)
    }

    /// YouTube Music: с cookie, если подключён, иначе гостем.
    private func youTubeClient() -> YouTube {
        YouTube(creds: youtube?.creds)
    }

    /// 401/403 — ключ не подошёл (публичный client_id SoundCloud время от времени меняется).
    static func isAuthError(_ error: Error) -> Bool {
        let text = (error as? ServiceError)?.message ?? error.localizedDescription
        return text.contains("HTTP 401") || text.contains("HTTP 403")
    }

    /// `audio.quality` → потолок битрейта Яндекса. По умолчанию — максимум (FLAC, если есть).
    static func qualityKbps(_ value: String?) -> Int {
        switch value {
        case "low": 192
        case "medium": 256
        case "high": 320
        default: Yandex.losslessKbps
        }
    }

    /// Сырой JSON SoundCloud → модели; JSON запоминаем для потока.
    private func keep(_ raw: [JSONValue]) -> [Track] {
        if soundCloudRaw.count > 5000 { soundCloudRaw.removeAll() }
        return raw.compactMap { json in
            guard let track = SoundCloud.parseTrack(json) else { return nil }
            soundCloudRaw[track.ref] = json
            return track
        }
    }

    // MARK: - Поиск

    func search(_ query: String, in service: Service, limit: Int = 30) async throws -> [Track] {
        switch service {
        case .soundcloud:
            let found = try await withSoundCloud { try await $0.search(query, limit: limit) }
            return keep(found.map(\.json))
        case .yandex:
            return try await yandexClient().search(query, limit: limit)
        case .youtube:
            return try await youTubeClient().search(query, limit: limit)
        case .vk:
            return try await vkSearch(query, limit: limit)
        }
    }

    func searchMore(_ query: String, in service: Service, limit: Int = 12) async throws -> SearchResults {
        let found = switch service {
        case .soundcloud: try await withSoundCloud { try await $0.searchMore(query, limit: limit) }
        case .yandex: try await yandexClient().searchMore(query, limit: limit)
        case .youtube: try await youTubeClient().searchMore(query, limit: limit)
        case .vk: try await vkClient().searchMore(query, limit: limit)
        }
        return SearchResults(tracks: [], artists: found.artists, albums: found.albums, playlists: found.playlists)
    }

    /// Ссылка из строки поиска → что за ней.
    func resolveLink(_ text: String) async throws -> LinkItem {
        guard let link = ServiceLink.parse(text) else { throw ServiceError(message: "Это не ссылка SoundCloud или Яндекс Музыки") }
        switch link {
        case let .ref(ref):
            let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
            let yandex = try yandexClient()
            switch parts[0] {
            case "ym":
                guard let track = try await yandex.tracks([parts[1]]).first else { throw ServiceError(message: "Яндекс Музыка: трек не найден") }
                return .track(track)
            case "ymalb": return .album(try await yandex.album(parts[1]).album)
            case "yma": return .artist(try await yandex.artist(parts[1]).artist)
            default:
                let ids = parts[1].split(separator: ":").map(String.init)
                guard ids.count == 2 else { throw ServiceError(message: "Неверная ссылка на плейлист") }
                return .playlist(try await yandex.playlist(uid: ids[0], kind: ids[1]).head)
            }
        case let .soundCloud(url):
            let json = try await withSoundCloud { try await $0.resolve(url) }
            let nothing = ServiceError(message: "SoundCloud: по ссылке ничего не нашлось")
            switch json["kind"].string {
            case "track":
                guard let track = keep([json]).first else { throw nothing }
                return .track(track)
            case "playlist":
                let isAlbum = ["album", "ep", "single", "compilation"].contains(json["set_type"].string ?? "") || json["is_album"].bool == true
                if isAlbum {
                    guard let album = SoundCloud.parseAlbum(json) else { throw nothing }
                    return .album(album)
                }
                guard let playlist = SoundCloud.parsePlaylist(json) else { throw nothing }
                return .playlist(playlist)
            case "user":
                guard let artist = SoundCloud.parseArtist(json) else { throw nothing }
                return .artist(artist)
            default:
                throw nothing
            }
        }
    }

    /// Похожие на трек — для «Авто похожих» и волны.
    func similar(to ref: String, limit: Int = 20) async throws -> [Track] {
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        switch parts[0] {
        case "sc": return keep(try await withSoundCloud { try await $0.related(parts[1], limit: limit) })
        case "ym": return try await yandexClient().similar(parts[1])
        case "yt": return Array(try await youTubeClient().similar(parts[1]).prefix(limit))
        case "vk": return try await vkSimilar(parts[1], limit: limit)
        default: return []
        }
    }

    // MARK: - Страницы: исполнитель, альбом, плейлисты

    private static func split(_ ref: String) throws -> (kind: String, id: String) {
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { throw ServiceError(message: "Неверная ссылка \(ref)") }
        return (parts[0], parts[1])
    }

    /// Страница исполнителя (`sca:` / `yma:` / `yta:` / `vka:` / `spa:`): шапка, популярные треки, альбомы и синглы.
    func artist(_ ref: String) async throws -> (artist: Artist, tracks: [Track], albums: [Album]) {
        let (kind, id) = try Self.split(ref)
        switch kind {
        case "sca":
            let (user, top, albums) = try await withSoundCloud { client in
                async let user = client.user(id)
                async let top = try? client.topTracks(id, limit: 10)
                async let albums = try? client.userAlbums(id)
                return (try await user, await top ?? [], await albums ?? [])
            }
            guard let artist = SoundCloud.parseArtist(user) else { throw ServiceError(message: "SoundCloud: исполнитель не найден") }
            return (artist, keep(top), albums)
        case "yma":
            let page = try await yandexClient().artist(id)
            return (page.artist, page.top, page.albums)
        case "yta":
            let page = try await youTubeClient().artist(id)
            return (page.artist, page.top, page.albums)
        case "vka":
            return try await vkArtist(id)
        case "spa":
            return try await SpotifyCore.shared.artist(id)
        default:
            throw ServiceError(message: "Неизвестный исполнитель \(ref)")
        }
    }

    /// Альбом или релиз (`scalb:` / `ymalb:` / `ytalb:` / `vkalb:` / `spalb:`) с треками.
    func album(_ ref: String) async throws -> (album: Album, tracks: [Track]) {
        let (kind, id) = try Self.split(ref)
        switch kind {
        case "scalb":
            let (head, raw) = try await withSoundCloud { try await $0.playlist(id) }
            guard let album = SoundCloud.parseAlbum(head) else { throw ServiceError(message: "SoundCloud: альбом не найден") }
            return (album, keep(raw))
        case "ymalb":
            return try await yandexClient().album(id)
        case "ytalb":
            return try await youTubeClient().album(id)
        case "vkalb":
            return try await vkAlbum(id)
        case "spalb":
            return try await SpotifyCore.shared.album(id)
        default:
            throw ServiceError(message: "Неизвестный альбом \(ref)")
        }
    }

    /// Популярные треки исполнителя — «знакомое» для волны и «Для вас».
    func artistTop(_ ref: String, limit: Int) async throws -> [Track] {
        let (kind, id) = try Self.split(ref)
        switch kind {
        case "sca": return keep(try await withSoundCloud { try await $0.topTracks(id, limit: limit) })
        case "yma": return Array(try await yandexClient().artist(id).top.prefix(limit))
        case "yta": return Array(try await youTubeClient().artist(id).top.prefix(limit))
        case "vka": return try await vkArtistTop(id, limit: limit)
        case "spa": return Array(try await SpotifyCore.shared.artist(id).tracks.prefix(limit))
        default: throw ServiceError(message: "Неизвестный исполнитель \(ref)")
        }
    }

    /// Альбомы и синглы исполнителя — для «Релизов».
    func artistAlbums(_ ref: String) async throws -> [Album] {
        let (kind, id) = try Self.split(ref)
        switch kind {
        case "sca": return try await withSoundCloud { try await $0.userAlbums(id) }
        case "yma": return try await yandexClient().artist(id).albums
        case "yta": return try await youTubeClient().artist(id).albums
        case "vka": return try await vkClient().artistAlbums(id, limit: 100)
        case "spa": return try await SpotifyCore.shared.artistAlbums(id)
        default: throw ServiceError(message: "Неизвестный исполнитель \(ref)")
        }
    }

    /// Новинки Яндекса; не подключён — пусто.
    func newReleases(limit: Int) async throws -> [Album] {
        guard yandex != nil else { return [] }
        return try await yandexClient().newReleases(limit: limit)
    }

    var hasYandex: Bool { yandex != nil }

    /// Лайков сервиса в плейлисте «Лайки» — не больше.
    static let maxServiceLikes = 2000

    /// Свои плейлисты подключённых сервисов для Медиатеки: сначала SoundCloud (первым — «Лайки
    /// SoundCloud», нужен OAuth-токен), потом Яндекс («Мне нравится» первым), потом YouTube Music
    /// («Лайки YouTube Music» первыми, нужен вход), потом VK («Моя музыка» первой), Spotify («Любимые треки»
    /// первыми) — последним. Ошибка одного сервиса не мешает другому.
    func myPlaylists() async -> [ServicePlaylist] {
        var out: [ServicePlaylist] = []
        if let soundCloud, let token = soundCloud.creds.oauthToken, !token.isEmpty, let uid = soundCloud.account.uid {
            let client = SoundCloud(clientId: soundCloud.creds.clientId, oauthToken: token)
            out.append(ServicePlaylist(ref: "scpl:likes", title: "Лайки SoundCloud", owner: soundCloud.account.name ?? "", coverURL: nil, trackCount: 0))
            out += (try? await client.userPlaylists(uid)) ?? []
        }
        if let yandex, let uid = yandex.account.uid {
            out.append(ServicePlaylist(ref: "ympl:likes", title: "Мне нравится", owner: yandex.account.name ?? "", coverURL: nil, trackCount: 0))
            // «Мне нравится» в Яндексе — kind 3, он уже есть строкой выше
            let lists = (try? await Yandex(token: yandex.creds.token).userPlaylists(uid)) ?? []
            out += lists.filter { !$0.ref.hasSuffix(":3") }
        }
        if let youtube {
            out.append(ServicePlaylist(ref: Self.youTubeLikesRef, title: YouTube.likesTitle, owner: youtube.account.name ?? "", coverURL: nil, trackCount: 0))
            out += (try? await YouTube(creds: youtube.creds).libraryPlaylists()) ?? []
        }
        out += await vkPlaylists()
        return out + (await SpotifyCore.shared.playlists())
    }

    /// «Лайки YouTube Music» («Понравившиеся», нужен вход).
    static let youTubeLikesRef = "ytpl:\(YouTube.likesID)"
    /// Обычный плейлист YouTube Music — не больше стольких треков.
    static let maxYouTubePlaylist = 1000

    /// Плейлист сервиса с треками: `scpl:<id>`, `scpl:likes`, `ympl:<uid>:<kind>`, `ympl:likes`,
    /// `ytpl:<id>`, `ytpl:likes`, `vkpl:…`, `sppl:<id>`, `sppl:likes`.
    func playlist(_ ref: String) async throws -> (head: ServicePlaylist, tracks: [Track]) {
        let (kind, id) = try Self.split(ref)
        switch (kind, id) {
        case ("scpl", "likes"):
            guard let soundCloud, let token = soundCloud.creds.oauthToken, !token.isEmpty, let uid = soundCloud.account.uid else {
                throw ServiceError(message: "Для лайков SoundCloud нужен OAuth-токен — Профиль → Сервисы")
            }
            let client = SoundCloud(clientId: soundCloud.creds.clientId, oauthToken: token)
            let tracks = keep(try await client.userLikes(uid, max: Self.maxServiceLikes))
            return (ServicePlaylist(ref: ref, title: "Лайки SoundCloud", owner: soundCloud.account.name ?? "",
                                    coverURL: tracks.first?.coverURL, trackCount: tracks.count), tracks)
        case ("scpl", _):
            let (head, raw) = try await withSoundCloud { try await $0.playlist(id) }
            guard let playlist = SoundCloud.parsePlaylist(head) else { throw ServiceError(message: "SoundCloud: плейлист не найден") }
            return (playlist, keep(raw))
        case ("ympl", "likes"):
            guard let yandex, let uid = yandex.account.uid else { throw ServiceError(message: "Яндекс Музыка не подключена — открой Профиль → Сервисы") }
            let tracks = try await Yandex(token: yandex.creds.token).likes(uid: uid, max: Self.maxServiceLikes)
            return (ServicePlaylist(ref: ref, title: "Мне нравится", owner: yandex.account.name ?? "",
                                    coverURL: tracks.first?.coverURL, trackCount: tracks.count), tracks)
        case ("ympl", _):
            let ids = id.split(separator: ":").map(String.init)
            guard ids.count == 2 else { throw ServiceError(message: "Неверная ссылка на плейлист") }
            return try await yandexClient().playlist(uid: ids[0], kind: ids[1])
        case ("ytpl", YouTube.likesID):
            guard let youtube else { throw ServiceError(message: "YouTube Music не подключён — открой Профиль → Сервисы") }
            var (head, tracks) = try await YouTube(creds: youtube.creds).playlist(id, max: Self.maxServiceLikes)
            head.owner = youtube.account.name ?? ""
            if head.coverURL == nil { head.coverURL = tracks.first?.coverURL }
            return (head, tracks)
        case ("ytpl", _):
            let page = try await youTubeClient().playlist(id, max: Self.maxYouTubePlaylist)
            return (page.playlist, page.tracks)
        case ("vkpl", _):
            return try await vkPlaylist(id)
        case ("sppl", _):
            return try await SpotifyCore.shared.playlist(id, max: Self.maxServiceLikes)
        default:
            throw ServiceError(message: "Неизвестный плейлист \(ref)")
        }
    }

    // MARK: - Скачивание

    /// Откуда скачать трек файлом. Яндекс — mp3 / FLAC как для плеера. SoundCloud: Яндекс-двойник (если
    /// включено «SoundCloud в качестве Яндекса»), иначе прямой mp3 SoundCloud, иначе двойник всё равно;
    /// только HLS — «Этот трек нельзя скачать».
    func downloadSource(_ ref: String) async throws -> DownloadSource {
        let (kind, id) = try Self.split(ref)
        let cannot = ServiceError(message: "Этот трек нельзя скачать")
        switch kind {
        case "sp":
            throw ServiceError(message: Spotify.needsFallback)
        case "ym":
            guard let source = DownloadSource.from(try await yandexClient().stream(id, maxKbps: maxKbps)) else { throw cannot }
            return source
        case "sc":
            if soundCloudViaYandex, let source = await twinDownload(ref, id: id) { return source }
            var json = soundCloudRaw[ref]
            if json == nil {
                json = try await withSoundCloud { try await $0.trackJSON(id) }
                soundCloudRaw[ref] = json
            }
            if let json, let progressive = SoundCloud.pickProgressive(json) {
                var stream = try? await withSoundCloud { try await $0.stream(json, transcoding: progressive) }
                if stream == nil, let fresh = try? await withSoundCloud({ try await $0.trackJSON(id) }),
                   let again = SoundCloud.pickProgressive(fresh) {
                    // в сохранённом JSON могла протухнуть track_authorization
                    soundCloudRaw[ref] = fresh
                    stream = try? await withSoundCloud { try await $0.stream(fresh, transcoding: again) }
                }
                if let stream, let source = DownloadSource.from(stream) { return source }
            }
            if !soundCloudViaYandex, let source = await twinDownload(ref, id: id) { return source }
            throw cannot
        default:
            throw ServiceError(message: "Неизвестный источник в \(ref)")
        }
    }

    private func twinDownload(_ ref: String, id: String) async -> DownloadSource? {
        guard yandex != nil, let stream = await yandexTwin(ref, id: id) else { return nil }
        return DownloadSource.from(stream)
    }

    // MARK: - Поток

    /// Ссылка на поток для `sc:123` / `ym:456` / `yt:<videoId>` / `vk:<owner>_<id>`. fresh — не брать из кэша
    /// (ссылка протухла). safe — запасной путь, если поток не открылся: без FLAC (Яндекс — mp3 до 320),
    /// SoundCloud — сам, без двойника, YouTube — с новой visitorData.
    func stream(_ ref: String, fresh: Bool = false, safe: Bool = false) async throws -> StreamSource {
        // Spotify на iPhone не играет — трек отметить для резервного сервиса (этап 4), не падать
        if ServiceRegistry.service(of: ref) == .sp { throw ServiceError(message: Spotify.needsFallback) }
        if safe {
            let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw ServiceError(message: "Неверный трек \(ref)") }
            let source = switch parts[0] {
            case "ym": try await yandexClient().stream(parts[1], maxKbps: min(maxKbps, 320))
            case "yt": try await youTubeStream(parts[1], fresh: true)
            case "vk": try await vkStream(parts[1], fresh: true)
            default: try await soundCloudStream(ref, id: parts[1], fresh: true)
            }
            streams[ref] = (source, Date())
            return source
        }
        if !fresh, let cached = streams[ref], Date().timeIntervalSince(cached.at) < Self.streamTTL {
            return cached.source
        }
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw ServiceError(message: "Неверный трек \(ref)") }
        let source: StreamSource
        switch parts[0] {
        case "sc":
            if soundCloudViaYandex, yandex != nil, let twin = await yandexTwin(ref, id: parts[1]) {
                source = twin
            } else {
                source = try await soundCloudStream(ref, id: parts[1], fresh: fresh)
            }
        case "ym":
            source = try await yandexClient().stream(parts[1], maxKbps: maxKbps)
        case "yt":
            source = try await youTubeStream(parts[1], fresh: fresh)
        case "vk":
            source = try await vkStream(parts[1], fresh: fresh)
        default:
            throw ServiceError(message: "Неизвестный источник в \(ref)")
        }
        streams[ref] = (source, Date())
        return source
    }

    private func soundCloudStream(_ ref: String, id: String, fresh: Bool) async throws -> StreamSource {
        let cached = fresh ? nil : soundCloudRaw[ref]
        do {
            return try await withSoundCloud { client in
                let json = if let cached { cached } else { try await client.trackJSON(id) }
                return try await client.stream(json)
            }
        } catch _ where cached != nil {
            // в сохранённом JSON могла протухнуть track_authorization — берём трек заново
            let json = try await withSoundCloud { try await $0.trackJSON(id) }
            soundCloudRaw[ref] = json
            return try await withSoundCloud { try await $0.stream(json) }
        }
    }

    /// Поток YouTube Music берётся гостем (клиент VISIONOS cookie не принимает). Не открылся — ещё
    /// раз с новой visitorData; вторая ошибка уходит наверх с причиной от YouTube.
    private func youTubeStream(_ videoID: String, fresh: Bool) async throws -> StreamSource {
        let guest = YouTube(creds: nil)
        do {
            return try await guest.stream(videoID, visitor: try await youTubeVisitor(fresh: fresh), high: youTubeHigh)
        } catch where !fresh {
            return try await guest.stream(videoID, visitor: try await youTubeVisitor(fresh: true), high: youTubeHigh)
        }
    }

    private func youTubeVisitor(fresh: Bool) async throws -> String {
        if !fresh, let youTubeVisitor { return youTubeVisitor }
        let visitor = try await YouTube.visitorData()
        youTubeVisitor = visitor
        return visitor
    }

    /// Тот же трек на Яндексе. Любая ошибка — nil, и играет SoundCloud. Пара запоминается на сеанс.
    private func yandexTwin(_ ref: String, id: String) async -> StreamSource? {
        let yandexId: String
        if let known = yandexTwins[ref] {
            guard let known else { return nil }
            yandexId = known
        } else {
            let found: String? = (try? await findYandexTwin(ref, id: id)) ?? nil
            yandexTwins[ref] = .some(found)
            guard let found else { return nil }
            yandexId = found
        }
        guard let client = try? yandexClient(), let source = try? await client.stream(yandexId, maxKbps: maxKbps) else { return nil }
        if case let .file(url, quality) = source { return .file(url: url, quality: "\(quality) · Яндекс") }
        return source
    }

    private func findYandexTwin(_ ref: String, id: String) async throws -> String? {
        let json: JSONValue
        if let cached = soundCloudRaw[ref] {
            json = cached
        } else {
            json = try await withSoundCloud { try await $0.trackJSON(id) }
        }
        let wanted = TrackMatch.soundCloud(
            uploader: json["user"]["username"].string ?? "",
            metaArtist: json["publisher_metadata"]["artist"].string,
            title: json["title"].string ?? "",
            durationMs: json["full_duration"].int ?? json["duration"].int ?? 0
        )
        let client = try yandexClient()
        for query in wanted.queries {
            if let match = wanted.best(try await client.search(query, limit: 8)) {
                return String(match.ref.dropFirst("ym:".count))
            }
        }
        return nil
    }
}

/// Ключи сервисов в Keychain — одним JSON на сервис.
enum ServiceVault {
    private static let keychainService = "SonarServices"

    static func load<C: Codable & Sendable>(_ account: String) -> StoredService<C>? {
        guard let data = Keychain.data(service: keychainService, account: account) else { return nil }
        return try? JSONDecoder().decode(StoredService<C>.self, from: data)
    }

    static func save<C: Codable & Sendable>(_ account: String, _ value: StoredService<C>) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        Keychain.set(String(decoding: data, as: UTF8.self), service: keychainService, account: account)
    }

    static func delete(_ account: String) {
        Keychain.set(nil, service: keychainService, account: account)
    }
}
