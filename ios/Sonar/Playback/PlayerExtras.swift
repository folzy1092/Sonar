import Foundation

// Чистая часть плеера без AVFoundation (тесты — `PlaybackExtrasTests`, можно Swift'ом для Linux):
// громкость трека по R128 Яндекса, таймер сна с затуханием, план офлайн-кэша волны и строка
// «Почему этот трек» у волны. К звуку и диску это применяют `PlaybackEngine` и `WaveCache`.

// MARK: - Громкость трека (нормализация)

/// Нормализация по данным сервиса: Яндекс отдаёт у трека `r128.i` — интегральную громкость EBU R128 (LUFS).
/// Громкость плеера (`AVPlayer.volume`) бывает только 0…1, поэтому громкие треки опускаются к цели, а тихие
/// остаются как есть (их подтягивает выравниватель `Leveler`, где звук идёт через `AudioTap`). Работает и на
/// HLS — громкость плеера AVFoundation применяет к любому потоку.
enum Loudness {
    /// Цель, LUFS (как у Spotify и YouTube).
    static let targetLufs: Double = -14
    /// Сильнее 12 дБ не убавляем — данные могли прийти странные.
    static let maxCutDb: Double = -12

    /// Сдвиг громкости, дБ (≤ 0). Нет данных, выключено или трек и так тише цели — 0.
    static func gainDb(lufs: Double?, enabled: Bool) -> Double {
        guard enabled, let lufs, lufs.isFinite, lufs < 0 else { return 0 }
        return max(maxCutDb, min(0, targetLufs - lufs))
    }

    /// Множитель громкости плеера 0…1.
    static func gain(lufs: Double?, enabled: Bool) -> Double {
        pow(10, gainDb(lufs: lufs, enabled: enabled) / 20)
    }
}

// MARK: - Наложение двух дек

extension Fades {
    /// Длина наложения: не длиннее трети уходящего и трети следующего трека (короткие не съедаются целиком).
    static func overlapSpan(seconds: Double, outgoing: Double, incoming: Double) -> Double {
        guard seconds > 0 else { return 0 }
        var span = seconds
        if outgoing > 0 { span = min(span, outgoing / 3) }
        if incoming > 0 { span = min(span, incoming / 3) }
        return max(0, span)
    }

    /// Равная мощность: нарастание следующего и затухание уходящего — сумма громкостей не проседает в середине.
    static func crossIn(_ t: Double) -> Double {
        sin(min(1, max(0, t)) * .pi / 2)
    }

    static func crossOut(_ t: Double) -> Double {
        cos(min(1, max(0, t)) * .pi / 2)
    }
}

// MARK: - Таймер сна

/// Что выбрали в листе таймера: через N минут или в конце трека.
enum SleepOption: Hashable, Sendable, Identifiable {
    case minutes(Int)
    case endOfTrack

    static let all: [SleepOption] = [.minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfTrack]

    var id: String {
        switch self {
        case let .minutes(n): "m\(n)"
        case .endOfTrack: "track"
        }
    }

    var title: String {
        switch self {
        case let .minutes(n): "\(n) мин"
        case .endOfTrack: "Конец трека"
        }
    }
}

/// Таймер сна: к концу громкость плавно уходит в ноль, потом пауза. Минуты — затухание последние 30 с,
/// «конец трека» — последние ≤ 12 с трека, и следующий не начинается (загружается на паузе).
struct SleepTimer: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case deadline(Date)
        case endOfTrack
    }

    static let fadeSeconds: Double = 30
    static let trackFadeSeconds: Double = 12

    var mode: Mode

    init(_ option: SleepOption, now: Date = Date()) {
        switch option {
        case let .minutes(n): mode = .deadline(now.addingTimeInterval(Double(n) * 60))
        case .endOfTrack: mode = .endOfTrack
        }
    }

    var isEndOfTrack: Bool { mode == .endOfTrack }

    /// Сколько секунд осталось (для подписи); «конец трека» — nil.
    func remaining(now: Date) -> TimeInterval? {
        guard case let .deadline(date) = mode else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    /// Время вышло — пора на паузу.
    func isDue(now: Date) -> Bool {
        remaining(now: now).map { $0 <= 0 } ?? false
    }

    /// Множитель громкости 0…1. Квадратичная кривая — на слух ровнее линейной.
    func factor(now: Date, position: Double, duration: Double) -> Double {
        let left: Double
        let span: Double
        switch mode {
        case let .deadline(date):
            left = date.timeIntervalSince(now)
            span = Self.fadeSeconds
        case .endOfTrack:
            guard duration > 0 else { return 1 }
            left = duration - position
            span = min(Self.trackFadeSeconds, duration / 3)
        }
        guard span > 0, left < span else { return 1 }
        let t = max(0, left / span)
        return t * t
    }

    /// «12:05» / «1:00:00» — сколько осталось.
    static func label(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Офлайн-кэш волны

/// Какие треки волны держать на диске: следующие `ahead` (на Wi‑Fi подкачиваются заранее), остальное из кэша
/// уходит — волна не повторяется, сыгранное больше не нужно. Скачанные вручную (`DownloadStore`) не трогаем.
enum WaveCachePlan {
    static let ahead = 15
    /// Сколько качать одновременно.
    static let parallel = 2

    struct Plan: Equatable, Sendable {
        var fetch: [String]
        var evict: [String]
    }

    /// upcoming — ref'ы «Далее» волны по порядку; cached — что уже в кэше; downloaded — скачанные вручную;
    /// attempted — уже пробовали в эту сессию (HLS без файла и ошибки не долбим).
    static func plan(upcoming: [String], current: String?, cached: Set<String>, downloaded: Set<String>,
                     attempted: Set<String>, enabled: Bool) -> Plan {
        guard enabled else { return Plan(fetch: [], evict: cached.sorted()) }
        let window = Array(upcoming.prefix(ahead))
        var keep = Set(window)
        if let current { keep.insert(current) }
        var seen = Set<String>()
        let fetch = window.filter { ref in
            seen.insert(ref).inserted && !cached.contains(ref) && !downloaded.contains(ref) && !attempted.contains(ref)
        }
        return Plan(fetch: fetch, evict: cached.filter { !keep.contains($0) }.sorted())
    }

    /// Без сети: ближайшая позиция в «Далее», у которой файл на телефоне (nil — нет такой).
    static func nextPlayable(from pos: Int, refs: [String], isLocal: (String) -> Bool) -> Int? {
        guard pos + 1 < refs.count else { return nil }
        return (pos + 1 ..< refs.count).first { isLocal(refs[$0]) }
    }
}

// MARK: - «Почему этот трек»

/// Одна строка под названием в плеере у трека волны — из того, откуда волна его взяла (`WaveOrigin.seedOf`):
/// похож на лайкнутый / на зашедший сейчас / на дослушанный, популярное у привычного артиста, забытый лайк.
enum WaveReason {
    struct Context: Sendable {
        /// Трек → сид (ref трека или артиста), в чьём списке он стоял выше всего.
        var seedOf: [String: String] = [:]
        /// ref → трек для названий сидов (Любимые, недавнее, зашедшее, кандидаты).
        var tracks: [String: Track] = [:]
        /// ref артиста → имя.
        var artistNames: [String: String] = [:]
        var likes: Set<String> = []
        /// «Забытые любимые», вставленные в порцию.
        var forgotten: Set<String> = []
        /// Зашедшие в этой сессии.
        var live: Set<String> = []
        /// «Волна по треку» — от какого.
        var waveSeed: String?
        var mode: WaveMode = .own
    }

    static func text(for track: Track, known: Bool, _ c: Context) -> String {
        if track.ref == c.waveSeed { return "С него началась волна" }
        if c.forgotten.contains(track.ref) { return "Из твоих Любимых — давно не звучал" }
        if c.likes.contains(track.ref) { return "Из твоих Любимых" }
        let base: String? = c.seedOf[track.ref].flatMap { seed in
            if let source = c.tracks[seed] {
                let title = "«\(source.title)»"
                if seed == c.waveSeed { return "Похож на \(title)" }
                if c.live.contains(seed) { return "Похож на \(title) — он зашёл сейчас" }
                if c.likes.contains(seed) { return "Ты лайкал \(title) — этот похож" }
                return "Похож на \(title)"
            }
            if let name = c.artistNames[seed] { return "Популярное у \(name) — ты его слушаешь" }
            return nil
        }
        let prefix: String? = c.mode.isMood && WaveMath.moodFit(c.mode, track) > 0 ? c.mode.label : nil
        if let base {
            return prefix.map { "\($0) · \(lowerFirst(base))" } ?? base
        }
        if !known { return "Новый для тебя артист" }
        return prefix.map { "Под настроение: \($0)" } ?? "Подобрано по твоему вкусу"
    }

    private static func lowerFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
