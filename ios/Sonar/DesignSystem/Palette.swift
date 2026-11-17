import Foundation

/// Цвет темы из обложки (SPEC §4.4) — порт `windows/src/theme/palette.ts`, поверхность «Эхо» (стиль
/// Sonar по умолчанию): пиксели обложки → k-means (k = 5) → кластер с лучшим `насыщенность × √доля`,
/// почти чёрные, белые и серые не берём. Дальше всё в OKLCH: фон и поверхности — тот же оттенок,
/// затемнённый, акцент — светлота 0.79, текст на акценте — тёмный в цвет. Без UIKit — гоняется тестами.
struct RGB: Equatable, Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

struct Lch: Equatable, Sendable {
    var l: Double
    var c: Double
    var h: Double
}

/// Токены темы — как CSS-переменные ПК-клиента (`--bg`, `--surface-*`, `--accent`…), в sRGB 0…255.
struct ThemeTokens: Equatable, Sendable {
    var bg: RGB
    var s1: RGB
    var s2: RGB
    var s3: RGB
    var border: RGB
    var text: RGB
    var t2: RGB
    var t3: RGB
    var accent: RGB
    var ink: RGB
    /// Подкраска верха страницы.
    var tint: RGB
    /// Свечение за обложкой.
    var glow: RGB
    /// Обложка почти серая — тема монохромная (акцент белый).
    var mono: Bool
}

enum Palette {
    // ---- HSL (для выбора кластера, как в ПК-клиенте) ----

    static func hsl(_ c: RGB) -> (h: Double, s: Double, l: Double) {
        let r = c.r / 255, g = c.g / 255, b = c.b / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        if mx == mn { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h /= 6
        return (h, s, l)
    }

    /// k-means по пикселям RGBA (по 4 байта). Детерминирован: стартовые центры — по равным шагам.
    static func kmeans(_ px: [UInt8], k: Int = 5, iterations: Int = 8) -> [(color: RGB, share: Double)] {
        var pts: [RGB] = []
        pts.reserveCapacity(px.count / 4)
        var i = 0
        while i + 3 < px.count {
            if px[i + 3] > 128 { pts.append(RGB(Double(px[i]), Double(px[i + 1]), Double(px[i + 2]))) }
            i += 4
        }
        guard !pts.isEmpty else { return [] }
        let step = max(1, pts.count / k)
        var centers = (0 ..< min(k, pts.count)).map { pts[min(pts.count - 1, $0 * step)] }
        var assign = [Int](repeating: 0, count: pts.count)
        for _ in 0 ..< iterations {
            for (n, p) in pts.enumerated() {
                var best = 0
                var bestD = Double.infinity
                for (j, c) in centers.enumerated() {
                    let d = (p.r - c.r) * (p.r - c.r) + (p.g - c.g) * (p.g - c.g) + (p.b - c.b) * (p.b - c.b)
                    if d < bestD {
                        bestD = d
                        best = j
                    }
                }
                assign[n] = best
            }
            var sums = [RGB](repeating: RGB(0, 0, 0), count: centers.count)
            var counts = [Int](repeating: 0, count: centers.count)
            for (n, p) in pts.enumerated() {
                let j = assign[n]
                counts[j] += 1
                sums[j].r += p.r
                sums[j].g += p.g
                sums[j].b += p.b
            }
            for j in centers.indices where counts[j] > 0 {
                let n = Double(counts[j])
                centers[j] = RGB((sums[j].r / n).rounded(), (sums[j].g / n).rounded(), (sums[j].b / n).rounded())
            }
        }
        var counts = [Int](repeating: 0, count: centers.count)
        for a in assign { counts[a] += 1 }
        return centers.indices
            .map { (centers[$0], Double(counts[$0]) / Double(pts.count)) }
            .filter { $0.1 > 0 }
    }

    /// Акцент обложки или nil (картинка почти серая / чёрно-белая).
    static func pickAccent(_ px: [UInt8]) -> RGB? {
        var best: RGB?
        var bestScore = 0.0
        for (color, share) in kmeans(px) {
            let (_, s, l) = hsl(color)
            if l < 0.1 || l > 0.92 || s < 0.15 { continue }
            let score = s * share.squareRoot()
            if score > bestScore {
                bestScore = score
                best = color
            }
        }
        return best
    }

    // ---- OKLCH ----

    private static func toLin(_ v: Double) -> Double {
        let x = v / 255
        return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }

    private static func fromLin(_ v: Double) -> Double {
        (v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055) * 255
    }

    static func oklch(_ c: RGB) -> Lch {
        let r = toLin(c.r), g = toLin(c.g), b = toLin(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        var h = atan2(B, A) * 180 / .pi
        if h < 0 { h += 360 }
        return Lch(l: L, c: (A * A + B * B).squareRoot(), h: h)
    }

    private static func linear(_ x: Lch) -> (Double, Double, Double) {
        let A = x.c * cos(x.h * .pi / 180)
        let B = x.c * sin(x.h * .pi / 180)
        let l = pow(x.l + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(x.l - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(x.l - 0.0894841775 * A - 1.291485548 * B, 3)
        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s
        )
    }

    private static func inGamut(_ x: Lch) -> Bool {
        let (r, g, b) = linear(x)
        return [r, g, b].allSatisfy { $0 >= -1e-4 && $0 <= 1 + 1e-4 }
    }

    /// Вписать в sRGB: та же светлота и оттенок, насыщенность меньше.
    static func fitGamut(_ x: Lch) -> Lch {
        if inGamut(x) { return x }
        var lo = 0.0, hi = x.c
        for _ in 0 ..< 18 {
            let mid = (lo + hi) / 2
            if inGamut(Lch(l: x.l, c: mid, h: x.h)) { lo = mid } else { hi = mid }
        }
        return Lch(l: x.l, c: lo, h: x.h)
    }

    static func rgb(_ x: Lch) -> RGB {
        let (r, g, b) = linear(fitGamut(x))
        func ch(_ v: Double) -> Double { max(0, min(255, fromLin(max(0, min(1, v))))).rounded() }
        return RGB(ch(r), ch(g), ch(b))
    }

    /// Ниже этой насыщенности обложка — монохромная.
    static let monoChroma = 0.03

    /// Токены по исходному цвету (nil — монохром), формулы поверхности «Эхо» тёмной темы.
    static func theme(from source: RGB?) -> ThemeTokens {
        let bgL = 0.135, bgC = 0.22, bgMax = 0.028
        let sL = (0.178, 0.218, 0.262), sC = 0.28, sMax = 0.034
        let bdL = 0.31, bdC = 0.32, bdMax = 0.05
        let base = source.map(oklch) ?? Lch(l: 0, c: 0, h: 0)
        let mono = base.c < monoChroma
        let c = mono ? 0 : base.c
        let h = base.h
        func cc(_ m: Double, _ mx: Double) -> Double { min(c * m, mx) }
        func ok(_ l: Double, _ ch: Double) -> RGB { rgb(Lch(l: l, c: ch, h: h)) }
        return ThemeTokens(
            bg: ok(bgL, cc(bgC, bgMax)),
            s1: ok(sL.0, cc(sC, sMax)),
            s2: ok(sL.1, cc(sC, sMax)),
            s3: ok(sL.2, cc(sC, sMax)),
            border: ok(bdL, cc(bdC, bdMax)),
            text: ok(0.97, cc(0.03, 0.008)),
            t2: ok(0.8, cc(0.06, 0.014)),
            t3: ok(0.65, cc(0.08, 0.018)),
            accent: mono ? ok(0.95, 0) : ok(0.79, min(c, 0.19)),
            ink: mono ? ok(0.16, 0) : ok(0.18, cc(0.35, 0.05)),
            tint: ok(0.2, cc(0.6, 0.09)),
            glow: mono ? ok(0.7, 0) : ok(0.62, min(c, 0.2)),
            mono: mono
        )
    }
}
