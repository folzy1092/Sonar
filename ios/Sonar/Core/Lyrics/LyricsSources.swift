import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // тесты логики на Linux
#endif

// Где искать текст (SPEC §3.7б, docs/LYRICS.md): lrclib → NetEase → Genius, всё прямо с телефона, без
// ключей. Порт `windows/src-tauri/src/lyrics/{mod,lrclib,netease,genius,translate}.rs` — те же шаги,
// пороги и запросы. Сеть — через `LyricsTransport`, чтобы порядок поиска проверялся тестами без сети.

/// Что ищем: исполнитель, название, длительность в секундах (0 — неизвестна).
struct LyricsQuery: Sendable, Equatable {
    var artist: String
    var title: String
    var duration: Double

    init(artist: String, title: String, duration: Double) {
        self.artist = artist
        self.title = title
        self.duration = duration
    }

    init(_ track: Track) {
        self.init(artist: track.artist, title: track.title, duration: Double(track.durationMs) / 1000)
    }
}

/// Ошибка источника: HTTP-код и понятная причина.
struct LyricsSourceError: LocalizedError, Equatable {
    var status: Int
    var message: String

    var errorDescription: String? { message }
}

/// Один HTTP-запрос: код, тело, заголовки (ключи — в нижнем регистре).
struct LyricsResponse: Sendable {
    var status: Int
    var body: Data
    var headers: [String: String] = [:]

    var text: String { String(decoding: body, as: UTF8.self) }
}

protocol LyricsTransport: Sendable {
    func send(_ request: URLRequest) async throws -> LyricsResponse
}

/// Обычный URLSession.
struct URLSessionLyricsTransport: LyricsTransport {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> LyricsResponse {
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            if let key = key as? String, let value = value as? String { headers[key.lowercased()] = value }
        }
        return LyricsResponse(status: http?.statusCode ?? 0, body: data, headers: headers)
    }
}

/// Что умеет источник текстов — так его видит `LyricsStore` (в тестах — заглушка).
protocol LyricsProviding: Sendable {
    /// `nil` — текста нигде нет; ошибка — сеть не ответила (не кэшировать как «нет»).
    func find(_ query: LyricsQuery) async throws -> Lyrics?
    /// Аннотации Genius к песне; нет — пусто.
    func annotations(_ query: LyricsQuery) async throws -> [LyricsAnnotation]
    /// Перевод строк (той же длины, пустые — пустые) и язык оригинала (`en`, `ja`…).
    func translate(_ lines: [String], to language: String) async throws -> (lines: [String], source: String)
}

/// Поиск текста: порт `fetch_any` из `mod.rs`.
struct LyricsFinder: LyricsProviding {
    var transport: LyricsTransport = URLSessionLyricsTransport()

    func find(_ query: LyricsQuery) async throws -> Lyrics? {
        var plain: String?
        var failed: Error?

        // lrclib: как есть → ядро названия без мусора → ключевые слова → «АРТИСТ - ТРЕК» из перезалива
        var attempts: [(String, String)] = [(query.artist, query.title)]
        let keyword = TrackText.keywordTitle(query.title)
        for t in [keyword.core, keyword.keywords] where !t.isEmpty { attempts.append((query.artist, t)) }
        if let re = TrackText.reuploadVariant(query.title) { attempts.append((re.artist, re.title)) }
        var unique: [(String, String)] = []
        for a in attempts {
            if let last = unique.last, last.0.lowercased() == a.0.lowercased(), last.1.lowercased() == a.1.lowercased() { continue }
            unique.append(a)
        }

        let lrclib = Lrclib(transport: transport)
        for (artist, title) in unique {
            do {
                let found = try await lrclib.fetch(artist: artist, title: title, duration: query.duration)
                if let synced = found.synced {
                    let lines = LyricsParser.parseLRC(synced, trackLength: query.duration)
                    if !lines.isEmpty { return Lyrics(lines: lines, synced: true, source: Lyrics.lrclib) }
                }
                if plain == nil { plain = found.plain }
            } catch {
                failed = error
                break // lrclib лежит — дальше спрашивать бесполезно
            }
        }

        // lrclib синхронного не нашёл — NetEase (пословный YRC или построчный LRC); не ответил — дальше Genius
        if let found = try? await NetEase(transport: transport)
            .fetch(artist: TrackText.firstArtist(query.artist), title: TrackText.cleanTitle(query.title), duration: query.duration) {
            return found
        }

        do {
            if let text = try await Genius(transport: transport).text(artist: query.artist, title: query.title) {
                let lines = LyricsParser.plainLines(Genius.stripSections(text))
                if !lines.isEmpty { return Lyrics(lines: lines, synced: false, source: Lyrics.genius) }
            }
        } catch {
            if failed == nil, plain == nil { failed = error }
        }

        if let plain {
            let lines = LyricsParser.plainLines(plain)
            if !lines.isEmpty { return Lyrics(lines: lines, synced: false, source: Lyrics.lrclib) }
        }
        if let failed { throw failed }
        return nil
    }

    func annotations(_ query: LyricsQuery) async throws -> [LyricsAnnotation] {
        try await Genius(transport: transport).annotations(artist: query.artist, title: query.title)
    }

    func translate(_ lines: [String], to language: String) async throws -> (lines: [String], source: String) {
        try await LyricsTranslator(transport: transport).translate(lines, to: language)
    }
}

// MARK: - lrclib

/// lrclib.net — открытая база LRC без ключа. Порт `lrclib.rs`.
struct Lrclib: Sendable {
    static let api = "https://lrclib.net/api"
    static let userAgent = "Sonar (https://github.com/folzy1092/Sonar)"
    /// Насколько длительность в lrclib может отличаться от трека, секунд.
    static let durationSlack = 4.0

    var transport: LyricsTransport

    struct Record: Equatable, Sendable {
        var trackName: String?
        var duration: Double?
        var instrumental: Bool
        var synced: String?
        var plain: String?

        init(trackName: String?, duration: Double?, instrumental: Bool = false, synced: String?, plain: String?) {
            self.trackName = trackName
            self.duration = duration
            self.instrumental = instrumental
            self.synced = synced
            self.plain = plain
        }

        init(json: JSONValue) {
            self.init(trackName: json["trackName"].string, duration: json["duration"].number,
                      instrumental: json["instrumental"].bool ?? false,
                      synced: json["syncedLyrics"].string, plain: json["plainLyrics"].string)
        }
    }

    struct Found: Equatable, Sendable {
        var synced: String?
        var plain: String?
    }

    static func fits(_ r: Record, duration: Double) -> Bool {
        guard duration > 0, let d = r.duration else { return true }
        return abs(d - duration) <= durationSlack
    }

    /// Лучший результат: сначала с тем же названием (без «(prod. …)»), потом любой подходящий.
    static func pick(_ results: [Record], duration: Double, title: String) -> Found {
        let wanted = TrackText.cleanTitle(title).lowercased()
        let fitting = results.filter { !$0.instrumental && fits($0, duration: duration) }
        func same(_ r: Record) -> Bool { !wanted.isEmpty && TrackText.cleanTitle(r.trackName ?? "").lowercased() == wanted }
        func has(_ s: String?) -> Bool { !(s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let withSynced = fitting.filter { has($0.synced) }
        let withPlain = fitting.filter { has($0.plain) }
        return Found(synced: (withSynced.first(where: same) ?? withSynced.first)?.synced,
                     plain: (withPlain.first(where: same) ?? withPlain.first)?.plain)
    }

    /// 404 — nil; другой не-2xx — ошибка.
    private func json(_ path: String, _ query: [(String, String)]) async throws -> JSONValue? {
        var request = URLRequest(url: try HTTP.url("\(Self.api)/\(path)", query: query), timeoutInterval: 10)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await transport.send(request)
        if response.status == 404 { return nil }
        guard (200 ..< 300).contains(response.status) else {
            throw LyricsSourceError(status: response.status, message: "lrclib \(path): HTTP \(response.status)")
        }
        return try JSONValue(data: response.body)
    }

    /// Поиск по исполнителю и названию: `/get` (точно, с длительностью), потом `/search`.
    /// Синхронный текст важнее: plain запоминается, но поиск synced идёт дальше.
    func fetch(artist: String, title: String, duration: Double) async throws -> Found {
        var best = Found()
        for name in TrackText.artistVariants(artist) {
            var query = [("artist_name", name), ("track_name", title)]
            if duration > 0 { query.append(("duration", String(Int(duration.rounded())))) }
            // 5xx на /get — не сбой: lrclib не дождался внешних источников. Дальше спрашиваем /search.
            if let record = try? await json("get", query), record.isObject {
                let found = Self.pick([Record(json: record)], duration: duration, title: title)
                if found.synced != nil { return found }
                best.plain = best.plain ?? found.plain
            }
            var titles = [title]
            let clean = TrackText.cleanTitle(title)
            if !clean.isEmpty, clean != title { titles.append(clean) }
            for t in titles {
                let records = (try await json("search", [("artist_name", name), ("track_name", t)]))?.items.map(Record.init(json:)) ?? []
                let found = Self.pick(records, duration: duration, title: title)
                if found.synced != nil { return found }
                best.plain = best.plain ?? found.plain
            }
        }
        return best
    }
}

// MARK: - NetEase

/// NetEase Cloud Music — запасной источник синхронного текста: спрашиваем, только если lrclib синхронного
/// не нашёл. Главное — пословный YRC; нет его — обычный LRC. Совпадение строгое: название ≥ 0.75,
/// артист ≥ 0.6, длительность ±3 с — чужую песню не берём. Порт `netease.rs`.
struct NetEase: Sendable {
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
    static let search = "https://music.163.com/api/search/get"
    static let lyric = "https://music.163.com/api/song/lyric/v1"

    var transport: LyricsTransport

    /// Лучшая песня из выдачи поиска (`result.songs`).
    static func pick(_ songs: [JSONValue], artist: String, title: String, duration: Double) -> Int? {
        let na = TrackText.norm(artist)
        let nt = TrackText.norm(title)
        var best: (id: Int, score: Double)?
        for song in songs {
            guard let id = song["id"].int, let name = song["name"].string else { continue }
            let ms = song["duration"].number ?? 0
            if duration > 0, ms > 0, abs(ms / 1000 - duration) > 3 { continue }
            let ts = TrackText.similarity(TrackText.norm(name), nt)
            let artistScore = song["artists"].items.compactMap { $0["name"].string }
                .map { TrackText.similarity(TrackText.norm($0), na) }.max() ?? 0
            guard ts >= 0.75, artistScore >= 0.6 else { continue }
            if best == nil || ts + artistScore > best!.score { best = (id, ts + artistScore) }
        }
        return best?.id
    }

    /// Ответ `song/lyric/v1` → текст: YRC (≥ 3 строк) или LRC (≥ 3 непустых строк, без титров).
    static func lyrics(from json: JSONValue, duration: Double) -> Lyrics? {
        if let yrc = json["yrc"]["lyric"].string, !yrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = LyricsParser.parseYRC(yrc)
            if lines.count >= 3 { return Lyrics(lines: lines, synced: true, source: Lyrics.netease) }
        }
        if let lrc = json["lrc"]["lyric"].string, !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = LyricsParser.parseLRC(lrc, trackLength: duration).filter { !LyricsParser.isCredit($0.text) }
            // «纯音乐，请欣赏» и подобное — инструментал, текста нет
            if lines.filter({ !$0.text.isEmpty }).count >= 3 { return Lyrics(lines: lines, synced: true, source: Lyrics.netease) }
        }
        return nil
    }

    private func get(_ base: String, _ query: [(String, String)]) async throws -> JSONValue {
        var request = URLRequest(url: try HTTP.url(base, query: query), timeoutInterval: 8)
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await transport.send(request)
        guard (200 ..< 300).contains(response.status) else {
            throw LyricsSourceError(status: response.status, message: "NetEase: HTTP \(response.status)")
        }
        return try JSONValue(data: response.body)
    }

    /// `nil` — не нашли (или только титры).
    func fetch(artist: String, title: String, duration: Double) async throws -> Lyrics? {
        let found = try await get(Self.search, [("s", "\(artist) \(title)"), ("type", "1"), ("limit", "10")])
        guard let id = Self.pick(found["result"]["songs"].items, artist: artist, title: title, duration: duration) else { return nil }
        let json = try await get(Self.lyric, [("id", String(id)), ("lv", "0"), ("yv", "0"), ("tv", "0"), ("rv", "0"), ("kv", "0")])
        return Self.lyrics(from: json, duration: duration)
    }
}

// MARK: - Genius

/// Genius — обычный текст без таймкодов и аннотации. Песня берётся, только если её исполнитель совпадает
/// с нашим (или с фитом из названия), а название похоже (≥ 0.8). Порт `genius.rs`.
///
/// В Windows Cloudflare Genius отвечал «я не робот» на TLS-отпечаток Rust-клиента, поэтому там запрос идёт
/// через системный curl. На iPhone запрос идёт обычным URLSession (отпечаток как у Safari) — должен
/// проходить, но на устройстве ещё не проверено; если Cloudflare всё же требует проверку — понятная ошибка,
/// и поиск откатывается на plain из lrclib.
struct Genius: Sendable {
    static let userAgent = HTTP.browserAgent
    static let minTitle = 0.8
    static let perPage = 5

    var transport: LyricsTransport

    static let section = Pattern(#"^\[[^\]]*\]$"#)
    static let allBrackets = Pattern(#"\s*[(\[][^)\]]*[)\]]|\s+(?i:feat|ft)\.?\s.*$"#)
    static let featTail = Pattern(#"(?i)\s+(?:\+|&|x|w/|with)\s+.*$"#)
    static let artistSplit = Pattern(#"(?i)\s*(?:[,&+()]|\b(?:feat|ft)\b\.?|\b(?:x|and|with|и)\b)\s*"#)

    static func artistNames(_ text: String) -> Set<String> {
        Set(artistSplit.split(text).map(TrackText.norm).filter { !$0.isEmpty })
    }

    /// Запросы по порядку: как есть, по ядру, по ключевым словам, только название, только исполнитель.
    static func queries(first: String, clean: String, keywords: String, core: String) -> [String] {
        var qs = ["\(first) \(clean)", "\(first) \(core)", "\(first) \(keywords)"]
        if core.filter(\.isLetter).count >= 3 { qs.append(core) }
        qs.append(first)
        var seen = Set<String>()
        return qs.map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Лучшая песня из выдачи: исполнитель из `allowed`, название похоже на один из вариантов.
    static func pick(_ hits: [JSONValue], variants: [String], allowed: Set<String>) -> (url: String, id: Int)? {
        var best: (url: String, id: Int, score: Double)?
        for hit in hits where hit["type"].string == "song" {
            let song = hit["result"]
            guard let url = song["url"].string else { continue }
            var names = artistNames(song["artist_names"].string ?? "")
            names.formUnion(artistNames(song["primary_artist"]["name"].string ?? ""))
            if names.isDisjoint(with: allowed) { continue } // чужой исполнитель — не берём, даже если название то же
            let found = TrackText.norm(allBrackets.replaceAll(song["title"].string ?? "", with: ""))
            let score = variants.map { TrackText.similarity(TrackText.norm($0), found) }.max() ?? 0
            if best == nil || score > best!.score { best = (url, song["id"].int ?? 0, score) }
        }
        guard let best, best.score >= minTitle else { return nil }
        return (best.url, best.id)
    }

    /// Ответ Genius: тело или ошибка с понятной причиной.
    static func check(_ response: LyricsResponse) throws -> String {
        let body = response.text
        if (200 ..< 300).contains(response.status) { return body }
        if response.headers["cf-mitigated"] == "challenge" || body.contains("challenge-platform") {
            throw LyricsSourceError(status: response.status, message: "Genius: Cloudflare требует проверку «я не робот»")
        }
        throw LyricsSourceError(status: response.status, message: "Genius: HTTP \(response.status)")
    }

    private func get(_ base: String, _ query: [(String, String)] = []) async throws -> String {
        var request = URLRequest(url: try HTTP.url(base, query: query), timeoutInterval: 12)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return try Self.check(try await transport.send(request))
    }

    /// Сырой текст песни (строки через `\n`) или nil.
    func text(artist: String, title: String) async throws -> String? {
        guard let song = try await findSong(artist: artist, title: title) else { return nil }
        let text = Self.lyrics(fromHTML: try await get(song.url))
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    /// Аннотации (по тем же правилам поиска, что текст).
    func annotations(artist: String, title: String) async throws -> [LyricsAnnotation] {
        guard let song = try await findSong(artist: artist, title: title), song.id != 0 else { return [] }
        let body = try await get("https://genius.com/api/referents",
                                 [("song_id", String(song.id)), ("text_format", "plain"), ("per_page", "50")])
        return Self.parseReferents(try JSONValue(data: Data(body.utf8)))
    }

    /// Заголовки частей («[Куплет 1]») без строк текста и пустые пояснения пропускаются.
    static func parseReferents(_ json: JSONValue) -> [LyricsAnnotation] {
        var out: [LyricsAnnotation] = []
        for referent in json["response"]["referents"].items {
            let lines = (referent["fragment"].string ?? "").split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !section.matches($0) }
            let annotation = referent["annotations"][0]
            guard !annotation.isNull else { continue }
            let body = (annotation["body"]["plain"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if lines.isEmpty || body.isEmpty { continue }
            let reviewed = annotation["state"].string == "accepted" || annotation["verified"].bool == true
            out.append(LyricsAnnotation(lines: lines, body: body, reviewed: reviewed))
        }
        return out
    }

    /// Песня на Genius (адрес и id) по исполнителю и названию — строгий подбор (`pick`).
    func findSong(artist: String, title: String) async throws -> (url: String, id: Int)? {
        var clean = Self.allBrackets.replaceAll(title, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { clean = title }
        let first = TrackText.firstArtist(artist)
        let keyword = TrackText.keywordTitle(title)
        var allowed = Set(keyword.feats.map(TrackText.norm))
        allowed.insert(TrackText.norm(first))
        allowed.remove("")
        if allowed.isEmpty { return nil }
        var variants: [String] = []
        for v in [clean, Self.featTail.replaceAll(clean, with: ""), keyword.keywords, keyword.core] where !v.isEmpty && !variants.contains(v) {
            variants.append(v)
        }

        for (i, q) in Self.queries(first: first, clean: clean, keywords: keyword.keywords, core: keyword.core).enumerated() {
            var hits: [JSONValue] = []
            for page in 1 ... (i == 0 ? 1 : 2) {
                let body: String
                do {
                    body = try await get("https://genius.com/api/search/multi",
                                         [("q", q), ("per_page", String(Self.perPage)), ("page", String(page))])
                } catch let error as LyricsSourceError where error.status == 422 {
                    break // запрос не понравился — следующий
                }
                let found = try JSONValue(data: Data(body.utf8))["response"]["sections"].items.flatMap { $0["hits"].items }
                hits.append(contentsOf: found)
                if found.count < Self.perPage { break }
            }
            if let song = Self.pick(hits, variants: variants, allowed: allowed) { return song }
        }
        return nil
    }

    /// Заголовки частей («[Припев]», «[Куплет 1: …]») → пустая строка между куплетами.
    static func stripSections(_ text: String) -> String {
        text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
            .map { section.matches($0.trimmingCharacters(in: .whitespaces)) ? "" : String($0) }
            .joined(separator: "\n")
    }

    /// HTML-сущности: `&amp;`, `&#39;`, `&#x27;`…
    static func unescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            rest = rest[amp...]
            let window = rest.prefix(12)
            guard let semi = window.firstIndex(of: ";") else {
                out += "&"
                rest = rest.dropFirst()
                continue
            }
            let entity = String(rest[rest.index(after: rest.startIndex) ..< semi])
            var char: Character?
            switch entity {
            case "amp": char = "&"
            case "lt": char = "<"
            case "gt": char = ">"
            case "quot": char = "\""
            case "apos": char = "'"
            case "nbsp": char = " "
            default:
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    char = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map(Character.init)
                } else if entity.hasPrefix("#") {
                    char = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map(Character.init)
                }
            }
            if let char {
                out.append(char)
                rest = rest[rest.index(after: semi)...]
            } else {
                out += "&"
                rest = rest.dropFirst()
            }
        }
        out += rest
        return out
    }

    /// Текст из блоков `data-lyrics-container="true"`; вставки `data-exclude-from-selection` пропускаются.
    static func lyrics(fromHTML html: String) -> String {
        var parts = ""
        var depth = 0
        var skip = 0
        var rest = Substring(html)
        while let lt = rest.firstIndex(of: "<") {
            if depth > 0, skip == 0 { parts += unescape(String(rest[..<lt])) }
            rest = rest[lt...]
            guard let gt = rest.firstIndex(of: ">") else { break }
            let tag = rest[rest.index(after: rest.startIndex) ..< gt]
            rest = rest[rest.index(after: gt)...]
            let closing = tag.hasPrefix("/")
            let name = tag.drop(while: { $0 == "/" }).prefix(while: { $0.isASCII && ($0.isLetter || $0.isNumber) }).lowercased()
            if depth > 0 {
                switch (name, closing) {
                case ("div", false):
                    depth += 1
                    if skip > 0 || tag.contains(#"data-exclude-from-selection="true""#) { skip += 1 }
                case ("div", true):
                    skip = max(0, skip - 1)
                    depth -= 1
                case ("br", _) where skip == 0:
                    parts += "\n"
                default:
                    break
                }
            } else if name == "div", !closing, tag.contains(#"data-lyrics-container="true""#) {
                depth = 1
                parts += "\n"
            }
        }
        return parts
    }
}

// MARK: - перевод

/// Перевод текста песни (меню текста → «Перевести»). Без сервера и ключей: открытая точка Google Translate
/// расширения Chrome (`clients5`, `dict-chrome-ex`) — каждая строка отдельным `q` одним запросом. Запасной
/// путь — `translate.googleapis.com` (`gtx`, строки через перевод строки). Пустые строки не отправляем.
/// Строки, которые уже на языке интерфейса, не переводим (2026-11-19): язык смотрим у каждой строки, а
/// перевод, совпавший с оригиналом, тоже убираем. Порт `translate.rs`.
struct LyricsTranslator: Sendable {
    static let url = "https://clients5.google.com/translate_a/t"
    static let gtx = "https://translate.googleapis.com/translate_a/single"

    var transport: LyricsTransport

    func translate(_ lines: [String], to language: String) async throws -> (lines: [String], source: String) {
        let indices = lines.indices.filter { !lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if indices.isEmpty { return (Array(repeating: "", count: lines.count), "") }
        let source = indices.map { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
        let got: (lines: [String], sources: [String])
        if let byLines = try? await byLines(source, to: language), byLines.lines.count == source.count {
            got = byLines
        } else {
            let byText = try await byText(source, to: language)
            got = (byText.lines, [byText.source])
        }
        let kept = Self.dropSameLanguage(source, translated: got.lines, sources: got.sources, to: language)
        var out = Array(repeating: "", count: lines.count)
        for (k, i) in indices.enumerated() where k < kept.lines.count { out[i] = kept.lines[k] }
        return (out, kept.source)
    }

    /// Убирает перевод у строк, которые уже на языке `to`: Google определил у строки этот язык или перевод
    /// совпал с оригиналом (без регистра и знаков). `sources` — язык каждой строки (gtx знает один на весь
    /// текст — тогда он один в списке). Язык оригинала — самый частый среди переведённых строк, а если
    /// переводить нечего — `to` (тогда «Текст уже на этом языке»).
    static func dropSameLanguage(_ original: [String], translated: [String], sources: [String],
                                 to language: String) -> (lines: [String], source: String) {
        let target = baseLanguage(language)
        func lineSource(_ k: Int) -> String {
            if sources.count == 1 { return sources[0] }
            return k < sources.count ? sources[k] : ""
        }
        let lines = translated.enumerated().map { k, text -> String in
            let same = baseLanguage(lineSource(k)) == target || (k < original.count && sameText(original[k], text))
            return same ? "" : text
        }
        let counts = Dictionary(grouping: lines.indices.filter { !lines[$0].isEmpty }.map { baseLanguage(lineSource($0)) }
            .filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        if lines.allSatisfy(\.isEmpty) { return (lines, target) }
        let source = counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? ""
        return (lines, source)
    }

    /// `pt-BR` → `pt`, `RU` → `ru`.
    static func baseLanguage(_ code: String) -> String {
        String(code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
            .trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Совпадают ли строки без регистра, пробелов и знаков: «Привет, мир!» = «привет мир».
    static func sameText(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String {
            String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
        }
        let (x, y) = (norm(a), norm(b))
        return !x.isEmpty && x == y
    }

    private func post(_ base: String, query: [(String, String)], form: [(String, String)]) async throws -> String {
        var request = URLRequest(url: try HTTP.url(base, query: query), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.form(form)
        let response = try await transport.send(request)
        guard (200 ..< 300).contains(response.status) else {
            throw LyricsSourceError(status: response.status, message: "переводчик ответил \(response.status)")
        }
        return response.text
    }

    private func byLines(_ source: [String], to language: String) async throws -> (lines: [String], sources: [String]) {
        let body = try await post(Self.url, query: [("client", "dict-chrome-ex"), ("sl", "auto"), ("tl", language)],
                                  form: source.map { ("q", $0) })
        return try Self.parseLines(body)
    }

    private func byText(_ source: [String], to language: String) async throws -> (lines: [String], source: String) {
        let body = try await post(Self.gtx, query: [("client", "gtx"), ("sl", "auto"), ("tl", language), ("dt", "t")],
                                  form: [("q", source.joined(separator: "\n"))])
        return try Self.parse(body)
    }

    static let unexpected = LyricsSourceError(status: 0, message: "неожиданный ответ переводчика")

    /// Ответ clients5: `[["перевод","en"],…]` (или просто `["перевод",…]`, если язык оригинала задан) —
    /// перевод и язык каждой строки (без языка — пустая строка).
    static func parseLines(_ body: String) throws -> (lines: [String], sources: [String]) {
        guard let items = try JSONValue(data: Data(body.utf8)).array else { throw unexpected }
        return try items.reduce(into: (lines: [String](), sources: [String]())) { acc, item in
            if let s = item.string {
                acc.lines.append(s.trimmingCharacters(in: .whitespacesAndNewlines))
                acc.sources.append("")
            } else if let pair = item.array {
                acc.lines.append((pair.first?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                acc.sources.append(item[1].string ?? "")
            } else {
                throw unexpected
            }
        }
    }

    /// Ответ gtx: `[[["перевод\n","original\n",…],…],null,"en",…]` — склеиваем куски и режем по строкам.
    static func parse(_ body: String) throws -> (lines: [String], source: String) {
        let json = try JSONValue(data: Data(body.utf8))
        guard let parts = json[0].array else { throw unexpected }
        let joined = parts.compactMap { $0[0].string }.joined()
        let lines = joined.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return (lines, json[2].string ?? "")
    }
}
