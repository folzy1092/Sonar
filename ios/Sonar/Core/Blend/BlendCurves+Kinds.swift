import Foundation

// Кривые по видам перехода (docs/BLEND.md §8) — порт `bass` / `filter` / `echo` / `smooth` / `drop` из
// `windows/src/player/blend/curves.ts`, менять — в обоих местах и в тестах.

extension BlendMix {
    static func key(_ bar: Double, _ v: Double, _ shape: BlendCurveShape = .lin) -> BlendCurveKey {
        BlendCurveKey(bar: bar, v: v, shape: shape)
    }

    /// Секунды → такты при самом быстром темпе перехода (резкое место не короче своих мс).
    static func barsOf(_ plan: TransitionPlan, _ sec: Double) -> Double {
        let ratio = plan.beatRatio != 0 && !plan.beatRatio.isNaN ? plan.beatRatio : 1
        let fastest = max(plan.tempoA, plan.tempoB / ratio)
        return (sec * fastest) / 240
    }

    /// Шаг за `sec` с центром на `bar`.
    static func step(_ plan: TransitionPlan, _ bar: Double, _ from: Double, _ to: Double, _ sec: Double) -> [BlendCurveKey] {
        let half = barsOf(plan, sec) / 2
        return [key(bar - half, from), key(bar + half, to)]
    }

    static func bass(_ plan: TransitionPlan) -> (BlendDeckCurves, BlendDeckCurves) {
        let f = Double(plan.bars) / bassGrid
        let swap = Double(plan.bars) / 2
        let a: BlendDeckCurves = [
            .gain: [key(7 * f, 1), key(8 * f, 0, .eq)],
            .low: step(plan, swap, 0, offDb, swapSec),
            .mid: [key(4 * f, 0), key(7 * f, -12)],
            .high: [key(2 * f, 0), key(4 * f, -6), key(7 * f, offDb)],
        ]
        let b: BlendDeckCurves = [
            .gain: [key(0, 0), key(2 * f, 1, .eq)],
            .low: step(plan, swap, offDb, 0, swapSec),
            .mid: [key(2 * f, -6), key(4 * f, 0)],
        ]
        return (a, b)
    }

    static func filter(_ plan: TransitionPlan, nyquist: Double) -> (BlendDeckCurves, BlendDeckCurves) {
        let n = Double(plan.bars)
        // такт, где экспонента HPF у A проходит 150 Гц (≈ середина), — оттуда бас B за такт выходит в 0 дБ
        let handoff = (n * log(filterBassHandoffHz / hpFrom)) / log(filterHpTo / hpFrom)
        let a: BlendDeckCurves = [
            .gain: [key(n - 1, 1), key(n, 0, .eq)],
            .hpHz: [key(0, hpFrom), key(n, filterHpTo, .exp)],
            .hpQ: [key(n - 2, qRest), key(n, filterQTo)],
        ]
        let b: BlendDeckCurves = [
            .gain: [key(0, 0), key(min(2, n / 2), 1, .eq)],
            .lpHz: [key(0, filterLpFrom), key(n, nyquist, .exp)],
            .low: [key(handoff, filterBLowDb), key(handoff + 1, 0)],
        ]
        return (a, b)
    }

    static func echo(_ plan: TransitionPlan) -> (BlendDeckCurves, BlendDeckCurves) {
        let one = Double(plan.inAtBar)
        let n = Double(plan.bars)
        let lastBeat = one - beat
        let dryEnd = one + BlendPlanner.echoDryFadeBars
        let open = barsOf(plan, dropSec)
        // эхо набирается от начала перехода до последней доли, сухой A гаснет полтакта после «раз»; эхо питается
        // после громкости дека — новых повторов нет, хвост крутится в петле до конца перехода
        let a: BlendDeckCurves = [
            .gain: [key(one, 1), key(dryEnd, 0, .eq)],
            .echoSend: [key(0, 0), key(lastBeat, 1), key(n - open, 1), key(n, 0)],
            .feedback: [key(0, 0), key(lastBeat, echoFeedback), key(dryEnd, echoFeedback), key(n, echoFeedbackTail)],
        ]
        let b: BlendDeckCurves = [
            .gain: [key(one, 0), key(one + echoBInBars, 1, .eq)],
            .low: [key(one, offDb), key(one + echoBBassBars, 0)],
        ]
        return (a, b)
    }

    static func smooth(_ plan: TransitionPlan) -> (BlendDeckCurves, BlendDeckCurves) {
        let n = Double(plan.bars)
        let a: BlendDeckCurves = [
            .gain: [key(0, 1), key(n, 0, .eq)],
            .low: [key((3 * n) / 8, 0), key(n / 2, smoothMeetDb), key((3 * n) / 4, offDb)],
            .mid: [key(0, 0), key(n, smoothFadeDb)],
            .high: [key(0, 0), key(n, smoothFadeDb)],
        ]
        let b: BlendDeckCurves = [
            .gain: [key(0, 0), key(n, 1, .eq)],
            .low: [key(n / 4, offDb), key(n / 2, smoothMeetDb), key((5 * n) / 8, 0)],
            .mid: [key(0, smoothFadeDb), key(n, 0)],
            .high: [key(0, smoothFadeDb), key(n, 0)],
        ]
        return (a, b)
    }

    static func drop(_ plan: TransitionPlan) -> (BlendDeckCurves, BlendDeckCurves) {
        let n = Double(plan.bars)
        let cut = barsOf(plan, dropSec)
        let tail = n + 2
        let a: BlendDeckCurves = [
            .gain: [key(0, 1), key(n, dropGain), key(n + cut, 0)],
            .hpHz: [key(0, hpFrom), key(n, dropHpTo, .exp)],
            .mid: [key(n - 1, 0), key(n, dropMidDb)],
            // разгон уходит в эхо: A срезается на дропе, а хвост ещё два такта звенит поверх B
            .echoSend: [key(n - 1, 0), key(n - beat, 1), key(tail - cut, 1), key(tail, 0)],
            .feedback: [key(n - 1, 0), key(n - beat, dropEchoFeedback), key(tail, 0)],
        ]
        let b: BlendDeckCurves = [.gain: [key(n, 0), key(n + cut, 1)]]
        return (a, b)
    }
}
