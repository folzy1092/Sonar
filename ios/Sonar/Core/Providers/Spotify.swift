import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto // тесты логики на Linux (swift-crypto, тот же API)
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ключ Spotify — cookie `sp_dc` с open.spotify.com.
struct SpotifyCreds: Codable, Sendable, Equatable {
    var spDc: String

    enum CodingKeys: String, CodingKey {
        case spDc = "sp_dc"
    }
}

/// Spotify — порт `windows/src-tauri/src/providers/spotify.rs`: `sp_dc` → токен веб-плеера (TOTP) → Web API
/// (поиск, «Любимые треки», плейлисты, исполнитель, альбом). Рекомендаций не берём. На iPhone Spotify не играет
/// (librespot — только ПК с Premium): трек `sp:` — «нужен резервный сервис» (резерв — этап 4).
/// `sp_dc` не попадает ни в ошибки, ни в лог.
struct Spotify: Sendable {
    static let api = "https://api.spotify.com/v1"
    static let tokenURL = "https://open.spotify.com/api/token"
    /// Страница входа: после входа accounts.spotify.com ведёт на open.spotify.com, там ставится `sp_dc`.
    static let loginURL = URL(string: "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F")!
    /// Строк в одной странице Web API.
    static let page = 50
    /// Токен обновляем за минуту до конца.
    static let tokenMarginMs: Int64 = 60_000
    /// Шаг TOTP веб-плеера, секунд.
    static let totpStep: UInt64 = 30
    /// Срок токена, если сервер его не прислал.
    static let defaultTokenLifeMs: Int64 = 30 * 60_000
    /// Плейлистов аккаунта не больше.
    static let maxPlaylists = 500

    static let needsFallback = "Spotify: нужен резервный сервис"
    static let totpStale = "Spotify сменил защиту — Sonar подтянет новый ключ сам, попробуй через минуту"
    static let spDcBad = "Spotify: ключ sp_dc не подошёл — войди заново"
    static let notConnected = "Spotify не подключён — открой Настройки → Сервисы"
    static let unreachable = "Spotify: open.spotify.com недоступен"

    /// Шифр TOTP веб-плеера: версия (`totpVer`) и байты — формат `updates/spotify-totp.json` (`SpotifyTotp`).
    struct TotpSecret: Sendable, Equatable, Decodable {
        var version: Int
        var cipher: [UInt8]

        /// Вшитый запасной — версия 61, проверена 2026-11-19 (как `default_totp()` в Rust; v5 Spotify отвергает).
        static let `default` = TotpSecret(version: 61, cipher: [44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97,
                                                                75, 76, 94, 102, 43, 69, 49, 120, 118, 80, 64, 78])
    }

    /// Токен веб-плеера и когда он кончается.
    struct WebToken: Sendable, Equatable {
        var accessToken: String
        var expiresAtMs: Int64

        func isFresh(atMs now: Int64) -> Bool { now + Spotify.tokenMarginMs < expiresAtMs }
    }

    var creds: SpotifyCreds
    var tokens: SpotifyTokens
    var totp: SpotifyTotp = .shared
    var session: URLSession = .shared

    // MARK: - TOTP и ключ

    /// Ключ HMAC из шифра: каждый байт XOR ((i % 33) + 9), числа подряд десятичной строкой.
    static func totpKey(_ cipher: [UInt8]) -> Data {
        let digits = cipher.enumerated().map { i, b in String(b ^ UInt8(i % 33 + 9)) }.joined()
        return Data(digits.utf8)
    }

    /// HOTP (RFC 4226), 6 цифр.
    static func hotp(key: Data, counter: UInt64) -> String {
        let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: key)))
        let offset = Int(mac[19] & 0x0f)
        let value = (UInt32(mac[offset] & 0x7f) << 24 | UInt32(mac[offset + 1]) << 16
            | UInt32(mac[offset + 2]) << 8 | UInt32(mac[offset + 3])) % 1_000_000
        let text = String(value)
        return String(repeating: "0", count: 6 - text.count) + text
    }

    /// TOTP (RFC 6238) на момент `unixSeconds`, шаг 30 с.
    static func totp(key: Data, unixSeconds: UInt64) -> String {
        hotp(key: key, counter: unixSeconds / totpStep)
    }

    /// `sp_dc` как его вставили: голое значение, `sp_dc=…`, `sp_dc=…;` или вся строка Cookie.
    static func normalizeSpDc(_ raw: String) -> String? {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromCookie = raw.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("sp_dc=") }
            .map { String($0.dropFirst("sp_dc=".count)) }
        var value = fromCookie ?? raw
        while value.hasSuffix(";") { value.removeLast() }
        value = value.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard value.count >= 20, value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }

    /// Параметры запроса токена с TOTP на момент `unixSeconds`.
    static func tokenQuery(_ secret: TotpSecret, unixSeconds: UInt64) -> [(String, String)] {
        let code = totp(key: totpKey(secret.cipher), unixSeconds: unixSeconds)
        return [("reason", "init"), ("productType", "web-player"), ("totp", code), ("totpServer", code), ("totpVer", String(secret.version))]
    }

    /// Ответ `api/token` → токен или понятная ошибка (без `sp_dc` в тексте).
    static func parseToken(status: Int, body: Data, nowMs: Int64) throws -> WebToken {
        // «totp» ищем только в ответе с ошибкой: в удачном случайный accessToken может его содержать
        let failed = !(200 ..< 300).contains(status)
        let text = String(decoding: body, as: UTF8.self).lowercased()
        if status == 400 || (failed && text.contains("totp")) { throw ServiceError(message: totpStale) }
        guard !failed else { throw ServiceError.http("Spotify", status) }
        guard let json = try? JSONValue(data: body) else { throw ServiceError(message: "Spotify: непонятный ответ веб-плеера") }
        guard let token = json["accessToken"].string, !token.isEmpty, json["isAnonymous"].bool != true else {
            throw ServiceError(message: spDcBad)
        }
        let expires = json["accessTokenExpirationTimestampMs"].int.map(Int64.init) ?? nowMs + defaultTokenLifeMs
        return WebToken(accessToken: token, expiresAtMs: expires)
    }

    static var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    // MARK: - Разбор JSON Web API

    /// Самая крупная картинка (Spotify отдаёт по убыванию, но не обещает).
    static func bestImage(_ images: JSONValue) -> String? {
        images.items
            .compactMap { image -> (Int, String)? in image["url"].string.map { (image["width"].int ?? 0, $0) } }
            .max { $0.0 < $1.0 }?.1
    }

    private static func artistRefs(_ json: JSONValue) -> [ArtistRef] {
        json["artists"].items.compactMap { artist in
            guard let id = artist["id"].string, let name = artist["name"].string else { return nil }
            return ArtistRef(ref: "spa:\(id)", name: name)
        }
    }

    private static func joined(_ artists: [ArtistRef]) -> String {
        artists.map(\.name).joined(separator: ", ")
    }

    /// Трек; `album` — альбом снаружи (у треков альбома своего `album` нет). Локальные файлы и эпизоды — мимо.
    static func parseTrack(_ json: JSONValue, album outer: JSONValue? = nil) -> Track? {
        if json["is_local"].bool == true { return nil }
        if let type = json["type"].string, type != "track" { return nil }
        guard let id = json["id"].string, let title = json["name"].string else { return nil }
        let album = outer ?? json["album"]
        let artists = artistRefs(json)
        return Track(
            ref: "sp:\(id)", title: title, artist: joined(artists), artists: artists,
            album: album["id"].string.map { AlbumRef(ref: "spalb:\($0)", title: album["name"].string ?? "") },
            durationMs: json["duration_ms"].int ?? 0, coverURL: bestImage(album["images"]),
            url: json["external_urls"]["spotify"].string, explicit: json["explicit"].bool ?? false,
            // играет через резервный сервис — для очереди трек доступен
            available: true, plays: nil, tags: nil
        )
    }

    static func parseAlbum(_ json: JSONValue) -> Album? {
        guard let id = json["id"].string, let title = json["name"].string else { return nil }
        let artists = artistRefs(json)
        let date = json["release_date"].string
        return Album(
            ref: "spalb:\(id)", title: title, artist: joined(artists), artists: artists,
            coverURL: bestImage(json["images"]), year: date.flatMap { Int($0.prefix(4)) },
            released: date.flatMap { $0.count == 10 ? $0 : nil }, trackCount: json["total_tracks"].int ?? 0,
            url: json["external_urls"]["spotify"].string
        )
    }

    static func parseArtist(_ json: JSONValue) -> Artist? {
        guard let id = json["id"].string, let name = json["name"].string else { return nil }
        return Artist(ref: "spa:\(id)", name: name, avatarURL: bestImage(json["images"]),
                      followers: json["followers"]["total"].int, url: json["external_urls"]["spotify"].string)
    }

    /// Плейлист; число треков — в `tracks.total` (старый ответ) или `items.total` (новый).
    static func parsePlaylist(_ json: JSONValue) -> ServicePlaylist? {
        guard let id = json["id"].string, let title = json["name"].string else { return nil }
        return ServicePlaylist(ref: "sppl:\(id)", title: title,
                               owner: json["owner"]["display_name"].string ?? json["owner"]["id"].string ?? "",
                               coverURL: bestImage(json["images"]),
                               trackCount: json["tracks"]["total"].int ?? json["items"]["total"].int ?? 0)
    }

    /// `GET /me`: имя, аватар, id и Premium (`product == "premium"`).
    static func parseAccount(_ json: JSONValue) -> ServiceAccount {
        ServiceAccount(name: json["display_name"].string ?? json["id"].string, avatarURL: bestImage(json["images"]),
                       uid: json["id"].string, premium: json["product"].string.map { $0 == "premium" })
    }

    /// Строка плейлиста или «Любимых»: трек лежит в `track` (старый ответ) или `item` (новый).
    static func itemTrack(_ row: JSONValue) -> Track? {
        parseTrack(row["track"].isObject ? row["track"] : row["item"])
    }

    // MARK: - Сеть

    private func fetchToken(_ secret: TotpSecret) async throws -> WebToken {
        let url = try HTTP.url(Self.tokenURL, query: Self.tokenQuery(secret, unixSeconds: UInt64(Self.nowMs / 1000)))
        var request = URLRequest(url: url)
        request.setValue("sp_dc=\(creds.spDc)", forHTTPHeaderField: "Cookie")
        request.setValue(HTTP.browserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: (Data, URLResponse)
        do {
            response = try await session.data(for: request)
        } catch {
            throw ServiceError(message: Self.unreachable)
        }
        let status = (response.1 as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.parseToken(status: status, body: response.0, nowMs: Self.nowMs)
    }

    /// Токен из общего кэша; renew — взять заново (401 от Web API).
    func token(renew: Bool = false) async throws -> String {
        try await tokens.token(renew: renew) { try await freshToken() }
    }

    /// Токен с текущим шифром; шифр устарел — перечитать файл из репо и попробовать ещё раз.
    private func freshToken() async throws -> WebToken {
        _ = await totp.refresh(force: false, session: session)
        do {
            return try await fetchToken(await totp.current)
        } catch let error as ServiceError where error.message == Self.totpStale {
            guard await totp.refresh(force: true, session: session) else { throw error }
            return try await fetchToken(await totp.current)
        }
    }

    private func send(_ url: URL, token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("ru", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// GET Web API; 401 — один повтор со свежим токеном.
    private func get(_ path: String, _ query: [(String, String)] = []) async throws -> JSONValue {
        let url = try HTTP.url(path.hasPrefix("https://") ? path : Self.api + path, query: query)
        var (data, status) = try await send(url, token: token())
        if status == 401 {
            (data, status) = try await send(url, token: token(renew: true))
        }
        guard (200 ..< 300).contains(status) else { throw ServiceError.http("Spotify", status) }
        return try JSONValue(data: data)
    }

    /// Все страницы списка (`next`) до `max` строк.
    private func pages(_ path: String, max: Int) async throws -> [JSONValue] {
        var out: [JSONValue] = []
        var page = try await get(path, [("limit", String(Self.page))])
        while true {
            out += page["items"].items
            guard out.count < max, let next = page["next"].string else { break }
            page = try await get(next)
        }
        return Array(out.prefix(max))
    }

    private func searchRaw(_ query: String, types: String, limit: Int) async throws -> JSONValue {
        try await get("/search", [("q", query), ("type", types), ("limit", String(min(max(limit, 1), Self.page))), ("market", "from_token")])
    }

    // MARK: - Метаданные

    func account() async throws -> ServiceAccount {
        Self.parseAccount(try await get("/me"))
    }

    func search(_ query: String, limit: Int) async throws -> [Track] {
        try await searchRaw(query, types: "track", limit: limit)["tracks"]["items"].items.compactMap { Self.parseTrack($0) }
    }

    func searchMore(_ query: String, limit: Int) async throws -> (artists: [Artist], albums: [Album], playlists: [ServicePlaylist]) {
        let data = try await searchRaw(query, types: "artist,album,playlist", limit: limit)
        return (data["artists"]["items"].items.compactMap(Self.parseArtist),
                data["albums"]["items"].items.compactMap(Self.parseAlbum),
                data["playlists"]["items"].items.compactMap(Self.parsePlaylist))
    }

    /// «Любимые треки» аккаунта (`me/tracks`).
    func likes(max: Int) async throws -> [Track] {
        try await pages("/me/tracks", max: max).compactMap(Self.itemTrack)
    }

    func playlists() async throws -> [ServicePlaylist] {
        try await pages("/me/playlists", max: Self.maxPlaylists).compactMap(Self.parsePlaylist)
    }

    func playlist(_ id: String, max: Int) async throws -> (head: ServicePlaylist, tracks: [Track]) {
        guard var head = Self.parsePlaylist(try await get("/playlists/\(id)")) else { throw ServiceError(message: "Spotify: плейлист не найден") }
        let tracks = try await pages("/playlists/\(id)/tracks", max: max).compactMap(Self.itemTrack)
        head.trackCount = Swift.max(head.trackCount, tracks.count)
        return (head, tracks)
    }

    /// Шапка, популярные (`top-tracks`) и альбомы исполнителя.
    func artist(_ id: String) async throws -> (artist: Artist, top: [Track], albums: [Album]) {
        guard let artist = Self.parseArtist(try await get("/artists/\(id)")) else { throw ServiceError(message: "Spotify: исполнитель не найден") }
        let top = try await get("/artists/\(id)/top-tracks", [("market", "from_token")])["tracks"].items.compactMap { Self.parseTrack($0) }
        return (artist, top, try await artistAlbums(id))
    }

    func artistAlbums(_ id: String) async throws -> [Album] {
        try await pages("/artists/\(id)/albums?include_groups=album,single", max: 200).compactMap(Self.parseAlbum)
    }

    func album(_ id: String) async throws -> (album: Album, tracks: [Track]) {
        let data = try await get("/albums/\(id)")
        guard let album = Self.parseAlbum(data) else { throw ServiceError(message: "Spotify: альбом не найден") }
        var tracks = data["tracks"]["items"].items.compactMap { Self.parseTrack($0, album: data) }
        // длинные альбомы: остальные страницы треков
        var next = data["tracks"]["next"].string
        while let url = next {
            let page = try await get(url)
            tracks += page["items"].items.compactMap { Self.parseTrack($0, album: data) }
            next = page["next"].string
        }
        return (album, tracks)
    }
}

/// Общий кэш токена веб-плеера (как `Core.sp_token` в Rust): один на ключ `sp_dc`.
actor SpotifyTokens {
    private var cached: Spotify.WebToken?

    func token(renew: Bool, fetch: @Sendable () async throws -> Spotify.WebToken) async throws -> String {
        if !renew, let cached, cached.isFresh(atMs: Spotify.nowMs) { return cached.accessToken }
        let fresh = try await fetch()
        cached = fresh
        return fresh.accessToken
    }

    func clear() {
        cached = nil
    }
}
