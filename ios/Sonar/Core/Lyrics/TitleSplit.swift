import Foundation

/// Пара «исполнитель — название» для поиска текста.
struct TitlePair: Hashable, Sendable {
    var artist: String
    var title: String

    init(_ artist: String, _ title: String) {
        self.artist = artist
        self.title = title
    }
}

/// Словарь «артист-дефис» (docs/TITLE_SPLIT.md): у этих имён «ИМЯ-трек» без пробелов — тоже разделитель.
/// Порт `DashArtists` из `windows/src-tauri/src/lyrics/title_split.rs`.
struct DashArtists: Sendable {
    static let defaultNames = ["cowboyclicker"]
    static let standard = DashArtists(defaultNames)

    /// Имена после нормализации: длинные первыми, чтобы «jay-z» не съел «jay».
    let names: [String]
    private let patterns: [Pattern]

    init(_ raw: some Sequence<String>) {
        var list: [String] = []
        for name in raw.compactMap(TitleSplit.normalizeDashName) where !list.contains(name) {
            list.append(name)
        }
        list.sort { a, b in
            let (la, lb) = (a.unicodeScalars.count, b.unicodeScalars.count)
            return la != lb ? la > lb : a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars)
        }
        names = list
        patterns = list.map { name in
            Pattern(#"(?i)^\s*("# + NSRegularExpression.escapedPattern(for: name) + #")\s*["# + TitleSplit.dashSet + #"]\s*(\S.*)$"#)
        }
    }

    /// Нет поля в файле правил — словарь по умолчанию; пустой список — словарь пуст.
    static func fromLoaded(_ loaded: [String]?) -> DashArtists {
        loaded.map { DashArtists($0) } ?? .standard
    }

    /// «cowboyclicker-трек» → «cowboyclicker - трек»; не из словаря — как есть.
    func compact(_ title: String) -> String {
        let text = title as NSString
        for pattern in patterns {
            if let groups = pattern.matchRanges(title).first {
                return "\(text.substring(with: groups[1])) - \(text.substring(with: groups[2]))"
            }
        }
        return title
    }
}

/// Перезаливы SoundCloud: «АРТИСТ - ТРЕК» в названии у чужого «исполнителя» (docs/TITLE_SPLIT.md).
/// Порт `windows/src-tauri/src/lyrics/title_split.rs` — те же шаблоны, слова и порядок вариантов.
enum TitleSplit {
    static let maxVariants = 4
    private static let dashNameMax = 40
    private static let cleanRounds = 8
    private static let swapNameMax = 40
    private static let swapWordsMax = 4
    private static let artistMax = 60
    private static let artistWordsMax = 6
    private static let slashPartMin = 3

    private static let dashChars: Set<Character> = ["-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}"]
    /// Дефис и тире — содержимое `[...]` в шаблоне.
    static let dashSet = #"\-\x{2010}\x{2011}\x{2012}\x{2013}\x{2014}\x{2015}\x{2212}"#

    private static func re(_ pattern: String) -> Pattern {
        Pattern(pattern.replacingOccurrences(of: "{DASH}", with: dashSet))
    }

    private static let separator = re(#"\s+[{DASH}]\s+"#)
    private static let collab = re(#"(?i)^[+@]|\s+(?:x\+?|\+|×|feat\.?|ft\.?)\s+|,\s"#)
    private static let leadMarks = re(#"^[\s+@~#*]+"#)
    private static let trailingGroup = re(#"\s*(?:\([^()]*\)|\[[^\[\]]*\]|\{[^\{\}]*\}|\*\*[^*]*\*\*)\s*$"#)
    private static let anyStars = re(#"\s*\*\*[^*]*\*\*"#)
    private static let spacedCompact = re(#"^([^{DASH}]*,[^{DASH}]*)[{DASH}](\S.*)$"#)
    private static let labelHead = re(#"^[\s(\[]*(?:feat|ft|featuring|prod|produced)\b"#)
    private static let labelNumber = re(#"^(?:(?:19[5-9]|20[0-3])\d|v\d+)$"#)
    private static let word = re(#"[^\W_]+"#)

    private static let titleTails: [Pattern] = [
        #"(?i)\.(?:mp3|мп3|wav|flac|m4a)\s*$"#,
        #"(?i)\s+prod(?:uced)?\b.*$"#,
        #"(?i)\s+p/\S.*$"#,
        #"(?i)\s+(?:feat|ft)\.?\s.*$"#,
        #"(?i)\s+\+.*$"#,
        #"(?i)\s*#\S*(?:\s+#\S*)*\s*$"#,
        #"(?i)\s+@\S+\s*$"#,
        #"(?i)\s+archive\s*$"#,
        #"(?i)\s+\d+\s*(?:й|-й|st|nd|rd|th)?\s*(?:парт|part)\w*\s*$"#,
        #"(?i)\s+tiktok\s+remix\s*$"#,
        #"(?i)\s+(?:speed(?:ed)?|sped|slowed|nightcore)(?:\s+(?:up|down|x\s+mix|mix|\+\s*reverb|and\s+reverb))*\s*$"#,
    ].map(re)

    private static let leadTags: Set<String> = [
        "remix", "official", "new", "exclusive", "unreleased", "leak", "leaked", "snippet", "preview", "premiere", "free",
        "mashup", "full", "tiktok remix",
    ]

    private static let labelWords: Set<String> = [
        "live", "edition", "remaster", "remastered", "remasters", "remix", "rmx", "edit", "edited", "radio", "acoustic",
        "version", "ver", "instrumental", "demo", "slowed", "sped", "speed", "up", "down", "nightcore", "reverb", "reverbed",
        "mix", "extended", "original", "deluxe", "bonus", "mono", "stereo", "explicit", "clean", "reprise", "unplugged",
        "session", "sessions", "cover", "official", "audio", "video", "lyric", "lyrics", "hq", "hd", "and", "x", "mixed",
        "bass", "boosted", "ремикс", "ремастер", "ремастеринг", "слоуд", "слоу", "замедленная", "замедленный", "ускоренная",
        "ускоренный", "версия", "акустика", "акустическая", "живое", "лайв", "инструментал", "демо", "оригинал", "радио",
        "эдит", "спид", "ап", "найткор", "реверб", "микс", "и",
    ]

    private enum Kind { case split, swap }
    private struct Variant {
        let artist: String
        let title: String
        let kind: Kind
    }

    // MARK: - мелочи

    private static func trimmed(_ s: some StringProtocol) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func length(_ s: String) -> Int { s.unicodeScalars.count }

    private static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: \.isWhitespace).count
    }

    /// Пробелы схлопнуты, нижний регистр — для сравнения имён.
    static func fold(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func letters(_ s: String) -> Int {
        s.unicodeScalars.filter(\.properties.isAlphabetic).count
    }

    /// Строка из словаря «артист-дефис» → имя для сравнения, мусор — `nil`.
    static func normalizeDashName(_ raw: String) -> String? {
        let text = trimmed(raw)
        if text.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) { return nil }
        let name = fold(String(text.drop(while: { $0 == "@" })))
        let alnum = name.unicodeScalars.filter(TrackText.isAlphanumeric).count
        return alnum >= 2 && length(name) <= dashNameMax ? name : nil
    }

    /// Пометка вместо названия: «Live», «2011 Remaster», «Radio Edit», «feat. X», «Слоуд».
    static func isLabel(_ text: String) -> Bool {
        let t = text.lowercased().replacingOccurrences(of: "(ed)", with: "ed")
        if labelHead.matches(t) { return true }
        let words = word.findAll(t)
        return !words.isEmpty && words.allSatisfy { labelWords.contains($0) || labelNumber.matches($0) }
    }

    private static func stripLabelTail(_ text: String) -> String {
        guard let last = separator.matchRanges(text).last?.first else { return text }
        let ns = text as NSString
        let tail = ns.substring(from: last.location + last.length)
        return isLabel(tail) ? ns.substring(to: last.location) : text
    }

    /// Чистка не может оставить пустоту — тогда прежнее.
    private static func keep(_ before: String, _ after: String) -> String {
        let after = trimmed(after)
        return after.isEmpty ? before : after
    }

    private static func trimEdges(_ s: String) -> String {
        let edge: (Character) -> Bool = { $0.isWhitespace || dashChars.contains($0) }
        guard let start = s.firstIndex(where: { !edge($0) }), let end = s.lastIndex(where: { !edge($0) }) else { return "" }
        return String(s[start ... end])
    }

    /// Название без хвостов SoundCloud: «(prod. …)», «.mp3», «#2016», «slowed + reverb», «- Radio Edit».
    static func cleanTitle(_ title: String) -> String {
        let original = trimmed(title)
        var cur = original
        for _ in 0 ..< cleanRounds {
            var next = keep(cur, anyStars.replaceAll(cur, with: ""))
            next = keep(next, trailingGroup.replaceFirst(next))
            for tail in titleTails {
                next = keep(next, tail.replaceFirst(next))
            }
            next = keep(next, stripLabelTail(next))
            next = keep(next, trimEdges(next))
            if next == cur { break }
            cur = next
        }
        return cur.isEmpty ? original : cur
    }

    /// Имя без «+», «@», «(…)» спереди и сзади; «ШИПЫ/ONDA ANDAR» → «ШИПЫ».
    static func cleanArtist(_ name: String) -> String {
        let name = trimmed(name)
        var s = keep(name, leadMarks.replaceFirst(name))
        s = keep(s, trailingGroup.replaceFirst(s))
        if s.contains("/") {
            let parts = s.split(separator: "/", omittingEmptySubsequences: false).map { trimmed($0) }
            if parts.allSatisfy({ length($0) >= slashPartMin }) { s = parts[0] }
        }
        return keep(s, leadMarks.replaceFirst(s))
    }

    private static func looksLikeArtist(_ name: String) -> Bool {
        !name.isEmpty && length(name) <= artistMax && wordCount(name) <= artistWordsMax
            && name.unicodeScalars.contains(where: TrackText.isAlphanumeric)
    }

    private static func isUploader(_ name: String, _ uploader: String) -> Bool {
        fold(name) == uploader || fold(TrackText.firstArtist(name)) == uploader
    }

    private static func usable(_ name: String, _ track: String) -> Bool {
        let clean = cleanTitle(track)
        return letters(name) >= 2 && letters(clean) >= 2 && !isLabel(track) && !isLabel(clean)
    }

    /// «A, B-трек» → «A, B - трек»: дефис без пробелов после списка через запятую.
    private static func spacedCompact(_ title: String) -> String {
        if separator.matches(title) { return title }
        guard let groups = spacedCompact.matchRanges(title).first else { return title }
        let ns = title as NSString
        let left = trimmed(ns.substring(with: groups[1]))
        let parts = left.split(separator: ",", omittingEmptySubsequences: false).map { trimmed($0) }
        guard parts.count >= 2, parts.allSatisfy({ length($0) >= 2 }) else { return title }
        return "\(left) - \(ns.substring(with: groups[2]))"
    }

    /// «REMIX - АРТИСТ - ТРЕК» → «АРТИСТ - ТРЕК»; заодно где разделители (UTF-16).
    private static func dropLeadTags(_ title: String) -> (String, [NSRange]) {
        var work = title
        while true {
            let spans = separator.matchRanges(work).map { $0[0] }
            let ns = work as NSString
            if spans.count >= 2, leadTags.contains(fold(ns.substring(to: spans[0].location))) {
                work = ns.substring(from: spans[0].location + spans[0].length)
                continue
            }
            return (work, spans)
        }
    }

    /// «ТРЕК - АРТИСТ»: только если справа — залившего или слева явный мусор названия.
    private static func swapVariant(artist: String, uploader: String, left: String, right: String) -> (Variant, Bool)? {
        if isUploader(left, uploader) || collab.matches(left) || isLabel(right) { return nil }
        var who = cleanArtist(cleanTitle(right))
        let byUploader = isUploader(who, uploader)
        let marked = cleanTitle(left) != left
        let fits = looksLikeArtist(who) && length(who) <= swapNameMax && wordCount(who) <= swapWordsMax
        guard fits, byUploader || marked else { return nil }
        if byUploader { who = artist }
        let track = cleanTitle(left)
        return usable(who, track) ? (Variant(artist: who, title: track, kind: .swap), byUploader) : nil
    }

    private static func collect(artist: String, title: String, dash: DashArtists) -> [Variant] {
        let artist = trimmed(artist)
        let title = trimmed(title)
        let (work, spans) = dropLeadTags(spacedCompact(dash.compact(title)))
        guard let first = spans.first, let last = spans.last else { return [] }
        let uploader = fold(artist)
        let ns = work as NSString
        var raw: [Variant] = [], clean: [Variant] = [], swapped: [Variant] = []
        var swappedFirst = false
        let cuts = first == last ? [first] : [first, last]
        for cut in cuts {
            let left = trimmed(ns.substring(to: cut.location))
            let right = trimmed(ns.substring(from: cut.location + cut.length))
            if left.isEmpty || right.isEmpty || isLabel(left) { continue }
            let who = fold(left) == uploader ? artist : cleanArtist(left)
            if looksLikeArtist(who), usable(who, right) {
                let tidy = cleanTitle(right)
                if tidy != right { clean.append(Variant(artist: who, title: tidy, kind: .split)) }
                raw.append(Variant(artist: who, title: right, kind: .split))
            }
            if spans.count == 1, let (pair, byUploader) = swapVariant(artist: artist, uploader: uploader, left: left, right: right) {
                swappedFirst = swappedFirst || byUploader
                swapped.append(pair)
            }
        }
        let ordered = swappedFirst ? swapped + raw + clean : raw + clean + swapped
        var seen: Set<[String]> = [[fold(artist), fold(title)]]
        return ordered.filter { seen.insert([fold($0.artist), fold($0.title)]).inserted }
    }

    /// До четырёх пар «настоящий артист — название» по названию перезалива, лучшая первой; без исходной пары.
    static func reuploadVariants(artist: String, title: String, dash: DashArtists = .standard) -> [TitlePair] {
        collect(artist: artist, title: title, dash: dash).prefix(maxVariants).map { TitlePair($0.artist, $0.title) }
    }

    /// Одна пара для NetEase и Genius: настоящий артист и чистое название, нет уверенности — исходная.
    static func searchPair(artist: String, title: String, dash: DashArtists = .standard) -> TitlePair {
        let original = TitlePair(artist, title)
        guard let best = collect(artist: artist, title: title, dash: dash).first else { return original }
        if best.kind == .swap, fold(best.artist) != fold(artist) { return original }
        return TitlePair(best.artist, cleanTitle(best.title))
    }
}
