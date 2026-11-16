import Foundation

/// Регулярное выражение для разбора названий и ссылок — те же шаблоны, что в Rust-клиенте
/// (`regex` крейт), через NSRegularExpression (ICU понимает `(?i)`, `\p{L}`, `\b` так же).
/// Неизменяемое после создания — можно держать в `static let`.
final class Pattern: @unchecked Sendable {
    private let regex: NSRegularExpression

    init(_ pattern: String) {
        // шаблоны — константы в коде: ошибка в них — ошибка программиста, тесты её поймают
        regex = try! NSRegularExpression(pattern: pattern)
    }

    private func all(_ s: String) -> [NSTextCheckingResult] {
        regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
    }

    /// Есть ли совпадение где-нибудь в строке (как `is_match`).
    func matches(_ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    func replaceAll(_ s: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: NSRegularExpression.escapedTemplate(for: template))
    }

    /// Куски между совпадениями, как `Regex::split` (пустые края сохраняются). limit — не больше кусков.
    func split(_ s: String, limit: Int = .max) -> [String] {
        let text = s as NSString
        var out: [String] = []
        var start = 0
        for match in all(s) {
            if out.count == limit - 1 { break }
            out.append(text.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = match.range.location + match.range.length
        }
        out.append(text.substring(from: start))
        return out
    }

    /// Все совпадения целиком.
    func findAll(_ s: String) -> [String] {
        let text = s as NSString
        return all(s).map { text.substring(with: $0.range) }
    }

    /// Группа `group` каждого совпадения.
    func captures(_ s: String, group: Int = 1) -> [String] {
        let text = s as NSString
        return all(s).compactMap { match in
            let range = match.range(at: group)
            return range.location == NSNotFound ? nil : text.substring(with: range)
        }
    }

    /// Первое совпадение: группа `group` и где кончается совпадение (в UTF-16, для хвоста строки).
    func firstCapture(_ s: String, group: Int = 1) -> (value: String, end: Int)? {
        guard let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        let range = match.range(at: group)
        guard range.location != NSNotFound else { return nil }
        return ((s as NSString).substring(with: range), match.range.location + match.range.length)
    }
}
