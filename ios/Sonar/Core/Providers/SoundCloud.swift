import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // тесты логики на Linux
#endif

/// SoundCloud через api-v2: поиск, трек, ссылка на поток, похожие, плейлисты, лайки. Порт
/// `windows/src-tauri/src/providers/soundcloud.rs` (опыт — selfbot `sc_api.py`, `sc_audio.py`).
struct SoundCloud: Sendable {
    static let api = "https://api-v2.soundcloud.com"

    var clientId: String
    /// OAuth-токен необязателен: без него играют только открытые треки.
    var oauthToken: String?
    var session: URLSession = .shared

    private func get(_ url: String, _ query: [(String, String)] = []) async throws -> JSONValue {
        var request = URLRequest(url: try HTTP.url(url, query: [("client_id", clientId)] + query))
        request.setValue(HTTP.browserAgent, forHTTPHeaderField: "User-Agent")
        if let token = oauthToken, !token.isEmpty {
            request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        }
        return try JSONValue(data: await HTTP.data(request, service: "SoundCloud", session: session))
    }

    /// Проверка ключей: с токеном — профиль, без — пробный поиск.
    func account() async throws -> ServiceAccount {
        if let token = oauthToken, !token.isEmpty {
            let me = try await get("\(Self.api)/me")
            return ServiceAccount(name: me["username"].string, avatarURL: me["avatar_url"].string, uid: me["id"].idString)
        }
        _ = try await get("\(Self.api)/search/tracks", [("q", "a"), ("limit", "1")])
        return ServiceAccount()
    }

    /// Поиск треков. Вместе с моделью — сырой JSON: в нём данные для потока.
    func search(_ query: String, limit: Int) async throws -> [(track: Track, json: JSONValue)] {
        let data = try await get("\(Self.api)/search/tracks", [("q", query), ("limit", "\(limit)")])
        return data["collection"].items.compactMap { json in Self.parseTrack(json).map { ($0, json) } }
    }

    /// Исполнители, альбомы и плейлисты для вкладок поиска.
    func searchMore(_ query: String, limit: Int) async throws -> (artists: [Artist], albums: [Album], playlists: [ServicePlaylist]) {
        let params = [("q", query), ("limit", "\(limit)")]
        async let users = try? get("\(Self.api)/search/users", params)
        async let albums = try? get("\(Self.api)/search/albums", params)
        async let lists = try? get("\(Self.api)/search/playlists_without_albums", params)
        return (
            await users?["collection"].items.compactMap(Self.parseArtist) ?? [],
            await albums?["collection"].items.compactMap(Self.parseAlbum) ?? [],
            await lists?["collection"].items.compactMap(Self.parsePlaylist) ?? []
        )
    }

    func user(_ id: String) async throws -> JSONValue {
        try await get("\(Self.api)/users/\(id)")
    }

    func topTracks(_ id: String, limit: Int) async throws -> [JSONValue] {
        try await get("\(Self.api)/users/\(id)/toptracks", [("limit", "\(limit)")])["collection"].items
    }

    func userAlbums(_ id: String) async throws -> [Album] {
        try await get("\(Self.api)/users/\(id)/albums", [("limit", "30")])["collection"].items.compactMap(Self.parseAlbum)
    }

    /// Что пользователь репостнул (`/stream/users/{id}/reposts`) — раздел «Репосты» на странице исполнителя.
    func userReposts(_ id: String, limit: Int) async throws -> [JSONValue] {
        Self.repostTracks(try await get("\(Self.api)/stream/users/\(id)/reposts", [("limit", "\(limit)")]))
    }

    /// Из ленты репостов — только треки (репосты плейлистов мимо), каждый один раз, по порядку. Как Rust `repost_tracks`.
    static func repostTracks(_ page: JSONValue) -> [JSONValue] {
        var seen = Set<Int>()
        return page["collection"].items
            .filter { $0["type"].string.map { $0.hasPrefix("track") } ?? true }
            .map { $0["track"] }
            .filter { track in track.isObject && (track["id"].int.map { seen.insert($0).inserted } ?? false) }
    }

    /// Свои плейлисты пользователя (без альбомов) — фантомные плейлисты в медиатеке.
    func userPlaylists(_ id: String) async throws -> [ServicePlaylist] {
        try await get("\(Self.api)/users/\(id)/playlists_without_albums", [("limit", "50")])["collection"].items.compactMap(Self.parsePlaylist)
    }

    /// Плейлист или альбом целиком: шапка + сырой JSON всех треков по порядку. SoundCloud отдаёт целиком
    /// только первые треки, остальные — заглушки с id: дозапрашиваем по 50.
    func playlist(_ id: String) async throws -> (head: JSONValue, tracks: [JSONValue]) {
        let head = try await get("\(Self.api)/playlists/\(id)", [("representation", "full")])
        return (head, try await fillStubs(head["tracks"].items))
    }

    /// Лайки пользователя (до max, новые первыми), постранично по `next_href`.
    func userLikes(_ id: String, max: Int) async throws -> [JSONValue] {
        var out: [JSONValue] = []
        var url = "\(Self.api)/users/\(id)/track_likes?limit=200&linked_partitioning=1"
        while true {
            let page = try await get(url)
            out.append(contentsOf: page["collection"].items.map { $0["track"] }.filter(\.isObject))
            guard let next = page["next_href"].string, out.count < max else { break }
            url = next
        }
        return Array(out.prefix(max))
    }

    private func fillStubs(_ items: [JSONValue]) async throws -> [JSONValue] {
        let missing = items.filter { $0["title"].isNull }.compactMap { $0["id"].int }
        var full: [Int: JSONValue] = [:]
        for start in stride(from: 0, to: missing.count, by: 50) {
            let ids = missing[start ..< min(start + 50, missing.count)].map(String.init).joined(separator: ",")
            for track in try await get("\(Self.api)/tracks", [("ids", ids)]).items {
                if let id = track["id"].int { full[id] = track }
            }
        }
        return items.compactMap { item in
            item["title"].isNull ? item["id"].int.flatMap { full[$0] } : item
        }
    }

    /// Похожие треки (`/tracks/{id}/related`) — кандидаты для волны и «Авто похожих».
    func related(_ id: String, limit: Int) async throws -> [JSONValue] {
        try await get("\(Self.api)/tracks/\(id)/related", [("limit", "\(limit)")])["collection"].items
    }

    /// Что за адресом soundcloud.com (трек, плейлист / альбом, пользователь).
    func resolve(_ url: String) async throws -> JSONValue {
        try await get("\(Self.api)/resolve", [("url", url)])
    }

    func trackJSON(_ id: String) async throws -> JSONValue {
        try await get("\(Self.api)/tracks/\(id)")
    }

    /// JSON трека → ссылка на поток (вариант выбирает `pickTranscoding`).
    func stream(_ track: JSONValue) async throws -> StreamSource {
        guard let transcoding = Self.pickTranscoding(track) else {
            throw Unplayable(reason: .unavailable, message: "SoundCloud: у трека нет доступного потока")
        }
        return try await stream(track, transcoding: transcoding)
    }

    /// Ссылка на поток выбранного варианта (для скачивания — `pickProgressive`).
    func stream(_ track: JSONValue, transcoding: JSONValue) async throws -> StreamSource {
        guard let url = transcoding["url"].string else { throw ServiceError(message: "SoundCloud: пустая ссылка потока") }
        let data = try await get(url, [("track_authorization", track["track_authorization"].string ?? "")])
        guard let link = data["url"].string.flatMap(URL.init(string:)) else {
            throw ServiceError(message: "SoundCloud: поток без ссылки")
        }
        let quality = Self.qualityLabel(transcoding)
        return transcoding["format"]["protocol"].string == "progressive"
            ? .file(url: link, quality: quality)
            : .hls(url: link, quality: quality)
    }

    // MARK: - Публичный client_id

    /// Публичный client_id с soundcloud.com (как `_sc_refresh_client_id` в selfbot): страница → скрипты
    /// `a-v2.sndcdn.com/assets/*.js` с конца → `client_id:"<32 символа>"`. Агент — десктопный: с айфонным
    /// soundcloud.com уводит на m.soundcloud.com, где этих скриптов нет.
    static func publicClientId(session: URLSession = .shared) async throws -> String {
        func text(_ url: String) async throws -> String {
            var request = URLRequest(url: URL(string: url)!)
            request.setValue(clientIdAgent, forHTTPHeaderField: "User-Agent")
            return String(decoding: try await HTTP.data(request, service: "SoundCloud", session: session), as: UTF8.self)
        }
        let page = try await text("https://soundcloud.com/")
        for source in scriptURLs(page).reversed() {
            if let js = try? await text(source), let id = findClientId(js) { return id }
        }
        throw ServiceError(message: "SoundCloud: не нашёл client_id на сайте — вставь свой в Профиль → Сервисы")
    }

    static let clientIdAgent = HTTP.desktopAgent

    static func scriptURLs(_ html: String) -> [String] {
        let start = "https://a-v2.sndcdn.com/assets/"
        var out: [String] = []
        var rest = Substring(html)
        while let range = rest.range(of: start) {
            let tail = rest[range.lowerBound...]
            let end = tail.firstIndex(of: "\"") ?? tail.endIndex
            let candidate = tail[..<end]
            if candidate.hasSuffix(".js") { out.append(String(candidate)) }
            rest = tail[end...]
        }
        return out
    }

    static func findClientId(_ js: String) -> String? {
        for pattern in ["client_id:\"", "client_id=\""] {
            var rest = Substring(js)
            while let range = rest.range(of: pattern) {
                let after = rest[range.upperBound...]
                let id = after.prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }
                if id.count == 32, after.dropFirst(32).first == "\"" { return String(id) }
                rest = after
            }
        }
        return nil
    }

    // MARK: - Разбор JSON

    /// «aac_160k» → «AAC 160», mp3 → «MP3 128» (битрейт у mp3_* в пресете не пишут).
    static func qualityLabel(_ transcoding: JSONValue) -> String {
        let codec = (transcoding["format"]["mime_type"].string ?? "").contains("mpeg") ? "MP3" : "AAC"
        return "\(codec) \(kbps(transcoding["preset"].string ?? ""))"
    }

    private static func kbps(_ preset: String) -> Int {
        preset.split(separator: "_").lazy.compactMap { part in
            part.hasSuffix("k") ? Int(part.dropLast()) : nil
        }.first ?? 128
    }

    /// Лучшее, что умеет AVPlayer: AAC HLS (больший битрейт) → mp3 файлом → mp3 HLS. DRM и Opus пропускаем;
    /// превью 30 с — только если другого нет.
    static func pickTranscoding(_ track: JSONValue) -> JSONValue? {
        func score(_ t: JSONValue) -> Int? {
            guard let proto = t["format"]["protocol"].string, let mime = t["format"]["mime_type"].string else { return nil }
            let base: Int
            switch (proto, mime) {
            case ("hls", let m) where m.hasPrefix("audio/mp4"): base = 3000
            case ("progressive", "audio/mpeg"): base = 2000
            case ("hls", "audio/mpeg"): base = 1000
            default: return nil
            }
            let total = base + kbps(t["preset"].string ?? "")
            return t["snipped"].bool == true ? total - 10_000 : total
        }
        return track["media"]["transcodings"].items
            .compactMap { t in score(t).map { (score: $0, t: t) } }
            .max { $0.score < $1.score }?.t
    }

    /// Играть можно только отрывок: `policy: SNIP` (без Go+) или лучший вариант потока — обрезанный.
    static func isSnippet(_ track: JSONValue) -> Bool {
        track["policy"].string == "SNIP" || pickTranscoding(track)?["snipped"].bool == true
    }

    /// Прямой mp3 файлом (`progressive`, не превью) — его можно скачать; у многих треков его нет, только HLS.
    static func pickProgressive(_ track: JSONValue) -> JSONValue? {
        track["media"]["transcodings"].items.first { t in
            t["format"]["protocol"].string == "progressive" && t["format"]["mime_type"].string == "audio/mpeg" && t["snipped"].bool != true
        }
    }

    static func parseTrack(_ json: JSONValue) -> Track? {
        guard let id = json["id"].int, let title = json["title"].string else { return nil }
        let user = json["user"]
        let name = user["username"].string ?? ""
        return Track(
            ref: "sc:\(id)",
            title: title,
            artist: name,
            artists: [ArtistRef(ref: "sca:\(user["id"].int ?? 0)", name: name, avatarURL: user["avatar_url"].string)],
            album: nil,
            durationMs: json["full_duration"].int ?? json["duration"].int ?? 0,
            coverURL: (json["artwork_url"].string ?? user["avatar_url"].string).map(bigArtwork),
            url: json["permalink_url"].string,
            explicit: json["publisher_metadata"]["explicit"].bool ?? false,
            available: json["policy"].string != "BLOCK",
            plays: json["playback_count"].int,
            tags: tags(json)
        )
    }

    static func parseArtist(_ json: JSONValue) -> Artist? {
        guard let id = json["id"].int, let name = json["username"].string else { return nil }
        return Artist(ref: "sca:\(id)", name: name, avatarURL: json["avatar_url"].string.map(bigArtwork),
                      followers: json["followers_count"].int, url: json["permalink_url"].string)
    }

    /// Обложка плейлиста: своя, иначе первого трека.
    private static func playlistCover(_ json: JSONValue) -> String? {
        (json["artwork_url"].string ?? json["tracks"][0]["artwork_url"].string).map(bigArtwork)
    }

    /// Альбом SoundCloud — плейлист с `set_type` album/ep; ref `scalb:<id>`.
    static func parseAlbum(_ json: JSONValue) -> Album? {
        guard let id = json["id"].int, let title = json["title"].string else { return nil }
        let user = json["user"]
        let name = user["username"].string ?? ""
        let date = json["release_date"].string ?? json["published_at"].string ?? json["created_at"].string ?? ""
        let released = date.count >= 10 && Array(date)[4] == "-" ? String(date.prefix(10)) : nil
        return Album(
            ref: "scalb:\(id)",
            title: title,
            artist: name,
            artists: user["id"].int.map { [ArtistRef(ref: "sca:\($0)", name: name, avatarURL: user["avatar_url"].string)] } ?? [],
            coverURL: playlistCover(json),
            year: Int(date.prefix(4)),
            released: released,
            trackCount: json["track_count"].int ?? 0,
            url: json["permalink_url"].string
        )
    }

    static func parsePlaylist(_ json: JSONValue) -> ServicePlaylist? {
        guard let id = json["id"].int, let title = json["title"].string else { return nil }
        return ServicePlaylist(ref: "scpl:\(id)", title: title, owner: json["user"]["username"].string ?? "",
                               coverURL: playlistCover(json), trackCount: json["track_count"].int ?? 0)
    }

    /// `…-large.jpg` → `…-t500x500.jpg`.
    static func bigArtwork(_ url: String) -> String {
        url.replacingOccurrences(of: "-large.", with: "-t500x500.")
    }

    /// Жанр и теги одной строкой в нижнем регистре — по ним волна понимает настроение.
    static func tags(_ json: JSONValue) -> String? {
        let parts = ["genre", "tag_list"].compactMap { json[$0].string?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.map { $0.lowercased() }.joined(separator: " ")
    }
}

/// Подключённый аккаунт сервиса — для экрана «Сервисы».
struct ServiceAccount: Codable, Equatable, Sendable {
    var name: String?
    var avatarURL: String?
    /// id аккаунта в сервисе — для его плейлистов и лайков.
    var uid: String?
    /// Подписка (Яндекс Плюс); nil — сервис не говорит. Старый JSON в Keychain без поля читается как nil.
    var premium: Bool? = nil
}
