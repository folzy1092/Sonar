import XCTest
@testable import Sonar

// Общие заготовки тестов сведения — порт фикстур `planner.test.ts`, `curves.test.ts`, `party-core.test.ts`,
// менять — в обоих местах.

enum BlendFixtures {
    static let phrases: [BlendPhrase] = [
        BlendPhrase(bar: 0, kind: .intro),
        BlendPhrase(bar: 16, kind: .body),
        BlendPhrase(bar: 32, kind: .drop),
        BlendPhrase(bar: 48, kind: .outro),
    ]

    /// Синтетический трек планировщика: ровная энергия, фразы через 16 тактов.
    static func track(
        _ ref: String,
        bpm: Double = 128,
        nBars: Int = 64,
        key: Int? = 0,
        loudness: Double = -10,
        gridStable: Bool = true,
        energy: Double = 0.5,
        tailMs: Double = 2000
    ) -> BlendAnalysis {
        let beatMs = 60000 / bpm
        let endMs = Double(nBars * beatsPerBar) * beatMs
        let fill = { (x: Double) in [Double](repeating: x, count: nBars) }
        return BlendAnalysis(
            version: 1,
            ref: ref,
            durationMs: endMs + tailMs,
            startMs: 0,
            endMs: endMs,
            bpm: bpm,
            bpmConf: 0.9,
            beatMs: beatMs,
            firstBeatMs: 0,
            downbeat: 0,
            gridStable: gridStable,
            key: key,
            keyConf: 0.8,
            loudness: loudness,
            bars: BlendBars(energy: fill(energy), low: fill(0.5), mid: fill(0.3), onsets: fill(0.5)),
            phrases: phrases.filter { $0.bar < nBars }
        )
    }

    static let opts = PlanOpts(
        type: .auto, lengthSec: 16, cutSec: 8, tempoTolPct: 6, keyShift: true,
        rateA: 1, rateB: 1, linkedA: false, linkedB: false
    )

    static func opts(_ edit: (inout PlanOpts) -> Void) -> PlanOpts {
        var o = opts
        edit(&o)
        return o
    }

    static let nyquist = 24_000.0

    /// Готовый план нужного вида для кривых.
    static func planOf(_ kind: BlendKind, _ edit: (inout TransitionPlan) -> Void = { _ in }) -> TransitionPlan {
        let bars: [BlendKind: Int] = [.bass: 8, .filter: 8, .echo: 3, .smooth: 16, .drop: 4]
        let n = bars[kind] ?? 8
        let inAtBar: [BlendKind: Int] = [.bass: 0, .filter: 0, .echo: 1, .smooth: 0, .drop: n]
        var plan = TransitionPlan(
            kind: kind,
            sync: kind != .echo,
            bars: n,
            outMs: 60_000,
            endAMs: 60_000 + Double(kind == .echo ? 1 : n) * 1875,
            inMs: 0,
            inAtBar: inAtBar[kind] ?? 0,
            tempoA: 128,
            tempoB: 128,
            beatRatio: 1,
            shift: 0,
            gainDb: 0,
            cutOutMs: 0,
            cutInMs: 0,
            score: 1,
            parts: [.tempo: 1, .key: 1, .energy: 1, .phrases: 1, .cut: 1, .vocal: 1, .fit: 1, .rating: 0.5]
        )
        edit(&plan)
        return plan
    }

    /// Равномерные точки 0…to, n + 1 штук.
    static func sample(_ to: Double, _ n: Int = 400) -> [Double] {
        (0...n).map { (to * Double($0)) / Double(n) }
    }

    /// Анализ с нужной «энергией» для вечеринки: громкость и темп.
    static func an(_ ref: String, _ loudness: Double, bpm: Double = 124) -> BlendAnalysis {
        BlendAnalysis(
            version: 1,
            ref: ref,
            durationMs: 200_000,
            startMs: 0,
            endMs: 200_000,
            bpm: bpm,
            bpmConf: 1,
            beatMs: 60_000 / bpm,
            firstBeatMs: 0,
            downbeat: 0,
            gridStable: true,
            key: nil,
            keyConf: 0,
            loudness: loudness,
            bars: BlendBars(energy: [], low: [], mid: [], onsets: []),
            phrases: []
        )
    }

    /// Детерминированный «случай» — тот же ряд, что на ПК.
    static func seeded(_ seed: Int = 1) -> () -> Double {
        var s = seed
        return {
            s = (s * 16807) % 2147483647
            return Double(s - 1) / 2147483646
        }
    }

    static func refs(_ n: Int) -> [String] {
        (0..<n).map { "t\($0)" }
    }
}
