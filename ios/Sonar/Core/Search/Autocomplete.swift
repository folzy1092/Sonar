import Foundation

// Подсказка-дописывание в поиске: набрал «Onda» — под полем чип «Onda Andar ↗». Порт Windows
// `windows/src/lib/autocomplete.ts` (те же источники, приоритет и раскладки). Кандидаты — только то, что уже
// есть у пользователя: артисты Любимых → история поиска → недавнее. Без сети, на каждую букву — поиск по
// готовому списку. Тесты — `SonarTests/AutocompleteTests.swift`.
enum Autocomplete {
    /// Подсказку показываем от стольких набранных символов.
    static let minTyped = 2
    /// Кандидат длиннее — пропускаем.
    static let maxCandidate = 60

    struct Suggestion: Equatable, Sendable {
        /// Кандидат целиком, в регистре оригинала — им заменяется текст при принятии.
        var full: String
        /// Что дописать после набранного. При другой раскладке — пусто (показываем `full`).
        var tail: String
        /// Набрано в другой раскладке: «щтвф» → «Onda Andar»; при принятии заменяется весь текст.
        var relayout: Bool
    }

    // MARK: кандидаты

    private static func artistNames(_ track: Track) -> [String] {
        let names = track.artists.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? [track.artist] : names
    }

    /// Артисты Любимых: у кого больше лайкнутых треков — выше; при равенстве — кто раньше в списке.
    static func likedArtists(_ liked: [Track]) -> [String] {
        var counts: [String: (name: String, n: Int, first: Int)] = [:]
        for (index, track) in liked.enumerated() {
            for raw in artistNames(track) {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = name.lowercased()
                guard !key.isEmpty else { continue }
                let was = counts[key]
                counts[key] = (was?.name ?? name, (was?.n ?? 0) + 1, was?.first ?? index)
            }
        }
        return counts.values
            .sorted { $0.n != $1.n ? $0.n > $1.n : $0.first < $1.first }
            .map(\.name)
    }

    /// Один список по приоритету: Любимые → история поиска → недавнее (новые первыми). Без дублей (регистр
    /// не важен), без пустых и длиннее `maxCandidate`.
    static func candidates(liked: [Track], history: [String], recent: [Track]) -> [String] {
        let all = likedArtists(liked) + history + recent.flatMap { artistNames($0) + [$0.title] }
        var seen = Set<String>()
        var out: [String] = []
        for raw in all {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = text.lowercased()
            guard !text.isEmpty, text.count <= maxCandidate, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(text)
        }
        return out
    }

    // MARK: подсказка

    private static func firstStarting(_ candidates: [String], with typed: String) -> String? {
        let query = typed.lowercased()
        return candidates.first { $0.count > typed.count && $0.lowercased().hasPrefix(query) }
    }

    /// Подсказка к набранному: только по началу всей строки. Сначала прямо, потом в других раскладках.
    static func suggest(_ candidates: [String], typed: String) -> Suggestion? {
        guard typed.trimmingCharacters(in: .whitespacesAndNewlines).count >= minTyped else { return nil }
        if let direct = firstStarting(candidates, with: typed) {
            return Suggestion(full: direct, tail: String(direct.dropFirst(typed.count)), relayout: false)
        }
        for alt in [Layout.cyrToEn(typed), Layout.enToRu(typed), Layout.enToUk(typed)] where alt != typed.lowercased() {
            if let hit = firstStarting(candidates, with: alt) {
                return Suggestion(full: hit, tail: "", relayout: true)
            }
        }
        return nil
    }

    // MARK: раскладка

    /// ЙЦУКЕН ↔ QWERTY, как `quick-core.ts`: русская, украинская (і ї є, ґ — на клавише г) и обратно.
    enum Layout {
        private static let en = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,.")
        private static let ru = Array("ёйцукенгшщзхъфывапролджэячсмитьбю")
        private static let uk = Array("'йцукенгшщзхїфівапролджєячсмитьбю")

        private static func map(_ from: [Character], _ to: [Character]) -> [Character: Character] {
            Dictionary(zip(from, to), uniquingKeysWith: { first, _ in first })
        }

        private static let enRu = map(en, ru)
        private static let enUk = map(en, uk)
        // русские буквы перекрывают украинские на общих клавишах — как в Windows (они совпадают)
        private static let cyrEn = map(uk, en).merging(map(ru, en)) { _, ru in ru }.merging(["ґ": "u"]) { _, g in g }

        private static func convert(_ text: String, _ table: [Character: Character]) -> String {
            String(text.lowercased().map { table[$0] ?? $0 })
        }

        /// `ghbdtn` → `привет`.
        static func enToRu(_ text: String) -> String { convert(text, enRu) }
        /// `ghbdsn` → `привіт`.
        static func enToUk(_ text: String) -> String { convert(text, enUk) }
        /// `руддщ` → `hello`.
        static func cyrToEn(_ text: String) -> String { convert(text, cyrEn) }
    }
}
