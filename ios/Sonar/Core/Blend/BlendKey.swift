import Foundation

// Тональность трека для сведения (docs/BLEND.md §4.3, п. 8) — порт `windows/src/player/blend/key.ts`.
// Менять — в обоих местах.
//
// Хрома за трек (энергия уже взвешивает кадры) и корреляция с профилями Темперли, 24 тональности.
// `key` 0…11 — мажор (до = 0), 12…23 — минор (ля минор = 21). Уверенность — разница лучшей и второй
// корреляции, умноженная на «чёткость» хромы: у шума все классы почти равны, и любая корреляция там случайна.

enum BlendKey {
    static let major: [Double] = [5, 2, 3.5, 2, 4.5, 4, 2, 4.5, 2, 3.5, 1.5, 4]
    static let minor: [Double] = [5, 2, 3.5, 4.5, 2, 4, 2, 4.5, 3.5, 2, 1.5, 4]
    /// Ниже — «не знаем».
    static let keyConfMin = 0.15
    /// Коэффициент вариации хромы, начиная с которого она считается чёткой.
    static let clearCv = 0.5

    private static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n
        let mb = b.reduce(0, +) / n
        var ab = 0.0
        var aa = 0.0
        var bb = 0.0
        for i in 0..<a.count {
            ab += (a[i] - ma) * (b[i] - mb)
            aa += pow(a[i] - ma, 2)
            bb += pow(b[i] - mb, 2)
        }
        return aa > 0 && bb > 0 ? ab / (aa * bb).squareRoot() : 0
    }

    /// Профиль, повёрнутый к тонике `tonic`.
    private static func rotated(_ profile: [Double], tonic: Int) -> [Double] {
        profile.indices.map { profile[($0 - tonic + 12) % 12] }
    }

    /// Тональность по хроме из 12 чисел.
    static func key(ofChroma chroma: [Double]) -> (key: Int?, keyConf: Double) {
        let total = chroma.reduce(0, +)
        if total <= 0 { return (nil, 0) }
        var scores: [(key: Int, r: Double)] = []
        for t in 0..<12 {
            scores.append((t, pearson(chroma, rotated(major, tonic: t))))
            scores.append((12 + t, pearson(chroma, rotated(minor, tonic: t))))
        }
        // Устойчивая сортировка по убыванию, как `Array.prototype.sort` в JS: при равенстве — порядок вставки.
        let ranked = scores.enumerated()
            .sorted { $0.element.r > $1.element.r || ($0.element.r == $1.element.r && $0.offset < $1.offset) }
            .map(\.element)
        let mean = total / 12
        let cv = (chroma.reduce(0) { $0 + pow($1 - mean, 2) } / 12).squareRoot() / mean
        let keyConf = max(0, min(1, (ranked[0].r - ranked[1].r) * min(1, cv / clearCv)))
        return (keyConf < keyConfMin ? nil : ranked[0].key, BlendMath.jsRound(keyConf * 1000) / 1000)
    }

    /// Тональность отрезка [startMs, endMs) трека.
    static func key(_ f: BlendFrames, startMs: Double, endMs: Double) -> (key: Int?, keyConf: Double) {
        var chroma = [Double](repeating: 0, count: 12)
        let a = max(0, BlendMath.jsRoundInt(BlendFeatures.frameAt(startMs)))
        let b = min(f.count, BlendMath.jsRoundInt(BlendFeatures.frameAt(endMs)))
        for i in stride(from: a, to: b, by: 1) {
            for c in 0..<12 { chroma[c] += Double(f.chroma[i * 12 + c]) }
        }
        return key(ofChroma: chroma)
    }
}
