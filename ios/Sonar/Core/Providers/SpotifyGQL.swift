import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Внутренний GraphQL веб-плеера Spotify («Pathfinder») — порт `windows/src-tauri/src/providers/spotify_gql.rs`,
/// менять в обоих местах. С декабря 2025 открытый Web API на токен веб-плеера отвечает 429 на всё подряд, а сам
/// веб-плеер ходит сюда. Запросы «сохранённые»: имя операции + sha256. Хэши вшиты (проверены 2026-11-24);
/// устаревший сервер отвергает HTTP 412 — тогда `SpotifyHashes.refresh` вынимает свежие из скрипта веб-плеера.
enum SpotifyGQL {
    static let endpoint = URL(string: "https://api-partner.spotify.com/pathfinder/v2/query")!
    static let webPlayer = URL(string: "https://open.spotify.com/")!
    /// Строк на страницу.
    static let page = 50

    enum Op: String, CaseIterable, Sendable {
        case profile = "profileAttributes"
        case account = "accountAttributes"
        case searchTracks
        case searchDesktop
        case libraryTracks = "fetchLibraryTracks"
        case libraryV3
        case playlist = "fetchPlaylist"
        case artistOverview = "queryArtistOverview"
        case discography = "queryArtistDiscographyAll"
        case album = "getAlbum"

        /// Вшитый хэш — из `web-player.e2037ec6.js` и его кусков, проверен 2026-11-24 (как `builtin` в Rust).
        var builtin: String {
            switch self {
            case .profile: "08ffb4730af3746e04a8301396f20875dbbce10c75243803091a9274eacc8ac0"
            case .account: "be4ce359daee01463ddb8e77536220e108e3d28105e12199f244d7a5954e9d14"
            case .searchTracks: "b02683192a98dde7966b5e6655a79eeb62713eab703eda9902c932818dd52751"
            case .searchDesktop: "eef7cc54888d91bdd6802623477873caa3948ae173a0c34fd86827b267e94c03"
            case .libraryTracks: "087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240"
            case .libraryV3: "390c78e5b951029bad359785e69b07b536a509c581cbcd0aded5e5067f187455"
            case .playlist: "21ea11a6ac75a5f3e01fd365d29c18e0a4a8b7dc09f89bbb5d73910190c6acaf"
            case .artistOverview: "eafb1620d783ece118e72fbfede2b0064483e029d3c1aafafa1c2de0e25a89e7"
            case .discography: "5e07d323febb57b4a56a42abbf781490e58764aa45feb6e3dc0591564fc56599"
            case .album: "0b6ce3511e1b02e4a40fa95440f992acbe85080eb308af9194322d708fc1914f"
            }
        }

        /// Ленивый кусок веб-плеера, где лежит операция.
        var chunk: String? {
            switch self {
            case .searchTracks, .searchDesktop: "xpui-routes-search"
            case .discography: "xpui-routes-artist"
            default: nil
            }
        }
    }

    /// Тело POST-запроса.
    static func body(_ op: Op, hash: String, variables: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "variables": variables,
            "operationName": op.rawValue,
            "extensions": ["persistedQuery": ["version": 1, "sha256Hash": hash]],
        ] as [String: Any])
    }

    // MARK: - Хэши из скрипта веб-плеера

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // шаблоны постоянные — сломаться может только при правке кода, тест это ловит
        try! NSRegularExpression(pattern: pattern) // swiftlint:disable:this force_try
    }

    private static let scriptRE = regex(#"https://open\.spotifycdn\.com/cdn/build/web-player/[A-Za-z0-9_~.\-]+\.js"#)
    private static let opRE = regex(#""([A-Za-z0-9_]+)",\s*"(?:query|mutation)",\s*"([0-9a-f]{64})""#)
    private static let chunkRE = regex(#"\(\{([^}]*)\}\)\[e\]\|\|e\)\+"\."\+\(\{([^}]*)\}\)\[e\]\+"\.js""#)
    private static let pairRE = regex(#"(\d+):"([^"]+)""#)

    private static func groups(_ re: NSRegularExpression, _ text: String) -> [[String]] {
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0 ..< m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }

    /// Адреса скриптов веб-плеера на странице (без повторов, по порядку).
    static func scriptURLs(_ html: String) -> [String] {
        var out: [String] = []
        for g in groups(scriptRE, html) where !out.contains(g[0]) { out.append(g[0]) }
        return out
    }

    /// Пары «операция → хэш» из скрипта.
    static func scan(_ js: String) -> [String: String] {
        var out: [String: String] = [:]
        for g in groups(opRE, js) { out[g[1]] = g[2] }
        return out
    }

    /// Адрес ленивого куска `name` по карте webpack в основном скрипте.
    static func chunkURL(mainURL: String, mainJS: String, name: String) -> String? {
        guard let caps = groups(chunkRE, mainJS).first, let slash = mainURL.lastIndex(of: "/") else { return nil }
        func pairs(_ s: String) -> [String: String] {
            Dictionary(groups(pairRE, s).map { ($0[1], $0[2]) }, uniquingKeysWith: { a, _ in a })
        }
        guard let id = pairs(caps[1]).first(where: { $0.value == name })?.key, let hash = pairs(caps[2])[id] else { return nil }
        return "\(mainURL[...slash])\(name).\(hash).js"
    }

    // MARK: - Разбор ответов

    /// `spotify:track:ID` → `ID` (только нужного вида).
    static func id(_ uri: String?, _ kind: String) -> String? {
        guard let uri, uri.hasPrefix("spotify:\(kind):") else { return nil }
        let rest = String(uri.dropFirst("spotify:\(kind):".count))
        return rest.isEmpty ? nil : rest
    }

    private static func webURL(_ kind: String, _ id: String) -> String {
        "https://open.spotify.com/\(kind)/\(id)"
    }

    /// Самая крупная картинка; без размеров — последняя (Spotify кладёт 640 в конец).
    static func bestSource(_ sources: JSONValue) -> String? {
        let candidates = sources.items.enumerated().compactMap { index, s -> (Int, Int, String)? in
            s["url"].string.map { (s["width"].int ?? 0, index, $0) }
        }
        return candidates.max { ($0.0, $0.1) < ($1.0, $1.1) }?.2
    }

    private static func artistRefs(_ v: JSONValue) -> [ArtistRef] {
        v["artists"]["items"].items.compactMap { a in
            guard let id = Self.id(a["uri"].string, "artist"), let name = a["profile"]["name"].string else { return nil }
            return ArtistRef(ref: "spa:\(id)", name: name)
        }
    }

    private static func joined(_ artists: [ArtistRef]) -> String {
        artists.map(\.name).joined(separator: ", ")
    }

    private static func isType(_ v: JSONValue, _ name: String) -> Bool {
        v["__typename"].string.map { $0 == name } ?? true
    }

    /// Альбом снаружи — у треков альбома своего `albumOfTrack` нет.
    struct AlbumCtx: Sendable {
        var album: AlbumRef?
        var cover: String?

        init(_ album: Album) {
            self.album = AlbumRef(ref: album.ref, title: album.title)
            cover = album.coverURL
        }
    }

    /// Трек из `Track`; не трек (эпизод, «не найдено») — nil.
    static func track(_ v: JSONValue, outer: AlbumCtx? = nil) -> Track? {
        guard isType(v, "Track"), let id = id(v["uri"].string, "track"), let title = v["name"].string else { return nil }
        let artists = artistRefs(v)
        let alb = v["albumOfTrack"]
        let own = Self.id(alb["uri"].string, "album").map { AlbumRef(ref: "spalb:\($0)", title: alb["name"].string ?? "") }
        let album = own ?? outer?.album
        let cover = own != nil ? bestSource(alb["coverArt"]["sources"]) : outer?.cover
        return Track(
            ref: "sp:\(id)", title: title, artist: joined(artists), artists: artists, album: album,
            durationMs: v["duration"]["totalMilliseconds"].int ?? 0, coverURL: cover, url: webURL("track", id),
            explicit: v["contentRating"]["label"].string == "EXPLICIT",
            // играет через резервный сервис — для очереди трек доступен
            available: true, plays: nil, tags: nil
        )
    }

    /// Год и полная дата из `date` (`year` или `isoString` с точностью `DAY`).
    private static func dates(_ v: JSONValue) -> (Int?, String?) {
        let iso = v["isoString"].string
        let year = v["year"].int ?? iso.flatMap { Int($0.prefix(4)) }
        let day = v["precision"].string == "DAY" ? iso.map { String($0.prefix(10)) } : nil
        return (year, day)
    }

    static func album(_ v: JSONValue) -> Album? {
        guard isType(v, "Album"), let id = id(v["uri"].string, "album"), let title = v["name"].string else { return nil }
        let artists = artistRefs(v)
        let (year, released) = dates(v["date"])
        return Album(
            ref: "spalb:\(id)", title: title, artist: joined(artists), artists: artists,
            coverURL: bestSource(v["coverArt"]["sources"]), year: year, released: released,
            trackCount: v["tracks"]["totalCount"].int ?? v["tracksV2"]["totalCount"].int ?? 0, url: webURL("album", id)
        )
    }

    static func artist(_ v: JSONValue) -> Artist? {
        guard isType(v, "Artist"), let id = id(v["uri"].string, "artist"), let name = v["profile"]["name"].string else { return nil }
        return Artist(ref: "spa:\(id)", name: name, avatarURL: bestSource(v["visuals"]["avatarImage"]["sources"]),
                      followers: v["stats"]["followers"].int, url: webURL("artist", id))
    }

    static func playlist(_ v: JSONValue) -> ServicePlaylist? {
        guard isType(v, "Playlist"), let id = id(v["uri"].string, "playlist"), let title = v["name"].string else { return nil }
        let owner = v["ownerV2"]["data"]
        return ServicePlaylist(ref: "sppl:\(id)", title: title, owner: owner["name"].string ?? owner["username"].string ?? "",
                               coverURL: v["images"]["items"].items.lazy.compactMap { bestSource($0["sources"]) }.first,
                               trackCount: v["content"]["totalCount"].int ?? 0)
    }

    /// Профиль + подписка (подписка не пришла — «не знаем»).
    static func account(profile: JSONValue, account: JSONValue?) -> ServiceAccount {
        let p = profile["me"]["profile"]
        return ServiceAccount(name: p["name"].string ?? p["username"].string, avatarURL: bestSource(p["avatar"]["sources"]),
                              uid: p["username"].string,
                              premium: account?["me"]["account"]["product"].string.map { $0.lowercased() == "premium" })
    }

    /// Страница: строки, сколько элементов было, всего.
    struct Page<T> {
        var rows: [T]
        var seen: Int
        var total: Int?
    }

    private static func page(_ v: JSONValue) -> ([JSONValue], Int?) {
        (v["items"].items, v["totalCount"].int)
    }

    static func searchTracks(_ data: JSONValue) -> [Track] {
        page(data["searchV2"]["tracksV2"]).0.compactMap { track($0["item"]["data"]) }
    }

    static func searchMore(_ data: JSONValue) -> (artists: [Artist], albums: [Album], playlists: [ServicePlaylist]) {
        let s = data["searchV2"]
        return (page(s["artists"]).0.compactMap { artist($0["data"]) },
                page(s["albumsV2"]).0.compactMap { album($0["data"]) },
                page(s["playlists"]).0.compactMap { playlist($0["data"]) })
    }

    static func libraryTracks(_ data: JSONValue) -> Page<Track> {
        let (items, total) = page(data["me"]["library"]["tracks"])
        return Page(rows: items.compactMap { track($0["track"]["data"]) }, seen: items.count, total: total)
    }

    static func libraryPlaylists(_ data: JSONValue) -> Page<ServicePlaylist> {
        let (items, total) = page(data["me"]["libraryV3"])
        let lists = items.filter { $0["item"]["__typename"].string == "PlaylistResponseWrapper" }.compactMap { playlist($0["item"]["data"]) }
        return Page(rows: lists, seen: items.count, total: total)
    }

    static func playlistPage(_ data: JSONValue) -> (head: ServicePlaylist?, page: Page<Track>) {
        let p = data["playlistV2"]
        let (items, total) = page(p["content"])
        return (playlist(p), Page(rows: items.compactMap { track($0["itemV2"]["data"]) }, seen: items.count, total: total))
    }

    static func artistOverview(_ data: JSONValue) -> (artist: Artist, top: [Track])? {
        let a = data["artistUnion"]
        guard let head = artist(a) else { return nil }
        return (head, page(a["discography"]["topTracks"]).0.compactMap { track($0["track"]) })
    }

    /// Дискография (`all`); сборники мимо (как раньше `include_groups=album,single`).
    static func discography(_ data: JSONValue, by: ArtistRef?) -> Page<Album> {
        let (groups, total) = page(data["artistUnion"]["discography"]["all"])
        let albums = groups.flatMap { page($0["releases"]).0 }
            .filter { $0["type"].string != "COMPILATION" }
            .compactMap { release -> Album? in
                guard var a = album(release) else { return nil }
                if a.artists.isEmpty, let by {
                    a.artists = [by]
                    a.artist = by.name
                }
                return a
            }
        return Page(rows: albums, seen: groups.count, total: total)
    }

    static func albumPage(_ data: JSONValue) -> (album: Album, page: Page<Track>)? {
        let u = data["albumUnion"]
        guard let head = album(u) else { return nil }
        let ctx = AlbumCtx(head)
        let (items, total) = page(u["tracksV2"])
        return (head, Page(rows: items.compactMap { track($0["track"], outer: ctx) }, seen: items.count, total: total))
    }

    /// Ответ → `data`; ошибки без данных — понятным текстом.
    static func data(_ v: JSONValue) throws -> JSONValue {
        let data = v["data"]
        if data.isObject { return data }
        if v["errors"][0]["message"].string?.contains("not authorized") == true { throw ServiceError(message: Spotify.spDcBad) }
        throw ServiceError(message: "Spotify: непонятный ответ веб-плеера")
    }
}

/// Текущие хэши операций (как `HASHES` в Rust): вшитые, пока веб-плеер не дал свежие.
actor SpotifyHashes {
    static let shared = SpotifyHashes()
    /// Перечитывать веб-плеер не чаще (скрипт ~5 МБ).
    static let rescanEvery: TimeInterval = 10 * 60

    private var map: [SpotifyGQL.Op: String] = Dictionary(uniqueKeysWithValues: SpotifyGQL.Op.allCases.map { ($0, $0.builtin) })
    private var scannedAt: Date?

    func hash(_ op: SpotifyGQL.Op) -> String {
        map[op] ?? op.builtin
    }

    /// Принять найденные хэши; true — что-то сменилось.
    @discardableResult
    func adopt(_ found: [String: String]) -> Bool {
        var changed = false
        for op in SpotifyGQL.Op.allCases {
            if let h = found[op.rawValue], map[op] != h {
                map[op] = h
                changed = true
            }
        }
        return changed
    }

    /// Скачать веб-плеер и вынуть свежие хэши (не чаще `rescanEvery`). true — хэш `op` сменился.
    func refresh(_ op: SpotifyGQL.Op, session: URLSession) async -> Bool {
        if let at = scannedAt, Date().timeIntervalSince(at) < Self.rescanEvery { return false }
        scannedAt = Date()
        let before = hash(op)
        guard let found = try? await Self.scanWebPlayer(session: session) else { return false }
        adopt(found)
        return hash(op) != before
    }

    private static func text(_ url: URL, session: URLSession) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(HTTP.browserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return String(decoding: data, as: UTF8.self)
    }

    private static func scanWebPlayer(session: URLSession) async throws -> [String: String] {
        let html = try await text(SpotifyGQL.webPlayer, session: session)
        var found: [String: String] = [:]
        var main: (url: String, js: String)?
        for raw in SpotifyGQL.scriptURLs(html) {
            guard let url = URL(string: raw) else { continue }
            let js = try await text(url, session: session)
            found.merge(SpotifyGQL.scan(js)) { _, new in new }
            if raw.contains("/web-player.") { main = (raw, js) }
        }
        guard let main else { return found }
        var chunks: [String] = []
        for op in SpotifyGQL.Op.allCases { if let c = op.chunk, !chunks.contains(c) { chunks.append(c) } }
        for name in chunks {
            guard let raw = SpotifyGQL.chunkURL(mainURL: main.url, mainJS: main.js, name: name), let url = URL(string: raw) else { continue }
            found.merge(SpotifyGQL.scan(try await text(url, session: session))) { _, new in new }
        }
        return found
    }
}
