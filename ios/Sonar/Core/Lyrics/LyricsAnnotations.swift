import Foundation

/// Аннотации Genius к строкам текста (порт `windows/src/lyrics/core/annotations.ts`): каждая строка
/// фрагмента, который выделен на Genius, получает свою аннотацию. Сопоставление — по похожести строк:
/// регистр, знаки, скобки бэк-вокала и лишние пробелы не важны.
enum LyricsAnnotations {
    private static let brackets = Pattern(#"\([^)]*\)|\[[^\]]*\]"#)
    private static let nonWord = Pattern(#"[^\p{L}\p{N}]+"#)

    /// Строка для сравнения: нижний регистр, без скобок с бэк-вокалом, только буквы и цифры.
    static func key(_ s: String) -> String {
        nonWord.replaceAll(brackets.replaceAll(s.lowercased(), with: " "), with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Похожесть строк 0…1 по общим словам (Дайс), чтобы «леса (Леса)» и «леса» совпали.
    static func likeness(_ a: String, _ b: String) -> Double {
        let wa = key(a).split(separator: " ").map(String.init)
        let wb = key(b).split(separator: " ").map(String.init)
        guard !wa.isEmpty, !wb.isEmpty else { return 0 }
        var rest = wb
        var common = 0
        for w in wa {
            if let i = rest.firstIndex(of: w) {
                common += 1
                rest.remove(at: i)
            }
        }
        return 2 * Double(common) / Double(wa.count + wb.count)
    }

    /// Номер строки текста → аннотация. Каждая строка фрагмента ищет лучшую строку текста (> 0.7),
    /// идя по порядку (фрагмент — подряд идущие строки, поэтому поиск следующей начинается дальше).
    static func map(_ lines: [String], _ annotations: [LyricsAnnotation]) -> [Int: LyricsAnnotation] {
        var out: [Int: LyricsAnnotation] = [:]
        for annotation in annotations {
            var from = 0
            for fragment in annotation.lines {
                var best = -1
                var score = 0.7
                var i = from
                while i < lines.count {
                    let s = likeness(fragment, lines[i])
                    if s > score {
                        score = s
                        best = i
                        if s == 1 { break }
                    }
                    i += 1
                }
                if best >= 0 {
                    if out[best] == nil { out[best] = annotation }
                    from = best + 1
                }
            }
        }
        return out
    }
}
