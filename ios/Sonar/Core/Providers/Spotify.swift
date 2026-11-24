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

/// Spotify — порт `windows/src-tauri/src/providers/spotify.rs`: `sp_dc` → токен веб-плеера (TOTP) → внутренний
/// GraphQL веб-плеера (`SpotifyGQL`: поиск, «Любимые треки», плейлисты, исполнитель, альбом). Открытый Web API с
/// декабря 2025 отвечает на такой токен 429 на всё — им больше не пользуемся. Рекомендаций не берём. На iPhone Spotify не играет
/// (librespot — только ПК с Premium): трек `sp:` — «нужен резервный сервис» (резерв — этап 4).
/// `sp_dc` не попадает ни в ошибки, ни в лог.
struct Spotify: Sendable {
    static let tokenURL = "https://open.spotify.com/api/token"
    /// Страница входа: после входа accounts.spotify.com ведёт на open.spotify.com, там ставится `sp_dc`.
    static let loginURL = URL(string: "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F")!
    /// Предел страниц одного списка: сервер без `totalCount` не крутит вечно.
    static let maxPages = 60
    /// Треков в одном альбоме (сборники на сотни треков).
    static let albumMaxTracks = 2000
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
    static let gqlStale = "Spotify обновил веб-плеер — Sonar не смог подхватить новые запросы, попробуй позже"
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

    private func send(_ op: SpotifyGQL.Op, _ variables: [String: Any], token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: SpotifyGQL.endpoint)
        request.httpMethod = "POST"
        request.httpBody = try SpotifyGQL.body(op, hash: await SpotifyHashes.shared.hash(op), variables: variables)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ru", forHTTPHeaderField: "Accept-Language")
        request.setValue(HTTP.browserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Операция → `data`; 401 — повтор со свежим токеном, 412 «хэш устарел» — свежие хэши из веб-плеера и повтор.
    private func query(_ op: SpotifyGQL.Op, _ variables: [String: Any] = [:]) async throws -> JSONValue {
        var (data, status) = try await send(op, variables, token: token())
        if status == 401 {
            (data, status) = try await send(op, variables, token: token(renew: true))
        }
        if status == 412, await SpotifyHashes.shared.refresh(op, session: session) {
            (data, status) = try await send(op, variables, token: token())
        }
        if status == 412 { throw ServiceError(message: Self.gqlStale) }
        guard (200 ..< 300).contains(status) else { throw ServiceError.http("Spotify", status) }
        return try SpotifyGQL.data(try JSONValue(data: data))
    }

    /// Страницы по `offset`, пока не кончатся или не наберётся `max`.
    private func paged<T>(_ op: SpotifyGQL.Op, max: Int, vars: (Int) -> [String: Any],
                          parse: (JSONValue) -> SpotifyGQL.Page<T>) async throws -> [T] {
        var out: [T] = []
        var offset = 0
        for _ in 0 ..< Self.maxPages {
            let page = parse(try await query(op, vars(offset)))
            out += page.rows
            offset += page.seen
            if page.seen == 0 || out.count >= max || page.total.map({ offset >= $0 }) == true { break }
        }
        return Array(out.prefix(max))
    }

    // MARK: - Метаданные

    func account() async throws -> ServiceAccount {
        let profile = try await query(.profile)
        guard profile["me"]["profile"].isObject else { throw ServiceError(message: Self.spDcBad) }
        let account = try? await query(.account)
        return SpotifyGQL.account(profile: profile, account: account)
    }

    func search(_ query: String, limit: Int) async throws -> [Track] {
        let vars: [String: Any] = [
            "searchTerm": query, "offset": 0, "limit": min(max(limit, 1), SpotifyGQL.page), "numberOfTopResults": 5,
            "includeAudiobooks": false, "includePreReleases": false, "includeAuthors": false,
        ]
        return SpotifyGQL.searchTracks(try await self.query(.searchTracks, vars))
    }

    func searchMore(_ query: String, limit: Int) async throws -> (artists: [Artist], albums: [Album], playlists: [ServicePlaylist]) {
        let vars: [String: Any] = [
            "searchTerm": query, "offset": 0, "limit": min(max(limit, 1), SpotifyGQL.page), "numberOfTopResults": 5,
            "includeAudiobooks": false, "includeArtistHasConcertsField": false, "includePreReleases": false,
            "includeAlbumPreReleases": false, "includeAuthors": false, "includeEpisodeContentRatingsV2": false,
            "isPrefix": NSNull(), "sectionFilters": ["GENERIC"],
        ]
        return SpotifyGQL.searchMore(try await self.query(.searchDesktop, vars))
    }

    /// «Любимые треки» аккаунта.
    func likes(max: Int) async throws -> [Track] {
        try await paged(.libraryTracks, max: max, vars: { ["offset": $0, "limit": SpotifyGQL.page] }, parse: SpotifyGQL.libraryTracks)
    }

    /// Плейлисты библиотеки (папки раскрыты).
    func playlists() async throws -> [ServicePlaylist] {
        try await paged(.libraryV3, max: Self.maxPlaylists, vars: { offset in
            ["filters": ["Playlists"], "order": NSNull(), "textFilter": NSNull(), "features": [String](), "limit": SpotifyGQL.page,
             "offset": offset, "flatten": true, "expandedFolders": [String](), "folderUri": NSNull(), "includeFoldersWhenFlattening": false]
        }, parse: SpotifyGQL.libraryPlaylists)
    }

    func playlist(_ id: String, max: Int) async throws -> (head: ServicePlaylist, tracks: [Track]) {
        let uri = "spotify:playlist:\(id)"
        var head: ServicePlaylist?
        let tracks = try await paged(.playlist, max: max, vars: { offset in
            ["uri": uri, "offset": offset, "limit": SpotifyGQL.page, "enableWatchFeedEntrypoint": false, "includeEpisodeContentRatingsV2": false]
        }, parse: { (data: JSONValue) -> SpotifyGQL.Page<Track> in
            let (h, page) = SpotifyGQL.playlistPage(data)
            if head == nil { head = h }
            return page
        })
        guard var head else { throw ServiceError(message: "Spotify: плейлист не найден") }
        head.trackCount = Swift.max(head.trackCount, tracks.count)
        return (head, tracks)
    }

    /// Шапка, популярные и альбомы исполнителя.
    func artist(_ id: String) async throws -> (artist: Artist, top: [Track], albums: [Album]) {
        let vars: [String: Any] = ["uri": "spotify:artist:\(id)", "locale": "", "preReleaseV2": false, "includeMusicVideoPreviews": false]
        guard let overview = SpotifyGQL.artistOverview(try await query(.artistOverview, vars)) else {
            throw ServiceError(message: "Spotify: исполнитель не найден")
        }
        let albums = try await discography(id, by: ArtistRef(ref: overview.artist.ref, name: overview.artist.name))
        return (overview.artist, overview.top, albums)
    }

    func artistAlbums(_ id: String) async throws -> [Album] {
        try await discography(id, by: nil)
    }

    private func discography(_ id: String, by: ArtistRef?) async throws -> [Album] {
        let uri = "spotify:artist:\(id)"
        return try await paged(.discography, max: 200, vars: { ["uri": uri, "offset": $0, "limit": SpotifyGQL.page, "order": "DATE_DESC"] },
                               parse: { SpotifyGQL.discography($0, by: by) })
    }

    func album(_ id: String) async throws -> (album: Album, tracks: [Track]) {
        let uri = "spotify:album:\(id)"
        var head: Album?
        let tracks = try await paged(.album, max: Self.albumMaxTracks, vars: { ["uri": uri, "locale": "", "offset": $0, "limit": SpotifyGQL.page] },
                                     parse: { (data: JSONValue) -> SpotifyGQL.Page<Track> in
                                         guard let found = SpotifyGQL.albumPage(data) else { return .init(rows: [], seen: 0, total: nil) }
                                         if head == nil { head = found.album }
                                         return found.page
                                     })
        guard let head else { throw ServiceError(message: "Spotify: альбом не найден") }
        return (head, tracks)
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
