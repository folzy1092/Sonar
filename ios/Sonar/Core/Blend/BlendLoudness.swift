import Foundation

// Громкость трека, грубый LUFS (docs/BLEND.md §4.3, п. 9) — порт `windows/src/player/blend/loudness.ts`.
// Менять — в обоих местах.
//
// K-фильтр (полка +4 дБ и срез низа, как в BS.1770, коэффициенты по RBJ под 11 025 Гц), блоки 400 мс
// с шагом 100 мс, отсечка −70 LUFS и −10 LU от среднего. Точность ±1 LU не нужна — нужна разница
// громкостей двух треков.

enum BlendLoudness {
    static let shelfHz = 1681.97
    static let shelfDb = 4.0
    static let shelfQ = 0.7071
    static let hpfHz = 38.13
    static let hpfQ = 0.5003
    static let blockMs = 400.0
    static let stepMs = 100.0
    static let absGate = -70.0
    static let relGate = -10.0
    /// Ниже — тишина: громкости нет.
    static let silentLufs = -70.0

    private struct Biquad {
        let b0, b1, b2, a1, a2: Double
    }

    private static var sampleRate: Double { Double(BlendFeatures.sampleRate) }

    private static func highShelf(_ f0: Double, db: Double, q: Double) -> Biquad {
        let a = pow(10, db / 40)
        let w = (2 * Double.pi * f0) / sampleRate
        let alpha = sin(w) / (2 * q)
        let c = cos(w)
        let s = 2 * a.squareRoot() * alpha
        let a0 = a + 1 - (a - 1) * c + s
        return Biquad(
            b0: (a * (a + 1 + (a - 1) * c + s)) / a0,
            b1: (-2 * a * (a - 1 + (a + 1) * c)) / a0,
            b2: (a * (a + 1 + (a - 1) * c - s)) / a0,
            a1: (2 * (a - 1 - (a + 1) * c)) / a0,
            a2: (a + 1 - (a - 1) * c - s) / a0
        )
    }

    private static func highPass(_ f0: Double, q: Double) -> Biquad {
        let w = (2 * Double.pi * f0) / sampleRate
        let alpha = sin(w) / (2 * q)
        let c = cos(w)
        let a0 = 1 + alpha
        return Biquad(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: (-2 * c) / a0, a2: (1 - alpha) / a0)
    }

    /// Биквад по отсчётам. Как на ПК: выход хранится во `Float`, а состояние `y1`/`y2` — в `Double`.
    private static func filter(_ x: [Float], _ q: Biquad) -> [Float] {
        var y = [Float](repeating: 0, count: x.count)
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0
        for i in 0..<x.count {
            let xi = Double(x[i])
            let v = q.b0 * xi + q.b1 * x1 + q.b2 * x2 - q.a1 * y1 - q.a2 * y2
            x2 = x1
            x1 = xi
            y2 = y1
            y1 = v
            y[i] = Float(v)
        }
        return y
    }

    private static func lufs(_ meanSquare: Double) -> Double {
        -0.691 + 10 * log10(meanSquare)
    }

    /// Интегральная громкость моно 11 025 Гц, ~LUFS с точностью 0.1.
    static func loudness(of mono: [Float]) -> Double {
        let k = filter(filter(mono, highShelf(shelfHz, db: shelfDb, q: shelfQ)), highPass(hpfHz, q: hpfQ))
        let block = BlendMath.jsRoundInt((blockMs / 1000) * sampleRate)
        let step = BlendMath.jsRoundInt((stepMs / 1000) * sampleRate)
        var blocks: [Double] = []
        var start = 0
        while start + block <= k.count {
            var s = 0.0
            for i in start..<(start + block) { s += Double(k[i]) * Double(k[i]) }
            let ms = s / Double(block)
            if ms > 0 && lufs(ms) > absGate { blocks.append(ms) }
            start += step
        }
        if blocks.isEmpty { return silentLufs }
        let gate = lufs(blocks.reduce(0, +) / Double(blocks.count)) + relGate
        let kept = blocks.filter { lufs($0) > gate }
        return BlendMath.jsRound(lufs(kept.reduce(0, +) / Double(kept.count)) * 10) / 10
    }
}
