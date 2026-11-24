import Foundation

// Оценка одной тройки «якорь A · вход B · вид» (docs/BLEND.md §7.2, §7.5) — порт `evaluate` и соседей из
// `windows/src/player/blend/planner.ts`, менять — в обоих местах и в тестах.

extension BlendPlanner {
    /// Сколько тактов идёт переход, сколько тактов A до якоря и на каком такте стартует B.
    struct PlanShape {
        var bars: Int
        var lead: Int
        var inAtBar: Int
    }

    /// Что известно о паре в этой точке — по этому вид получает бонус (§7.5).
    struct Facts {
        var syncOk: Bool
        var clash: Bool
        var calm: Bool
        var loud: Bool
        var outroA: Bool
        var introB: Bool
        var dropB: Bool
        var spectrumGap: Bool
    }

    static func shapeOf(_ kind: BlendKind, base: Int) -> PlanShape {
        let short = base >= 8 ? longShortBars : shortBars
        switch kind {
        case .echo: return PlanShape(bars: 1 + short, lead: 1, inAtBar: 1)
        case .drop: return PlanShape(bars: short, lead: short, inAtBar: short)
        case .smooth: return PlanShape(bars: max(smoothMinBars, base), lead: max(smoothMinBars, base), inAtBar: 0)
        case .bass, .filter: return PlanShape(bars: base, lead: base, inAtBar: 0)
        }
    }

    /// Среднее `xs[from..<to]`; за краем массива — нули, отрицательные индексы не считаются.
    static func mean(_ xs: [Double], _ from: Int, _ to: Int) -> Double {
        let lo = max(0, from)
        guard to > lo else { return 0 }
        let sum = (lo..<to).reduce(0.0) { $0 + ($1 < xs.count ? xs[$1] : 0) }
        return sum / Double(to - lo)
    }

    static func startScore(_ phrases: [Int: PhraseKind], _ bar: Int) -> Double {
        if phrases[bar] == .outro { return 1 }
        if phrases[bar] != nil { return 0.8 }
        return bar % 4 == 0 ? 0.4 : 0.1
    }

    static func endScore(_ phrases: [Int: PhraseKind], nBars: Int, _ bar: Int) -> Double {
        if bar == nBars { return 1 }
        if bar > nBars { return 0.6 }
        if phrases[bar] != nil { return 0.9 }
        return bar % 4 == 0 ? 0.4 : 0.1
    }

    static func inScore(_ phrases: [Int: PhraseKind], _ bar: Int, kind: BlendKind) -> Double {
        let at = phrases[bar]
        let perfect = kind == .drop ? at == .drop : (bar == 0 || at == .intro)
        if perfect { return 1 }
        if at != nil { return 0.8 }
        return bar % 4 == 0 ? 0.4 : 0.1
    }

    /// Вид фразы, в которой лежит такт.
    static func phraseAt(_ t: BlendAnalysis, _ bar: Int) -> PhraseKind? {
        t.phrases.reduce(nil) { kind, p in p.bar <= bar ? p.kind : kind }
    }

    /// Насколько вид подходит паре (§7.5): не правило, а бонус.
    static func kindFit(_ kind: BlendKind, _ f: Facts) -> Double {
        let fit: Double
        switch kind {
        case .echo: fit = !f.syncOk || f.clash ? 1 : 0.3
        case .smooth: fit = f.calm ? 1 : 0.4
        case .bass: fit = f.outroA && f.introB ? 1 : 0.5
        case .drop: fit = f.dropB ? (f.loud ? 1 : 0.6) : 0.1
        case .filter: fit = f.spectrumGap ? 1 : 0.5
        }
        return overlapKinds.contains(kind) && f.clash ? fit * clashFit : fit
    }

    static func keyFor(_ p: BlendPair, _ kind: BlendKind, sync: Bool) -> (term: Double, match: CamelotMatch) {
        if !overlapKinds.contains(kind) {
            // наложения нет или оно — хвост эха: тон не сдвигаем, а несовместимость почти не слышна
            var fixed = p.keyFixed
            fixed.shift = 0
            return (max(0.5, p.keyFixed.score), fixed)
        }
        let match = sync ? p.keySync : p.keyFree
        return (match.score, match)
    }

    static func evaluate(_ p: BlendPair, kind: BlendKind, anchor: Int, entry: Int) -> TransitionPlan? {
        let a = p.a
        let b = p.b
        let shape = shapeOf(kind, base: p.base)
        let outBar = anchor - shape.lead
        let outMs = barTime(a, outBar)
        if outBar < 0 || outMs < a.startMs { return nil }
        let sync = kind == .echo ? false : p.syncOk
        let nA = a.bars.energy.count
        let overlapB = max(1, Int(BlendMath.jsRound(Double(shape.bars) * p.beatRatio)))
        let energyA = mean(a.bars.energy, anchor - edgeBars, anchor)
        let energyB = mean(b.bars.energy, entry, entry + edgeBars)
        let midA = mean(a.bars.mid, outBar, anchor)
        let midB = mean(b.bars.mid, entry, entry + overlapB)
        let key = keyFor(p, kind, sync: sync)
        let endAMs = barTime(a, anchor)
        let inMs = barTime(b, entry)
        let cutOutMs = max(0, a.endMs - endAMs)
        let cutInMs = max(0, inMs - b.startMs)
        let cutMs = p.opts.cutSec * 1000
        let phraseA = shape.inAtBar == 0
            ? (startScore(p.phrasesA, outBar) + endScore(p.phrasesA, nBars: nA, anchor)) / 2
            : endScore(p.phrasesA, nBars: nA, anchor)
        let lowGap = abs(mean(a.bars.low, outBar, anchor) - mean(b.bars.low, entry, entry + overlapB))
        let facts = Facts(
            syncOk: p.syncOk,
            clash: p.keySync.clash,
            calm: energyA < calm && energyB < calm,
            loud: energyA > loud,
            outroA: phraseAt(a, outBar) == .outro,
            introB: entry == 0 || phraseAt(b, entry) == .intro,
            dropB: p.phrasesB[entry] == .drop,
            spectrumGap: lowGap > spectrumGap
        )
        let rating = BlendMath.clamp(p.opts.ratings[kind] ?? 0, -1, 1)
        let parts: [ScorePart: Double] = [
            .tempo: p.tempoScore,
            .key: key.term,
            .energy: 1 - abs(energyA - energyB),
            .phrases: (phraseA + inScore(p.phrasesB, entry, kind: kind)) / 2,
            .cut: cutMs > 0 ? 1 - (cutOutMs + cutInMs) / (2 * cutMs) : 1,
            .vocal: overlapKinds.contains(kind) ? 1 - BlendMath.clamp((min(midA, midB) - vocalFrom) * 2, 0, 1) : 1,
            .fit: kindFit(kind, facts),
            .rating: 1 + min(0, rating),
        ]
        let total = ScorePart.allCases.reduce(0.0) { $0 + $1.weight * (parts[$1] ?? 0) }
        return TransitionPlan(
            kind: kind,
            sync: sync,
            bars: shape.bars,
            outMs: BlendMath.round(outMs, 1),
            endAMs: BlendMath.round(endAMs, 1),
            inMs: BlendMath.round(inMs, 1),
            inAtBar: shape.inAtBar,
            tempoA: BlendMath.round(p.tempoA, 2),
            tempoB: BlendMath.round(p.tempoB, 2),
            beatRatio: p.beatRatio,
            shift: key.match.shift,
            gainDb: p.gainDb,
            cutOutMs: BlendMath.jsRound(cutOutMs),
            cutInMs: BlendMath.jsRound(cutInMs),
            score: BlendMath.round(total / weightSum, 4),
            parts: parts
        )
    }
}
