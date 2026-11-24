import Foundation

// Темп, сетка долей и «раз» такта для сведения (docs/BLEND.md §4.3, пп. 2–5) — порт
// `windows/src/player/blend/tempo.ts`. Менять — в обоих местах.
//
// Огибающая атак — сумма потоков полос (каждая к своему среднему, верх вполовину), сглаженная и без
// скользящего среднего. Темп: автокорреляция в 60–200 BPM с гауссом вокруг 120 по октавам, затем
// уточнение перебором темпа и фазы по самой огибающей (точнее, чем лаг в кадр ~23 мс). Против ошибки
// «вдвое медленнее»: если между долями атак почти столько же, сколько на долях, — темп удваиваем.

/// Сетка долей трека.
struct BlendGrid: Sendable, Equatable {
    var bpm: Double
    var bpmConf: Double
    var beatMs: Double
    var firstBeatMs: Double
    var gridStable: Bool

    /// Время доли `k` сетки.
    func beatTime(_ k: Int) -> Double {
        firstBeatMs + Double(k) * beatMs
    }
}

enum BlendTempo {
    static let bpmMin = 60.0
    static let bpmMax = 200.0
    /// Итоговый темп приводится сюда (§4.3).
    static let bpmNormMin = 70.0
    static let bpmNormMax = 180.0
    static let priorBpm = 120.0
    /// Ширина гаусса по октавам.
    static let priorOctaves = 1.0
    /// Перебор фазы с таким шагом, мс.
    static let phaseStepMs = 5.0
    /// Сетки третей расходятся больше — сетка «плывёт».
    static let driftMaxMs = 40.0
    /// Атаки между долями не слабее этой доли атак на долях — темп вдвое быстрее.
    static let doubleRatio = 0.8
    /// Треть с атаками слабее этой доли лучшей в сверке дрейфа не участвует (пауза, тишина).
    static let driftMinScore = 0.3
    static let highWeight = 0.5
    /// Окно скользящего среднего огибающей, кадров в каждую сторону (~0.4 с).
    static let meanRadius = 9
    /// Уточнение темпа: грубо ±3 % шагом 0.1, затем ±0.15 шагом 0.01.
    static let coarseSpan = 0.03
    static let fineSpan = 0.15

    private static func meanOf(_ a: [Float]) -> Double {
        var s = 0.0
        for v in a { s += Double(v) }
        return a.isEmpty ? 0 : s / Double(a.count)
    }

    /// Сумма полос (каждая к своему среднему) → сглаживание → минус скользящее среднее, не ниже нуля.
    private static func envelope(_ bands: [(band: [Float], weight: Double)]) -> [Float] {
        let n = bands[0].band.count
        var raw = [Float](repeating: 0, count: n)
        for (band, weight) in bands {
            let mean = meanOf(band)
            let m = mean == 0 ? 1 : mean
            for i in 0..<n { raw[i] = Float(Double(raw[i]) + (weight * Double(band[i])) / m) }
        }
        var smooth = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let left = Double(i > 0 ? raw[i - 1] : raw[i])
            let right = Double(i + 1 < n ? raw[i + 1] : raw[i])
            smooth[i] = Float(0.25 * left + 0.5 * Double(raw[i]) + 0.25 * right)
        }
        var out = [Float](repeating: 0, count: n)
        var acc = 0.0
        var lo = 0
        var hi = -1
        for i in 0..<n {
            while hi < min(n - 1, i + meanRadius) {
                hi += 1
                acc += Double(smooth[hi])
            }
            while lo < i - meanRadius {
                acc -= Double(smooth[lo])
                lo += 1
            }
            out[i] = Float(max(0, Double(smooth[i]) - acc / Double(hi - lo + 1)))
        }
        return out
    }

    static func onsetEnvelope(_ f: BlendFrames) -> [Float] {
        envelope([(f.fluxLow, 1), (f.fluxMid, 1), (f.fluxHigh, highWeight)])
    }

    /// Без верха: тарелки и хэты между долями не должны удваивать темп.
    static func bodyEnvelope(_ f: BlendFrames) -> [Float] {
        envelope([(f.fluxLow, 1), (f.fluxMid, 1)])
    }

    /// Значение огибающей в момент `ms` (линейно между кадрами).
    static func envAt(_ env: [Float], _ ms: Double) -> Double {
        let p = BlendFeatures.frameAt(ms)
        if p < 0 || p > Double(env.count - 1) { return 0 }
        let fi = p.rounded(.down)
        let i = Int(fi)
        let frac = p - fi
        return i + 1 < env.count ? Double(env[i]) * (1 - frac) + Double(env[i + 1]) * frac : Double(env[i])
    }

    /// Средняя огибающая в точках сетки `phase + k·beat` внутри [from, to).
    private static func gridScore(_ env: [Float], beat: Double, phase: Double, from: Double, to: Double) -> Double {
        var k = ((from - phase) / beat).rounded(.up)
        var s = 0.0
        var n = 0
        var t = phase + k * beat
        while t < to {
            s += envAt(env, t)
            n += 1
            k += 1
            t = phase + k * beat
        }
        return n > 0 ? s / Double(n) : 0
    }

    /// Лучшая фаза (0…beat) для длины доли на отрезке.
    static func bestPhase(_ env: [Float], beat: Double, from: Double, to: Double) -> (phase: Double, score: Double) {
        var best = (phase: 0.0, score: -1.0)
        var phase = 0.0
        while phase < beat {
            let score = gridScore(env, beat: beat, phase: phase, from: from, to: to)
            if score > best.score { best = (phase, score) }
            phase += phaseStepMs
        }
        return best
    }

    /// Грубый темп по автокорреляции с гауссом вокруг 120 BPM.
    private static func roughTempo(_ env: [Float]) -> (bpm: Double, conf: Double) {
        let frameMs = BlendFeatures.frameMs
        let lagMin = Int((60000 / bpmMax / frameMs).rounded(.down))
        let lagMax = Int((60000 / bpmMin / frameMs).rounded(.up))
        var acf = [Float](repeating: 0, count: lagMax + 2)
        for lag in (lagMin - 1)...(lagMax + 1) {
            var s = 0.0
            var i = 0
            while i + lag < env.count {
                s += Double(env[i]) * Double(env[i + lag])
                i += 1
            }
            acf[lag] = Float(s / Double(max(1, env.count - lag)))
        }
        func weighted(_ lag: Int) -> Double {
            let octaves = log2(60000 / (Double(lag) * frameMs) / priorBpm) / priorOctaves
            return Double(acf[lag]) * exp(-0.5 * octaves * octaves)
        }
        var best = lagMin
        var sum = 0.0
        for lag in lagMin...lagMax {
            sum += Double(acf[lag])
            if weighted(lag) > weighted(best) { best = lag }
        }
        let (a, b, c) = (weighted(best - 1), weighted(best), weighted(best + 1))
        let bend = a - 2 * b + c
        let shift = bend < 0 ? max(-0.5, min(0.5, (0.5 * (a - c)) / bend)) : 0
        let mean = sum / Double(lagMax - lagMin + 1)
        let top = Double(acf[best])
        let conf = top > 0 ? max(0, min(1, (top - mean) / top)) : 0
        return (60000 / ((Double(best) + shift) * frameMs), conf)
    }

    /// Уточнение темпа перебором темпа и фазы по огибающей.
    private static func refineTempo(
        _ env: [Float], rough: Double, from: Double, to: Double
    ) -> (bpm: Double, phase: Double, score: Double) {
        func search(_ lo: Double, _ hi: Double, _ step: Double) -> (bpm: Double, phase: Double, score: Double) {
            var best = (bpm: rough, phase: 0.0, score: -1.0)
            var i = 0.0
            while lo + i * step <= hi + 1e-9 {
                let bpm = lo + i * step
                let found = bestPhase(env, beat: 60000 / bpm, from: from, to: to)
                if found.score > best.score { best = (bpm, found.phase, found.score) }
                i += 1
            }
            return best
        }
        let coarse = search(rough * (1 - coarseSpan), rough * (1 + coarseSpan), 0.1)
        return search(coarse.bpm - fineSpan, coarse.bpm + fineSpan, 0.01)
    }

    /// Расстояние от `t` до ближайшей доли сетки (`phase`, `beat`), мс.
    private static func offGrid(_ t: Double, phase: Double, beat: Double) -> Double {
        let d = ((t - phase).truncatingRemainder(dividingBy: beat) + beat).truncatingRemainder(dividingBy: beat)
        return min(d, beat - d)
    }

    /// Своя сетка каждой трети (темп и фаза подобраны заново) на краях трети расходится с общей больше
    /// 40 мс — темп не постоянный. Трети без атак (пауза, тишина) не в счёт.
    private static func driftOk(_ env: [Float], bpm: Double, phase: Double, from: Double, to: Double) -> Bool {
        let beat = 60000 / bpm
        let third = (to - from) / 3
        let parts = (0..<3).map { i -> (a: Double, b: Double, bpm: Double, phase: Double, score: Double) in
            let a = from + Double(i) * third
            let b = from + Double(i + 1) * third
            let r = refineTempo(env, rough: bpm, from: a, to: b)
            return (a, b, r.bpm, r.phase, r.score)
        }
        let top = parts.map(\.score).max() ?? 0
        for p in parts where p.score >= driftMinScore * top {
            let local = 60000 / p.bpm
            for t in [p.a, p.b] {
                let nearest = p.phase + BlendMath.jsRound((t - p.phase) / local) * local
                if offGrid(nearest, phase: phase, beat: beat) > driftMaxMs { return false }
            }
        }
        return true
    }

    /// Темп и сетка долей на отрезке без тишины.
    static func grid(_ f: BlendFrames, startMs: Double, endMs: Double) -> BlendGrid {
        let env = onsetEnvelope(f)
        let rough = roughTempo(env)
        let refined = refineTempo(env, rough: rough.bpm, from: startMs, to: endMs)
        var bpm = refined.bpm
        var phase = refined.phase
        let body = bodyEnvelope(f)
        let beat0 = 60000 / bpm
        let on = gridScore(body, beat: beat0, phase: phase, from: startMs, to: endMs)
        let off = gridScore(body, beat: beat0, phase: phase + beat0 / 2, from: startMs, to: endMs)
        if bpm * 2 <= bpmNormMax && on > 0 && off >= doubleRatio * on { bpm *= 2 }
        while bpm < bpmNormMin { bpm *= 2 }
        while bpm > bpmNormMax { bpm /= 2 }
        let beatMs = 60000 / bpm
        phase = phase.truncatingRemainder(dividingBy: beatMs)
        let k = ((startMs - beatMs / 2 - phase) / beatMs).rounded(.up)
        return BlendGrid(
            bpm: bpm,
            bpmConf: rough.conf,
            beatMs: beatMs,
            firstBeatMs: phase + k * beatMs,
            gridStable: driftOk(env, bpm: bpm, phase: phase, from: startMs, to: endMs)
        )
    }
}

// MARK: - «Раз» такта

extension BlendTempo {
    static func cosineDistance(_ a: [Float], _ b: [Float]) -> Double {
        var ab = 0.0
        var aa = 0.0
        var bb = 0.0
        for i in 0..<a.count {
            let x = Double(a[i])
            let y = Double(b[i])
            ab += x * y
            aa += x * x
            bb += y * y
        }
        return aa > 0 && bb > 0 ? 1 - ab / (aa * bb).squareRoot() : 0
    }

    /// Сумма хромы кадров в [from, to) мс.
    static func chromaBetween(_ f: BlendFrames, from: Double, to: Double) -> [Float] {
        var out = [Float](repeating: 0, count: 12)
        let a = max(0, BlendMath.jsRoundInt(BlendFeatures.frameAt(from)))
        let b = min(f.count, BlendMath.jsRoundInt(BlendFeatures.frameAt(to)))
        for i in stride(from: a, to: b, by: 1) {
            for c in 0..<12 { out[c] = Float(Double(out[c]) + Double(f.chroma[i * 12 + c])) }
        }
        return out
    }

    /// Какая доля сетки (0…3) — «раз»: максимум атак низа и смены гармонии.
    static func downbeat(_ f: BlendFrames, grid g: BlendGrid, endMs: Double) -> Int {
        var lows: [Double] = []
        var changes: [Double] = []
        // До первой доли — обычно тишина: сравнение с ней дало бы выброс «смены гармонии» на доле 0.
        var prev: [Float]?
        var k = 0
        while g.beatTime(k) < endMs {
            let t = g.beatTime(k)
            let p = BlendMath.jsRoundInt(BlendFeatures.frameAt(t))
            var peak = 0.0
            for i in stride(from: max(0, p - 1), through: min(f.count - 1, p + 1), by: 1) {
                peak = max(peak, Double(f.fluxLow[i]))
            }
            lows.append(peak)
            let cur = chromaBetween(f, from: t, to: t + g.beatMs)
            changes.append(prev.map { cosineDistance($0, cur) } ?? 0)
            prev = cur
            k += 1
        }
        func norm(_ xs: [Double]) -> [Double] {
            let m = xs.reduce(0, +) / Double(max(1, xs.count))
            return m > 0 ? xs.map { $0 / m } : xs.map { _ in 0 }
        }
        let l = norm(lows)
        let c = norm(changes)
        var score = [0.0, 0.0, 0.0, 0.0]
        var count = [0, 0, 0, 0]
        for k in 0..<l.count {
            score[k % 4] += l[k] + 0.5 * c[k]
            count[k % 4] += 1
        }
        func mean(_ d: Int) -> Double { score[d] / Double(max(1, count[d])) }
        var best = 0
        for d in 1..<4 where mean(d) > mean(best) { best = d }
        return best
    }
}
