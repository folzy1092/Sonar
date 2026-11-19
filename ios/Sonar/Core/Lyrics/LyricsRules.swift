import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Правила поиска текста — порт `windows/src-tauri/src/lyrics/rules.rs` (docs/POLISH_PROMPT.md п. 7,
// docs/TITLE_SPLIT.md): словарь «артист-трек», перезаливщики, ручные пары на трек и игнор. До сервера —
// файл `updates/lyrics-rules.json` из репо: вшитые значения по умолчанию, файл перечитывается раз в сутки
// (не вышло — через час). Здесь же — память промахов по вариантам перезалива.

/// Ручная пара на трек: искать текст по ней вместо всех шагов.
struct ManualPair: Decodable, Equatable, Sendable {
    var artist: String
    var title: String
    /// Показывать трек под этой парой (для будущего показа перезаливов).
    var display: Bool

    init(artist: String, title: String, display: Bool = false) {
        self.artist = artist
        self.title = title
        self.display = display
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(artist: try c.decode(String.self, forKey: .artist), title: try c.decode(String.self, forKey: .title),
                  display: try c.decodeIfPresent(Bool.self, forKey: .display) ?? false)
    }

    private enum CodingKeys: String, CodingKey { case artist, title, display }
}

/// Готовые к поиску правила.
struct LyricsRuleSet: Sendable {
    /// Больше записей в файле не берём — защита от битого файла.
    static let maxEntries = 5000

    var dash: DashArtists = .standard
    private var reuploaders: Set<String> = []
    private var pairs: [String: ManualPair] = [:]
    private var ignore: Set<String> = []

    init() {}

    /// Содержимое `lyrics-rules.json`; незнакомые поля (`about`) — мимо.
    private struct File: Decodable {
        var dash_artists: [String]?
        var reuploaders: [String]?
        var pairs: [String: ManualPair]?
        var ignore: [String]?
    }

    /// Разобрать файл правил; битый или слишком большой — `nil`.
    static func parse(_ data: Data) -> LyricsRuleSet? {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        let sizes = [file.dash_artists?.count ?? 0, file.reuploaders?.count ?? 0, file.pairs?.count ?? 0, file.ignore?.count ?? 0]
        guard sizes.allSatisfy({ $0 <= maxEntries }) else { return nil }
        func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var rules = LyricsRuleSet()
        rules.dash = DashArtists.fromLoaded(file.dash_artists)
        rules.reuploaders = Set((file.reuploaders ?? []).map(TrackText.norm).filter { !$0.isEmpty })
        for (key, pair) in file.pairs ?? [:] where !blank(key) && !blank(pair.artist) && !blank(pair.title) {
            rules.pairs[key.trimmingCharacters(in: .whitespacesAndNewlines)] = pair
        }
        rules.ignore = Set((file.ignore ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return rules
    }

    static func parse(_ json: String) -> LyricsRuleSet? { parse(Data(json.utf8)) }

    /// Залившего этого трека нет смысла считать артистом — разбор «артист - трек» идёт первым.
    func isReuploader(_ artist: String) -> Bool {
        let n = TrackText.norm(artist)
        return !n.isEmpty && reuploaders.contains(n)
    }

    func pair(_ key: String) -> ManualPair? { pairs[key] }

    /// Текста у трека точно нет — не искать.
    func isIgnored(_ key: String) -> Bool { ignore.contains(key) }
}

/// Правила сейчас, их обновление из репо и промахи по вариантам перезалива этого запуска.
actor LyricsRules {
    static let shared = LyricsRules(remote: URL(string: "https://raw.githubusercontent.com/folzy1092/Sonar/main/updates/lyrics-rules.json"))

    /// Перечитывать файл правил раз в сутки…
    static let refreshEvery: Duration = .seconds(24 * 3600)
    /// …а не вышло — через час.
    static let retryAfter: Duration = .seconds(3600)
    static let fetchTimeout: TimeInterval = 10
    /// Промах по вариантам перезалива помнится столько.
    static let variantRecheck: Duration = .seconds(6 * 3600)

    private let remote: URL?
    private(set) var current: LyricsRuleSet
    /// Когда перечитывать файл; `nil` — ещё ни разу.
    private var nextCheck: ContinuousClock.Instant?
    /// Ключ трека → до какого момента варианты перезалива не пробовать.
    private var misses: [String: ContinuousClock.Instant] = [:]

    /// `remote == nil` — без сети (тесты).
    init(remote: URL?, rules: LyricsRuleSet = LyricsRuleSet()) {
        self.remote = remote
        current = rules
    }

    /// Перечитать файл правил, если пора. Сбой — в журнал, правила остаются прежними.
    func refreshIfDue(transport: LyricsTransport) async {
        guard let remote else { return }
        let now = ContinuousClock.now
        if let nextCheck, now < nextCheck { return }
        nextCheck = now + Self.retryAfter // пока идёт запрос, второй не начинаем
        var request = URLRequest(url: remote, timeoutInterval: Self.fetchTimeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let response = try await transport.send(request)
            guard (200 ..< 300).contains(response.status) else { throw LyricsSourceError(status: response.status, message: "HTTP \(response.status)") }
            guard let rules = LyricsRuleSet.parse(response.body) else { throw LyricsSourceError(status: response.status, message: "файл не разобрать") }
            current = rules
            nextCheck = ContinuousClock.now + Self.refreshEvery
        } catch {
            CrashLog.warn("тексты: файл правил недоступен — \(error.localizedDescription)")
            nextCheck = ContinuousClock.now + Self.retryAfter
        }
    }

    /// Промах ещё помнится.
    func missIsFresh(_ key: String, now: ContinuousClock.Instant) -> Bool {
        misses[key].map { now < $0 } ?? false
    }

    func rememberMiss(_ key: String, now: ContinuousClock.Instant) {
        misses = misses.filter { now < $0.value }
        misses[key] = now + Self.variantRecheck
    }

    /// Ручная перепроверка трека — пробовать варианты снова.
    func forgetMiss(_ key: String) {
        misses[key] = nil
    }
}
