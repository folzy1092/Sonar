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

    /// Поправка громкости на такте (`gainMul` = громкость B под A), как `trimAt` на ПК. Только убавляем — тихий
    /// трек не раздуваем (иначе после перехода он «проседает» обратно): громкий B входит приглушённым, громкий A
    /// притихает к уровню B. К концу перехода поправка плавно (в дБ) уходит в 1 — B выходит на свою громкость.
    static func trim(_ c: BlendCurves, side: BlendSide, bar: Double, gainMul: Double) -> Double {
        let x = min(1, max(0, bar / max(1e-6, c.endBar)))
        if side == .b { return gainMul < 1 ? pow(gainMul, 1 - x) : 1 }
        return gainMul > 1 ? pow(gainMul, -x) : 1
    }

    /// Значение ручки дека на такте. A до начала перехода — в нейтрали; громкость — с поправкой `trim`.
    static func deckValue(_ c: BlendCurves, side: BlendSide, _ p: DeckParam, bar: Double, gainMul: Double = 1) -> Double {
        let rest = c.rest[p]
        if side == .a && bar < 0 { return rest }
        let v = BlendMix.valueAt(c[side][p], rest: rest, bar: bar)
        return p == .gain ? v * trim(c, side: side, bar: bar, gainMul: gainMul) : v
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
