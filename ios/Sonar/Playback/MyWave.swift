import Foundation

// Своя «Моя волна» (SPEC §3.7, docs/WAVE.md) — упрощённый порт Windows `wave.rs` + `my-wave.svelte.ts`.
// Rotor Яндекса не используем: кандидаты — «похожие» SoundCloud и Яндекса от сидов (Любимые, недавно
// дослушанное, что зашло в этой сессии) и популярное 1–2 привычных артистов; три «забытых любимых»
// на места 2, 5, 8. Порция — 10 треков, догружается, когда до конца меньше трёх. Сигналы — оценка
// исхода (`Outcome.reward`): дослушанное и лайкнутое становится сидами, пропущенный артист теряет вес,
// два ранних пропуска артиста подряд — пауза до конца сессии, два ранних пропуска подряд — «Далее»
// пересобирается. 👎 не попадает никогда.
//
// Режимы — те же 6, что в Windows (`WAVE_MODES`, `wave.rs` `MODES` / `MOODS` / `mood_fit` / `weights`):
// «Своя» — по лайкам, настроения (Жёсткая / Спокойная / Грустная / Весёлая) — словарь настроений по
// тегам и названию, «Незнакомое» — артисты, которых нет в Любимых и истории (+ второй шаг разведки).
// Чего из Windows пока нет: профиль тегов, время суток, своя платформа, кэш похожих, журнал
// `wave_events`; вкус к артисту — без выборки Томпсона (шум даёт разброс).

/// Режим волны — кнопка под «Моя волна» на Главной. Хранится в настройке `wave.mode`.
enum WaveMode: String, CaseIterable, Sendable, Identifiable {
    case own, hard, calm, sad, fun, new

    var id: String { rawValue }

    var title: String {
        switch self {
        case .own: "Своя"
        case .hard: "Жёсткая"
        case .calm: "Спокойная"
        case .sad: "Грустная"
        case .fun: "Весёлая"
        case .new: "Незнакомое"
        }
    }

    var subtitle: String {
        switch self {
        case .own: "по твоим лайкам"
        case .hard: "фонк, рэйдж, рок"
        case .calm: "чилл, лоу-фай, акустика"
        case .sad: "когда накрыло"
        case .fun: "поп, хаус, движ"
        case .new: "новые для тебя артисты"
        }
    }

    /// Настроение (подбор по словарю `moods`).
    var isMood: Bool {
        switch self {
        case .hard, .calm, .sad, .fun: true
        case .own, .new: false
        }
    }

    /// Следующий по кругу.
    var next: WaveMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Веса признаков режима — `wave.rs` `weights` (без профиля тегов, времени суток и платформы).
struct WaveWeights: Sendable, Equatable {
    var affinity = 0.0
    var likedArtist = 0.0
    var known = 0.0
    var fresh = 0.0
    var votes = 0.6
    var rank = 0.5
    var fromSession = 0.7
    var sessionSkipped = -0.9
    var trackSkips = -1.2
    var mood = 0.0
    var skipRate = 0.0

    static func of(_ mode: WaveMode) -> WaveWeights {
        var w = WaveWeights()
        switch mode {
        case .new:
            w.known = -2.5
            w.fresh = 1
            w.skipRate = -1
        case .hard, .calm, .sad, .fun:
            w.mood = 1.5
            w.likedArtist = 1
            w.known = 0.4
            w.affinity = 0.6
        case .own:
            w.likedArtist = 2
            w.known = 0.8
            w.affinity = 1
        }
        return w
    }
}

/// Откуда кандидат: сколько сидов его предложили, как высоко, чей он.
struct WaveOrigin: Sendable {
    var votes: [String: Int] = [:]
    /// 1 — первый в списке похожих, ближе к 0 — ниже.
    var rank: [String: Double] = [:]
    /// Трек → сид, в чьём списке он стоял выше всего.
    var seedOf: [String: String] = [:]
    /// Предложены сидами из этой сессии («зашло»).
    var fromSession: Set<String> = []

    mutating func add(seed: String, list: [Track], live: Bool) {
        let count = Double(max(list.count, 1))
        for (i, track) in list.enumerated() {
            votes[track.ref, default: 0] += 1
            let r = 1 - Double(i) / count
            if r > (rank[track.ref] ?? -1) {
                rank[track.ref] = r
                seedOf[track.ref] = seed
            }
            if live { fromSession.insert(track.ref) }
        }
    }

    /// Популярное привычного артиста — без голосов сида.
    mutating func addArtist(_ artist: String, list: [Track]) {
        let count = Double(max(list.count, 1))
        for (i, track) in list.enumerated() where rank[track.ref] == nil {
            rank[track.ref] = 0.5 * (1 - Double(i) / count)
            seedOf[track.ref] = artist
        }
    }
}

/// Что нельзя ставить в порцию.
struct WaveFilter: Sendable {
    /// Слушали за 7 дней.
    var recent: Set<String> = []
    /// 👎.
    var banned: Set<String> = []
    /// Уже выданы в этой сессии.
    var exclude: Set<String> = []
    /// Артисты на паузе (два ранних пропуска подряд).
    var pausedArtists: Set<String> = []
    /// Сколько треков незнакомых артистов пускать в порцию; nil — без лимита.
    var maxUnknown: Int?
    /// Трек SoundCloud незнакомого артиста с меньшим числом прослушиваний не берём (случайные заливы).
    var minPlaysUnknown = 0
}

/// Серия ранних пропусков (`skip-series.ts`): две подряд — «Далее» подобрано не под настроение.
struct SkipSeries: Sendable {
    static let length = 2
    static let cooldown: TimeInterval = 60

    private var run = 0
    private var lastAt = Date.distantPast

    /// true — пора пересобрать «Далее». Ранний — ручной пропуск с оценкой ≤ −1 (ранний или 👎).
    mutating func push(_ reward: Double, skipped: Bool, now: Date) -> Bool {
        guard skipped, reward <= -1 else {
            run = 0
            return false
        }
        run += 1
        guard run >= Self.length, now.timeIntervalSince(lastAt) >= Self.cooldown else { return false }
        run = 0
        lastAt = now
        return true
    }

    mutating func reset() {
        run = 0
        lastAt = .distantPast
    }
}

/// Состояние одной сессии волны: что выдано, кто на паузе, что зашло и что нет.
struct WaveSession: Sendable {
    /// «Волна по треку» — стиль держится всю сессию.
    var seed: Track?
    var mode: WaveMode = .own
    var served: Set<String> = []
    /// Главные артисты выданных треков по порядку.
    var servedArtists: [String] = []
    var paused: Set<String> = []
    var skipRun: [String: Int] = [:]
    /// Зашедшие (оценка ≥ +1), новые в конце — сиды следующих порций.
    var good: [Track] = []
    /// Артисты, пропущенные в сессии (до следующего плюса).
    var skippedArtists: Set<String> = []
    var series = SkipSeries()

    var servedCount: [String: Int] {
        servedArtists.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    mutating func serve(_ track: Track) {
        served.insert(track.ref)
        servedArtists.append(track.artistKey)
    }

    /// Трек так и не прозвучал (пересборка «Далее») — вернуть в пул.
    mutating func unserve(_ track: Track) {
        served.remove(track.ref)
        if let i = servedArtists.lastIndex(of: track.artistKey) { servedArtists.remove(at: i) }
    }

    /// Исход трека волны. Вернёт true, если пора пересобрать «Далее».
    mutating func ended(_ track: Track, reward: Double, manualSkip: Bool, now: Date) -> Bool {
        let artist = track.artistKey
        if reward < 0 { skippedArtists.insert(artist) }
        if reward == -1 {
            let n = (skipRun[artist] ?? 0) + 1
            skipRun[artist] = n
            if n >= 2 { paused.insert(artist) }
        } else {
            skipRun[artist] = nil
        }
        if reward >= 1 {
            skippedArtists.remove(artist)
            good.removeAll { $0.ref == track.ref }
            good.append(track)
        }
        return series.push(reward, skipped: manualSkip, now: now)
    }
}

/// Чистая часть волны: сиды, оценка, отбор порции. Без сети и состояния — тесты гоняют на Linux.
enum WaveMath {
    static let portion = 10
    /// Не больше стольких треков артиста за сессию.
    static let sessionArtistCap = 4
    /// Не больше стольких треков порции от одного сида (мягкий лимит).
    static let seedCap = 4
    /// Похожих от каждого сида: «Своя» — 25, остальным — 35 (есть из чего выбрать подходящее).
    static func similarLimit(_ mode: WaveMode) -> Int { mode == .own ? 25 : 35 }

    /// Настроения — группы тегов Last.fm / MIREX плюс жанры, что обычно туда ложатся (`wave.rs` `MOODS` 1:1).
    static let moods: [(mode: WaveMode, words: [String])] = [
        (.hard, [
            "phonk", "drift", "hardstyle", "hardcore", "drill", "trap", "rage", "metal", "rock", "punk", "dubstep", "dnb",
            "drum & bass", "drum and bass", "breakcore", "jersey", "hard", "aggressive", "brazilian", "funk", "techno", "industrial",
            "rusrap", "hip-hop", "hiphop", "rap", "energetic", "workout", "gym", "intense", "angry", "энерг",
        ]),
        (.calm, [
            "lofi", "lo-fi", "chill", "ambient", "acoustic", "piano", "jazz", "sleep", "calm", "relax", "study", "classical",
            "instrumental", "soul", "r&b", "rnb", "downtempo", "bossa", "folk", "mellow", "soothing", "serene", "meditat",
            "lounge", "new age", "спокой",
        ]),
        (.sad, [
            "sad", "emo", "depress", "melanchol", "slowed", "reverb", "heartbreak", "lonely", "cry", "alone", "grief", "tears",
            "cloud rap", "cloudrap", "dark", "gloomy", "sorrow", "sadcore", "грус", "одинок", "слёз", "слез", "печал", "тоск",
            "меланхол",
        ]),
        (.fun, [
            "pop", "dance", "house", "disco", "party", "happy", "summer", "hyperpop", "electro", "edm", "club", "remix",
            "sped up", "nightcore", "funk", "k-pop", "kpop", "upbeat", "feel good", "sunny", "cheerful", "latin", "весел",
            "радост", "лето",
        ]),
    ]

    /// Насколько трек подходит настроению (`mood_fit`): совпал по жанру / тегам / названию — плюс
    /// (1.6…2.2), похож на другое настроение — −0.8, ничего не известно — 0. Не настроение — 0.
    static func moodFit(_ mode: WaveMode, _ track: Track) -> Double {
        guard mode.isMood else { return 0 }
        let text = "\((track.tags ?? "").lowercased()) \(track.title.lowercased())"
        var own = 0
        var other = 0
        for (m, words) in moods {
            let n = words.filter { text.contains($0) }.count
            if m == mode { own = n } else { other = max(other, n) }
        }
        if own > 0 { return 1.6 + 0.3 * Double(min(own, 3) - 1) - (other > own ? 0.4 : 0) }
        return other > 0 ? -0.8 : 0
    }

    /// Знакомое и новое по режиму (`familiarity`): сколько незнакомых артистов пустить в порцию из n и
    /// порог прослушиваний SoundCloud для незнакомых. «Незнакомое» — без лимита и порога.
    static func familiarity(_ mode: WaveMode, bySeed: Bool, n: Int = portion) -> (maxUnknown: Int?, minPlays: Int) {
        let share = { (k: Double) in Int((Double(n) * k).rounded()) }
        if mode == .new { return (nil, 0) }
        if bySeed { return (share(0.5), 300) }
        return mode == .own ? (share(0.3), 1000) : (share(0.4), 1000)
    }

    /// Сколько своих «забытых» лайков в порции (`liked_share`): «Своя» — 3, настроение — 2, остальное — 0.
    static func likedShare(_ mode: WaveMode, bySeed: Bool) -> Int {
        if bySeed { return 0 }
        return mode == .own ? 3 : mode.isMood ? 2 : 0
    }

    /// Сиды порции (ref треков). Волна по треку — он и 2 последних зашедших; сессия уже идёт — 3
    /// последних зашедших + 2 свежих лайка + 1 старый («разведка»); начало — 5 из свежих лайков и
    /// дослушанного + 1 старый лайк; ничего нет — недавнее.
    static func seeds(seed: Track?, good: [Track], likes: [String], finished: [String], recent: [String],
                      mode: WaveMode = .own, random: () -> Double) -> [String] {
        if let seed {
            var out = [seed.ref]
            for track in good.reversed() where track.ref != seed.ref && out.count < 3 { out.append(track.ref) }
            return out
        }
        let fresh = Array(likes.prefix(15))
        let old = likes.count > 15 ? Array(likes[15 ..< min(likes.count, 300)]) : []
        let live = good.reversed().prefix(3).map(\.ref)
        if !live.isEmpty {
            var out = Array(live)
            out += sample(fresh.filter { !out.contains($0) }, 2, random: random)
            out += sample(old.filter { !out.contains($0) }, 1, random: random)
            return out
        }
        var pool = fresh
        for ref in finished.prefix(10) where !pool.contains(ref) { pool.append(ref) }
        if pool.isEmpty { pool = Array(recent.prefix(10)) }
        // настроение — больше сидов, чтобы было из чего выбрать подходящее
        var out = sample(pool, mode.isMood ? 8 : 5, random: random)
        out += sample(old.filter { !out.contains($0) }, 1, random: random)
        return out
    }

    /// Привычные артисты (ref): главные артисты свежих Любимых, потом недавнего — уникально.
    static func favoriteArtistRefs(liked: [Track], recent: [Track], limit: Int) -> [String] {
        var out: [String] = []
        for track in liked.prefix(300) + recent {
            guard out.count < limit else { break }
            if let ref = track.mainArtistRef, !out.contains(ref) { out.append(ref) }
        }
        return out
    }

    /// k случайных без повторов, порядок выборки.
    static func sample<T>(_ items: [T], _ k: Int, random: () -> Double) -> [T] {
        var rest = items
        var out: [T] = []
        while out.count < k, !rest.isEmpty {
            let i = min(rest.count - 1, Int(random() * Double(rest.count)))
            out.append(rest.remove(at: i))
        }
        return out
    }

    /// Оценка кандидата без шума: признаки × веса режима сессии (`wave.rs` `features` · `weights`).
    static func score(_ track: Track, taste: Taste, origin: WaveOrigin, session: WaveSession) -> Double {
        let w = WaveWeights.of(session.mode)
        let known = taste.isKnown(track) ? 1.0 : 0
        let liked = taste.likesArtist(track) ? 1.0 : 0
        let votes = Double(min(max((origin.votes[track.ref] ?? 1) - 1, 0), 3))
        let rank = origin.rank[track.ref] ?? 0
        let live = origin.fromSession.contains(track.ref) ? 1.0 : 0
        let skippedArtist = session.skippedArtists.contains(track.artistKey) ? 1.0 : 0
        let trackSkips = min(taste.trackSkips[track.ref] ?? 0, 2)
        let skipRate = track.artistKeys.map { key -> Double in
            let plays = taste.plays[key] ?? 0
            let skips = taste.skips[key] ?? 0
            return skips / (plays + skips + 1)
        }.min() ?? 0
        return w.affinity * taste.affinity(track) + w.likedArtist * liked + w.known * known + w.fresh * (1 - known)
            + w.votes * votes + w.rank * rank + w.fromSession * live + w.sessionSkipped * skippedArtist
            + w.trackSkips * trackSkips + w.mood * moodFit(session.mode, track) + w.skipRate * skipRate
    }

    /// Порция из n: без дублей и фильтрованных, не два одинаковых артиста подряд (и не тот, что только
    /// что звучал, первым), ≤ 2 трека артиста в порции и ≤ 4 за сессию, ≤ 4 от одного сида (второй проход
    /// добирает без этого лимита). relaxed — разрешить слушанное за 7 дней.
    static func pick(_ candidates: [Track], taste: Taste, origin: WaveOrigin, session: WaveSession, filter: WaveFilter,
                     n: Int = portion, relaxed: Bool = false, noise: () -> Double) -> [Track] {
        let served = session.servedCount
        var seen = Set<String>()
        var pool = candidates.filter { track in
            let artist = track.artistKey
            return track.available && seen.insert(track.ref).inserted
                && !filter.banned.contains(track.ref) && !filter.exclude.contains(track.ref)
                && (relaxed || !filter.recent.contains(track.ref))
                && !filter.pausedArtists.contains(artist)
                && (served[artist] ?? 0) < sessionArtistCap
                && (filter.minPlaysUnknown == 0 || taste.isKnown(track) || (track.plays ?? Int.max) >= filter.minPlaysUnknown)
        }
        // настроение: подходящих хватает — неподходящие мимо совсем
        if session.mode.isMood, pool.filter({ moodFit(session.mode, $0) > 0 }).count >= n * 3 {
            pool.removeAll { moodFit(session.mode, $0) < 0 }
        }
        let scored = pool.map { (score: score($0, taste: taste, origin: origin, session: session) + noise() * 0.3, track: $0) }
            .sorted { $0.score > $1.score }
            .map(\.track)

        var out: [Track] = []
        var perArtist: [String: Int] = [:]
        var perSeed: [String: Int] = [:]
        var unknown = 0
        let maxUnknown = filter.maxUnknown ?? Int.max
        let tail = Set(session.servedArtists.suffix(3))
        var pending: [Track] = []
        var queue = scored
        for capSeeds in [true, false] {
            for track in queue {
                pending.append(track)
                while true {
                    let index = pending.firstIndex { t in
                        let a = t.artistKey
                        let count = perArtist[a] ?? 0
                        return !(out.isEmpty && tail.contains(a))
                            && (unknown < maxUnknown || taste.isKnown(t))
                            && out.last?.artistKey != a
                            && count < 2
                            && count + (served[a] ?? 0) < sessionArtistCap
                            && (!capSeeds || origin.seedOf[t.ref].map { (perSeed[$0] ?? 0) < Self.seedCap } ?? true)
                    }
                    guard let index else { break }
                    let t = pending.remove(at: index)
                    if !taste.isKnown(t) { unknown += 1 }
                    perArtist[t.artistKey, default: 0] += 1
                    if let s = origin.seedOf[t.ref] { perSeed[s, default: 0] += 1 }
                    out.append(t)
                    if out.count == n { return out }
                }
            }
            queue = pending
            pending = []
        }
        return out
    }

    /// Порция с запасными проходами (как `wave_portion`): знакомого не хватило на половину — без лимита
    /// незнакомых; меньше трёх — и со слушанным за неделю.
    static func portion(_ candidates: [Track], taste: Taste, origin: WaveOrigin, session: WaveSession, filter: WaveFilter,
                        n: Int = portion, noise: () -> Double) -> [Track] {
        var out = pick(candidates, taste: taste, origin: origin, session: session, filter: filter, n: n, noise: noise)
        var open = filter
        open.maxUnknown = nil
        if out.count < n / 2, filter.maxUnknown != nil {
            out = pick(candidates, taste: taste, origin: origin, session: session, filter: open, n: n, noise: noise)
        }
        if out.count < 3 {
            out = pick(candidates, taste: taste, origin: origin, session: session, filter: open, n: n, relaxed: true, noise: noise)
        }
        return out
    }

    /// Второй шаг разведки «Незнакомого»: лучшие по месту в похожих кандидаты незнакомых артистов
    /// (по одному на артиста) — от них ещё похожие.
    static func hopSeeds(_ candidates: [Track], taste: Taste, origin: WaveOrigin, banned: Set<String>, k: Int) -> [String] {
        let best = candidates.filter { !taste.isKnown($0) && !banned.contains($0.ref) }
            .sorted { (origin.rank[$0.ref] ?? 0) > (origin.rank[$1.ref] ?? 0) }
        var artists = Set<String>()
        var out: [String] = []
        for track in best where out.count < k && artists.insert(track.artistKey).inserted && !out.contains(track.ref) {
            out.append(track.ref)
        }
        return out
    }

    /// «Забытые любимые»: лайки, что не играли 30 дней, лучшие по вкусу, артисты не повторяются.
    static func pickLiked(_ liked: [Track], taste: Taste, session: WaveSession, filter: WaveFilter, playedMonth: Set<String>,
                          k: Int, noise: () -> Double) -> [Track] {
        guard k > 0 else { return [] }
        let served = session.servedCount
        let scored = liked.filter { t in
            t.available && !filter.banned.contains(t.ref) && !filter.exclude.contains(t.ref) && !playedMonth.contains(t.ref)
                && !filter.pausedArtists.contains(t.artistKey) && (served[t.artistKey] ?? 0) < sessionArtistCap
                && (!session.mode.isMood || moodFit(session.mode, t) > 0)
        }
        .map { (score: taste.affinity($0) - 0.6 * min(taste.trackSkips[$0.ref] ?? 0, 2) + noise() * 0.6, track: $0) }
        .sorted { $0.score > $1.score }
        var artists = Set<String>()
        return Array(scored.map(\.track).filter { artists.insert($0.artistKey).inserted }.prefix(k))
    }

    /// Свои лайки — на места 2, 5, 8 (первым всегда новое); рядом тот же артист — место дальше.
    static func insertLiked(_ portion: [Track], liked: [Track], n: Int = portion) -> [Track] {
        var out = portion
        let taken = Set(out.map(\.ref))
        for (slot, track) in zip([2, 5, 8], liked.filter { !taken.contains($0.ref) }) {
            let a = track.artistKey
            let fits = { (i: Int) -> Bool in
                i > 0 && i <= out.count
                    && out[i - 1].artistKey != a
                    && (i == out.count || out[i].artistKey != a)
                    && out.filter { $0.artistKey == a }.count < 2
            }
            if let i = (min(slot, out.count) ... out.count).first(where: fits) {
                out.insert(track, at: i)
            }
        }
        return Array(out.prefix(n))
    }
}

/// Волна на телефоне: сессия + подбор порций. Плеер (`PlaybackEngine`) зовёт `start`, `more` и `ended`.
@MainActor
final class MyWave {
    private let source: MusicSource
    private let library: LibraryStore
    private let history: PlayHistory
    private let random: () -> Double
    private(set) var session = WaveSession()
    /// «Почему этот трек» — ref → одна строка (`WaveReason`), для выданных в этой сессии.
    private(set) var reasons: [String: String] = [:]

    init(source: MusicSource, library: LibraryStore, history: PlayHistory, random: @escaping () -> Double = { Double.random(in: 0 ..< 1) }) {
        self.source = source
        self.library = library
        self.history = history
        self.random = random
    }

    /// Новая сессия и первая порция. seed — «Волна по треку»: он играет первым; mode — режим волны.
    func start(seed: Track?, mode: WaveMode = .own) async throws -> [Track] {
        session = WaveSession(seed: seed, mode: mode)
        reasons = [:]
        var list = try await portion()
        if let seed {
            list.removeAll { $0.ref == seed.ref }
            list.insert(seed, at: 0)
            session.serve(seed)
            reasons[seed.ref] = "С него началась волна"
        }
        guard !list.isEmpty else { throw ServiceError(message: "Волне пока нечего предложить") }
        return list
    }

    /// Следующая порция в конец очереди.
    func more() async throws -> [Track] {
        try await portion()
    }

    /// Исход трека волны. true — пора пересобрать «Далее».
    func ended(_ track: Track, reward: Double, manualSkip: Bool, now: Date = Date()) -> Bool {
        session.ended(track, reward: reward, manualSkip: manualSkip, now: now)
    }

    /// Выданные треки так и не прозвучали — вернуть в пул.
    func unserve(_ tracks: [Track]) {
        for track in tracks { session.unserve(track) }
    }

    /// «Почему этот трек» для порции: от какого сида (трек или артист) волна его взяла.
    private func explain(_ out: [Track], origin: WaveOrigin, taste: Taste, liked: [Track], candidates: [Track], forgotten: [Track]) {
        var context = WaveReason.Context(seedOf: origin.seedOf, likes: Set(liked.map(\.ref)), forgotten: Set(forgotten.map(\.ref)),
                                         live: Set(session.good.map(\.ref)), waveSeed: session.seed?.ref, mode: session.mode)
        var pool: [Track] = candidates
        pool += history.recent
        pool += liked
        pool += session.good
        if let seed = session.seed { pool.append(seed) }
        for track in pool {
            context.tracks[track.ref] = track
            for artist in track.artists where context.artistNames[artist.ref] == nil {
                context.artistNames[artist.ref] = artist.name
            }
        }
        for track in out {
            reasons[track.ref] = WaveReason.text(for: track, known: taste.isKnown(track), context)
        }
    }

    private func portion() async throws -> [Track] {
        let liked = library.liked
        let likeRefs = liked.map(\.ref)
        let seedRefs = WaveMath.seeds(seed: session.seed, good: session.good, likes: likeRefs,
                                      finished: history.finishedRefs(limit: 10), recent: history.recent.map(\.ref),
                                      mode: session.mode, random: random)
        guard !seedRefs.isEmpty else {
            throw ServiceError(message: "Волне пока не от чего оттолкнуться — лайкни или послушай пару треков.")
        }
        let mode = session.mode
        // знакомое в котёл: популярное 1–2 привычных артистов (у волны по треку — его артиста); в «Незнакомом» — нет
        let artists: [String] = if mode == .new {
            []
        } else if let seed = session.seed {
            seed.mainArtistRef.map { [$0] } ?? []
        } else {
            WaveMath.sample(WaveMath.favoriteArtistRefs(liked: liked, recent: history.recent, limit: 15), mode == .own ? 2 : 1, random: random)
        }
        let source = source
        let limit = WaveMath.similarLimit(mode)
        async let similarLists = concurrentMap(seedRefs) { try await source.similar(to: $0, limit: limit) }
        async let topLists = concurrentMap(artists) { try await source.artistTop($0, limit: 10) }
        let (similar, tops) = await (similarLists, topLists)

        var origin = WaveOrigin()
        var candidates: [Track] = []
        let live = Set(session.good.map(\.ref))
        for (seed, list) in zip(seedRefs, similar) {
            guard let list else { continue }
            origin.add(seed: seed, list: list, live: live.contains(seed))
            candidates += list
        }
        for (artist, list) in zip(artists, tops) {
            guard let list else { continue }
            origin.addArtist(artist, list: list)
            candidates += list
        }
        guard !candidates.isEmpty else {
            throw ServiceError(message: "Похожих треков не нашлось — проверь сеть или лайкни что-нибудь ещё.")
        }

        let taste = history.taste(liked: liked)
        let bySeed = session.seed != nil
        // «Незнакомое»: второй шаг — похожие от лучших незнакомых (3 запроса)
        if mode == .new, !bySeed {
            let hops = WaveMath.hopSeeds(candidates, taste: taste, origin: origin, banned: library.disliked, k: 3)
            let more = await concurrentMap(hops) { try await source.similar(to: $0, limit: 20) }
            for (hop, list) in zip(hops, more) {
                guard let list else { continue }
                origin.add(seed: hop, list: list, live: false)
                candidates += list
            }
        }
        let familiar = WaveMath.familiarity(mode, bySeed: bySeed)
        var filter = WaveFilter(
            recent: history.playedRefs(withinDays: 7),
            banned: library.disliked,
            exclude: session.served,
            pausedArtists: session.paused,
            maxUnknown: familiar.maxUnknown,
            minPlaysUnknown: familiar.minPlays
        )
        if let seed = session.seed { filter.exclude.insert(seed.ref) }
        let noise = random
        var out = WaveMath.portion(candidates, taste: taste, origin: origin, session: session, filter: filter, noise: noise)
        let share = WaveMath.likedShare(mode, bySeed: bySeed)
        var forgotten: [Track] = []
        if share > 0 {
            forgotten = WaveMath.pickLiked(liked, taste: taste, session: session, filter: filter,
                                           playedMonth: history.playedRefs(withinDays: 30), k: share, noise: noise)
            out = WaveMath.insertLiked(out, liked: forgotten)
        }
        for track in out { session.serve(track) }
        explain(out, origin: origin, taste: taste, liked: liked, candidates: candidates, forgotten: forgotten)
        return out
    }
}
