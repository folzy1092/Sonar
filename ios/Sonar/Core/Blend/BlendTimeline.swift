import Foundation

// Кривые → значения ручек деков во времени (docs/BLEND.md §6.3) — порт чистой части
// `windows/src/player/blend/automation.ts` (`deckValue`, `curvedParams`, `deckValues`, `spanBars`) и
// `startBar` / `expectedB` из `controller.svelte.ts`, менять — в обоих местах и в тестах.

/// Окно, на которое движок кладёт рампы.
struct BlendSpan: Hashable, Sendable {
    /// Такт сейчас.
    var bar: Double
    /// Время аудио-контекста сейчас, с.
    var t0: Double
    /// Секунд на такт при текущем темпе.
    var secPerBar: Double
    /// На сколько секунд вперёд класть рампы.
    var horizonSec: Double
}

enum BlendTimeline {
    /// Шаг выборки кривой между ключевыми тактами, с.
    static let sampleSec = 0.1
    /// У синка B стартует за столько тактов до входа.
    static let leadBars = 2.0

    /// Значение ручки дека на такте. A до начала перехода — в нейтрали; громкость B — с поправкой `gainMul`.
    static func deckValue(_ c: BlendCurves, side: BlendSide, _ p: DeckParam, bar: Double, gainMul: Double = 1) -> Double {
        let rest = c.rest[p]
        if side == .a && bar < 0 { return rest }
        let v = BlendMix.valueAt(c[side][p], rest: rest, bar: bar)
        return p == .gain && side == .b ? v * gainMul : v
    }

    /// Ручки, у которых в этом переходе есть кривая.
    static func curvedParams(_ c: BlendCurves, side: BlendSide) -> [DeckParam] {
        DeckParam.allCases.filter { !(c[side][$0] ?? []).isEmpty }
    }

    /// Все значения дека на такте (для ручек без кривой — нейтраль).
    static func deckValues(_ c: BlendCurves, side: BlendSide, bar: Double, gainMul: Double = 1) -> DeckValues {
        DeckParam.allCases.reduce(c.rest) { out, p in
            out.with(p, deckValue(c, side: side, p, bar: bar, gainMul: gainMul))
        }
    }

    /// Такты точек рампы в окне: ключевые + равномерные выборки, по порядку, без повторов.
    static func spanBars(_ c: BlendCurves, _ s: BlendSpan) -> [Double] {
        let to = s.bar + s.horizonSec / s.secPerBar
        let stepBars = sampleSec / s.secPerBar
        var bars = Set(BlendMix.keyBars(c, from: s.bar, to: to))
        // накопление сложением, как на ПК, — те же такты до последнего бита
        var x = s.bar + stepBars
        while x < to {
            bars.insert(x)
            x += stepBars
        }
        bars.insert(to)
        return bars.sorted()
    }

    /// Где должен быть B (мс файла) на такте перехода.
    static func expectedB(_ plan: TransitionPlan, _ anB: BlendAnalysis, bar: Double) -> Double {
        plan.inMs + (bar - Double(plan.inAtBar)) * plan.beatRatio * BlendPlanner.barMs(anB)
    }

    /// Такт, с которого играет B: у синка — за 2 такта до входа (но не раньше начала файла), у «Эха» — на входе.
    static func startBar(_ plan: TransitionPlan, _ anB: BlendAnalysis) -> Double {
        let inAt = Double(plan.inAtBar)
        if !plan.sync { return inAt }
        let fromFileStart = inAt - plan.inMs / (plan.beatRatio * BlendPlanner.barMs(anB))
        return max(inAt - leadBars, fromFileStart)
    }
}
