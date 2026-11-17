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
    /// Поверхность 0 — между фоном и первой поверхностью.
    var s0: RGB
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
    /// Дорожка прогресса.
    var track: RGB
    /// Прозрачность мягкого акцента (`--accent-soft`).
    var softAlpha: Double
    /// Обложка почти серая — тема монохромная (акцент белый / тёмный в светлой).
    var mono: Bool
    /// Светлая тема.
    var light: Bool
}

/// Поверхность стиля Sonar (`appearance.surface`, SETTINGS.md «Стиль»): формулы фона, поверхностей и
/// текста. Цвет берётся из обложки или готовой темы, формулы — отсюда.
enum Surface: String, CaseIterable, Identifiable, Sendable {
    case echo, signal, edge, tactile, monolith

    var id: String { rawValue }

    var title: String {
        switch self {
        case .echo: "Эхо"
        case .signal: "Сигнал"
        case .edge: "Грань"
        case .tactile: "Тактиль"
        case .monolith: "Монолит"
        }
    }
}

/// Формулы поверхности — `SurfaceFormula` из `palette.ts`.
struct SurfaceFormula: Sendable {
    var bgL: Double, bgC: Double, bgMax: Double
    var sL: (Double, Double, Double), sC: Double, sMax: Double
    var bdL: Double, bdC: Double, bdMax: Double
    var txL: Double, t2L: Double, t3L: Double
    var accL: Double, accMax: Double
    var softA: Double
    /// Текст без подкраски (Монолит: цвет обложки — только свечение и прогресс).
    var grayText = false
}

/// Готовая тема (`appearance.preset`, как ПК `PRESETS`): исходный цвет; фон — его оттенок. AMOLED —
/// чистый чёрный (в светлой теме его нет).
struct ThemePreset: Identifiable, Sendable {
    let id: String
    let title: String
    let accent: RGB?
    var black = false

    static let all: [ThemePreset] = [
        ThemePreset(id: "neutral", title: "Neutral", accent: nil),
        ThemePreset(id: "amoled", title: "AMOLED", accent: nil, black: true),
        ThemePreset(id: "crimson", title: "Crimson", accent: RGB(229, 72, 77)),
        ThemePreset(id: "nord", title: "Nord", accent: RGB(136, 192, 208)),
        ThemePreset(id: "sky", title: "Sky", accent: RGB(76, 154, 255)),
        ThemePreset(id: "mint", title: "Mint", accent: RGB(62, 207, 142)),
        ThemePreset(id: "violet", title: "Violet", accent: RGB(169, 112, 255)),
        ThemePreset(id: "blossom", title: "Blossom", accent: RGB(240, 84, 122)),
        ThemePreset(id: "sakura", title: "Sakura", accent: RGB(244, 166, 196)),
        ThemePreset(id: "terminal", title: "Terminal", accent: RGB(34, 229, 90)),
        ThemePreset(id: "aqua", title: "Aqua", accent: RGB(46, 196, 182)),
        ThemePreset(id: "sunset", title: "Sunset", accent: RGB(255, 138, 61)),
        ThemePreset(id: "slate", title: "Slate", accent: RGB(107, 140, 255)),
    ]

    /// Неизвестный id — Neutral.
    static func named(_ id: String) -> ThemePreset {
        all.first { $0.id == id } ?? all[0]
    }
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

    /// Формулы тёмной темы — `SURFACES` из `palette.ts`.
    static let surfaces: [Surface: SurfaceFormula] = [
        .echo: SurfaceFormula(bgL: 0.135, bgC: 0.22, bgMax: 0.028, sL: (0.178, 0.218, 0.262), sC: 0.28, sMax: 0.034,
                              bdL: 0.31, bdC: 0.32, bdMax: 0.05, txL: 0.97, t2L: 0.8, t3L: 0.65, accL: 0.79, accMax: 0.19, softA: 0.22),
        .signal: SurfaceFormula(bgL: 0.15, bgC: 0.4, bgMax: 0.06, sL: (0.195, 0.24, 0.285), sC: 0.45, sMax: 0.065,
                                bdL: 0.3, bdC: 0.45, bdMax: 0.07, txL: 0.97, t2L: 0.82, t3L: 0.68, accL: 0.8, accMax: 0.2, softA: 0.18),
        .edge: SurfaceFormula(bgL: 0.12, bgC: 0.2, bgMax: 0.025, sL: (0.165, 0.205, 0.25), sC: 0.25, sMax: 0.03,
                              bdL: 0.36, bdC: 0.35, bdMax: 0.06, txL: 0.975, t2L: 0.8, t3L: 0.65, accL: 0.8, accMax: 0.2, softA: 0.16),
        .tactile: SurfaceFormula(bgL: 0.17, bgC: 0.15, bgMax: 0.022, sL: (0.215, 0.255, 0.305), sC: 0.18, sMax: 0.026,
                                 bdL: 0.34, bdC: 0.2, bdMax: 0.03, txL: 0.965, t2L: 0.8, t3L: 0.68, accL: 0.82, accMax: 0.2, softA: 0.35),
        .monolith: SurfaceFormula(bgL: 0.1, bgC: 0, bgMax: 0, sL: (0.145, 0.185, 0.23), sC: 0, sMax: 0,
                                  bdL: 0.27, bdC: 0, bdMax: 0, txL: 0.98, t2L: 0.76, t3L: 0.62, accL: 0.78, accMax: 0.2, softA: 0.2,
                                  grayText: true),
    ]

    /// Светлая тема — `SURFACES_LIGHT`: фон ≈ .97–.985, поверхности темнее фона, текст .18 / .40 / .52,
    /// акцент темнее (≥ 3:1 к поверхности), текст на акценте светлый.
    static let surfacesLight: [Surface: SurfaceFormula] = [
        .echo: SurfaceFormula(bgL: 0.975, bgC: 0.1, bgMax: 0.012, sL: (0.955, 0.93, 0.905), sC: 0.12, sMax: 0.016,
                              bdL: 0.86, bdC: 0.15, bdMax: 0.02, txL: 0.18, t2L: 0.4, t3L: 0.52, accL: 0.55, accMax: 0.18, softA: 0.16),
        .signal: SurfaceFormula(bgL: 0.965, bgC: 0.2, bgMax: 0.03, sL: (0.945, 0.915, 0.885), sC: 0.22, sMax: 0.032,
                                bdL: 0.86, bdC: 0.25, bdMax: 0.035, txL: 0.18, t2L: 0.4, t3L: 0.52, accL: 0.55, accMax: 0.19, softA: 0.14),
        .edge: SurfaceFormula(bgL: 0.985, bgC: 0.08, bgMax: 0.01, sL: (0.965, 0.94, 0.91), sC: 0.1, sMax: 0.012,
                              bdL: 0.82, bdC: 0.15, bdMax: 0.02, txL: 0.17, t2L: 0.4, t3L: 0.52, accL: 0.55, accMax: 0.19, softA: 0.14),
        .tactile: SurfaceFormula(bgL: 0.955, bgC: 0.08, bgMax: 0.01, sL: (0.935, 0.91, 0.88), sC: 0.1, sMax: 0.012,
                                 bdL: 0.84, bdC: 0.1, bdMax: 0.014, txL: 0.18, t2L: 0.4, t3L: 0.5, accL: 0.54, accMax: 0.18, softA: 0.22),
        .monolith: SurfaceFormula(bgL: 0.985, bgC: 0, bgMax: 0, sL: (0.965, 0.94, 0.91), sC: 0, sMax: 0,
                                  bdL: 0.88, bdC: 0, bdMax: 0, txL: 0.16, t2L: 0.42, t3L: 0.52, accL: 0.54, accMax: 0.19, softA: 0.14,
                                  grayText: true),
    ]

    /// Токены: исходный цвет (обложка / готовая тема / nil — монохром) × формулы поверхности, как
    /// `themeFrom` в `palette.ts`. Без аргументов — «Эхо» тёмной темы.
    static func theme(from source: RGB?, surface: Surface = .echo, light: Bool = false) -> ThemeTokens {
        let k = (light ? surfacesLight : surfaces)[surface] ?? surfaces[.echo]!
        let base = source.map(oklch) ?? Lch(l: 0, c: 0, h: 0)
        let mono = base.c < monoChroma
        let c = mono ? 0 : base.c
        let h = base.h
        let gray = k.grayText
        func cc(_ m: Double, _ mx: Double) -> Double { min(c * m, mx) }
        func ok(_ l: Double, _ ch: Double) -> RGB { rgb(Lch(l: l, c: ch, h: h)) }
        let ink: RGB
        if light {
            ink = ok(0.985, mono || gray ? 0 : cc(0.03, 0.008))
        } else if mono {
            ink = ok(0.16, 0)
        } else if gray {
            ink = ok(0.12, 0)
        } else {
            ink = ok(0.18, cc(0.35, 0.05))
        }
        return ThemeTokens(
            bg: ok(k.bgL, cc(k.bgC, k.bgMax)),
            s0: ok((k.bgL + k.sL.0) / 2, cc(k.sC, k.sMax)),
            s1: ok(k.sL.0, cc(k.sC, k.sMax)),
            s2: ok(k.sL.1, cc(k.sC, k.sMax)),
            s3: ok(k.sL.2, cc(k.sC, k.sMax)),
            border: ok(k.bdL, cc(k.bdC, k.bdMax)),
            text: ok(k.txL, gray ? 0 : cc(0.03, 0.008)),
            t2: ok(k.t2L, gray ? 0 : cc(0.06, 0.014)),
            t3: ok(k.t3L, gray ? 0 : cc(0.08, 0.018)),
            accent: mono ? ok(light ? 0.22 : 0.95, 0) : ok(k.accL, min(c, k.accMax)),
            ink: ink,
            tint: ok(light ? 0.93 : 0.2, gray ? 0 : cc(light ? 0.3 : 0.6, light ? 0.04 : 0.09)),
            glow: mono ? ok(0.7, 0) : ok(light ? 0.7 : 0.62, min(c, 0.2)),
            track: surface == .signal ? ok(light ? 0.82 : 0.42, cc(0.4, 0.06)) : ok(k.sL.2, cc(k.sC, k.sMax)),
            softAlpha: mono ? (light ? 0.08 : 0.12) : k.softA,
            mono: mono,
            light: light
        )
    }

    /// AMOLED — чистый чёрный фон и поверхности (`tokens.css :root.amoled`), остальное — от темы.
    static func amoled(_ t: ThemeTokens) -> ThemeTokens {
        var out = t
        out.bg = RGB(0, 0, 0)
        out.s0 = RGB(0, 0, 0)
        out.s1 = RGB(7, 7, 8)
        out.s2 = RGB(14, 14, 16)
        out.s3 = RGB(24, 24, 27)
        return out
    }
}
