import Foundation

// Быстрое преобразование Фурье для анализа сведения (docs/BLEND.md §4.3) — порт
// `windows/src/player/blend/fft.ts`: радикс-2, на месте, таблицы поворотов и перестановки считаются один
// раз на размер. Менять — в обоих местах.
//
// Хранение — `Float` (как `Float32Array` на ПК), арифметика — `Double` (как `number` в JS): так тот же
// трек даёт тот же результат на ПК и на iPhone. Accelerate не берём — код гоняется и вне iOS.

struct BlendFFT: Sendable {
    let size: Int
    private let rev: [Int]
    private let cos: [Float]
    private let sin: [Float]

    init(size: Int) {
        precondition(size >= 2 && size & (size - 1) == 0, "FFT: размер \(size) — не степень двойки")
        self.size = size
        let bits = size.trailingZeroBitCount
        rev = (0..<size).map { i in
            var r = 0
            for b in 0..<bits { r |= ((i >> b) & 1) << (bits - 1 - b) }
            return r
        }
        cos = (0..<size / 2).map { Float(Foundation.cos((-2 * Double.pi * Double($0)) / Double(size))) }
        sin = (0..<size / 2).map { Float(Foundation.sin((-2 * Double.pi * Double($0)) / Double(size))) }
    }

    /// Прямое преобразование на месте: `re`, `im` длиной `size`.
    func transform(_ re: inout [Float], _ im: inout [Float]) {
        precondition(re.count == size && im.count == size, "FFT: длина не \(size)")
        let n = size
        re.withUnsafeMutableBufferPointer { re in
            im.withUnsafeMutableBufferPointer { im in
                rev.withUnsafeBufferPointer { rev in
                    for i in 0..<n {
                        let j = rev[i]
                        if j > i {
                            re.swapAt(i, j)
                            im.swapAt(i, j)
                        }
                    }
                }
                cos.withUnsafeBufferPointer { cos in
                    sin.withUnsafeBufferPointer { sin in
                        Self.butterflies(re: re, im: im, cos: cos, sin: sin, n: n)
                    }
                }
            }
        }
    }

    private static func butterflies(
        re: UnsafeMutableBufferPointer<Float>,
        im: UnsafeMutableBufferPointer<Float>,
        cos: UnsafeBufferPointer<Float>,
        sin: UnsafeBufferPointer<Float>,
        n: Int
    ) {
        var len = 2
        while len <= n {
            let half = len >> 1
            let step = n / len
            var start = 0
            while start < n {
                for k in 0..<half {
                    let wr = Double(cos[k * step])
                    let wi = Double(sin[k * step])
                    let a = start + k
                    let b = a + half
                    let rb = Double(re[b])
                    let ib = Double(im[b])
                    let xr = rb * wr - ib * wi
                    let xi = rb * wi + ib * wr
                    let ra = Double(re[a])
                    let ia = Double(im[a])
                    re[b] = Float(ra - xr)
                    im[b] = Float(ia - xi)
                    re[a] = Float(ra + xr)
                    im[a] = Float(ia + xi)
                }
                start += len
            }
            len <<= 1
        }
    }

    /// Окно Ханна длиной `n`.
    static func hann(_ n: Int) -> [Float] {
        (0..<n).map { Float(0.5 - 0.5 * Foundation.cos((2 * Double.pi * Double($0)) / Double(n - 1))) }
    }
}

/// Округления как в JS: на ПК те же числа должны получаться бит в бит.
enum BlendMath {
    /// `Math.round`: ближайшее целое, половина — вверх (к +∞), в отличие от `rounded()` Swift.
    static func jsRound(_ x: Double) -> Double {
        let down = x.rounded(.down)
        return x - down >= 0.5 ? down + 1 : down
    }

    /// `Math.round` в целое.
    static func jsRoundInt(_ x: Double) -> Int {
        Int(jsRound(x))
    }
}
