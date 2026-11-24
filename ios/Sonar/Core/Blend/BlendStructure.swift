import Foundation

// Такты, энергия по тактам и фразы для сведения (docs/BLEND.md §4.3, пп. 6–7) — порт
// `windows/src/player/blend/structure.ts`. Менять — в обоих местах.
//
// Фразы: границы по 8 тактов, но если на 4-м такте «новизна» (ядро Фута по сходству тактов) даёт
// явный пик — граница там. Метки считаются от медианы энергии без крайних фраз, иначе тихое интро и
// аутро тянут её вниз и «дроп» не отличить от тела трека.

enum BlendStructure {
    static let phraseBars = 8
    static let shortPhraseBars = 4
    /// Полуширина ядра Фута, тактов.
    static let kernelBars = 4
    static let quietRatio = 0.6
    static let dropRatio = 1.6
    /// Сколько тактов подряд должна расти энергия, чтобы фраза была «build».
    static let buildBars = 4

    /// Начала полных тактов (мс) от доли «раз».
    static func barStarts(_ g: BlendGrid, downbeat: Int, endMs: Double) -> [Double] {
        var out: [Double] = []
        var b = 0
        while true {
            let t = g.beatTime(downbeat + beatsPerBar * b)
            if t + Double(beatsPerBar) * g.beatMs > endMs { return out }
            out.append(t)
            b += 1
        }
    }

    private static func round3(_ x: Double) -> Double {
        BlendMath.jsRound(x * 1000) / 1000
    }

    private static func normalized(_ xs: [Double]) -> [Double] {
        let top = xs.reduce(0, max)
        return xs.map { top > 0 ? round3($0 / top) : 0 }
    }

    /// Средние признаки кадров каждого такта + хрома такта (для новизны).
    static func barFeatures(
        _ f: BlendFrames, starts: [Double], barMs: Double
    ) -> (bars: BlendBars, chroma: [[Float]]) {
        var energy: [Double] = []
        var low: [Double] = []
        var mid: [Double] = []
        var onsets: [Double] = []
        var chroma: [[Float]] = []
        for t in starts {
            let a = max(0, BlendMath.jsRoundInt(BlendFeatures.frameAt(t)))
            let b = min(f.count, max(a + 1, BlendMath.jsRoundInt(BlendFeatures.frameAt(t + barMs))))
            var sums = (rms: 0.0, low: 0.0, mid: 0.0, onsets: 0.0)
            var c = [Float](repeating: 0, count: 12)
            for i in stride(from: a, to: b, by: 1) {
                sums.rms += Double(f.rms[i])
                sums.low += Double(f.low[i])
                sums.mid += Double(f.mid[i])
                sums.onsets += Double(f.fluxLow[i]) + Double(f.fluxMid[i]) + Double(f.fluxHigh[i])
                for k in 0..<12 { c[k] = Float(Double(c[k]) + Double(f.chroma[i * 12 + k])) }
            }
            let n = Double(b - a)
            energy.append(sums.rms / n)
            low.append(sums.low / n)
            mid.append(sums.mid / n)
            onsets.append(sums.onsets / n)
            chroma.append(c)
        }
        let bars = BlendBars(
            energy: normalized(energy), low: normalized(low), mid: normalized(mid), onsets: normalized(onsets)
        )
        return (bars, chroma)
    }

    private static func barVectors(_ bars: BlendBars, chroma: [[Float]]) -> [[Double]] {
        chroma.enumerated().map { i, c in
            let total = c.reduce(0.0) { $0 + Double($1) }
            let sum = total == 0 ? 1 : total
            return c.map { Double($0) / sum } + [bars.energy[i], bars.low[i], bars.mid[i]]
        }
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var ab = 0.0
        var aa = 0.0
        var bb = 0.0
        for i in 0..<a.count {
            ab += a[i] * b[i]
            aa += a[i] * a[i]
            bb += b[i] * b[i]
        }
        return aa > 0 && bb > 0 ? ab / (aa * bb).squareRoot() : 1
    }

    /// Новизна на границе каждого такта: ядро-шахматка по матрице косинусного сходства.
    static func novelty(_ vectors: [[Double]]) -> [Double] {
        let n = vectors.count
        var out = [Double](repeating: 0, count: n)
        guard n > 1 else { return out }
        for b in 1..<n {
            var s = 0.0
            var count = 0
            for i in -kernelBars..<kernelBars {
                for j in -kernelBars..<kernelBars {
                    let x = b + i
                    let y = b + j
                    if x < 0 || y < 0 || x >= n || y >= n { continue }
                    let sign: Double = (i < 0) == (j < 0) ? 1 : -1
                    s += sign * cosine(vectors[x], vectors[y])
                    count += 1
                }
            }
            out[b] = count > 0 ? max(0, s / Double(count)) : 0
        }
        return out
    }

    /// Номера тактов, с которых начинаются фразы: по 8, раньше на 4, если там явный пик новизны.
    static func phraseBounds(_ nov: [Double]) -> [Int] {
        let n = nov.count
        if n == 0 { return [] }
        let mean = nov.reduce(0, +) / Double(n)
        let sd = (nov.reduce(0) { $0 + pow($1 - mean, 2) } / Double(n)).squareRoot()
        var out = [0]
        var b = 0
        while true {
            let short = b + shortPhraseBars
            let long = b + phraseBars
            let early = short < n && nov[short] > mean + sd && nov[short] >= (long < n ? nov[long] : 0)
            b = early ? short : long
            if b >= n { return out }
            out.append(b)
        }
    }

    private static func median(_ xs: [Double]) -> Double {
        if xs.isEmpty { return 0 }
        let s = xs.sorted()
        let m = s.count >> 1
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    private static func avg(_ xs: ArraySlice<Double>) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }

    private static func rises(_ xs: ArraySlice<Double>) -> Bool {
        var run = 0
        var prev: Double?
        for x in xs {
            if let p = prev { run = x > p ? run + 1 : 0 }
            if run >= buildBars { return true }
            prev = x
        }
        return false
    }

    /// Метки фраз по энергии и низу тактов.
    static func phraseKinds(_ bars: BlendBars, bounds: [Int]) -> [BlendPhrase] {
        let n = bars.energy.count
        let spans = bounds.enumerated().map { i, bar in (a: bar, b: i + 1 < bounds.count ? bounds[i + 1] : n) }
        let energy = spans.map { avg(bars.energy[$0.a..<$0.b]) }
        let low = spans.map { avg(bars.low[$0.a..<$0.b]) }
        let inner = spans.count > 2 ? Array(spans[1..<(spans.count - 1)]) : spans
        let ref = median(inner.flatMap { bars.energy[$0.a..<$0.b] })
        let quiet = energy.map { $0 < quietRatio * ref }
        var kinds = [PhraseKind](repeating: .body, count: spans.count)
        var i = 0
        while i < spans.count && quiet[i] {
            kinds[i] = .intro
            i += 1
        }
        var j = spans.count - 1
        while j > 0 && quiet[j] && kinds[j] != .intro {
            kinds[j] = .outro
            j -= 1
        }
        for i in 0..<spans.count where kinds[i] == .body {
            let p = i - 1
            let jump = p >= 0 && energy[i] >= dropRatio * energy[p] && low[i] >= dropRatio * low[p]
            if jump && (kinds[p] == .build || quiet[p]) {
                kinds[i] = .drop
            } else if rises(bars.energy[spans[i].a..<spans[i].b]) {
                kinds[i] = .build
            }
        }
        return spans.enumerated().map { BlendPhrase(bar: $1.a, kind: kinds[$0]) }
    }

    static func phrases(_ bars: BlendBars, chroma: [[Float]]) -> [BlendPhrase] {
        phraseKinds(bars, bounds: phraseBounds(novelty(barVectors(bars, chroma: chroma))))
    }
}
