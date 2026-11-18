import Foundation

/// Разбор ответов InnerTube YouTube Music (клиент WEB_REMIX) в модели Sonar — порт
/// `windows/src-tauri/src/providers/youtube/parse.rs`. Только чистые функции: на вход JSON ответа,
/// на выход `Track` / `Album` / …; сеть — в `YouTube.swift`. Ответы глубоко вложены и меняют обёртки,
/// поэтому нужные «рендереры» ищем рекурсивно по имени ключа. Ключи объекта обходим по алфавиту —
/// как `serde_json` в Rust (BTreeMap), чтобы ПК и iPhone находили одно и то же.
enum YTParse {
    /// Сайт YouTube Music — для ссылок «Открыть в YouTube Music».
    static let web = "https://music.youtube.com"
    /// Сторона обложки, до которой растягиваем картинки Google (самая крупная в ответах).
    static let coverSide = 544
    /// «Понравившиеся» в browse — у нас это `ytpl:likes`.
    static let likesBrowseID = "VLLM"

    /// Разделитель колонок в строках: «Lil Peep • Альбом • 2:26».
    private static let dot = " • "
    private static let explicitBadge = "MUSIC_EXPLICIT_BADGE"
    private static let greyOut = "MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT"
    private static let pageArtist = "MUSIC_PAGE_TYPE_ARTIST"
    private static let pageChannel = "MUSIC_PAGE_TYPE_USER_CHANNEL"
    private static let pageAlbum = "MUSIC_PAGE_TYPE_ALBUM"
    private static let pagePlaylist = "MUSIC_PAGE_TYPE_PLAYLIST"
    /// Первая часть строки, которая говорит о типе, а не об исполнителе.
    private static let typeWords: Set<String> = ["Песня", "Song", "Видео", "Video", "Трек", "Пісня", "Відео", "Episode"]
    /// Слова, по которым часть строки — число треков.
    private static let countWords = ["трек", "track", "song", "песн", "пісн"]

    // MARK: ссылки

    static func trackURL(_ videoID: String) -> String { "\(web)/watch?v=\(videoID)" }
    static func artistURL(_ channelID: String) -> String { "\(web)/channel/\(channelID)" }
    static func albumURL(_ browseID: String) -> String { "\(web)/browse/\(browseID)" }

    // MARK: общие помощники

    /// Текст поля: `runs` склеиваются, иначе `simpleText` или `content`.
    static func text(_ v: JSONValue) -> String {
        if let runs = v["runs"].array { return runs.compactMap { $0["text"].string }.joined() }
        return v["simpleText"].string ?? v["content"].string ?? ""
    }

    private static func sortedPairs(_ object: [String: JSONValue]) -> [(String, JSONValue)] {
        object.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { ($0, object[$0] ?? .null) }
    }

    /// Все значения ключа на любой глубине, в порядке обхода.
    static func findAll(_ v: JSONValue, _ key: String) -> [JSONValue] {
        var out: [JSONValue] = []
        collect(v, key, into: &out)
        return out
    }

    private static func collect(_ v: JSONValue, _ key: String, into out: inout [JSONValue]) {
        switch v {
        case let .object(object):
            for (k, child) in sortedPairs(object) {
                if k == key { out.append(child) }
                collect(child, key, into: &out)
            }
        case let .array(array):
            for child in array { collect(child, key, into: &out) }
        default: break
        }
    }

    /// Ближайшее значение ключа: сначала на этом уровне, потом вглубь.
    static func findFirst(_ v: JSONValue, _ key: String) -> JSONValue? {
        switch v {
        case let .object(object):
            if let hit = object[key] { return hit }
            for (_, child) in sortedPairs(object) {
                if let hit = findFirst(child, key) { return hit }
            }
            return nil
        case let .array(array):
            for child in array {
                if let hit = findFirst(child, key) { return hit }
            }
            return nil
        default: return nil
        }
    }

    /// Самая крупная картинка из ближайшего `thumbnails`; картинки Google — до 544×544.
    static func bestThumb(_ v: JSONValue) -> String? {
        guard let list = findFirst(v, "thumbnails")?.array, !list.isEmpty else { return nil }
        var best = list[0]
        for thumb in list.dropFirst() where (thumb["width"].int ?? 0) >= (best["width"].int ?? 0) {
            best = thumb
        }
        guard let url = best["url"].string, !url.isEmpty else { return nil }
        return upscale(url)
    }

    /// `=w120-h120` → `=w544-h544`, `=s192` → `=s544` у картинок Google; превью `i.ytimg.com` — как есть.
    static func upscale(_ url: String) -> String {
        guard url.contains(".googleusercontent.com/") || url.contains(".ggpht.com/") else { return url }
        var out = url
        if let range = out.range(of: #"=w\d+-h\d+"#, options: .regularExpression) {
            out.replaceSubrange(range, with: "=w\(coverSide)-h\(coverSide)")
        }
        if let range = out.range(of: #"=s\d+"#, options: .regularExpression) {
            out.replaceSubrange(range, with: "=s\(coverSide)")
        }
        return out
    }

    /// «2:26» → 146 000 мс, «1:02:03» → 3 723 000 мс.
    static func parseDuration(_ s: String) -> Int? {
        let s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.contains(":") else { return nil }
        var total = 0
        for part in s.split(separator: ":", omittingEmptySubsequences: false) {
            guard let n = Int(part.trimmingCharacters(in: .whitespaces)), n >= 0 else { return nil }
            total = total * 60 + n
        }
        return total * 1000
    }

    /// «1.2K plays» → 1200, «61,5 млн» → 61 500 000, «500 треков» → 500.
    static func parseCount(_ raw: String) -> Int? {
        let s = raw.replacingOccurrences(of: "\u{a0}", with: " ")
        guard let start = s.firstIndex(where: \.isASCIIDigitChar) else { return nil }
        let rest = s[start...]
        let end = rest.firstIndex { !($0.isASCIIDigitChar || $0 == "." || $0 == ",") } ?? rest.endIndex
        let num = String(rest[..<end])
        let tail = rest[end...].drop { $0.isWhitespace }.lowercased()
        let mult: Double = if tail.hasPrefix("млрд") || tail.hasPrefix("b") {
            1e9
        } else if tail.hasPrefix("млн") || (tail.hasPrefix("m") && !tail.hasPrefix("min")) {
            1e6
        } else if tail.hasPrefix("тыс") || tail.hasPrefix("k") {
            1e3
        } else {
            1
        }
        let value: Double? = mult > 1
            ? Double(num.replacingOccurrences(of: ",", with: "."))
            : Int(num.filter { $0 != "," && $0 != "." }).map(Double.init)
        guard let value else { return nil }
        return Int((value * mult).rounded())
    }

    /// Последний год в строке («Сингл • 2015» → 2015).
    static func lastYear(_ s: String) -> Int? {
        s.split(whereSeparator: { !$0.isASCIIDigitChar })
            .filter { $0.count == 4 }
            .compactMap { Int($0) }
            .filter { (1900 ... 2100).contains($0) }
            .last
    }

    private static func pageType(_ run: JSONValue) -> String {
        run["navigationEndpoint"]["browseEndpoint"]["browseEndpointContextSupportedConfigs"]["browseEndpointContextMusicConfig"]["pageType"].string ?? ""
    }

    private static func browseID(_ run: JSONValue) -> String? {
        run["navigationEndpoint"]["browseEndpoint"]["browseId"].string.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Части строки между « • ».
    static func segments(_ runs: [JSONValue]) -> [[JSONValue]] {
        var out: [[JSONValue]] = [[]]
        for run in runs {
            if run["text"].string == dot { out.append([]) } else { out[out.count - 1].append(run) }
        }
        return out.filter { !$0.isEmpty }
    }

    static func segText(_ seg: [JSONValue]) -> String {
        seg.compactMap { $0["text"].string }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func flexRuns(_ item: JSONValue, _ col: Int) -> [JSONValue] {
        item["flexColumns"][col]["musicResponsiveListItemFlexColumnRenderer"]["text"]["runs"].items
    }

    private static func artistRef(_ run: JSONValue) -> ArtistRef? {
        guard let id = browseID(run), let name = run["text"].string else { return nil }
        return ArtistRef(ref: "yta:\(id)", name: name.trimmingCharacters(in: .whitespacesAndNewlines), avatarURL: nil)
    }

    private static func isArtistRun(_ run: JSONValue) -> Bool {
        let kind = pageType(run)
        return kind == pageArtist || kind == pageChannel
    }

    /// Исполнители из ссылок в строке (без повторов).
    private static func artistsIn(_ runs: [JSONValue]) -> [ArtistRef] {
        var out: [ArtistRef] = []
        for artist in runs.filter(isArtistRun).compactMap(artistRef) where !out.contains(where: { $0.ref == artist.ref }) {
            out.append(artist)
        }
        return out
    }

    private static func albumIn(_ runs: [JSONValue]) -> AlbumRef? {
        guard let run = runs.first(where: { pageType($0) == pageAlbum }), let id = browseID(run), let title = run["text"].string else { return nil }
        return AlbumRef(ref: "ytalb:\(id)", title: title)
    }

    private static func hasExplicit(_ v: JSONValue) -> Bool {
        findAll(v, "iconType").contains { $0.string == explicitBadge }
    }

    private static func names(_ artists: [ArtistRef]) -> String {
        artists.map(\.name).joined(separator: ", ")
    }

    /// Что подставить треку, если в строке этого нет (на странице альбома у треков пусто).
    struct Fallback {
        var artists: [ArtistRef] = []
        var album: AlbumRef?
        var cover: String?
    }

    // MARK: треки

    /// Строка списка (`musicResponsiveListItemRenderer`) → трек. Не трек (артист, альбом) — nil.
    static func track(item: JSONValue, fallback fb: Fallback = Fallback()) -> Track? {
        let col0 = flexRuns(item, 0)
        guard let videoID = item["playlistItemData"]["videoId"].string ?? col0.first?["navigationEndpoint"]["watchEndpoint"]["videoId"].string else { return nil }
        let title = col0.compactMap { $0["text"].string }.joined()
        let columns = item["flexColumns"].items.count
        let other = columns > 1 ? (1 ..< columns).flatMap { flexRuns(item, $0) } : []
        let col1 = segments(flexRuns(item, 1))
        var artists = artistsIn(other)
        let firstText = col1.first.map(segText).flatMap { typeWords.contains($0) ? nil : $0 } ?? (col1.count > 1 ? segText(col1[1]) : nil)
        var artist = firstText.flatMap { parseDuration($0) == nil ? $0 : nil } ?? ""
        if artists.isEmpty, artist.isEmpty { artists = fb.artists }
        if artist.isEmpty { artist = names(artists) }
        let fixed = text(item["fixedColumns"][0]["musicResponsiveListItemFixedColumnRenderer"]["text"])
        let duration = parseDuration(fixed) ?? col1.reversed().lazy.compactMap { parseDuration(segText($0)) }.first ?? 0
        let plays = flexRuns(item, 2).first?["text"].string.flatMap(parseCount)
        return Track(
            ref: "yt:\(videoID)", title: title, artist: artist, artists: artists,
            album: albumIn(other) ?? fb.album, durationMs: duration,
            coverURL: bestThumb(item["thumbnail"]) ?? fb.cover, url: trackURL(videoID),
            explicit: hasExplicit(item), available: item["musicItemRendererDisplayPolicy"].string != greyOut,
            plays: plays, tags: nil
        )
    }

    /// Трек очереди «Похожие» (`playlistPanelVideoRenderer`).
    static func track(panel p: JSONValue) -> Track? {
        guard let videoID = p["videoId"].string else { return nil }
        let byline = p["longBylineText"]["runs"].items
        let artists = artistsIn(byline)
        let first = segments(byline).first.map(segText) ?? ""
        return Track(
            ref: "yt:\(videoID)", title: text(p["title"]), artist: first.isEmpty ? names(artists) : first,
            artists: artists, album: albumIn(byline), durationMs: parseDuration(text(p["lengthText"])) ?? 0,
            coverURL: bestThumb(p["thumbnail"]), url: trackURL(videoID),
            explicit: hasExplicit(p), available: true, plays: nil, tags: nil
        )
    }

    static func tracks(in v: JSONValue, fallback: Fallback = Fallback()) -> [Track] {
        findAll(v, "musicResponsiveListItemRenderer").compactMap { track(item: $0, fallback: fallback) }
    }

    /// Токен следующей страницы списка.
    static func continuation(_ v: JSONValue) -> String? {
        findFirst(v, "continuationCommand")?["token"].string ?? findFirst(v, "nextContinuationData")?["continuation"].string
    }

    /// Похожие треки (`next` с `RDAMVM<id>`), без самого трека.
    static func nextTracks(_ v: JSONValue, seed: String) -> [Track] {
        findAll(v, "playlistPanelVideoRenderer").compactMap(track(panel:)).filter { $0.ref != "yt:\(seed)" }
    }

    /// Продолжение списка: треки и токен следующей страницы.
    static func continuationPage(_ v: JSONValue) -> (tracks: [Track], next: String?) {
        (tracks(in: v), continuation(v))
    }

    // MARK: поиск

    private static func itemBrowse(_ item: JSONValue) -> (id: String, kind: String)? {
        let endpoint = item["navigationEndpoint"]["browseEndpoint"]
        guard let id = endpoint["browseId"].string else { return nil }
        return (id, endpoint["browseEndpointContextSupportedConfigs"]["browseEndpointContextMusicConfig"]["pageType"].string ?? "")
    }

    private static func listItems(_ v: JSONValue) -> [JSONValue] {
        findAll(v, "musicResponsiveListItemRenderer")
    }

    static func searchTracks(_ v: JSONValue) -> [Track] { tracks(in: v) }

    static func searchArtists(_ v: JSONValue) -> [Artist] {
        listItems(v).compactMap { item in
            guard let (id, kind) = itemBrowse(item), kind == pageArtist || id.hasPrefix("UC") else { return nil }
            return Artist(ref: "yta:\(id)", name: segText(flexRuns(item, 0)), avatarURL: bestThumb(item["thumbnail"]), followers: nil, url: artistURL(id))
        }
    }

    static func searchAlbums(_ v: JSONValue) -> [Album] {
        listItems(v).compactMap { item in
            guard let (id, kind) = itemBrowse(item), kind == pageAlbum else { return nil }
            let col1 = segments(flexRuns(item, 1))
            let artists = artistsIn(flexRuns(item, 1))
            // «Сингл • Lil Peep • 2015»: исполнители — вторая часть
            let second = col1.count > 1 ? segText(col1[1]) : nil
            let artist = second.flatMap { lastYear($0) == nil ? $0 : nil } ?? names(artists)
            return Album(
                ref: "ytalb:\(id)", title: segText(flexRuns(item, 0)), artist: artist, artists: artists,
                coverURL: bestThumb(item["thumbnail"]), year: col1.last.flatMap { lastYear(segText($0)) },
                released: nil, trackCount: 0, url: albumURL(id)
            )
        }
    }

    /// Число треков из строки вида «500 треков» / «12 songs».
    static func trackCount(in segments: [String]) -> Int? {
        segments.first { s in
            let lower = s.lowercased()
            return countWords.contains { lower.contains($0) }
        }.flatMap(parseCount)
    }

    static func stripVL(_ id: String) -> String {
        id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    }

    static func searchPlaylists(_ v: JSONValue) -> [ServicePlaylist] {
        listItems(v).compactMap { item in
            guard let (id, kind) = itemBrowse(item), kind == pagePlaylist, id != likesBrowseID else { return nil }
            let col1 = segments(flexRuns(item, 1)).map(segText)
            return ServicePlaylist(
                ref: "ytpl:\(stripVL(id))", title: segText(flexRuns(item, 0)), owner: col1.first ?? "",
                coverURL: bestThumb(item["thumbnail"]), trackCount: trackCount(in: col1) ?? 0
            )
        }
    }

    // MARK: страницы

    /// Страница исполнителя: он сам, «Топ треков», альбомы и синглы, id плейлиста «все треки».
    struct ArtistPage {
        var artist: Artist
        var top: [Track]
        var albums: [Album]
        /// Плейлист со всеми треками исполнителя (`OLAK5uy_…`, без `VL`) — для вкладки «Треки».
        var allTracks: String?
    }

    static func artistPage(_ v: JSONValue, channelID: String) throws -> ArtistPage {
        guard case let .object(headers) = v["header"], let header = sortedPairs(headers).first?.1 else {
            throw ServiceError(message: "YouTube Music: исполнитель не найден")
        }
        let name = text(header["title"])
        let me = ArtistRef(ref: "yta:\(channelID)", name: name, avatarURL: nil)
        let avatar = bestThumb(v["microformat"]) ?? bestThumb(header["thumbnail"])
        let shelf = findFirst(v, "musicShelfRenderer")
        let top = shelf.map { tracks(in: $0["contents"], fallback: Fallback(artists: [me])) } ?? []
        let allTracks = shelf.flatMap {
            $0["bottomEndpoint"]["browseEndpoint"]["browseId"].string ?? $0["title"]["runs"][0]["navigationEndpoint"]["browseEndpoint"]["browseId"].string
        }.map(stripVL)
        var albums: [Album] = []
        for item in findAll(v, "musicTwoRowItemRenderer") {
            if let album = album(twoRow: item, me: me), !albums.contains(where: { $0.ref == album.ref }) { albums.append(album) }
        }
        let artist = Artist(ref: me.ref, name: name, avatarURL: avatar, followers: nil, url: artistURL(channelID))
        return ArtistPage(artist: artist, top: top, albums: albums, allTracks: allTracks)
    }

    private static func album(twoRow item: JSONValue, me: ArtistRef) -> Album? {
        let run = item["title"]["runs"][0]
        guard pageType(run) == pageAlbum, let id = browseID(run), let title = run["text"].string else { return nil }
        return Album(
            ref: "ytalb:\(id)", title: title, artist: me.name, artists: [me],
            coverURL: bestThumb(item["thumbnailRenderer"]), year: lastYear(text(item["subtitle"])),
            released: nil, trackCount: 0, url: albumURL(id)
        )
    }

    private static func header(_ v: JSONValue) -> JSONValue? {
        findFirst(v, "musicResponsiveHeaderRenderer") ?? findFirst(v, "musicDetailHeaderRenderer")
    }

    static func albumPage(_ v: JSONValue, browseID: String) throws -> (album: Album, tracks: [Track]) {
        guard let h = header(v) else { throw ServiceError(message: "YouTube Music: альбом не найден") }
        let title = text(h["title"])
        let artists = artistsIn(h["straplineTextOne"]["runs"].items)
        let strap = text(h["straplineTextOne"])
        let cover = bestThumb(h["thumbnail"])
        let fallback = Fallback(artists: artists, album: AlbumRef(ref: "ytalb:\(browseID)", title: title), cover: cover)
        let list = findAll(v, "musicShelfRenderer").flatMap { tracks(in: $0["contents"], fallback: fallback) }
        let album = Album(
            ref: "ytalb:\(browseID)", title: title, artist: strap.isEmpty ? names(artists) : strap, artists: artists,
            coverURL: cover, year: lastYear(text(h["subtitle"])), released: nil, trackCount: list.count, url: albumURL(browseID)
        )
        return (album, list)
    }

    /// Плейлист: шапка, первые треки и токен продолжения.
    static func playlistPage(_ v: JSONValue, listID: String) throws -> (playlist: ServicePlaylist, tracks: [Track], next: String?) {
        let shelf = findFirst(v, "musicPlaylistShelfRenderer") ?? findFirst(v, "musicShelfRenderer")
        let found = header(v)
        guard found != nil || shelf != nil else { throw ServiceError(message: "YouTube Music: плейлист не найден") }
        let h = found ?? .null
        let list = shelf.map { tracks(in: $0["contents"]) } ?? []
        let token = shelf.flatMap { continuation($0["contents"]) }
        let owner = h["facepile"]["avatarStackViewModel"]["text"]["content"].string ?? text(h["straplineTextOne"])
        let second = segments(h["secondSubtitle"]["runs"].items).map(segText)
        let playlist = ServicePlaylist(
            ref: "ytpl:\(listID)", title: text(h["title"]), owner: owner,
            coverURL: bestThumb(h["thumbnail"]) ?? list.first?.coverURL,
            trackCount: trackCount(in: second) ?? list.count
        )
        return (playlist, list, token)
    }

    /// Плейлисты библиотеки (`FEmusic_liked_playlists`) без «Понравившихся» — те идут первой строкой.
    static func libraryPlaylists(_ v: JSONValue) -> [ServicePlaylist] {
        var out: [ServicePlaylist] = []
        for item in findAll(v, "musicTwoRowItemRenderer") {
            guard let id = item["navigationEndpoint"]["browseEndpoint"]["browseId"].string, id.hasPrefix("VL"), id != likesBrowseID else { continue }
            let runs = item["subtitle"]["runs"].items
            let owner = runs.first(where: isArtistRun)?["text"].string ?? ""
            let playlist = ServicePlaylist(
                ref: "ytpl:\(stripVL(id))", title: text(item["title"]), owner: owner,
                coverURL: bestThumb(item["thumbnailRenderer"]), trackCount: trackCount(in: segments(runs).map(segText)) ?? 0
            )
            if !out.contains(where: { $0.ref == playlist.ref }) { out.append(playlist) }
        }
        return out
    }

    // MARK: аккаунт

    /// `account/account_menu` → имя и аватар. Нет шапки аккаунта — cookie не подошёл.
    static func account(_ v: JSONValue) throws -> ServiceAccount {
        guard let h = findFirst(v, "activeAccountHeaderRenderer") else {
            throw ServiceError(message: "YouTube Music: cookie не подошёл или устарел — войди заново")
        }
        let name = text(h["accountName"])
        return ServiceAccount(name: name.isEmpty ? nil : name, avatarURL: bestThumb(h["accountPhoto"]), uid: nil, premium: premium(v))
    }

    /// YouTube Premium по служебным параметрам ответа (`has_unlimited_entitlement`). Не сказано — nil.
    static func premium(_ v: JSONValue) -> Bool? {
        for service in v["responseContext"]["serviceTrackingParams"].items {
            for param in service["params"].items where param["key"].string == "has_unlimited_entitlement" {
                let value = param["value"].string
                return value == "True" || value == "true"
            }
        }
        return nil
    }

    // MARK: поток

    /// Аудиодорожка из ответа `player`.
    struct Format: Equatable {
        var itag: Int
        var url: String
        var mime: String
        var bitrate: Int
    }

    /// AAC 256 — редко, только у части треков с YouTube Premium.
    static let itagAAC256 = 141
    static let itagAAC128 = 140

    /// Аудио с прямой ссылкой. Трек не играется — ошибка с причиной от YouTube.
    static func playerFormats(_ v: JSONValue) throws -> [Format] {
        let status = v["playabilityStatus"]["status"].string ?? "UNKNOWN"
        guard status == "OK" else {
            let reason = v["playabilityStatus"]["reason"].string ?? status
            throw ServiceError(message: "YouTube Music: трек не играется (\(reason))")
        }
        let formats = v["streamingData"]["adaptiveFormats"].items.compactMap { f -> Format? in
            guard let mime = f["mimeType"].string, mime.hasPrefix("audio/"), let itag = f["itag"].int, let url = f["url"].string else { return nil }
            return Format(itag: itag, url: url, mime: mime, bitrate: f["bitrate"].int ?? 0)
        }
        guard !formats.isEmpty else { throw ServiceError(message: "YouTube Music: у трека нет аудио с прямой ссылкой") }
        return formats
    }

    /// AVPlayer не играет Opus в WebM, поэтому на iPhone только AAC: «Высокое» — 256, если есть, иначе 128;
    /// «Обычное» — 128. Нет нужной — самая плотная из AAC (`audio/mp4`).
    static func pickFormat(_ formats: [Format], high: Bool) -> Format? {
        let order = high ? [itagAAC256, itagAAC128] : [itagAAC128]
        for itag in order {
            if let hit = formats.first(where: { $0.itag == itag }) { return hit }
        }
        return formats.filter { $0.mime.hasPrefix("audio/mp4") }.max { $0.bitrate < $1.bitrate }
    }

    /// Плашка качества в плеере.
    static func qualityLabel(_ f: Format) -> String {
        switch f.itag {
        case itagAAC256: "AAC 256"
        case itagAAC128: "AAC 128"
        default: "AAC \(f.bitrate / 1000)"
        }
    }
}

private extension Character {
    var isASCIIDigitChar: Bool { isASCII && isNumber }
}
