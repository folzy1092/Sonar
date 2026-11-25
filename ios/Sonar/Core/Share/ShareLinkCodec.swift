import Foundation

/// Ссылка «Поделиться» треком: `https://try-sonar.ru/t/#<данные>` (docs/SPACE_SHARE_PROMPT.md §3).
/// Порт сборки из `site/src/lib/share-link.ts` — **строка должна выйти байт в байт той же**: JSON с тем же
/// порядком ключей и теми же экранированиями, что `JSON.stringify`, → UTF-8 → base64url. Общий пример —
/// `site/src/lib/share-link.fixture.json` (его читают тесты сайта, ПК и iPhone). Формат менять во всех трёх местах.
struct ShareData: Equatable, Sendable {
    /// Название, артист, длительность (с), обложка (https с хостов сервисов).
    var t: String
    var a: String
    var d: Int?
    var c: String?
    /// Откуда делились: `ym` / `sc` / `yt` / `sp`.
    var src: String
    /// Id трека в каждом сервисе, где он нашёлся (без префикса ref).
    var ids: [String: String]
    /// Путь SoundCloud «user/slug» — для кнопки на сайте.
    var sl: String?
    /// Что сайт играет: `yt` или `sc`.
    var play: String?
    /// Кто поделился — `@username` без «@», если вошёл в аккаунт Sonar.
    var by: String?
}

enum ShareLinkCodec {
    static let version = 1
    static let maxLength = 600
    static let site = "https://try-sonar.ru"
    static let services = ["ym", "sc", "yt", "sp"]
    private static let textMax = 160

    static func validID(_ service: String, _ id: String) -> Bool {
        guard id.allSatisfy(\.isASCII) else { return false }
        return switch service {
        case "ym": id.wholeMatch(of: #/\d{1,12}/#) != nil
        case "sc": id.wholeMatch(of: #/\d{1,14}/#) != nil
        case "yt": id.wholeMatch(of: #/[\w-]{11}/#) != nil
        case "sp": id.wholeMatch(of: #/[A-Za-z0-9]{22}/#) != nil
        default: false
        }
    }

    static func validCover(_ url: String?) -> Bool {
        guard let url, url.utf16.count <= 400, let u = URLComponents(string: url), u.scheme == "https",
              u.user == nil, u.password == nil, u.port == nil, let host = u.host?.lowercased() else { return false }
        return host.wholeMatch(of: #/(?:i\d?\.sndcdn\.com|avatars\.yandex\.net|i\d?\.ytimg\.com|(?:lh\d|yt\d)\.googleusercontent\.com|i\.scdn\.co|[\w-]+\.spotifycdn\.com)/#) != nil
    }

    private static func validSCPath(_ p: String) -> Bool {
        p.wholeMatch(of: #/[\w-]{1,80}\/[\w-]{1,160}/#) != nil && p.allSatisfy(\.isASCII)
    }

    /// «user/slug» из ссылки SoundCloud (без `?si=`); не трек — nil.
    static func scPath(_ url: String?) -> String? {
        guard let url, let u = URLComponents(string: url), let host = u.host?.lowercased(),
              host.wholeMatch(of: #/(?:www\.|m\.)?soundcloud\.com/#) != nil else { return nil }
        let path = u.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard validSCPath(path), path.firstMatch(of: #/^(?:discover|search|you|stations|charts)\//#) == nil else { return nil }
        return path
    }

    /// YouTube (всегда целиком), иначе SoundCloud, если не Go+-отрывок; Яндекс и Spotify во встройке — 30 с.
    static func pickPlay(_ ids: [String: String], scFull: Bool) -> String? {
        if ids["yt"] != nil { return "yt" }
        if ids["sc"] != nil, scFull { return "sc" }
        return nil
    }

    /// Пробелы схлопнуты; длиннее 160 (в UTF-16, как в JS) — обрезаем с «…».
    static func clip(_ s: String) -> String {
        let one = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard one.utf16.count > textMax else { return one }
        return String(decoding: Array(one.utf16.prefix(textMax - 1)), as: UTF16.self) + "…"
    }

    /// Как `normalize` на сайте: битое — прочь. Нечем делиться — nil.
    static func normalize(_ raw: ShareData) -> ShareData? {
        let t = clip(raw.t), a = clip(raw.a)
        guard !t.isEmpty, services.contains(raw.src) else { return nil }
        var ids: [String: String] = [:]
        for s in services { if let id = raw.ids[s], validID(s, id) { ids[s] = id } }
        var out = ShareData(t: t, a: a, src: raw.src, ids: ids)
        if let d = raw.d, d > 0, d < 6 * 3600 { out.d = d }
        if validCover(raw.c) { out.c = raw.c }
        if let sl = raw.sl, validSCPath(sl) { out.sl = sl }
        if let p = raw.play, p == "yt" || p == "sc", ids[p] != nil { out.play = p }
        if let by = raw.by, validBy(by) { out.by = by }
        return out
    }

    /// @username — латиница, цифры и «_», 3–32 знака (как на сервере).
    static func validBy(_ s: String) -> Bool {
        (3...32).contains(s.count) && s.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_") }
    }

    // ——— JSON как у JSON.stringify ———

    static func jsonString(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where u.value < 0x20: out += String(format: "\\u%04x", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        return out + "\""
    }

    static func serialize(_ d: ShareData) -> String {
        var parts = ["\"v\":\(version)", "\"t\":\(jsonString(d.t))", "\"a\":\(jsonString(d.a))"]
        if let v = d.d, v != 0 { parts.append("\"d\":\(v)") }
        if let c = d.c { parts.append("\"c\":\(jsonString(c))") }
        parts.append("\"src\":\(jsonString(d.src))")
        let ids = services.compactMap { s in d.ids[s].map { "\(jsonString(s)):\(jsonString($0))" } }
        parts.append("\"ids\":{\(ids.joined(separator: ","))}")
        if let sl = d.sl { parts.append("\"sl\":\(jsonString(sl))") }
        if let p = d.play { parts.append("\"play\":\(jsonString(p))") }
        if let by = d.by { parts.append("\"by\":\(jsonString(by))") }
        return "{\(parts.joined(separator: ","))}"
    }

    static func base64url(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func encode(_ data: ShareData) -> String? {
        guard let clean = normalize(data) else { return nil }
        let full = base64url(serialize(clean))
        if full.count <= maxLength || clean.c == nil { return full }
        var noCover = clean
        noCover.c = nil
        return base64url(serialize(noCover))
    }

    /// Полная ссылка; не русский язык — `/en/t/` и т. п.
    static func url(_ data: ShareData, lang: String = "ru") -> URL? {
        guard let enc = encode(data) else { return nil }
        let prefix = lang == "ru" || lang.isEmpty ? "" : "/\(lang)"
        return URL(string: "\(site)\(prefix)/t/#\(enc)")
    }

    // ——— из трека ———

    private static func split(_ ref: String) -> (String, String)? {
        guard let i = ref.firstIndex(of: ":") else { return nil }
        return (String(ref[..<i]), String(ref[ref.index(after: i)...]))
    }

    /// Трек + найденные двойники (`refs`: сервис → ref, `urls`: сервис → ссылка) → данные. Локальным не делимся.
    static func data(_ track: Track, refs: [String: String] = [:], urls: [String: String] = [:], scFull: Bool = false, by: String? = nil) -> ShareData? {
        guard let own = split(track.ref), services.contains(own.0), validID(own.0, own.1) else { return nil }
        let src = own.0
        var ids = [src: own.1]
        for r in refs.values {
            if let p = split(r), services.contains(p.0), ids[p.0] == nil, validID(p.0, p.1) { ids[p.0] = p.1 }
        }
        let seconds = track.durationMs > 0 ? Int((Double(track.durationMs) / 1000).rounded()) : nil
        return ShareData(
            t: track.title, a: track.artist, d: seconds,
            c: validCover(track.coverURL) ? track.coverURL : nil,
            src: src, ids: ids,
            sl: scPath(src == "sc" ? track.url : urls["sc"]),
            play: pickPlay(ids, scFull: scFull),
            by: by
        )
    }

    static func canShare(_ track: Track) -> Bool { data(track) != nil }
}
