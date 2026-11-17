import Foundation

/// Разбор текстов: LRC (lrclib, NetEase), YRC (пословный NetEase), обычный текст (plain lrclib, Genius).
/// Порт `parse_lrc` / `plain_lines` из `windows/src-tauri/src/lyrics/mod.rs` и `parse_yrc` из `netease.rs`.
enum LyricsParser {
    /// Последняя строка длится до конца трека, но не дольше 10 с.
    static let lastLineMax = 10.0

    private static let timeTag = Pattern(#"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)
    private static let wordTag = Pattern(#"<(\d+):(\d+(?:[.:]\d+)?)>"#)
    private static let offsetTag = Pattern(#"(?i)^\[offset:\s*([+-]?\d+)\s*\]"#)

    private static func seconds(_ m: String, _ s: String) -> Double {
        (Double(m) ?? 0) * 60 + (Double(s.replacingOccurrences(of: ":", with: ".")) ?? 0)
    }

    /// Строка целиком в скобках — бэк-вокал.
    static func isBackground(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.count > 2 && t.hasPrefix("(") && t.hasSuffix(")")
    }

    /// Черновое слово: конец ещё не известен (`end < 0`) — считается потом.
    private struct RawWord {
        var start: Double
        var end: Double
        var text: String
        var spaceAfter: Bool
    }

    private struct RawLine {
        var start: Double
        var text: String
        var words: [RawWord]
    }

    /// Слова enhanced-LRC (`<mm:ss.xx>слово`). Нет тегов — пустой список.
    private static func parseWords(_ raw: String, shift: Double) -> (String, [RawWord]) {
        let text = raw as NSString
        let tags = wordTag.matchRanges(raw)
        if tags.isEmpty { return (raw.trimmingCharacters(in: .whitespaces), []) }
        var words: [RawWord] = []
        for (i, tag) in tags.enumerated() {
            let whole = tag[0]
            let chunkStart = whole.location + whole.length
            let chunkEnd = i + 1 < tags.count ? tags[i + 1][0].location : text.length
            let chunk = text.substring(with: NSRange(location: chunkStart, length: chunkEnd - chunkStart))
            let body = chunk.trimmingCharacters(in: .whitespaces)
            let time = max(0, seconds(text.substring(with: tag[1]), text.substring(with: tag[2])) - shift)
            if body.isEmpty {
                // пустой тег в конце строки — конец последнего слова
                if !words.isEmpty { words[words.count - 1].end = max(time, words[words.count - 1].start) }
                continue
            }
            words.append(RawWord(start: time, end: -1, text: body, spaceAfter: chunk.hasSuffix(" ") || chunk.hasSuffix("\t")))
        }
        let joined = words.map { $0.spaceAfter ? $0.text + " " : $0.text }.joined().trimmingCharacters(in: .whitespaces)
        return (joined, words)
    }

    /// LRC → строки по времени (LYRICS.md §1): несколько таймкодов на строку, `[offset:±ms]`,
    /// пустые строки — паузы, строки в `( )` — бэк-вокал, слова из enhanced-LRC.
    /// `trackLength` — длительность трека в секундах (для последней строки), 0 — неизвестна.
    static func parseLRC(_ source: String, trackLength: Double) -> [LyricLine] {
        var shift = 0.0
        var lines: [RawLine] = []
        for rawLine in source.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let raw = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if let offset = offsetTag.firstCapture(raw.trimmingCharacters(in: .whitespaces)) {
                // положительный offset в LRC — текст раньше
                shift = (Double(offset.value) ?? 0) / 1000
                continue
            }
            let text = raw as NSString
            // теги должны идти подряд с начала строки
            var end = 0
            var times: [Double] = []
            for tag in timeTag.matchRanges(raw) {
                let gap = text.substring(with: NSRange(location: end, length: tag[0].location - end))
                guard gap.trimmingCharacters(in: .whitespaces).isEmpty else { break }
                end = tag[0].location + tag[0].length
                times.append(seconds(text.substring(with: tag[1]), text.substring(with: tag[2])))
            }
            if times.isEmpty { continue }
            let (body, words) = parseWords(text.substring(from: end), shift: shift)
            for t in times {
                let time = max(0, t - shift)
                // у повтора строки (несколько таймкодов) слова сдвигаются вместе с ней
                let base = words.first?.start ?? time
                let moved = words.map { word in
                    var w = word
                    w.start = time + max(0, word.start - base)
                    if word.end >= 0 { w.end = time + max(0, word.end - base) }
                    return w
                }
                lines.append(RawLine(start: time, text: body, words: moved))
            }
        }
        // как sort_by в Rust — устойчиво
        lines = lines.enumerated().sorted { a, b in a.element.start != b.element.start ? a.element.start < b.element.start : a.offset < b.offset }.map(\.element)
        // подряд идущие пустые строки — одна пауза
        var merged: [RawLine] = []
        for line in lines {
            if line.text.isEmpty, merged.last?.text.isEmpty == true { continue }
            merged.append(line)
        }
        var out = finish(merged, trackLength: trackLength)
        // пустые строки в начале не нужны: до первой строки и так «•••»
        while out.first?.text.isEmpty == true { out.removeFirst() }
        return out.enumerated().map { index, line in
            var line = line
            line.id = index
            return line
        }
    }

    /// Концы строк и слов: строка — до следующей (последняя — до конца трека, ≤ 10 с), слово без
    /// конца — до следующего слова или конца строки.
    private static func finish(_ lines: [RawLine], trackLength: Double) -> [LyricLine] {
        var out: [LyricLine] = []
        for (i, line) in lines.enumerated() {
            let end: Double
            if i + 1 < lines.count { end = lines[i + 1].start }
            else if trackLength > line.start { end = min(line.start + lastLineMax, trackLength) }
            else { end = line.start + lastLineMax }
            let lineEnd = max(end, line.start)
            var words: [LyricWord] = []
            for (j, w) in line.words.enumerated() {
                var wordEnd = w.end
                if wordEnd < 0 { wordEnd = j + 1 < line.words.count ? line.words[j + 1].start : lineEnd }
                words.append(LyricWord(start: w.start, end: max(wordEnd, w.start), text: w.text,
                                       spaceAfter: j + 1 < line.words.count && w.spaceAfter, isBackground: isBackground(w.text)))
            }
            out.append(LyricLine(id: i, start: line.start, end: lineEnd, text: line.text, words: words, isBackground: isBackground(line.text)))
        }
        return out
    }

    /// Обычный текст (plain из lrclib, Genius) — строки без таймкодов; подряд пустые — одна.
    static func plainLines(_ text: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty, out.last.map({ $0.text.isEmpty }) ?? true { continue }
            out.append(LyricLine(id: out.count, start: 0, end: 0, text: t, words: [], isBackground: isBackground(t)))
        }
        while out.last?.text.isEmpty == true { out.removeLast() }
        return out
    }

    // MARK: - NetEase YRC

    /// Строки-титры NetEase (автор слов, музыки, аранжировка…) — не текст песни.
    static func isCredit(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        let keys = ["作词", "作曲", "编曲", "制作", "混音", "母带", "录音", "和声", "吉他", "贝斯", "鼓", "监制", "出品", "发行"]
        return keys.contains { t.hasPrefix($0) && (t.contains(":") || t.contains("：")) }
    }

    /// YRC → строки со словами: `[начало,длит](начало_слова,длит,0)слово…`, миллисекунды.
    /// Строки-метаданные (`{"t":…}`) и титры пропускаются.
    static func parseYRC(_ source: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for rawLine in source.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let raw = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.hasPrefix("["), let close = raw.firstIndex(of: "]") else { continue }
            let head = raw[raw.index(after: raw.startIndex) ..< close].split(separator: ",", omittingEmptySubsequences: false)
            guard head.count >= 2, let start = Double(head[0]), let duration = Double(head[1]) else { continue }
            var words: [LyricWord] = []
            var rest = raw[raw.index(after: close)...]
            while let open = rest.firstIndex(of: "(") {
                guard let end = rest[open...].firstIndex(of: ")") else { break }
                let tag = rest[rest.index(after: open) ..< end].split(separator: ",", omittingEmptySubsequences: false)
                let after = rest[rest.index(after: end)...]
                let next = after.firstIndex(of: "(") ?? after.endIndex
                let chunk = after[..<next]
                if tag.count >= 2, let ws = Double(tag[0]), let wd = Double(tag[1]) {
                    let w = chunk.trimmingCharacters(in: .whitespaces)
                    if !w.isEmpty {
                        words.append(LyricWord(start: ws / 1000, end: (ws + max(0, wd)) / 1000, text: w,
                                               spaceAfter: chunk.hasSuffix(" "), isBackground: false))
                    }
                }
                rest = after[next...]
            }
            let text = words.map { $0.spaceAfter ? $0.text + " " : $0.text }.joined().trimmingCharacters(in: .whitespaces)
            if text.isEmpty || isCredit(text) { continue }
            if !words.isEmpty { words[words.count - 1].spaceAfter = false }
            out.append(LyricLine(id: 0, start: start / 1000, end: (start + max(0, duration)) / 1000, text: text, words: words,
                                 isBackground: text.hasPrefix("(") && text.hasSuffix(")")))
        }
        return out.enumerated().sorted { a, b in a.element.start != b.element.start ? a.element.start < b.element.start : a.offset < b.offset }
            .enumerated().map { index, pair in
                var line = pair.element
                line.id = index
                return line
            }
    }
}
