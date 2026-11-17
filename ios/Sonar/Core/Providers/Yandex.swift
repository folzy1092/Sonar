import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto // тесты логики на Linux (swift-crypto, тот же API)
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Яндекс Музыка: поиск, трек, артист, альбом, плейлисты, лайки, похожие, ссылка на mp3 и FLAC.
/// Заголовки и подписи — как `windows/src-tauri/src/providers/yandex.rs` и `server/tools/check_ym.py`.
/// Запросы — с телефона, не чаще, чем просит пользователь; rotor не используем (банит из-за границы).
struct Yandex: Sendable {
    static let api = "https://api.music.yandex.net"
    /// Соль подписи ссылки на mp3 (как в yandex-music-api).
    static let salt = "XGRlBW9FXlekgbPrRHuSiA"
    /// Ключ подписи `get-file-info` (как в yandex-music-api).
    static let signKey = Data("p93jhgh689SBReK6ghtw62".utf8)
    /// «Без потерь» в настройке качества: FLAC, от 1411 кбит/с.
    static let losslessKbps = 1411

    var token: String
    var session: URLSession = .shared

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("YandexMusicAndroid/24023621", forHTTPHeaderField: "X-Yandex-Music-Client")
        request.setValue("Yandex-Music-API", forHTTPHeaderField: "User-Agent")
        request.setValue("ru", forHTTPHeaderField: "Accept-Language")
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func get(_ path: String, _ query: [(String, String)] = []) async throws -> JSONValue {
        let url = try HTTP.url(path.hasPrefix("http") ? path : Self.api + path, query: query)
        return try JSONValue(data: await HTTP.data(request(url), service: "Яндекс Музыка", session: session))["result"]
    }

    private func post(_ path: String, form: [(String, String)]) async throws -> JSONValue {
        var request = request(try HTTP.url(Self.api + path, query: []))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.form(form)
        return try JSONValue(data: await HTTP.data(request, service: "Яндекс Музыка", session: session))["result"]
    }

    func account() async throws -> ServiceAccount {
        let account = try await get("/account/status")["account"]
        guard let uid = account["uid"].idString else { throw ServiceError(message: "Яндекс Музыка: токен не подошёл") }
        return ServiceAccount(name: account["displayName"].string ?? account["login"].string, avatarURL: nil, uid: uid)
    }

    func search(_ query: String, limit: Int) async throws -> [Track] {
        let data = try await get("/search", [("text", query), ("type", "track"), ("page", "0"), ("nocorrect", "false")])
        return Array(data["tracks"]["results"].items.compactMap(Self.parseTrack).prefix(limit))
    }

    /// Исполнители, альбомы и плейлисты для вкладок поиска (один запрос `type=all`).
    func searchMore(_ query: String, limit: Int) async throws -> (artists: [Artist], albums: [Album], playlists: [ServicePlaylist]) {
        let data = try await get("/search", [("text", query), ("type", "all"), ("page", "0"), ("nocorrect", "false")])
        return (
            Array(data["artists"]["results"].items.compactMap(Self.parseArtist).prefix(limit)),
            Array(data["albums"]["results"].items.compactMap(Self.parseAlbum).prefix(limit)),
            Array(data["playlists"]["results"].items.compactMap(Self.parsePlaylist).prefix(limit))
        )
    }

    /// Артист: шапка, популярные треки, альбомы (`brief-info`).
    func artist(_ id: String) async throws -> (artist: Artist, top: [Track], albums: [Album]) {
        let data = try await get("/artists/\(id)/brief-info")
        guard let artist = Self.parseArtist(data["artist"]) else { throw ServiceError(message: "Яндекс Музыка: артист не найден") }
        return (artist, data["popularTracks"].items.compactMap(Self.parseTrack), data["albums"].items.compactMap(Self.parseAlbum))
    }

    func album(_ id: String) async throws -> (album: Album, tracks: [Track]) {
        let data = try await get("/albums/\(id)/with-tracks")
        guard let album = Self.parseAlbum(data) else { throw ServiceError(message: "Яндекс Музыка: альбом не найден") }
        return (album, data["volumes"].items.flatMap(\.items).compactMap(Self.parseTrack))
    }

    func userPlaylists(_ uid: String) async throws -> [ServicePlaylist] {
        try await get("/users/\(uid)/playlists/list").items.compactMap(Self.parsePlaylist)
    }

    /// Плейлист целиком: шапка и треки; пришли без данных — дозапрашиваем по id.
    func playlist(uid: String, kind: String) async throws -> (head: ServicePlaylist, tracks: [Track]) {
        let data = try await get("/users/\(uid)/playlists/\(kind)", [("rich-tracks", "true")])
        guard let head = Self.parsePlaylist(data) else { throw ServiceError(message: "Яндекс Музыка: плейлист не найден") }
        let items = data["tracks"].items
        if items.allSatisfy({ $0["track"].isObject }) {
            return (head, items.compactMap { Self.parseTrack($0["track"]) })
        }
        return (head, try await tracks(items.compactMap { $0["id"].idString }))
    }

    /// Лайки в Яндексе (до max, новые первыми).
    func likes(uid: String, max: Int) async throws -> [Track] {
        let ids = try await get("/users/\(uid)/likes/tracks")["library"]["tracks"].items.compactMap { item -> String? in
            guard let id = item["id"].idString else { return nil }
            return item["albumId"].idString.map { "\(id):\($0)" } ?? id
        }
        return try await tracks(Array(ids.prefix(max)))
    }

    /// Похожие треки (`/tracks/{id}/similar`) — кандидаты своей волны.
    func similar(_ id: String) async throws -> [Track] {
        try await get("/tracks/\(id)/similar")["similarTracks"].items.compactMap(Self.parseTrack)
    }

    /// Треки по id (`POST /tracks`, порциями по 100), в том же порядке.
    func tracks(_ ids: [String]) async throws -> [Track] {
        var out: [Track] = []
        for start in stride(from: 0, to: ids.count, by: 100) {
            let chunk = ids[start ..< min(start + 100, ids.count)].joined(separator: ",")
            out.append(contentsOf: try await post("/tracks", form: [("track-ids", chunk)]).items.compactMap(Self.parseTrack))
        }
        return out
    }

    /// Новинки (`landing3/new-releases` → альбомы по id) — запасной вариант «Релизов».
    func newReleases(limit: Int) async throws -> [Album] {
        let ids = try await get("/landing3/new-releases")["newReleases"].items.compactMap(\.idString).prefix(limit)
        guard !ids.isEmpty else { return [] }
        return try await post("/albums", form: [("album-ids", ids.joined(separator: ","))]).items.compactMap(Self.parseAlbum)
    }

    // MARK: - Поток

    /// Без потерь: `get-file-info` с `quality=lossless` → FLAC без шифрования (`transports=raw`).
    /// На iPhone — только FLAC в MP4 (`flac-mp4`): голый `flac` по сети AVPlayer не открывает («Не удается
    /// открыть»). Нет FLAC в MP4 (нет Плюса, трек не в lossless) — nil, дальше обычный mp3.
    func losslessURL(_ id: String) async throws -> URL? {
        let ts = String(Int(Date().timeIntervalSince1970))
        let codecs = "flac-mp4,aac,he-aac,mp3"
        let transports = "raw"
        let sign = Self.fileInfoSign(ts: ts, id: id, quality: "lossless", codecs: codecs, transports: transports)
        let info = try await get("/get-file-info", [("ts", ts), ("trackId", id), ("quality", "lossless"), ("codecs", codecs),
                                                    ("transports", transports), ("sign", sign)])["downloadInfo"]
        let codec = info["codec"].string ?? ""
        guard codec == "flac-mp4", info["transport"].string != "encraw",
              let url = (info["url"].string ?? info["urls"][0].string).flatMap(URL.init(string:)) else { return nil }
        return url
    }

    /// download-info → лучший mp3 не выше maxKbps → XML → подписанная ссылка на CDN. maxKbps ≥ 1411 —
    /// сначала FLAC.
    func stream(_ id: String, maxKbps: Int) async throws -> StreamSource {
        if maxKbps >= Self.losslessKbps, let url = try? await losslessURL(id) {
            return .file(url: url, quality: "FLAC")
        }
        let infos = try await get("/tracks/\(id)/download-info")
        guard let info = Self.pickMP3(infos, maxKbps: maxKbps) else { throw ServiceError(message: "Яндекс Музыка: нет mp3 для этого трека") }
        guard let xmlURL = info["downloadInfoUrl"].string.flatMap(URL.init(string:)) else {
            throw ServiceError(message: "Яндекс Музыка: нет downloadInfoUrl")
        }
        let xml = String(decoding: try await HTTP.data(request(xmlURL), service: "Яндекс Музыка", session: session), as: UTF8.self)
        guard let link = Self.signedLink(xml).flatMap(URL.init(string:)) else {
            throw ServiceError(message: "Яндекс Музыка: не разобрал ссылку на файл")
        }
        return .file(url: link, quality: "MP3 \(info["bitrateInKbps"].int ?? 0)")
    }

    // MARK: - Подписи и разбор

    /// base64(HMAC-SHA256(ts + trackId + quality + codecs без запятых + transports)) без последнего символа.
    static func fileInfoSign(ts: String, id: String, quality: String, codecs: String, transports: String) -> String {
        let message = ts + id + quality + codecs.replacingOccurrences(of: ",", with: "") + transports
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: signKey))
        return String(Data(mac).base64EncodedString().dropLast())
    }

    static func pickMP3(_ infos: JSONValue, maxKbps: Int) -> JSONValue? {
        let mp3 = infos.items.filter { $0["codec"].string == "mp3" }
        let kbps = { (info: JSONValue) in info["bitrateInKbps"].int ?? 0 }
        return mp3.filter { kbps($0) <= maxKbps }.max { kbps($0) < kbps($1) } ?? mp3.min { kbps($0) < kbps($1) }
    }

    private static func tag(_ xml: String, _ name: String) -> String? {
        guard let open = xml.range(of: "<\(name)>"), let close = xml.range(of: "</\(name)>", range: open.upperBound ..< xml.endIndex) else {
            return nil
        }
        return String(xml[open.upperBound ..< close.lowerBound])
    }

    /// `https://{host}/get-mp3/{md5(SALT + path[1:] + s)}/{ts}{path}`.
    static func signedLink(_ xml: String) -> String? {
        guard let host = tag(xml, "host"), let path = tag(xml, "path"), let ts = tag(xml, "ts"), let s = tag(xml, "s"),
              !path.isEmpty else { return nil }
        let digest = Insecure.MD5.hash(data: Data((salt + String(path.dropFirst()) + s).utf8))
        let sign = digest.map { String(format: "%02x", $0) }.joined()
        return "https://\(host)/get-mp3/\(sign)/\(ts)\(path)"
    }

    /// `avatars.yandex.net/…/%%` → `https://avatars.yandex.net/…/400x400`.
    static func cover(_ uri: String) -> String {
        "https://" + uri.replacingOccurrences(of: "%%", with: "400x400")
    }

    private static func artistRefs(_ json: JSONValue) -> [ArtistRef] {
        json.items.compactMap { item in
            guard let id = item["id"].idString, let name = item["name"].string else { return nil }
            return ArtistRef(ref: "yma:\(id)", name: name, avatarURL: item["cover"]["uri"].string.map(cover))
        }
    }

    static func parseArtist(_ json: JSONValue) -> Artist? {
        guard let id = json["id"].idString, let name = json["name"].string else { return nil }
        return Artist(ref: "yma:\(id)", name: name, avatarURL: (json["cover"]["uri"].string ?? json["ogImage"].string).map(cover),
                      followers: json["likesCount"].int, url: "https://music.yandex.ru/artist/\(id)")
    }

    static func parseAlbum(_ json: JSONValue) -> Album? {
        guard let id = json["id"].idString, let title = json["title"].string else { return nil }
        let artists = artistRefs(json["artists"])
        return Album(
            ref: "ymalb:\(id)",
            title: title,
            artist: artists.map(\.name).joined(separator: ", "),
            artists: artists,
            coverURL: (json["coverUri"].string ?? json["ogImage"].string).map(cover),
            year: json["year"].int,
            released: json["releaseDate"].string.flatMap { $0.count >= 10 ? String($0.prefix(10)) : nil },
            trackCount: json["trackCount"].int ?? 0,
            url: "https://music.yandex.ru/album/\(id)"
        )
    }

    static func parsePlaylist(_ json: JSONValue) -> ServicePlaylist? {
        guard let uid = json["uid"].idString ?? json["owner"]["uid"].idString, let kind = json["kind"].idString,
              let title = json["title"].string else { return nil }
        let picture = json["cover"]["uri"].string ?? json["cover"]["itemsUri"][0].string ?? json["ogImage"].string
        return ServicePlaylist(ref: "ympl:\(uid):\(kind)", title: title,
                               owner: json["owner"]["name"].string ?? json["owner"]["login"].string ?? "",
                               coverURL: picture.map(cover), trackCount: json["trackCount"].int ?? 0)
    }

    static func parseTrack(_ json: JSONValue) -> Track? {
        guard let id = json["id"].idString, var title = json["title"].string else { return nil }
        if let version = json["version"].string, !version.isEmpty { title += " (\(version))" }
        let artists = artistRefs(json["artists"])
        let album = json["albums"][0]
        let albumId = album["id"].idString
        return Track(
            ref: "ym:\(id)",
            title: title,
            artist: artists.map(\.name).joined(separator: ", "),
            artists: artists,
            album: albumId.map { AlbumRef(ref: "ymalb:\($0)", title: album["title"].string ?? "") },
            durationMs: json["durationMs"].int ?? 0,
            coverURL: (json["coverUri"].string ?? album["coverUri"].string).map(cover),
            url: albumId.map { "https://music.yandex.ru/album/\($0)/track/\(id)" } ?? "https://music.yandex.ru/track/\(id)",
            explicit: json["contentWarning"].string == "explicit",
            available: json["available"].bool ?? true,
            plays: nil,
            tags: album["genre"].string.flatMap { $0.isEmpty ? nil : $0.lowercased() },
            loudness: json["r128"]["i"].number
        )
    }
}
