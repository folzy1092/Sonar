import Foundation

// Планировщик сведения (docs/BLEND.md §7) — порт `windows/src/player/blend/planner.ts`, менять — в обоих местах
// и в тестах. По анализу A и B и настройкам — где выйти из A, где войти в B и каким видом. Чистая
// детерминированная функция `BlendPlanner.plan(a, b, opts:)`: перебирает такты конца A, такты входа B и виды,
// оценивает каждую тройку суммой весов (§7.2) и отдаёт топ-8 («Другой момент» берёт следующий).
// Оценка одной тройки — `BlendPlanner+Score.swift`.
//
// Время везде — позиция в самом треке (мс). Такт A номер k начинается в `firstBeatMs + (downbeat + 4k)·beatMs`;
// такты можно брать и за концом музыки (там тишина или затухание). «Якорь» — такт A, на котором A замолкает:
// для бас-свапа, фильтра и плавного — конец наложения, для эха — «раз» после последней доли фразы (сухой A
// гаснет, хвост эха идёт дальше), для «На дроп» — вход дропа B.

/// Вид перехода; строки — те же, что в настройке `audio.blend_type` на ПК.
enum BlendKind: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case bass, filter, echo, smooth, drop
}

/// `audio.blend_type`: «Авто» или конкретный вид.
enum BlendType: String, Codable, CaseIterable, Sendable {
    case auto, bass, filter, echo, smooth, drop

    /// Конкретный вид; у «Авто» — nil.
    var kind: BlendKind? { BlendKind(rawValue: rawValue) }
}

/// Слагаемые оценки (§7.2) — в том же порядке, что `WEIGHTS` на ПК: от порядка зависит сумма.
enum ScorePart: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case tempo, key, energy, phrases, cut, vocal, fit, rating

    var weight: Double {
        switch self {
        case .tempo: 3
        case .key: 2
        case .energy: 2
        case .phrases: 1.5
        case .cut: 1
        case .vocal: 1
        case .fit: 1
        case .rating: 0.5
        }
    }
}

struct PlanOpts: Hashable, Sendable {
    /// `audio.blend_type`.
    var type: BlendType
    /// `audio.blend_length`, с.
    var lengthSec: Double
    /// `audio.blend_cut`: сколько можно срезать с конца A и с начала B, с.
    var cutSec: Double
    /// `audio.blend_tempo`: допуск темпа, %.
    var tempoTolPct: Double
    /// `audio.blend_key`: можно сдвигать тон B.
    var keyShift: Bool
    /// Собственные скорости треков (§6.3) и связана ли с ней высота тона.
    var rateA: Double
    var rateB: Double
    var linkedA: Bool
    var linkedB: Bool
    /// Перевес 👍/👎 по видам за 60 дней, −1…1 (§8.6).
    var ratings: [BlendKind: Double] = [:]
}

struct TransitionPlan: Codable, Hashable, Sendable {
    var kind: BlendKind
    /// Темп сводится и доли совпадают.
    var sync: Bool
    /// Длина перехода в тактах A.
    var bars: Int
    /// Позиция A в начале перехода (начало такта).
    var outMs: Double
    /// Позиция A, где он замолкает (конец полосы прогресса, §6.5).
    var endAMs: Double
    /// Позиция B, с которой он стартует (начало такта).
    var inMs: Double
    /// На каком такте перехода стартует B: 0 — сразу, у «Эха» — 1, у «На дроп» — в конце разгона.
    var inAtBar: Int
    /// Эффективные темпы с собственными скоростями, уд/мин.
    var tempoA: Double
    var tempoB: Double
    /// B считается в удвоенной (2) или половинной (0.5) сетке.
    var beatRatio: Double
    /// Сдвиг тона B на время перехода, полутонов.
    var shift: Double
    /// Поправка громкости B под A, дБ.
    var gainDb: Double
    /// Срезано с конца A и с начала B, мс.
    var cutOutMs: Double
    var cutInMs: Double
    /// 0…1.
    var score: Double
    var parts: [ScorePart: Double]
}

enum BlendPlanner {
    static let topPlans = 8
    /// Длина перехода в тактах — целая, чтобы «Коротко · Норм · Длинно» не слипались ни при каком темпе.
    static let minBars = 2
    static let maxBars = 32
    /// С такой длины (тактов) — только чётные: при 3–4 тактах на медленном темпе иначе слипаются длины.
    static let evenFrom = 3.5
    /// «Плавный» — вдвое длиннее выбранной длины.
    static let smoothFactor = 2
    /// «Эхо»: сколько тактов эхо набирается до «раз» (при длине от 6 тактов — 2).
    static let echoLeadLongFrom = 6
    /// Сухой A после «раз» у «Эха» гаснет за полтакта, а не обрывается (такты). Зеркало в `BlendMix`.
    static let echoDryFadeBars = 0.5
    /// A должен доиграть до конца своей части перехода с запасом: иначе конец файла оборвёт переход.
    static let endSafeMs = 300.0
    static let maxGainDb = 9.0
    /// Тактов по краям наложения для энергии.
    static let edgeBars = 2
    static let calm = 0.4
    static let loud = 0.6
    static let spectrumGap = 0.35
    static let vocalFrom = 0.5
    /// Сколько теряет вид при несовместимой тональности (§7.4).
    static let clashFit = 0.5
    static let beatRatios: [Double] = [0.5, 1, 2]
    /// Громкость тишины (~LUFS) — как `SILENT_LUFS` в `loudness.ts`.
    static let silentLufs = -70.0
    /// Долгое наложение двух треков — тут важна тональность и вокал.
    static let overlapKinds: Set<BlendKind> = [.bass, .filter, .smooth]
    static let weightSum = ScorePart.allCases.reduce(0.0) { $0 + $1.weight }

    static func barMs(_ t: BlendAnalysis) -> Double {
        Double(beatsPerBar) * t.beatMs
    }

    static func barTime(_ t: BlendAnalysis, _ bar: Int) -> Double {
        t.firstBeatMs + Double(t.downbeat + beatsPerBar * bar) * t.beatMs
    }

    /// Длина перехода в тактах: секунды при темпе A, до целого такта, от 4 тактов — до чётного (ровнее по фразам), 2…32.
    static func lengthBars(_ lengthSec: Double, tempo: Double) -> Int {
        let bars = (lengthSec * tempo) / 60 / Double(beatsPerBar)
        guard bars.isFinite else { return minBars }
        let whole = bars < evenFrom ? BlendMath.jsRoundInt(bars) : 2 * BlendMath.jsRoundInt(bars / 2)
        return min(maxBars, max(minBars, whole))
    }

    /// B ближе к удвоенному или половинному темпу A, чем к тому же, — считаем его в такой сетке.
    static func beatRatioOf(_ ratio: Double) -> Double {
        let distance = { (k: Double) in abs(log2(ratio / k)) }
        return beatRatios.dropFirst().reduce(beatRatios[0]) { best, k in distance(k) < distance(best) ? k : best }
    }

    /// Какие виды пробовать. Ручной вид — всегда он (без синка — на своих скоростях, §6.3); «Авто» без синка
    /// не берёт бас-свап и дроп: две разные сетки на одном басу — каша.
    static func kindsFor(_ type: BlendType, syncOk: Bool) -> [BlendKind] {
        guard let kind = type.kind else { return syncOk ? BlendKind.allCases : [.filter, .echo, .smooth] }
        return [kind]
    }

    /// Лучшие варианты перехода A → B, лучший первым; пусто — свести нечем (обычный кроссфейд).
    static func plan(_ a: BlendAnalysis, _ b: BlendAnalysis, opts: PlanOpts) -> [TransitionPlan] {
        guard a.bpm > 0, b.bpm > 0, opts.rateA > 0, opts.rateB > 0 else { return [] }
        // на ПК битая длина доли повесила бы перебор тактов; у живого анализа она всегда 60000 / bpm > 0
        guard a.beatMs > 0, b.beatMs > 0 else { return [] }
        let p = BlendPair(a, b, opts: opts)
        let cutMs = max(0, opts.cutSec) * 1000
        let anchors = anchorsOf(a, cutMs: cutMs)
        let entries = entriesOf(b, cutMs: cutMs)
        var seen = Set<PlanID>()
        var out: [TransitionPlan] = []
        for kind in kindsFor(opts.type, syncOk: p.syncOk) {
            for anchor in anchors {
                for entry in entries {
                    guard let t = evaluate(p, kind: kind, anchor: anchor, entry: entry) else { continue }
                    let id = PlanID(kind: t.kind, outMs: t.outMs, inMs: t.inMs)
                    if seen.contains(id) { continue }
                    seen.insert(id)
                    out.append(t)
                }
            }
        }
        return Array(out.sorted(by: isBetter).prefix(topPlans))
    }

    private struct PlanID: Hashable {
        var kind: BlendKind
        var outMs: Double
        var inMs: Double
    }

    /// Такты A, где он может замолкнуть: от `endMs − cut` до конца файла (или такт за концом музыки).
    private static func anchorsOf(_ a: BlendAnalysis, cutMs: Double) -> [Int] {
        let from = a.endMs - cutMs
        let to = min(a.durationMs, a.endMs + barMs(a))
        var out: [Int] = []
        var k = 0
        while barTime(a, k) <= to {
            if barTime(a, k) >= from { out.append(k) }
            k += 1
        }
        return out
    }

    /// Такты B, с которых он может стартовать: не дальше `startMs + cut` и в пределах музыки.
    private static func entriesOf(_ b: BlendAnalysis, cutMs: Double) -> [Int] {
        var out: [Int] = []
        var j = 0
        while j < b.bars.energy.count && barTime(b, j) <= b.startMs + cutMs {
            if barTime(b, j) >= 0 { out.append(j) }
            j += 1
        }
        return out
    }

    private static func kindOrder(_ k: BlendKind) -> Int {
        BlendKind.allCases.firstIndex(of: k) ?? 0
    }

    /// Порядок топа: оценка, потом вид по списку, потом поздний выход из A, потом ранний вход в B.
    private static func isBetter(_ x: TransitionPlan, _ y: TransitionPlan) -> Bool {
        if x.score != y.score { return x.score > y.score }
        if x.kind != y.kind { return kindOrder(x.kind) < kindOrder(y.kind) }
        if x.outMs != y.outMs { return x.outMs > y.outMs }
        return x.inMs < y.inMs
    }
}

/// Всё, что считается один раз на пару треков.
struct BlendPair {
    let a: BlendAnalysis
    let b: BlendAnalysis
    let opts: PlanOpts
    let tempoA: Double
    let tempoB: Double
    let beatRatio: Double
    let syncOk: Bool
    let tempoScore: Double
    /// Длина перехода по настройке, тактов A.
    let base: Int
    let keySync: CamelotMatch
    let keyFree: CamelotMatch
    let keyFixed: CamelotMatch
    let phrasesA: [Int: PhraseKind]
    let phrasesB: [Int: PhraseKind]
    let gainDb: Double

    init(_ a: BlendAnalysis, _ b: BlendAnalysis, opts: PlanOpts) {
        self.a = a
        self.b = b
        self.opts = opts
        tempoA = a.bpm * opts.rateA
        tempoB = b.bpm * opts.rateB
        beatRatio = BlendPlanner.beatRatioOf(tempoB / tempoA)
        let diff = abs(tempoB / beatRatio / tempoA - 1)
        let tol = max(0, opts.tempoTolPct) / 100
        tempoScore = tol > 0 ? BlendMath.clamp(1 - diff / tol, 0, 1) : (diff < 1e-6 ? 1 : 0)
        syncOk = diff <= tol + 1e-9 && a.gridStable && b.gridStable
        let driftA = Self.drift(opts.linkedA, opts.rateA)
        // в синке B играет со скоростью, при которой его доли совпадают с долями A
        let syncRateB = (tempoA * beatRatio) / b.bpm
        let match = { (rateB: Double, allow: Bool) in
            BlendCamelot.keyMatch(a.key, b.key, driftA: driftA, driftB: Self.drift(opts.linkedB, rateB), allowShift: allow)
        }
        base = BlendPlanner.lengthBars(opts.lengthSec, tempo: tempoA)
        keySync = match(syncRateB, opts.keyShift)
        keyFree = match(opts.rateB, opts.keyShift)
        keyFixed = match(opts.rateB, false)
        phrasesA = Dictionary(a.phrases.map { ($0.bar, $0.kind) }, uniquingKeysWith: { $1 })
        phrasesB = Dictionary(b.phrases.map { ($0.bar, $0.kind) }, uniquingKeysWith: { $1 })
        let silent = a.loudness <= BlendPlanner.silentLufs || b.loudness <= BlendPlanner.silentLufs
        let maxGain = BlendPlanner.maxGainDb
        gainDb = silent ? 0 : BlendMath.round(BlendMath.clamp(a.loudness - b.loudness, -maxGain, maxGain), 1)
    }

    private static func drift(_ linked: Bool, _ rate: Double) -> Double {
        linked && rate > 0 ? 12 * log2(rate) : 0
    }
}
