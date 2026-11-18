import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto // тесты логики на Linux (swift-crypto, тот же API)
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cookie входа в music.youtube.com. Секрет: живёт только в Keychain, в описание не печатается.
struct YouTubeCreds: Codable, Sendable, CustomStringConvertible {
    var cookie: String

    var description: String { "YouTubeCreds(cookie: <скрыт>)" }
}

/// Вход YouTube Music по cookie браузера (как `auth.rs`): из cookie берём `SAPISID` (или
/// `__Secure-3PAPISID`) и подписываем каждый запрос `Authorization: SAPISIDHASH <ts>_<sha1>` —
/// так делает сам music.youtube.com.
enum YouTubeAuth {
    /// Адрес сайта, с которого «пришёл» запрос, — часть подписи.
    static let origin = "https://music.youtube.com"
    /// Cookie, по которым видно, что вход выполнен (любая годится для подписи).
    static let sapisidNames = ["SAPISID", "__Secure-3PAPISID"]

    /// Значение cookie `name` из строки вида `a=1; b=2`.
    static func cookieValue(_ cookie: String, _ name: String) -> String? {
        for part in cookie.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            guard trimmed[..<eq].trimmingCharacters(in: .whitespaces) == name else { continue }
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    static func sapisid(_ cookie: String) -> String? {
        sapisidNames.lazy.compactMap { cookieValue(cookie, $0) }.first
    }

    /// `SAPISIDHASH <ts>_<sha1(ts + " " + SAPISID + " " + origin)>`.
    static func sapisidHash(_ sapisid: String, timestamp: Int) -> String {
        let digest = Insecure.SHA1.hash(data: Data("\(timestamp) \(sapisid) \(origin)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(timestamp)_\(hex)"
    }

    /// Вставленный cookie → одна строка `a=1; b=2`. Принимает заголовок целиком (`Cookie: …`),
    /// переносы строк и лишние `;`. Без `SAPISID` — понятная ошибка (сам cookie в текст не попадает).
    static func normalize(_ raw: String) throws -> String {
        var body = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        for prefix in ["Cookie:", "cookie:"] where body.hasPrefix(prefix) {
            body = body.dropFirst(prefix.count)
            break
        }
        let parts = body.split(omittingEmptySubsequences: true) { $0 == ";" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("=") && !$0.hasPrefix("=") }
        let cookie = parts.joined(separator: "; ")
        guard !cookie.isEmpty else { throw ServiceError(message: "Вставь cookie YouTube Music") }
        guard sapisid(cookie) != nil else {
            throw ServiceError(message: "В cookie нет SAPISID — войди на music.youtube.com и скопируй cookie заново")
        }
        return cookie
    }

    /// Страница входа Google, после которой браузер возвращается на music.youtube.com (как на ПК, `login.rs`).
    static let loginURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F")!
    /// Хост, на котором вход считается завершённым.
    static let musicHost = "music.youtube.com"

    /// Cookie окна входа (имя, значение) → строка `a=1; b=2` — порт `yt_cookie_header` из `login.rs`.
    /// Пустые имена и значения выкидываются; без `SAPISID` / `__Secure-3PAPISID` вход ещё не завершён — nil.
    static func cookieHeader(_ pairs: [(String, String)]) -> String? {
        let header = pairs
            .filter { !$0.0.isEmpty && !$0.1.isEmpty }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "; ")
        return sapisid(header) == nil ? nil : header
    }
}

/// YouTube Music через InnerTube — порт `windows/src-tauri/src/providers/youtube/mod.rs`. Каталог,
/// похожие и поток работают гостем; «Лайки» и плейлисты библиотеки — с cookie. Поток берётся клиентом
/// VISIONOS (без подписи cookie), формат — только AAC: AVPlayer не играет Opus в WebM.
struct YouTube: Sendable {
    static let api = "https://music.youtube.com/youtubei/v1"
    static let player = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
    static let remixVersion = "1.20251110.01.00"
    static let visionVersion = "0.1"
    static let visionClientID = "101"
    static let visionAgent = "Mozilla/5.0 (iPad; CPU OS 16_7_10 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"
    /// Фильтры поиска WEB_REMIX: песни, исполнители, альбомы, плейлисты.
    static let searchSongs = "EgWKAQIIAWoKEAkQBRAKEAMQBA=="
    static let searchArtists = "EgWKAQIgAWoKEAkQChAFEAMQBA=="
    static let searchAlbums = "EgWKAQIYAWoKEAkQChAFEAMQBA=="
    static let searchPlaylists = "EgeKAQQoAEABagoQAxAEEAoQCRAF"
    /// Страниц продолжения плейлиста за один раз (по ~100 треков).
    static let maxPages = 30
    static let likesTitle = "Лайки YouTube Music"
    static let likesID = "likes"
    private static let hl = "ru"
    private static let gl = "LV"
    private static let name = "YouTube Music"

    /// Без cookie работают поиск, страницы и поток; библиотеке нужен вход.
    var creds: YouTubeCreds?
    var session: URLSession = .shared

    static var remixContext: JSONValue {
        .object(["client": .object([
            "clientName": .string("WEB_REMIX"), "clientVersion": .string(remixVersion), "hl": .string(hl), "gl": .string(gl),
        ])])
    }

    /// Тело запроса `player` клиентом VISIONOS.
    static func playerBody(videoID: String, visitor: String) -> JSONValue {
        .object([
            "context": .object(["client": .object([
                "clientName": .string("VISIONOS"), "clientVersion": .string(visionVersion), "deviceMake": .string("Apple"),
                "deviceModel": .string("RealityDevice14,1"), "osName": .string("visionOS"), "osVersion": .string("1.3.21O771"),
                "hl": .string(hl), "gl": .string(gl), "visitorData": .string(visitor),
            ])]),
            "videoId": .string(videoID),
            "contentCheckOk": .bool(true),
            "racyCheckOk": .bool(true),
        ])
    }

    private static func jsonRequest(_ url: String, body: JSONValue) throws -> URLRequest {
        guard let target = URL(string: url) else { throw ServiceError(message: "Неверный адрес: \(url)") }
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// `visitorData` гостя — без неё `player` чаще отвечает «подтверди, что ты не бот».
    static func visitorData(session: URLSession = .shared) async throws -> String {
        var request = try jsonRequest("\(api)/browse?prettyPrint=false", body: .object(["context": remixContext, "browseId": .string("FEmusic_home")]))
        request.setValue(HTTP.browserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(YouTubeAuth.origin, forHTTPHeaderField: "Origin")
        let json = try JSONValue(data: await HTTP.data(request, service: name, session: session))
        guard let visitor = json["responseContext"]["visitorData"].string, !visitor.isEmpty else {
            throw ServiceError(message: "YouTube Music: не выдал visitorData")
        }
        return visitor
    }

    /// Запрос к InnerTube сайта; с cookie — подписанный.
    private func post(_ endpoint: String, _ fields: [String: JSONValue]) async throws -> JSONValue {
        var body = fields
        body["context"] = Self.remixContext
        var request = try Self.jsonRequest("\(Self.api)/\(endpoint)?prettyPrint=false", body: .object(body))
        request.setValue(HTTP.browserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(YouTubeAuth.origin, forHTTPHeaderField: "Origin")
        request.setValue("\(YouTubeAuth.origin)/", forHTTPHeaderField: "Referer")
        if let creds {
            guard let sapisid = YouTubeAuth.sapisid(creds.cookie) else {
                throw ServiceError(message: "YouTube Music: в cookie нет SAPISID — войди заново")
            }
            request.httpShouldHandleCookies = false
            request.setValue(creds.cookie, forHTTPHeaderField: "Cookie")
            request.setValue(YouTubeAuth.sapisidHash(sapisid, timestamp: Int(Date().timeIntervalSince1970)), forHTTPHeaderField: "Authorization")
            request.setValue(YouTubeAuth.origin, forHTTPHeaderField: "X-Origin")
            request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        }
        return try JSONValue(data: await HTTP.data(request, service: Self.name, session: session))
    }

    private func searchRaw(_ query: String, _ params: String) async throws -> JSONValue {
        try await post("search", ["query": .string(query), "params": .string(params)])
    }

    func search(_ query: String, limit: Int) async throws -> [Track] {
        Array(YTParse.searchTracks(try await searchRaw(query, Self.searchSongs)).prefix(limit))
    }

    /// Исполнители, альбомы и плейлисты для вкладок поиска (три запроса разом).
    func searchMore(_ query: String, limit: Int) async throws -> (artists: [Artist], albums: [Album], playlists: [ServicePlaylist]) {
        async let artists = searchRaw(query, Self.searchArtists)
        async let albums = searchRaw(query, Self.searchAlbums)
        async let lists = searchRaw(query, Self.searchPlaylists)
        return (
            Array(YTParse.searchArtists(try await artists).prefix(limit)),
            Array(YTParse.searchAlbums(try await albums).prefix(limit)),
            Array(YTParse.searchPlaylists(try await lists).prefix(limit))
        )
    }

    func artist(_ channelID: String) async throws -> YTParse.ArtistPage {
        try YTParse.artistPage(await post("browse", ["browseId": .string(channelID)]), channelID: channelID)
    }

    func album(_ browseID: String) async throws -> (album: Album, tracks: [Track]) {
        try YTParse.albumPage(await post("browse", ["browseId": .string(browseID)]), browseID: browseID)
    }

    /// Плейлист (`listID` без `VL`; `likes` — «Понравившиеся», нужен вход) до `max` треков.
    func playlist(_ listID: String, max: Int) async throws -> (playlist: ServicePlaylist, tracks: [Track]) {
        let browse = listID == Self.likesID ? YTParse.likesBrowseID : "VL\(listID)"
        var (playlist, tracks, token) = try YTParse.playlistPage(await post("browse", ["browseId": .string(browse)]), listID: listID)
        var pages = 0
        while let next = token, tracks.count < max, pages < Self.maxPages {
            let page = YTParse.continuationPage(try await post("browse", ["continuation": .string(next)]))
            if page.tracks.isEmpty { break }
            tracks += page.tracks
            token = page.next
            pages += 1
        }
        tracks = Array(tracks.prefix(max))
        if listID == Self.likesID {
            playlist.title = Self.likesTitle
            playlist.trackCount = Swift.max(playlist.trackCount, tracks.count)
        }
        if playlist.trackCount == 0 { playlist.trackCount = tracks.count }
        return (playlist, tracks)
    }

    /// Очередь «радио» по треку (`RDAMVM<id>`) — похожие треки.
    func similar(_ videoID: String) async throws -> [Track] {
        let body: [String: JSONValue] = [
            "videoId": .string(videoID),
            "playlistId": .string("RDAMVM\(videoID)"),
            "isAudioOnly": .bool(true),
            "enablePersistentPlaylistPanel": .bool(true),
            "tunerSettingValue": .string("AUTOMIX_SETTING_NORMAL"),
        ]
        return YTParse.nextTracks(try await post("next", body), seed: videoID)
    }

    /// Плейлисты библиотеки (нужен вход), без «Понравившихся».
    func libraryPlaylists() async throws -> [ServicePlaylist] {
        YTParse.libraryPlaylists(try await post("browse", ["browseId": .string("FEmusic_liked_playlists")]))
    }

    /// Аккаунт по cookie: имя, аватар, YouTube Premium.
    func account() async throws -> ServiceAccount {
        guard creds != nil else { throw ServiceError(message: "YouTube Music не подключён") }
        return try YTParse.account(await post("account/account_menu", [:]))
    }

    /// Ответ `player` клиентом VISIONOS (гостем: подпись cookie этот клиент не принимает).
    func player(_ videoID: String, visitor: String) async throws -> JSONValue {
        var request = try Self.jsonRequest(Self.player, body: Self.playerBody(videoID: videoID, visitor: visitor))
        request.setValue(Self.visionAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.visionClientID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(Self.visionVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
        return try JSONValue(data: await HTTP.data(request, service: Self.name, session: session))
    }

    /// Ссылка на аудио: «Высокое» — AAC 256, если есть, иначе 128; «Обычное» — AAC 128.
    func stream(_ videoID: String, visitor: String, high: Bool) async throws -> StreamSource {
        let formats = try YTParse.playerFormats(await player(videoID, visitor: visitor))
        guard let format = YTParse.pickFormat(formats, high: high), let url = URL(string: format.url) else {
            throw ServiceError(message: "YouTube Music: у трека нет аудио AAC")
        }
        return .file(url: url, quality: YTParse.qualityLabel(format))
    }
}
