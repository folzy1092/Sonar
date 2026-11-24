import Foundation

// Кривые сведения (docs/BLEND.md §8) — порт `windows/src/player/blend/curves.ts`, менять — в обоих местах и в
// тестах. Чем станет каждая ручка обеих цепочек на каждом такте перехода. Чистые данные: по плану — ключевые
// точки по тактам A от начала перехода (такт 0 = `outMs`), между ними — линейно, по экспоненте (частоты) или с
// равной мощностью (громкость). Движок только сэмплирует их и ставит рампами (§6.3).
//
// Резкие места (свап басов, сухой A на «раз», дроп) — тоже рампы, но короткие: 5–12 мс, не короче 5 мс ни при
// каком темпе перехода.

/// Константы цепочки дека — зеркало `deck-chain.ts`.
enum BlendChain {
    static let lowHz = 180.0
    static let midHz = 1000.0
    static let midQ = 0.7
    static let highHz = 3200.0
    /// Пределы полосы изолятора: −40 дБ — полоса выключена.
    static let isoMinDb = -40.0
    static let isoMaxDb = 6.0
    /// hp в покое — ниже слышимого; lp в покое — на Найквисте.
    static let hpRestHz = 10.0
    static let echoHpHz = 300.0
    static let echoMaxSec = 4.0
    /// Перекрытие при включении и выключении тона.
    static let pitchXfadeSec = 0.03
    /// Самый короткий ход параметра — короче щёлкает.
    static let minRampSec = 0.005
}

/// Ручки цепочки дека; порядок — как `DECK_PARAMS` на ПК.
enum DeckParam: String, Codable, CaseIterable, Sendable {
    case gain, low, mid, high, hpHz, hpQ, lpHz, echoSend, feedback
}

/// Значения всех ручек дека.
struct DeckValues: Hashable, Sendable {
    var gain: Double
    var low: Double
    var mid: Double
    var high: Double
    var hpHz: Double
    var hpQ: Double
    var lpHz: Double
    var echoSend: Double
    var feedback: Double

    subscript(p: DeckParam) -> Double {
        get {
            switch p {
            case .gain: gain
            case .low: low
            case .mid: mid
            case .high: high
            case .hpHz: hpHz
            case .hpQ: hpQ
            case .lpHz: lpHz
            case .echoSend: echoSend
            case .feedback: feedback
            }
        }
        set {
            switch p {
            case .gain: gain = newValue
            case .low: low = newValue
            case .mid: mid = newValue
            case .high: high = newValue
            case .hpHz: hpHz = newValue
            case .hpQ: hpQ = newValue
            case .lpHz: lpHz = newValue
            case .echoSend: echoSend = newValue
            case .feedback: feedback = newValue
            }
        }
    }

    /// Копия с другим значением одной ручки.
    func with(_ p: DeckParam, _ v: Double) -> DeckValues {
        var out = self
        out[p] = v
        return out
    }
}

/// Как прийти к точке от предыдущей: по прямой, по экспоненте (частоты), с равной мощностью (громкость).
enum BlendCurveShape: String, Sendable {
    case lin, exp, eq
}

struct BlendCurveKey: Hashable, Sendable {
    var bar: Double
    var v: Double
    var shape: BlendCurveShape
}

/// Какой дек: уходящий A или входящий B.
enum BlendSide: String, Sendable, CaseIterable {
    case a, b
}

typealias BlendDeckCurves = [DeckParam: [BlendCurveKey]]

struct BlendCurves: Hashable, Sendable {
    var a: BlendDeckCurves
    var b: BlendDeckCurves
    /// Такт, где A замолк и B становится текущим (`endAMs`).
    var promoteBar: Double
    /// Такт, после которого автоматизации нет (у «Эха» — конец хвоста).
    var endBar: Double
    /// Задержка эха, с (¾ доли A).
    var echoDelaySec: Double
    var rest: DeckValues

    subscript(side: BlendSide) -> BlendDeckCurves {
        side == .a ? a : b
    }
}

enum BlendMix {
    /// «−∞» изолятора.
    static let offDb = BlendChain.isoMinDb
    static let qRest = 0.5.squareRoot()
    /// Длительности резких мест (§8), с.
    static let swapSec = 0.008
    static let dropSec = 0.005
    /// Бас-свап расписан на 8 тактов; длиннее или короче — те же доли.
    /// Бас-свап: B до свапа звучит на 0.8 одной серединой, A после свапа держится на 0.8 и гаснет второй половиной
    /// остатка; верх A после свапа сразу −20 дБ — две пары тарелок не звенят вместе.
    static let bassHold = 0.8
    static let bassHighDb = -20.0
    static let filterHpTo = 1200.0
    static let filterQTo = 3.0
    static let filterLpFrom = 300.0
    static let filterBLowDb = -12.0
    /// Пока HPF у A ниже этой частоты, бас B приглушён: два баса не дерутся.
    static let filterBassHandoffHz = 150.0
    static let echoFeedback = 0.55
    static let echoFeedbackTail = 0.3
    /// B у «Эха» выходит в полную громкость за такт, бас — за два: не стена звука на «раз».
    static let echoBInBars = 1.0
    static let echoBBassBars = 2.0
    /// «На дроп»: последний такт разгона A уходит в эхо, хвост звенит поверх дропа B.
    static let dropEchoFeedback = 0.45
    static let dropHpTo = 800.0
    static let dropGain = pow(10, -3.0 / 20)
    static let dropMidDb = 3.0
    static let hpFrom = 20.0
    /// «Плавный»: басы встречаются на середине по −3 дБ (с громкостью −3 — по −6 каждый).
    static let smoothMeetDb = -3.0
    static let smoothFadeDb = -12.0
    static let beat = 0.25

    /// Нейтраль цепочки: всё прозрачно, эхо молчит.
    static func restValues(nyquist: Double) -> DeckValues {
        DeckValues(
            gain: 1, low: 0, mid: 0, high: 0, hpHz: BlendChain.hpRestHz, hpQ: qRest, lpHz: nyquist, echoSend: 0, feedback: 0
        )
    }

    static func curvesFor(_ plan: TransitionPlan, nyquist: Double) -> BlendCurves {
        let (a, b): (BlendDeckCurves, BlendDeckCurves) = switch plan.kind {
        case .bass: bass(plan)
        case .filter: filter(plan, nyquist: nyquist)
        case .echo: echo(plan)
        case .smooth: smooth(plan)
        case .drop: drop(plan)
        }
        let lastKey = [a, b].flatMap { $0.values.flatMap { $0.map(\.bar) } }.max() ?? -.infinity
        return BlendCurves(
            a: a,
            b: b,
            // A играет, пока не замолк: у «Эха» — ещё полтакта затухания после «раз»
            promoteBar: plan.kind == .echo ? Double(plan.inAtBar) + BlendPlanner.echoDryFadeBars : Double(plan.bars),
            endBar: max(Double(plan.bars), lastKey),
            echoDelaySec: (0.75 * 60) / plan.tempoA,
            rest: restValues(nyquist: nyquist)
        )
    }

    /// Значение кривой на такте: до первой точки — её значение, после последней — последней, пусто — нейтраль.
    static func valueAt(_ curve: [BlendCurveKey]?, rest: Double, bar: Double) -> Double {
        guard let curve, let first = curve.first, let last = curve.last else { return rest }
        if bar <= first.bar { return first.v }
        for i in 1..<curve.count {
            let to = curve[i]
            if bar > to.bar { continue }
            let from = curve[i - 1]
            let span = to.bar - from.bar
            return span > 0 ? between(from, to, (bar - from.bar) / span) : to.v
        }
        return last.v
    }

    /// Значения обеих цепочек на такте перехода.
    static func paramsAt(_ c: BlendCurves, bar: Double) -> (a: DeckValues, b: DeckValues) {
        (deckAt(c.a, rest: c.rest, bar: bar), deckAt(c.b, rest: c.rest, bar: bar))
    }

    /// Такты ключевых точек в (from, to]: на них движок ставит точку рампы точно.
    static func keyBars(_ c: BlendCurves, from: Double, to: Double) -> [Double] {
        let bars = [c.a, c.b].flatMap { $0.values.flatMap { $0.map(\.bar) } }.filter { $0 > from && $0 <= to }
        return Set(bars).sorted()
    }

    struct Step: Hashable, Sendable {
        var side: BlendSide
        var param: DeckParam
        var bars: Double
    }

    /// Соседние точки с разными значениями — по ним тест ловит резкие места короче 5 мс.
    static func steps(_ c: BlendCurves) -> [Step] {
        BlendSide.allCases.flatMap { side in
            DeckParam.allCases.flatMap { p -> [Step] in
                let curve = c[side][p] ?? []
                guard curve.count > 1 else { return [] }
                return (1..<curve.count).compactMap { i in
                    curve[i].v != curve[i - 1].v ? Step(side: side, param: p, bars: curve[i].bar - curve[i - 1].bar) : nil
                }
            }
        }
    }

    /// Общий темп перехода в сетке A, уд/мин (§6.3): из `TA` в `TB / beatRatio` по smoothstep за всю длину.
    /// nil — без синка, каждый дек на своей скорости.
    static func tempoAt(_ plan: TransitionPlan, bar: Double) -> Double? {
        guard plan.sync else { return nil }
        let x = min(1, max(0, bar / Double(plan.bars)))
        let to = plan.tempoB / plan.beatRatio
        return plan.tempoA + (to - plan.tempoA) * (x * x * (3 - 2 * x))
    }

    // MARK: - Внутреннее

    private static func between(_ from: BlendCurveKey, _ to: BlendCurveKey, _ x: Double) -> Double {
        if x >= 1 { return to.v } // cos(π/2) ≠ 0 в плавающей точке
        if to.shape == .eq { return from.v * cos((Double.pi / 2) * x) + to.v * sin((Double.pi / 2) * x) }
        if to.shape == .exp && from.v > 0 && to.v > 0 { return from.v * pow(to.v / from.v, x) }
        return from.v + (to.v - from.v) * x
    }

    private static func deckAt(_ d: BlendDeckCurves, rest: DeckValues, bar: Double) -> DeckValues {
        DeckParam.allCases.reduce(rest) { out, p in out.with(p, valueAt(d[p], rest: rest[p], bar: bar)) }
    }
}
