import Foundation

/// Сила темы под обложку (`appearance.cover_strength`, как ПК `COVER_STRENGTH` в `palette.ts`):
/// насколько поверхности уходят по светлоте за обложкой (тёмная — темнее, светлая — светлее), во
/// сколько раз сильнее подкраска и минимальная насыщенность оттенка — чтобы поверхность не стала серой.
enum CoverStrength: String, CaseIterable, Identifiable, Sendable {
    case weak, medium, strong

    var id: String { rawValue }

    /// Подпись в настройках (ключ перевода — русская строка, как на ПК).
    var title: String {
        switch self {
        case .weak: "Слабо"
        case .medium: "Средне"
        case .strong: "Сильно"
        }
    }

    var params: (shift: Double, chroma: Double, hue: Double) {
        switch self {
        case .weak: (0.08, 0.8, 0.004)
        case .medium: (0.14, 1, 0.008)
        case .strong: (0.2, 1.3, 0.012)
        }
    }

    /// Неизвестное значение из синка — «Средне».
    init(setting: String) {
        self = CoverStrength(rawValue: setting) ?? .medium
    }
}

/// Обложка для сдвига: сила из настроек и средняя светлота OKLCH (0…1) её пикселей.
struct CoverShift: Equatable, Sendable {
    var strength: CoverStrength
    var lightness: Double
}

/// Что тема берёт из обложки: акцент (nil — серая) и средняя светлота OKLCH (тёмная / светлая).
struct CoverSample: Equatable, Sendable {
    var accent: RGB?
    var lightness: Double
}

extension Palette {
    /// Пиксели уменьшенной обложки (RGBA) → акцент и светлота.
    static func sample(_ px: [UInt8]) -> CoverSample {
        CoverSample(accent: pickAccent(px), lightness: coverLightness(px))
    }

    /// Сдвиг светлоты не больше 20 % — и ниже порога контраста не опускаемся.
    static let maxCoverShift = 0.2
    /// Средняя светлота обложки: L ≤ .3 — «тёмная», L ≥ .9 — «светлая».
    static let pivotLightness = 0.6
    private static let spanLightness = 0.3
    /// Тёмная тема не уходит в чёрный, светлая — в белый.
    private static let darkFloor = 0.075
    private static let lightCeil = 0.992
    /// Контраст просел — сдвиг ослабляем шагами, пока не пройдёт.
    static let guardStep = 0.7
    static let guardTries = 8

    /// Средняя светлота OKLCH непрозрачных пикселей (RGBA подряд); пустая картинка — середина шкалы.
    static func coverLightness(_ px: [UInt8]) -> Double {
        var sum = 0.0
        var n = 0
        var i = 0
        while i + 3 < px.count {
            if px[i + 3] >= 128 {
                sum += oklch(RGB(Double(px[i]), Double(px[i + 1]), Double(px[i + 2]))).l
                n += 1
            }
            i += 4
        }
        return n > 0 ? sum / Double(n) : pivotLightness
    }

    /// Насколько и куда сдвигать (−shift…shift): тёмная обложка — минус, светлая — плюс.
    static func coverBias(_ cover: CoverShift) -> Double {
        let bias = max(-1, min(1, (cover.lightness - pivotLightness) / spanLightness))
        return max(-maxCoverShift, min(maxCoverShift, bias * cover.strength.params.shift))
    }

    /// Светлота поверхности со сдвигом f: в тёмной теме — от нуля, в светлой — от белого.
    static func shiftLightness(_ l: Double, f: Double, light: Bool) -> Double {
        if f == 0 { return l }
        return light ? min(lightCeil, 1 - (1 - l) * (1 - f)) : max(darkFloor, l * (1 + f))
    }

    // ---- контраст WCAG ----

    private static func channel(_ v: Double) -> Double {
        let x = v / 255
        return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ c: RGB) -> Double {
        0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Порог контраста WCAG для каждой пары из `contrasts` (как `CONTRAST_PAIRS` в `palette.ts`).
    private static let contrastMins: [Double] = [12, 4.5, 4.5, 4.5, 3, 4.5]
    /// Погрешность округления sRGB при сравнении контраста до и после сдвига.
    private static let contrastEps = 1e-6

    /// Текст / фон, t3 / фон, t3 / s1, t2 / s3, акцент / s1, акцент / текст на акценте.
    private static func contrasts(_ t: ThemeTokens) -> [Double] {
        [contrast(t.text, t.bg), contrast(t.t3, t.bg), contrast(t.t3, t.s1),
         contrast(t.t2, t.s3), contrast(t.accent, t.s1), contrast(t.accent, t.ink)]
    }

    /// Текст и акцент читаются на всех поверхностях (WCAG AA).
    static func readable(_ t: ThemeTokens) -> Bool {
        zip(contrasts(t), contrastMins).allSatisfy { $0 >= $1 }
    }

    /// Сдвиг под обложку не портит чтение: каждая пара не ниже порога AA — а где тема и без сдвига ниже
    /// порога (например, акцент на светлой теме), не ниже, чем была. Как `keepsContrast` в `palette.ts`.
    static func keepsContrast(_ t: ThemeTokens, base: ThemeTokens) -> Bool {
        let before = contrasts(base)
        return zip(zip(contrasts(t), before), contrastMins).allSatisfy { pair, floor in
            pair.0 >= min(floor, pair.1) - contrastEps
        }
    }
}
