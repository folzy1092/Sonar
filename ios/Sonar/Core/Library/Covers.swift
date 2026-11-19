import Foundation

/// Обложки для коллажа без повторов (docs/POLISH_PROMPT.md п. 1). Зеркало ПК — `windows/src/lib/covers.ts`
/// и `src-tauri/src/store/covers.rs`.
///
/// Повтор — тот же альбом, тот же адрес картинки после нормализации (без размера, схемы и `?…`) или, у
/// трека без альбома, тот же исполнитель + адрес. Идём по порядку и останавливаемся на четвёртой разной —
/// порядок стабильный. Итог: 4 разные → сетка 2×2; 1–3 → одна первая обложка; 0 → пусто (значок).
/// Сравнение по пикселям (perceptual hash) — потом, если повторы всё ещё будут видны.
enum Covers {
    /// Сколько обложек в сетке коллажа.
    static let collageSize = 4

    private static let sizePatterns: [(NSRegularExpression, String)] = [
        (#"-(t\d+x\d+|large|crop|original|small|tiny|badge|mini|medium)(\.\w+)$"#, "$2"),
        (#"/(%%|m?\d+x\d+)$"#, ""),
        (#"=(w\d+-h\d+|s\d+)[^/]*$"#, ""),
    ].map { pattern, template in
        // swiftlint:disable:next force_try
        (try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), template)
    }

    /// Адрес обложки без схемы, `?…`, `#…` и размера (SoundCloud, Яндекс, YouTube).
    static func key(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespaces)
        if let range = u.range(of: "://") {
            u = String(u[range.upperBound...])
        } else if u.hasPrefix("//") {
            u = String(u.dropFirst(2))
        }
        if let cut = u.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            u = String(u[..<cut])
        }
        for (regex, template) in sizePatterns {
            let range = NSRange(u.startIndex..., in: u)
            u = regex.stringByReplacingMatches(in: u, range: range, withTemplate: template)
        }
        return u.lowercased()
    }

    /// До `limit` разных обложек по порядку списка.
    static func distinct(_ tracks: [Track], limit: Int = collageSize) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for track in tracks {
            if out.count >= limit { break }
            guard let url = track.coverURL, !url.isEmpty else { continue }
            let urlKey = key(url)
            let keys: [String]
            if let album = track.album?.ref, !album.isEmpty {
                keys = ["u:\(urlKey)", "a:\(album)"]
            } else {
                let artist = track.artist.trimmingCharacters(in: .whitespaces).lowercased()
                keys = ["u:\(urlKey)", "p:\(artist)|\(urlKey)"]
            }
            if keys.contains(where: seen.contains) { continue }
            seen.formUnion(keys)
            out.append(url)
        }
        return out
    }

    /// Что рисовать: 4 разные — сетка, иначе одна первая обложка, или пусто.
    static func collage(_ tracks: [Track]) -> [String] {
        let covers = distinct(tracks)
        return covers.count >= collageSize ? covers : Array(covers.prefix(1))
    }
}
