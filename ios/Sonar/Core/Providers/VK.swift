import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // тесты логики на Linux
#endif

/// VK Музыка: поиск, «Моя музыка», плейлисты, альбомы, исполнители, похожие, ссылка на поток.
/// Порт `windows/src-tauri/src/providers/vk.rs`. Ключ — токен Kate Mobile (`vk1.a.…`, вход на oauth.vk.com
/// в `VKLoginSheet` или «Вставить ключ»): методы `audio.*` VK отдаёт только «своим» клиентам, поэтому у
/// каждого запроса — User-Agent Kate Mobile. Запросы — POST с формой: токен в теле, не в адресе, и не
/// попадает ни в ошибку, ни в журнал.
///
/// ref: трек `vk:<owner>_<id>` (access_key трека — на диске, `VKKeyStore`), альбом
/// `vkalb:<owner>_<id>[_<access_key>]`, плейлист `vkpl:<owner>_<id>[_<access_key>]` и `vkpl:likes`,
/// исполнитель `vka:<id>` (docs/API.md «Префиксы ref»).
struct VK: Sendable {
    static let api = "https://api.vk.com/method"
    /// Версия API, на которой проверены поля ответа.
    static let version = "5.131"
    /// Приложение Kate Mobile: ему VK открывает `audio.*`.
    static let clientId = "2685278"
    /// User-Agent Kate Mobile — на каждом запросе к API и к CDN VK (`PlaybackEngine`).
    static let userAgent = "KateMobileAndroid/56 lite-460 (Android 4.4.2; SDK 19; x86; unknown Android SDK built for x86; en)"
    static let name = "VK Музыка"
    /// Ключ отозван, устарел или без права `audio` (коды 5, 15, 25, 201, 1117).
    static let authExpired = "Ключ VK больше не работает — войди заново"
    static let tooMany = "VK Музыка: слишком много запросов, подожди минуту"
    static let captcha = "VK Музыка: VK просит подтвердить вход — войди заново"
    static let failed = "VK Музыка: сервис ответил ошибкой"
    static let offline = "VK Музыка: нет связи с VK"
    static let noStream = "VK Музыка: VK не отдал ссылку на трек"
    /// VK пускает не больше 3 запросов в секунду с одного ключа.
    static let gap: TimeInterval = 0.35
    /// Сколько отдаёт за раз `audio.get` / `audio.getAudiosByArtist`.
    static let page = 200
    /// Пауза перед повтором, когда VK просит реже (код 6).
    static let retryDelay: UInt64 = 1_000_000_000
    /// CDN VK: им тоже нужен User-Agent Kate Mobile.
    static let cdnHosts = [".vkuseraudio.net", ".vkuseraudio.com", ".vk-cdn.net", ".userapi.com"]

    var token: String
    var session: URLSession = .shared

    // MARK: - Запросы

    /// Метод API: ответ — поле `response`. Код 6 (слишком часто) — один повтор через секунду.
    private func call(_ method: String, _ params: [(String, String)]) async throws -> JSONValue {
        do {
            return try await callOnce(method, params)
        } catch let error as ServiceError where error.message == Self.tooMany {
            try await Task.sleep(nanoseconds: Self.retryDelay)
            return try await callOnce(method, params)
        }
    }

    private func callOnce(_ method: String, _ params: [(String, String)]) async throws -> JSONValue {
        let wait = await VKThrottle.shared.turn()
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        var request = URLRequest(url: try HTTP.url("\(Self.api)/\(method)", query: []))
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.form(params + [("access_token", token), ("v", Self.version)])
        let data: Data
        do {
            data = try await HTTP.data(request, service: Self.name, session: session)
        } catch let error as ServiceError {
            throw error
        } catch {
            // текст ошибки сети не берём: в нём адрес, а мало ли что туда попадёт
            throw ServiceError(message: Self.offline)
        }
        guard let json = try? JSONValue(data: data) else { throw ServiceError(message: Self.failed) }
        if let error = Self.apiError(json) { throw error }
        return json["response"]
    }

    /// Ошибка API (`{"error": {...}}`) → текст для человека. Сообщение VK в текст не берём (в нём бывает ключ).
    static func apiError(_ json: JSONValue) -> ServiceError? {
        let error = json["error"]
        guard error.isObject else { return nil }
        let text = switch error["error_code"].int ?? 0 {
        case 5, 15, 25, 201, 1117: authExpired
        case 6, 9, 29: tooMany
        case 14, 17: captcha
        default: failed
        }
        return ServiceError(message: text)
    }

    // MARK: - Методы

    /// Кто вошёл, и проверка, что ключу открыта музыка (иначе — «войди заново»).
    func account() async throws -> ServiceAccount {
        let me = try await call("users.get", [("fields", "photo_200")])
        guard let account = Self.parseAccount(me[0]) else { throw ServiceError(message: Self.authExpired) }
        _ = try await call("audio.get", [("owner_id", account.uid ?? ""), ("count", "1")])
        return account
    }

    func search(_ query: String, limit: Int) async throws -> [VKAudio] {
        let data = try await call("audio.search", [("q", query), ("count", String(min(limit, 300))), ("auto_complete", "1"), ("sort", "2")])
        return Self.audios(data["items"])
    }

    /// Исполнители, альбомы и плейлисты. Каждый из трёх запросов необязателен: упал один — остальные всё
    /// равно показываем; общей ошибкой — только протухший ключ.
    func searchMore(_ query: String, limit: Int) async throws -> (artists: [Artist], albums: [Album], playlists: [ServicePlaylist]) {
        let params = [("q", query), ("count", String(min(limit, 100)))]
        let artists = try await optionalItems("audio.searchArtists", params)
        let albums = try await optionalItems("audio.searchAlbums", params)
        let playlists = try await optionalItems("audio.searchPlaylists", params)
        return (
            artists.compactMap(Self.parseArtist),
            albums.compactMap(Self.parseAlbum),
            playlists.compactMap(Self.parsePlaylist)
        )
    }

    /// `items` метода; ошибка (кроме протухшего ключа) — пустой список.
    private func optionalItems(_ method: String, _ params: [(String, String)]) async throws -> [JSONValue] {
        do {
            return Self.items(try await call(method, params))
        } catch let error as ServiceError where error.message == Self.authExpired {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return []
        }
    }

    /// Треки по `owner_id_id[_access_key]` (до 100 за раз).
    func byId(_ ids: [String]) async throws -> [VKAudio] {
        Self.audios(try await call("audio.getById", [("audios", ids.joined(separator: ","))]))
    }

    /// «Моя музыка» аккаунта (до max), новые сверху.
    func likes(uid: String, max: Int) async throws -> [VKAudio] {
        try await pages("audio.get", [("owner_id", uid)], max: max)
    }

    /// Плейлисты аккаунта (свои и добавленные).
    func playlists(uid: String) async throws -> [ServicePlaylist] {
        Self.items(try await call("audio.getPlaylists", [("owner_id", uid), ("count", "100")])).compactMap(Self.parsePlaylist)
    }

    /// Плейлист или альбом по `owner_id_id[_access_key]`: шапка (сырой JSON) и треки (до max).
    func playlist(_ id: String, max: Int) async throws -> (head: JSONValue, tracks: [VKAudio]) {
        guard let parsed = VKPlaylistID.parse(id) else { throw ServiceError(message: "Неверная ссылка на плейлист VK") }
        let key = parsed.key.map { [("access_key", $0)] } ?? []
        let head = try await call("audio.getPlaylistById", [("owner_id", parsed.owner), ("playlist_id", parsed.id)] + key)
        let tracks = try await pages("audio.get", [("owner_id", parsed.owner), ("album_id", parsed.id)] + key, max: max)
        return (head, tracks)
    }

    func artist(_ id: String) async throws -> Artist {
        guard let artist = Self.parseArtist(try await call("audio.getArtistById", [("artist_id", id)])) else {
            throw ServiceError(message: "VK Музыка: исполнитель не найден")
        }
        return artist
    }

    /// Треки исполнителя (до max) в порядке популярности VK.
    func artistTracks(_ id: String, max: Int) async throws -> [VKAudio] {
        try await pages("audio.getAudiosByArtist", [("artist_id", id)], max: max)
    }

    func artistAlbums(_ id: String, limit: Int) async throws -> [Album] {
        Self.items(try await call("audio.getAlbumsByArtist", [("artist_id", id), ("count", String(min(limit, 100)))])).compactMap(Self.parseAlbum)
    }

    /// Похожие на трек `owner_id_id` — рекомендации VK от него.
    func similar(_ id: String, limit: Int) async throws -> [VKAudio] {
        Self.audios(try await call("audio.getRecommendations", [("target_audio", id), ("count", String(min(limit, 100)))])["items"])
    }

    /// Метод со страницами `count`/`offset`: до max треков.
    private func pages(_ method: String, _ params: [(String, String)], max: Int) async throws -> [VKAudio] {
        var out: [VKAudio] = []
        var offset = 0
        while out.count < max {
            let asked = min(Self.page, max - out.count)
            let data = try await call(method, params + [("count", String(asked)), ("offset", String(offset))])
            let raw = Self.items(data)
            offset += raw.count
            out += raw.compactMap(Self.parseAudio)
            if Self.lastPage(got: raw.count, asked: asked, offset: offset, total: data["count"].int) { break }
        }
        return Array(out.prefix(max))
    }

    /// Страниц больше нет: пустая страница; есть `count` — дошли до него; нет `count` (так бывает у
    /// `audio.getAudiosByArtist`) — VK отдал меньше, чем просили.
    static func lastPage(got: Int, asked: Int, offset: Int, total: Int?) -> Bool {
        if got == 0 { return true }
        guard let total else { return got < asked }
        return offset >= total
    }
}

/// Трек VK и то, что нужно для потока: access_key и ссылка (если VK отдал её сразу).
struct VKAudio: Sendable, Equatable {
    var track: Track
    var accessKey: String?
    var streamURL: String?
}

/// Разобранный `owner_id_id[_access_key]` (owner бывает отрицательным: `-2000123_456_abc`).
struct VKPlaylistID: Equatable, Sendable {
    var owner: String
    var id: String
    var key: String?

    static func parse(_ text: String) -> VKPlaylistID? {
        let parts = text.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let owner = Int(parts[0]), let id = Int(parts[1]) else { return nil }
        let key = parts.count == 3 ? parts[2] : nil
        let valid = key.flatMap { $0.isEmpty || !$0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } ? nil : $0 }
        return VKPlaylistID(owner: String(owner), id: String(id), key: valid)
    }
}

// MARK: - Разбор ответов (как в Rust)

extension VK {
    /// `items` ответа-списка (или сам ответ, если это массив).
    static func items(_ json: JSONValue) -> [JSONValue] {
        json["items"].array ?? json.array ?? []
    }

    static func audios(_ json: JSONValue) -> [VKAudio] {
        json.items.compactMap(parseAudio)
    }

    /// id трека `owner_id_id` (часть ref после `vk:`) — проверка формы.
    static func isAudioID(_ text: String) -> Bool {
        guard let parsed = VKPlaylistID.parse(text) else { return false }
        return parsed.key == nil && text.filter { $0 == "_" }.count == 1
    }

    /// Строка или число, непустое.
    private static func text(_ json: JSONValue) -> String? {
        if let s = json.string { return s.isEmpty ? nil : s }
        return json.int.map(String.init)
    }

    /// Самая крупная обложка из `thumb` / `photo` (`photo_600` → `photo_68`).
    static func cover(_ thumb: JSONValue) -> String? {
        ["photo_600", "photo_1200", "photo_300", "photo_270", "photo_135", "photo_68"].lazy
            .compactMap { thumb[$0].string }.first { !$0.isEmpty }
    }

    /// Картинка исполнителя: самый широкий кадр из `photo: [{url, width}]`.
    private static func widest(_ photos: JSONValue) -> String? {
        photos.array?.max { ($0["width"].int ?? 0) < ($1["width"].int ?? 0) }?["url"].string
    }

    /// Жанр VK (`genre_id`) → тег для режимов волны.
    static func genre(_ id: Int) -> String? {
        [1: "rock", 2: "pop", 3: "rap hip-hop", 4: "easy listening", 5: "house dance", 6: "instrumental", 7: "metal",
         8: "dubstep", 10: "drum and bass", 11: "trance", 12: "chanson", 13: "ethnic", 14: "acoustic", 15: "reggae",
         16: "classical", 17: "indie pop", 21: "alternative", 22: "electropop disco", 1001: "jazz blues"][id]
    }

    private static func artistRefs(_ json: JSONValue) -> [ArtistRef] {
        (json["main_artists"].items + json["featured_artists"].items).compactMap { artist in
            guard let id = text(artist["id"]), let name = artist["name"].string else { return nil }
            return ArtistRef(ref: "vka:\(id)", name: name)
        }
    }

    /// `owner_id`, `id`, `access_key` → `owner_id_id[_access_key]` (как ссылки vk.com/music/…).
    private static func fullID(_ owner: JSONValue, _ id: JSONValue, _ key: JSONValue) -> String? {
        guard let owner = owner.int, let id = id.int else { return nil }
        if let key = key.string, !key.isEmpty { return "\(owner)_\(id)_\(key)" }
        return "\(owner)_\(id)"
    }

    /// Аудиозапись VK → трек Sonar.
    static func parseAudio(_ json: JSONValue) -> VKAudio? {
        guard let owner = json["owner_id"].int, let id = json["id"].int, let rawTitle = json["title"].string else { return nil }
        let base = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = json["subtitle"].string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let album = json["album"]
        let albumRef = fullID(album["owner_id"], album["id"], album["access_key"])
            .map { AlbumRef(ref: "vkalb:\($0)", title: album["title"].string ?? "") }
        let track = Track(
            ref: "vk:\(owner)_\(id)",
            title: subtitle.isEmpty ? base : "\(base) (\(subtitle))",
            artist: (json["artist"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            artists: artistRefs(json),
            album: albumRef,
            durationMs: (json["duration"].int ?? 0) * 1000,
            coverURL: cover(album["thumb"]),
            url: "https://vk.com/audio\(owner)_\(id)",
            explicit: json["is_explicit"].bool ?? false,
            available: (json["content_restricted"].int ?? 0) == 0,
            plays: nil,
            tags: json["genre_id"].int.flatMap(genre)
        )
        return VKAudio(track: track, accessKey: json["access_key"].string.flatMap { $0.isEmpty ? nil : $0 },
                       streamURL: json["url"].string.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Ссылка из ответа VK → откуда играть. Пустая или заглушка «audio_api_unavailable» — ошибка.
    /// HLS у VK шифрован AES-128 — AVPlayer расшифровывает его сам.
    static func source(_ link: String) throws -> StreamSource {
        guard let url = URL(string: link), url.scheme?.hasPrefix("http") == true, url.host != nil,
              !url.path.contains("audio_api_unavailable") else { throw Unplayable(reason: .unavailable, message: noStream) }
        let quality = "MP3 320"
        return url.path.hasSuffix(".m3u8") ? .hls(url: url, quality: quality) : .file(url: url, quality: quality)
    }

    /// Адрес на CDN VK — ему нужен User-Agent Kate Mobile.
    static func isCDN(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return cdnHosts.contains { host.hasSuffix($0) }
    }

    static func parseAccount(_ user: JSONValue) -> ServiceAccount? {
        guard let id = user["id"].int else { return nil }
        let name = [user["first_name"].string, user["last_name"].string].compactMap { $0 }.joined(separator: " ")
        return ServiceAccount(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name,
                              avatarURL: user["photo_200"].string, uid: String(id), premium: nil)
    }

    static func parseArtist(_ json: JSONValue) -> Artist? {
        guard let id = text(json["id"]), let name = json["name"].string else { return nil }
        return Artist(ref: "vka:\(id)", name: name, avatarURL: widest(json["photo"]), followers: nil,
                      url: json["domain"].string.map { "https://vk.com/artist/\($0)" })
    }

    /// Обложка плейлиста: своя `photo` или первая из `thumbs` (коллаж из обложек альбомов).
    private static func playlistCover(_ json: JSONValue) -> String? {
        cover(json["photo"]) ?? cover(json["thumbs"][0])
    }

    /// id плейлиста для запросов: добавленный к себе чужой плейлист ведёт на оригинал.
    private static func playlistFullID(_ json: JSONValue) -> String? {
        let original = json["original"]
        return fullID(original["owner_id"], original["playlist_id"], original["access_key"])
            ?? fullID(json["owner_id"], json["id"], json["access_key"])
    }

    static func parseAlbum(_ json: JSONValue) -> Album? {
        guard let id = playlistFullID(json), let title = json["title"].string else { return nil }
        let artists = artistRefs(json)
        return Album(ref: "vkalb:\(id)", title: title, artist: artists.map(\.name).joined(separator: ", "), artists: artists,
                     coverURL: playlistCover(json), year: json["year"].int, released: nil,
                     trackCount: json["count"].int ?? 0, url: "https://vk.com/music/album/\(id)")
    }

    static func parsePlaylist(_ json: JSONValue) -> ServicePlaylist? {
        guard let id = playlistFullID(json), let title = json["title"].string else { return nil }
        return ServicePlaylist(ref: "vkpl:\(id)", title: title, owner: artistRefs(json).map(\.name).joined(separator: ", "),
                               coverURL: playlistCover(json), trackCount: json["count"].int ?? 0)
    }
}

/// Очередь запросов к VK: между запросами не меньше `VK.gap` (общая на всё приложение).
actor VKThrottle {
    static let shared = VKThrottle()

    private var next: Date?

    /// Сколько подождать перед запросом; следующий слот сдвигается.
    func turn() -> TimeInterval {
        let slot = Self.takeSlot(next: next, now: Date())
        next = slot.next
        return slot.wait
    }

    /// Чистая часть: сколько ждать и когда следующий свободный слот.
    static func takeSlot(next: Date?, now: Date, gap: TimeInterval = VK.gap) -> (wait: TimeInterval, next: Date) {
        let at = max(next ?? now, now)
        return (at.timeIntervalSince(now), at.addingTimeInterval(gap))
    }
}

/// Вход в VK в один клик: окно oauth.vk.com (implicit flow Kate Mobile) → `blank.html#access_token=…`.
/// Двухфакторка и капча проходят в том же окне. Порт `vk_auth_url` / `vk_outcome` из `login.rs`.
enum VKLogin {
    static let redirect = "https://oauth.vk.com/blank.html"

    enum Outcome: Equatable {
        case token(String)
        /// VK вернул ошибку: отказ, отмена.
        case denied
    }

    static var authURL: URL {
        var components = URLComponents(string: "https://oauth.vk.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: VK.clientId),
            URLQueryItem(name: "display", value: "mobile"),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "scope", value: "audio,offline"),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "revoke", value: "1"),
            URLQueryItem(name: "v", value: VK.version),
        ]
        return components.url!
    }

    /// Адрес окна → чем кончился вход; nil — вход ещё идёт (страница входа, двухфакторка, капча, чужой адрес).
    static func outcome(_ url: URL) -> Outcome? {
        guard url.scheme == "https", url.host == "oauth.vk.com", url.path == "/blank.html" else { return nil }
        let fragment = url.fragment ?? ""
        let pairs = fragment.split(separator: "&").map(String.init)
        if let raw = pairs.first(where: { $0.hasPrefix("access_token=") })?.dropFirst("access_token=".count), !raw.isEmpty {
            return .token(String(raw).removingPercentEncoding ?? String(raw))
        }
        let query = url.query ?? ""
        let failed = (pairs + query.split(separator: "&").map(String.init)).contains { $0.hasPrefix("error=") }
        return failed ? .denied : nil
    }
}
