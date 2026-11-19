import Foundation

/// Названия и исполнители: очистка от мусора SoundCloud, сравнение. Порт `windows/src-tauri/src/lyrics/mod.rs`
/// («названия и исполнители») — им пользуются поиск текста и сопоставление трека с Яндексом.
enum TrackText {
    /// «(prod. …)», «[Official Video]», «feat. …» мешают найти трек.
    static let titleNoise = Pattern(#"(?i)\s*[(\[][^)\]]*(?:prod|feat|ft\.|official|video|audio|lyric|remaster)[^)\]]*[)\]]|\s+(?:feat|ft)\.?\s.*$"#)
    /// «A, B», «A & B», «A x B», «A feat. B», «A и B» — несколько артистов.
    static let artistSplit = Pattern(#"(?i)\s*,\s*|\s+(?:&|feat\.?|ft\.?|x\+?|\+|×|и|and|with|w/)\s+"#)
    static let anyBrackets = Pattern(#"\s*[(\[][^)\]]*[)\]]"#)
    static let featCredit = Pattern(#"(?i)\b(?:feat|ft)\b\.?\s+([^()\[\],&+]+)"#)
    static let featSplit = Pattern(#"(?i)\s+(?:\+|&|w/|feat\.?|ft\.?)\s*"#)
    static let featHead = Pattern(#"(?i)^(?:\+|&|w/|feat\.?|ft\.?)\s*(\S+)\s+"#)
    static let emoticon = Pattern(#"^(?:[:;=8][-'^]?[()\[\]DdPpOo3|/*]+|<3+|x[Dd]+|\^[_.-]?\^|T_T)$"#)

    static func cleanTitle(_ title: String) -> String {
        titleNoise.replaceAll(title, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstArtist(_ artist: String) -> String {
        (artistSplit.split(artist).first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// «Big Baby Tape, Kizaru» → [«Big Baby Tape, Kizaru», «Big Baby Tape»]: в lrclib чаще только первый.
    static func artistVariants(_ artist: String) -> [String] {
        var out = [artist.trimmingCharacters(in: .whitespacesAndNewlines)]
        let first = firstArtist(artist)
        if !first.isEmpty, first != out[0] { out.append(first) }
        return out.filter { !$0.isEmpty }
    }

    private static func isPictograph(_ scalar: Unicode.Scalar) -> Bool {
        let u = scalar.value
        return (0x1F000...0x1FAFF).contains(u) || (0x2190...0x2BFF).contains(u) || (0x2600...0x27BF).contains(u) || u == 0xFE0F || u == 0x200D
    }

    /// Как `char::is_alphanumeric` в Rust: буква (Alphabetic) или цифра (Numeric).
    static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    /// Название без мусора SoundCloud: (ключевые слова, ядро без фитов, фиты).
    /// «+ elox1m PAGER =( #2016» → («elox1m PAGER», «PAGER», [«elox1m»]).
    static func keywordTitle(_ title: String) -> (keywords: String, core: String, feats: [String]) {
        var feats = featCredit.captures(title).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var scalars = String.UnicodeScalarView()
        for scalar in anyBrackets.replaceAll(title, with: " ").unicodeScalars {
            scalars.append(isPictograph(scalar) ? " " : scalar)
        }
        let cleaned = titleNoise.replaceAll(String(scalars), with: " ")
        let words = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { word in
            !word.hasPrefix("#") && !word.hasPrefix("@") && !emoticon.matches(word)
        }.filter { word in
            word.unicodeScalars.contains(where: isAlphanumeric) || ["+", "&", "w/"].contains(word)
        }
        let text = words.joined(separator: " ")
        var core = text
        if let head = featHead.firstCapture(text) {
            feats.append(head.value)
            core = (text as NSString).substring(from: head.end)
        }
        let parts = featSplit.split(core)
        if parts.count > 1, !parts[0].trimmingCharacters(in: .whitespaces).isEmpty {
            feats.append(contentsOf: parts.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            core = parts[0]
        }
        core = core.trimmingCharacters(in: CharacterSet(charactersIn: "+&").union(.whitespacesAndNewlines))
        let keywords = words.filter { !["+", "&", "w/"].contains($0) }.joined(separator: " ")
        return (keywords, core, feats)
    }

    /// Для сравнения: нижний регистр, без знаков, ё → е.
    static func norm(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in s.lowercased().replacingOccurrences(of: "ё", with: "е").unicodeScalars where isAlphanumeric(scalar) {
            out.append(scalar)
        }
        return String(out)
    }

    /// Похожесть строк 0…1 (как difflib.ratio: 2·совпадения / сумма длин, через LCS).
    static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a.unicodeScalars)
        let b = Array(b.unicodeScalars)
        if a.isEmpty, b.isEmpty { return 1 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var current = [Int](repeating: 0, count: b.count + 1)
            for (j, y) in b.enumerated() {
                current[j + 1] = x == y ? previous[j] + 1 : max(previous[j + 1], current[j])
            }
            previous = current
        }
        return 2 * Double(previous[b.count]) / Double(a.count + b.count)
    }
}
