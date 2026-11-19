import Foundation

// Порядок поиска текста — порт `windows/src-tauri/src/lyrics/search.rs` (docs/TITLE_SPLIT.md «Порядок
// поиска текста», как в selfbot `fetch_any`):
// 1. обычная пара в lrclib — как есть → ядро названия → ключевые слова;
// 2. только если синхронного нет — варианты перезалива `TitleSplit.reuploadVariants` по очереди (у
//    перезаливщика из правил — первыми); не нашлось ни по одному — промах на `LyricsRules.variantRecheck`,
//    сетевой сбой — не промах;
// 3. NetEase и Genius — по `TitleSplit.searchPair` (настоящий артист + чистое название);
// 4. нет синхронного нигде — простой текст из lrclib.
// Ручная пара из правил — вместо всех шагов; трек из «игнора» не ищется.

extension LyricsFinder {
    /// Пары для lrclib и одна пара для NetEase / Genius.
    struct Plan: Equatable {
        var normal: [TitlePair]
        var variants: [TitlePair]
        var variantsFirst: Bool
        var other: TitlePair
    }

    /// Пара без повторов (без учёта регистра и знаков).
    static func samePair(_ a: TitlePair, _ b: TitlePair) -> Bool {
        TrackText.norm(a.artist) == TrackText.norm(b.artist) && TrackText.norm(a.title) == TrackText.norm(b.title)
    }

    /// Как есть → ядро названия → ключевые слова, без повторов.
    static func attempts(artist: String, title: String) -> [TitlePair] {
        let keyword = TrackText.keywordTitle(title)
        var out: [TitlePair] = []
        for t in [title, keyword.core, keyword.keywords] {
            let pair = TitlePair(artist, t)
            if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !out.contains(where: { samePair($0, pair) }) {
                out.append(pair)
            }
        }
        return out
    }

    static func plan(_ query: LyricsQuery, rules: LyricsRuleSet, missFresh: Bool) -> Plan {
        if let manual = rules.pair(query.key) {
            return Plan(normal: attempts(artist: manual.artist, title: manual.title), variants: [], variantsFirst: false,
                        other: TitlePair(manual.artist, manual.title))
        }
        let normal = attempts(artist: query.artist, title: query.title)
        let variants = !query.key.isEmpty && missFresh ? [] :
            TitleSplit.reuploadVariants(artist: query.artist, title: query.title, dash: rules.dash)
            .filter { v in !normal.contains(where: { samePair($0, v) }) }
        return Plan(normal: normal, variants: variants, variantsFirst: rules.isReuploader(query.artist),
                    other: TitleSplit.searchPair(artist: query.artist, title: query.title, dash: rules.dash))
    }

    func find(_ query: LyricsQuery) async throws -> Lyrics? {
        if !query.key.isEmpty { await rules.refreshIfDue(transport: transport) }
        return try await find(query, now: .now)
    }

    /// Ручная перепроверка трека — варианты перезалива пробовать снова.
    func recheck(_ key: String) async {
        await rules.forgetMiss(key)
    }

    /// Найти текст. `nil` — текста нигде нет; ошибка — сеть не ответила (не кэшировать как «нет»).
    func find(_ query: LyricsQuery, now: ContinuousClock.Instant) async throws -> Lyrics? {
        let ruleSet = await rules.current
        if !query.key.isEmpty, ruleSet.isIgnored(query.key) { return nil }
        let missFresh = query.key.isEmpty ? false : await rules.missIsFresh(query.key, now: now)
        let plan = Self.plan(query, rules: ruleSet, missFresh: missFresh)
        let stages = plan.variantsFirst ? [(plan.variants, true), (plan.normal, false)] : [(plan.normal, false), (plan.variants, true)]

        var lrc = LrclibPass(lrclib: Lrclib(transport: transport), duration: query.duration)
        for (pairs, isVariant) in stages {
            if let (found, pair) = await lrc.tryPairs(pairs) {
                if isVariant { CrashLog.note("тексты: текст нашёлся по названию перезалива «\(pair.artist)» — «\(pair.title)»") }
                return found
            }
            if lrc.failed != nil { break }
            if isVariant, !pairs.isEmpty, !query.key.isEmpty { await rules.rememberMiss(query.key, now: now) }
        }

        let other = plan.other
        // lrclib синхронного не нашёл — NetEase (пословный YRC или построчный LRC); не ответил — дальше Genius
        if let found = try? await NetEase(transport: transport)
            .fetch(artist: TrackText.firstArtist(other.artist), title: TrackText.cleanTitle(other.title), duration: query.duration) {
            return found
        }

        do {
            if let text = try await Genius(transport: transport).text(artist: other.artist, title: other.title) {
                let lines = LyricsParser.plainLines(Genius.stripSections(text))
                if !lines.isEmpty { return Lyrics(lines: lines, synced: false, source: Lyrics.genius) }
            }
        } catch {
            if lrc.failed == nil, lrc.plain == nil { lrc.failed = error }
        }

        if let plain = lrc.plain {
            let lines = LyricsParser.plainLines(plain)
            if !lines.isEmpty { return Lyrics(lines: lines, synced: false, source: Lyrics.lrclib) }
        }
        if let failed = lrc.failed { throw failed }
        return nil
    }
}

/// Что lrclib уже дал: простой текст про запас и сбой сети.
private struct LrclibPass {
    let lrclib: Lrclib
    let duration: Double
    var plain: String?
    var failed: Error?

    init(lrclib: Lrclib, duration: Double) {
        self.lrclib = lrclib
        self.duration = duration
    }

    /// Синхронный текст по первой подходящей паре и сама пара. Сбой сети — `failed`, дальше не спрашиваем.
    mutating func tryPairs(_ pairs: [TitlePair]) async -> (Lyrics, TitlePair)? {
        for pair in pairs {
            do {
                let found = try await lrclib.fetch(artist: pair.artist, title: pair.title, duration: duration)
                if let synced = found.synced {
                    let lines = LyricsParser.parseLRC(synced, trackLength: duration)
                    if !lines.isEmpty { return (Lyrics(lines: lines, synced: true, source: Lyrics.lrclib), pair) }
                }
                if plain == nil { plain = found.plain }
            } catch {
                failed = error
                return nil // lrclib лежит — дальше спрашивать бесполезно
            }
        }
        return nil
    }
}
