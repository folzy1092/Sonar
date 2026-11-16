import Foundation

/// Ссылка из буфера в строке поиска: трек, альбом, артист или плейлист SoundCloud / Яндекс Музыки.
/// Яндекс разбирается по адресу; SoundCloud — только через `resolve` его API (в адресе имя, а не id),
/// короткие `on.soundcloud.com` раскрываются переходом. Порт `providers/links.rs`.
enum ServiceLink: Equatable, Sendable {
    /// Готовый ref Sonar: `ym:…`, `ymalb:…`, `yma:…`, `ympl:<uid>:<kind>`.
    case ref(String)
    /// Ссылка SoundCloud — что за ней, узнаём у API.
    case soundCloud(String)

    /// Похоже ли на ссылку (как `looksLikeLink` в строке поиска Windows).
    static func looksLikeLink(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !s.contains(where: { $0.isWhitespace })
            && (s.hasPrefix("http://") || s.hasPrefix("https://") || s.contains("soundcloud.com/") || s.contains("music.yandex."))
    }

    static func parse(_ raw: String) -> ServiceLink? {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains(where: { $0.isWhitespace }) else { return nil }
        let withScheme = raw.contains("://") ? raw : "https://" + raw
        guard var components = URLComponents(string: withScheme), var host = components.host?.lowercased() else { return nil }
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        let parts = components.path.split(separator: "/").map(String.init)
        if host.hasSuffix("soundcloud.com") || host == "snd.sc" {
            // свои страницы SoundCloud без контента — не ссылки на музыку
            if host == "soundcloud.com", parts.isEmpty { return nil }
            components.query = nil
            components.fragment = nil
            if components.path.isEmpty { components.path = "/" }
            return components.string.map { .soundCloud($0) }
        }
        guard host.hasPrefix("music.yandex.") else { return nil }
        func number(_ s: String) -> String? {
            !s.isEmpty && s.allSatisfy(\.isASCII) && s.allSatisfy(\.isNumber) ? s : nil
        }
        switch parts.count {
        case 4... where parts[0] == "album" && parts[2] == "track":
            return number(parts[3]).map { .ref("ym:\($0)") }
        case 2... where parts[0] == "track":
            return number(parts[1]).map { .ref("ym:\($0)") }
        case 2... where parts[0] == "album":
            return number(parts[1]).map { .ref("ymalb:\($0)") }
        case 2... where parts[0] == "artist":
            return number(parts[1]).map { .ref("yma:\($0)") }
        case 4... where parts[0] == "users" && parts[2] == "playlists":
            return number(parts[3]).map { .ref("ympl:\(parts[1]):\($0)") }
        default:
            return nil
        }
    }
}
