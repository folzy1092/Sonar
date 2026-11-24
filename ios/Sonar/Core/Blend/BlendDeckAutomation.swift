import Foundation

// Ручки дека во время сведения на iPhone (docs/BLEND.md §13). На ПК кривые ставятся рампами Web Audio по часам
// контекста (`automation.ts`); у AVPlayer часов для рамп нет, поэтому значения считаются прямо по времени файла:
// тап знает, какой кусок файла сейчас играет, — значит, и такт перехода. Пауза, перемотка и сбой потока кривые
// не сдвигают. Отмена и окончание перехода — короткие рампы поверх кривых (`BlendRamp`).
//
// Чистая часть: её гоняют и звуковой поток (`BlendDeckDSP`, по кадрам), и дек HLS без тапа (по таймеру, только
// громкость).

/// Время файла дека → такт перехода (такт 0 — `outMs` A).
struct BlendBarMap: Hashable, Sendable {
    var bar0: Double
    var ms0: Double
    var msPerBar: Double

    func bar(atMs ms: Double) -> Double {
        bar0 + (ms - ms0) / msPerBar
    }

    /// A: такт 0 — точка выхода.
    static func a(_ plan: TransitionPlan, _ anA: BlendAnalysis) -> BlendBarMap {
        BlendBarMap(bar0: 0, ms0: plan.outMs, msPerBar: BlendPlanner.barMs(anA))
    }

    /// B: на такте `inAtBar` играет `inMs`, такт B длиннее или короче в `beatRatio` раз (как `expectedB`).
    static func b(_ plan: TransitionPlan, _ anB: BlendAnalysis) -> BlendBarMap {
        BlendBarMap(bar0: Double(plan.inAtBar), ms0: plan.inMs, msPerBar: plan.beatRatio * BlendPlanner.barMs(anB))
    }
}

/// Что играет дек: кривые одной стороны перехода.
struct BlendDeckProgram: Hashable, Sendable {
    var curves: BlendCurves
    var side: BlendSide
    /// Поправка громкости B (`gainDb` плана).
    var gainMul: Double
    var map: BlendBarMap

    func values(atMs ms: Double) -> DeckValues {
        BlendTimeline.deckValues(curves, side: side, bar: map.bar(atMs: ms), gainMul: gainMul)
    }
}

/// Рампа поверх кривых: к значениям `to` (или к текущим с другой громкостью `gain`) за `seconds`.
struct BlendRamp: Hashable, Sendable {
    var to: DeckValues?
    var gain: Double?
    var seconds: Double

    static func values(_ to: DeckValues, seconds: Double) -> BlendRamp {
        BlendRamp(to: to, gain: nil, seconds: seconds)
    }

    static func gain(_ gain: Double, seconds: Double) -> BlendRamp {
        BlendRamp(to: nil, gain: gain, seconds: seconds)
    }

    func target(from: DeckValues) -> DeckValues {
        let base = to ?? from
        return gain.map { base.with(.gain, $0) } ?? base
    }
}

/// Значения ручек дека по шагам. Пока есть рампы — идут они по очереди, потом держится последнее значение
/// (кривые больше не читаются: переход отменён или закончен). Новая программа сбрасывает всё.
struct BlendDeckAutomation: Sendable {
    /// Нейтраль: ФНЧ на этой частоте и выше — выключен (`BlendDeckDSP` обходит его).
    static let nyquist = 22050.0
    static let rest = BlendMix.restValues(nyquist: nyquist)

    private(set) var program: BlendDeckProgram?
    private(set) var current = BlendDeckAutomation.rest
    private var ramps: [BlendRamp] = []
    private var rampFrom: DeckValues?
    private var rampElapsed = 0.0
    private var held = false

    /// Ничего не меняет звук: без программы, без рамп и в нейтрали.
    var isIdle: Bool {
        program == nil && ramps.isEmpty && current == Self.rest
    }

    mutating func start(_ program: BlendDeckProgram?) {
        self = BlendDeckAutomation()
        self.program = program
    }

    mutating func enqueue(_ ramp: BlendRamp) {
        ramps.append(ramp)
    }

    /// Шаг на `dt` секунд; `ms` — где сейчас файл (nil — не знаем, кривые стоят).
    mutating func step(ms: Double?, dt: Double) -> DeckValues {
        if let ramp = ramps.first {
            let from = rampFrom ?? current
            rampFrom = from
            rampElapsed += dt
            let x = ramp.seconds > 0 ? min(1, rampElapsed / ramp.seconds) : 1
            current = Self.mix(from, ramp.target(from: from), x)
            if x >= 1 {
                ramps.removeFirst()
                rampFrom = nil
                rampElapsed = 0
                held = true
                // отмена или конец дошли до нейтрали — дек снова обычный, тап его обходит
                if ramps.isEmpty && current == Self.rest {
                    program = nil
                    held = false
                }
            }
            return current
        }
        guard !held, let program, let ms else { return current }
        current = program.values(atMs: ms)
        return current
    }

    /// Частоты — по экспоненте (на слух ровно), остальное — по прямой.
    static func mix(_ from: DeckValues, _ to: DeckValues, _ x: Double) -> DeckValues {
        // конец рампы — ровно цель: иначе нейтраль не совпадёт до бита и дек не уйдёт в обход
        if x >= 1 { return to }
        return DeckParam.allCases.reduce(from) { out, p in
            let a = from[p], b = to[p]
            let geometric = (p == .hpHz || p == .lpHz) && a > 0 && b > 0
            return out.with(p, geometric ? a * pow(b / a, x) : a + (b - a) * x)
        }
    }
}
