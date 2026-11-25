import Foundation
import Observation

/// Сигнал прослушивания — короткая запись для вкуса волны и подборок (аналог строк `plays` и `skips`
/// в `docs/DB.md`; когда появится SQLite — переедут туда).
struct PlaySignal: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Засчитано прослушивание: ≥ min(30 с, половины трека) — SPEC §3.8.
        case play
        /// Дослушан (оценка исхода ≥ +1, f ≥ 0.8).
        case finish
        /// Пропущен вручную с минусом.
        case skip
    }

    var ref: String
    /// Артисты трека (`Track.artistKeys`), первый — главный.
    var artists: [String]
    var kind: Kind
    /// Для пропуска — |оценка| (0.4 / 1); для остальных — 1.
    var weight: Double
    var at: Date
}

/// Вкус по истории и Любимым: кого слушаешь, кого пропускаешь (с затуханием) — для волны и «Для вас».
/// Упрощённый `store/wave.rs` `taste()`: окно 180 дней, полураспад 30 дней.
struct Taste: Sendable, Equatable {
    /// Артисты из Любимых.
    var likedArtists: Set<String> = []
    /// Артист → плюсы с затуханием (прослушивание 0.4, дослушанное — ещё 0.6).
    var plays: [String: Double] = [:]
    /// Артист → минусы с затуханием (|оценка| пропуска).
    var skips: [String: Double] = [:]
    /// Трек → штраф за его собственные пропуски.
    var trackSkips: [String: Double] = [:]
    /// «Чаще» (+1) / «Реже» (−1) по артисту — экран «Вкус» (`ArtistPrefs`), ставит волна перед подбором.
    var artistPref: [String: Double] = [:]

    static let windowDays = 180.0
    static let halfLifeDays = 30.0

    /// Знакомый артист: лайкнут или его слушали (по любому из артистов трека).
    func isKnown(_ track: Track) -> Bool {
        track.artistKeys.contains { likedArtists.contains($0) || (plays[$0] ?? 0) > 0 }
    }

    /// Признак «Чаще / Реже» трека: «Чаще» любого из соавторов перебивает «Реже» (`wave.rs` `pref_of`).
    func pref(_ track: Track) -> Double {
        let all = track.artistKeys.compactMap { artistPref[$0] }
        if all.contains(where: { $0 > 0 }) { return 1 }
        return all.contains(where: { $0 < 0 }) ? -1 : 0
    }

    func likesArtist(_ track: Track) -> Bool {
        track.artistKeys.contains { likedArtists.contains($0) }
    }

    /// Отношение к артисту −1…1: лучший из артистов трека, (плюсы − минусы) / (плюсы + минусы + 2).
    /// Вместо Томпсона Rust — без случайности, шум добавляет сама волна.
    func affinity(_ track: Track) -> Double {
        track.artistKeys.map { key in
            let pos = plays[key] ?? 0
            let neg = skips[key] ?? 0
            return (pos - neg) / (pos + neg + 2)
        }.max() ?? 0
    }

    static func build(signals: [PlaySignal], liked: [Track], now: Date) -> Taste {
        var taste = Taste()
        for track in liked { taste.likedArtists.formUnion(track.artistKeys) }
        for signal in signals {
            let days = now.timeIntervalSince(signal.at) / 86_400
            guard days < windowDays else { continue }
            let w = pow(0.5, max(0, days) / halfLifeDays)
            switch signal.kind {
            case .play:
                for key in signal.artists { taste.plays[key, default: 0] += 0.4 * w }
            case .finish:
                for key in signal.artists { taste.plays[key, default: 0] += 0.6 * w }
            case .skip:
                for key in signal.artists { taste.skips[key, default: 0] += signal.weight * w }
                taste.trackSkips[signal.ref, default: 0] += signal.weight * w
            }
        }
        return taste
    }
}

/// История прослушиваний на телефоне: «Недавнее» на Главной (уникальные по ref, новые первыми, до 100)
/// и сигналы для волны — прослушал / дослушал / пропустил. JSON в Application Support, как
/// `LibraryStore`. Прослушивание засчитывается, как в Windows `plays`: ≥ min(30 с, половины трека)
/// (`QueueMath.countsAsPlay`) — плеер зовёт `record`, как только порог пройден.
@MainActor
@Observable
final class PlayHistory {
    static let shared: PlayHistory = {
        let history = PlayHistory()
        // журнал «Статистики»: один раз переносит старую историю
        history.log = .shared
        PlayLog.shared.backfill(signals: history.signals, recent: history.recent)
        return history
    }()

    static let recentLimit = 100
    static let signalLimit = 5000

    /// Недавно игравшие, новые первыми.
    private(set) var recent: [Track] = []
    @ObservationIgnored private(set) var signals: [PlaySignal] = []

    private struct Snapshot: Codable {
        var recent: [Track]
        var signals: [PlaySignal]
    }

    @ObservationIgnored private let file: URL
    @ObservationIgnored private let now: () -> Date
    /// Журнал для «Статистики» (`PlayLog`): у `shared` — общий, в тестах — свой или нет.
    @ObservationIgnored var log: PlayLog?

    init(file: URL? = nil, now: @escaping () -> Date = Date.init) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.file = file ?? base.appendingPathComponent("Sonar/history.json")
        self.now = now
        if let data = try? Data(contentsOf: self.file), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            recent = snapshot.recent
            signals = snapshot.signals
        }
    }

    // MARK: - Запись

    /// Трек засчитан как прослушанный: наверх «Недавнего» и сигнал `play`.
    func record(_ track: Track) {
        recent.removeAll { $0.ref == track.ref }
        recent.insert(track, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
        append(PlaySignal(ref: track.ref, artists: track.artistKeys, kind: .play, weight: 1, at: now()))
        log?.started(track, at: now(), listenedMs: min(30_000, track.durationMs > 0 ? track.durationMs / 2 : 30_000))
    }

    /// Дослушан (f ≥ 0.8).
    func finished(_ track: Track) {
        append(PlaySignal(ref: track.ref, artists: track.artistKeys, kind: .finish, weight: 1, at: now()))
    }

    /// Пропущен вручную с минусом. reward — оценка исхода (−1 ранний, −0.4 мягкий).
    func skipped(_ track: Track, reward: Double = -1) {
        guard reward < 0 else { return }
        append(PlaySignal(ref: track.ref, artists: track.artistKeys, kind: .skip, weight: min(2, -reward), at: now()))
    }

    /// Трек сменился: записать дослушанный или пропуск по оценке исхода. Вернёт полную оценку (с лайком
    /// и 👎) — её берёт волна. Само прослушивание пишет `record`, не это.
    @discardableResult
    func ended(_ track: Track, listenedMs: Int, manualSkip: Bool, liked: Bool = false, disliked: Bool = false) -> Double {
        log?.ended(track, listenedMs: listenedMs, now: now())
        let plain = Outcome.reward(listenedMs: listenedMs, durationMs: track.durationMs, manualSkip: manualSkip)
        if plain >= 1 {
            finished(track)
        } else if manualSkip, plain < 0 {
            skipped(track, reward: plain)
        }
        return Outcome.reward(listenedMs: listenedMs, durationMs: track.durationMs, manualSkip: manualSkip, liked: liked, disliked: disliked)
    }

    /// Убрать из «Недавнего» (меню трека) — сигналы вкуса остаются.
    func removeRecent(_ ref: String) {
        recent.removeAll { $0.ref == ref }
        save()
    }

    /// Очистить историю целиком (Хранилище).
    func clear() {
        recent = []
        signals = []
        log?.clear()
        save()
    }

    private func append(_ signal: PlaySignal) {
        signals.append(signal)
        let cutoff = now().addingTimeInterval(-Taste.windowDays * 86_400)
        if let first = signals.first, first.at < cutoff { signals.removeAll { $0.at < cutoff } }
        if signals.count > Self.signalLimit { signals.removeFirst(signals.count - Self.signalLimit) }
        save()
    }

    private func save() {
        let snapshot = Snapshot(recent: recent, signals: signals)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        onChange?()
    }

    /// Новое прослушивание или очистка — синк отправит прослушивания (`POST /plays`, `SyncService`).
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    // MARK: - Чтение

    /// Слушали за последние days дней — волна их не повторяет.
    func playedRefs(withinDays days: Double) -> Set<String> {
        let cutoff = now().addingTimeInterval(-days * 86_400)
        return Set(signals.lazy.filter { $0.kind == .play && $0.at >= cutoff }.map(\.ref))
    }

    /// Последние дослушанные, уникальные, новые первыми.
    func finishedRefs(limit: Int) -> [String] {
        var out: [String] = []
        for signal in signals.reversed() where signal.kind == .finish && !out.contains(signal.ref) {
            out.append(signal.ref)
            if out.count >= limit { break }
        }
        return out
    }

    func taste(liked: [Track]) -> Taste {
        Taste.build(signals: signals, liked: liked, now: now())
    }
}
