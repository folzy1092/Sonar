import Foundation

/// Вид строки текста — числами для SwiftUI (порт `LineLook` из `motion.ts`, там — CSS-строки).
/// Нулевые сдвиги, `scale` 1 и `blur` 0 — без трансформации.
struct LineLook: Equatable, Sendable {
    var opacity: Double
    /// Радиус размытия, pt (в CSS — px).
    var blur: Double
    var scale: Double
    var dx: Double
    var dy: Double
    /// Сдвиг «к зрителю» (`translateZ`, перспектива 800): в SwiftUI — лёгкий доп. масштаб `800 / (800 − dz)`.
    var dz: Double
    /// Градусы.
    var rotateX: Double
    var rotateZ: Double
    var skewX: Double
    /// В em (0.02 у «Кино»).
    var letterSpacing: Double
    /// Главная длительность перехода (transform), секунды.
    var duration: Double
    /// Пружина с перелётом (в CSS — cubic-bezier с y > 1, анимация «Отскок»).
    var bounce: Bool

    /// Перспектива 3D-поворота строки (`perspective(800px)`).
    static let perspective = 800.0
}

/// Слово текущей строки в караоке (порт `wordLook` из `motion.ts`).
struct WordLook: Equatable, Sendable {
    var opacity: Double
    var blur: Double
    var scale: Double
    var dy: Double
    /// Градусы, перспектива 400 (`flip3d`).
    var rotateX: Double
    var skewX: Double
    /// Длительность перехода между кадрами, секунды.
    var duration: Double
    var bounce: Bool
    /// «Обычная» анимация: слово не двигается, а заливается слева направо (`LyricsMotion.fill`).
    var usesFill: Bool

    static let perspective = 400.0
    static let fill = WordLook(opacity: 1, blur: 0, scale: 1, dy: 0, rotateX: 0, skewX: 0, duration: 0, bounce: false, usesFill: true)
}

/// «Задержка» на длинном слове (≥ 1,2 с): вспышка яркости или покачивание (порт `holdLook`).
struct HoldLook: Equatable, Sendable {
    /// Множитель яркости: 1 — как есть (в SwiftUI `.brightness(value − 1)`).
    var brightness: Double = 1
    var scale: Double = 1
    var rotateX: Double = 0
    var skewX: Double = 0

    static let none = HoldLook()
}

/// Стили и анимации текста — формулы Dotify один в один (порт `windows/src/lyrics/core/motion.ts`,
/// плюс числа прокрутки, «магнита», заливки слова и точек паузы из `LyricsView.svelte`). Чистые функции.
enum LyricsMotion {
    // MARK: прозрачность и вид строки

    /// Прозрачность строки: текущая 1, следующая 0.58, прошлая 0.42, дальше — тише.
    /// `delta` — индекс строки минус индекс текущей.
    static func lineOpacity(_ delta: Int, synced: Bool, isBg: Bool) -> Double {
        let d = abs(delta)
        var at = 1.0
        if !synced { at = 0.85 }
        else if delta < 0 { at = delta == -1 ? 0.42 : max(0.16, 0.3 - 0.07 * Double(d - 2)) }
        else if delta > 0 { at = delta == 1 ? 0.58 : delta == 2 ? 0.4 : max(0.18, 0.28 - 0.05 * Double(delta - 3)) }
        if delta == 0, synced { return isBg ? 0.88 : 1 }
        return isBg ? 0.8 * at : at
    }

    /// Вид строки: `delta` — индекс минус индекс текущей (0 — текущая). `reduced` — без движения
    /// («Уменьшение движения» или выключенные анимации): только прозрачность.
    static func lineLook(style: LyricsTextStyle, animation: LyricsAnimation, delta: Int, synced: Bool, isBg: Bool = false,
                         reduced: Bool = false) -> LineLook {
        let anim = animation.look
        let cur = delta == 0
        let d = Double(abs(delta))
        let opacity = lineOpacity(delta, synced: synced, isBg: isBg)

        var it = 1.0
        var styleBlur: Double?
        var spacing = 0.0
        var shift = 0.0
        switch style {
        case .scale: it = cur ? 1.08 : max(0.74, 1 - 0.07 * d)
        case .blur:
            it = cur ? 1.05 : max(0.82, 1 - 0.05 * d)
            styleBlur = cur ? 0 : min(2.5 * d, 7)
        case .cinema:
            spacing = 0.02
            it = cur ? 1.04 : 0.95
        case .shift:
            shift = cur ? 14 : 0
            it = cur ? 1.04 : 0.96
        case .normal: break
        }

        var ty = 0.0, tz = 0.0, tx = shift, rx = 0.0, rz = 0.0, skew = 0.0, k = 1.0
        var blur = styleBlur ?? 0
        if styleBlur == nil {
            switch anim {
            case .blur:
                blur = cur ? 0 : d == 1 ? 2.6 : 5.5
                ty = cur ? 0 : delta == 1 ? 5 : -4
            case .float: blur = cur || d < 1 ? 0 : 1.5
            case .zoom: blur = cur || d < 2 ? 0 : 2.2
            default: break
            }
        }
        func side(_ a: Double, _ b: Double) -> Double { cur ? 0 : delta == 1 ? a : b }
        switch anim {
        case .flip3d:
            rx = cur ? 0 : delta == 1 ? 10 : delta == -1 ? -8 : delta > 0 ? 16 : -14
            tz = cur ? 8 : -4
            ty = side(3, -3)
            k = cur ? 1.03 : 0.98
        case .bounce:
            k = cur ? 1.036 : d == 1 ? 0.985 : 0.965
            ty = side(3, -3)
        case .wave:
            ty = cur ? 0 : delta == 1 ? 3 : delta == -1 ? -3 : delta > 0 ? 6 : -5
            rz = cur ? 0 : delta == 1 ? 0.5 : delta == -1 ? -0.5 : 0
            k = cur ? 1.028 : 0.985
        case .float:
            ty = cur ? -1 : delta == 1 ? 4 : delta == -1 ? -4 : delta > 0 ? 7 : -6
            k = cur ? 1.032 : 0.985
        case .drift:
            skew = cur ? 0 : delta == 1 ? -2 : delta == -1 ? 1.5 : 0
            tx = shift + (cur ? 0 : delta == 1 ? 3 : delta == -1 ? -2 : 0)
            ty = side(3, -3)
            k = cur ? 1.028 : 0.985
        case .zoom:
            k = cur ? 1.042 : d == 1 ? 0.97 : max(0.92, 1 - 0.02 * d)
            ty = side(3, -3)
        case .blur:
            k = cur ? 1.032 : 0.98
            ty = side(3, -3)
        case .normal, .fade, .ladder: break
        }
        let scale = style == .scale || style == .blur ? it : k * it
        let simple = anim == .normal || anim == .fade

        var look = LineLook(opacity: opacity, blur: blur, scale: 1, dx: 0, dy: 0, dz: 0, rotateX: 0, rotateZ: 0, skewX: 0,
                            letterSpacing: spacing, duration: 0, bounce: false)
        if !(simple && style == .normal) {
            if simple {
                look.dx = shift
                look.scale = it
            } else {
                look.dx = tx
                look.dy = ty
                look.dz = tz
                look.scale = scale
                look.rotateX = rx
                look.rotateZ = rz
                look.skewX = skew
            }
        }

        // длительности — transform из CSS-переходов motion.ts
        if simple, style != .normal { look.duration = 0.7 } // T_SOFT
        else if anim == .normal { look.duration = 0.868 } // T_NORMAL
        else if anim == .bounce {
            look.duration = 0.868
            look.bounce = true
        } else if anim == .float { look.duration = 0.952 }
        else if anim == .fade { look.duration = 0.924 }
        else { look.duration = 1.092 } // T_SLOW

        if reduced {
            return LineLook(opacity: opacity, blur: 0, scale: 1, dx: 0, dy: 0, dz: 0, rotateX: 0, rotateZ: 0, skewX: 0,
                            letterSpacing: spacing, duration: 0.42, bounce: false)
        }
        return look
    }

    /// Длительность смены прозрачности строки (в CSS у «Обычной» текущая гаснет быстрее: 870 / 1010 мс).
    static func opacityDuration(animation: LyricsAnimation, style: LyricsTextStyle, current: Bool, reduced: Bool = false) -> Double {
        if reduced { return 0.42 }
        let anim = animation.look
        let simple = anim == .normal || anim == .fade
        if simple, style != .normal { return 0.7 }
        switch anim {
        case .normal: return current ? 0.87 : 1.01
        case .bounce: return 0.84
        case .float: return 0.952
        case .fade: return 0.924
        default: return 1.092
        }
    }

    // MARK: слова в караоке

    /// Слово текущей строки (кроме «Обычной» — та идёт заливкой, `WordLook.usesFill`). `p` — прогресс
    /// слова, `past` — уже спето, `current` — поётся сейчас.
    static func wordLook(animation: LyricsAnimation, progress p: Double, past: Bool, current: Bool) -> WordLook {
        let op = past ? 1 : current ? 0.5 + 0.5 * p : 0.52
        var look = WordLook(opacity: op, blur: 0, scale: 1, dy: 0, rotateX: 0, skewX: 0, duration: 0, bounce: false, usesFill: false)
        switch animation.look {
        case .fade:
            look.duration = 0.22
        case .blur:
            look.blur = past ? 0 : current ? (p > 0.95 ? 0 : 3.5 * (1 - p)) : 3
            look.duration = 0.12
        case .flip3d:
            look.rotateX = past ? 0 : current ? 45 * (1 - p) : 45
            look.duration = 0.24
        case .bounce:
            look.scale = past ? 1 : current ? 0.93 + 0.07 * p : 0.93
            look.dy = past ? 0 : current ? -2.5 * (1 - p) : 0
            look.duration = 0.2
            look.bounce = true
        case .wave:
            look.dy = current ? -3.2 * sin(p * Double.pi) : 0
            look.duration = 0.16
        case .float:
            look.dy = past ? 0 : current ? 4.5 * (1 - p) : 4.5
            look.duration = 0.2
        case .drift:
            look.skewX = past ? 0 : current ? -6 * (1 - p) : -6
            look.scale = past ? 1 : current ? 0.95 + 0.05 * p : 0.95
            look.duration = 0.18
        case .zoom:
            look.scale = past ? 1 : current ? 0.88 + 0.12 * p : 0.88
            look.duration = 0.18
        case .normal, .ladder:
            return .fill
        }
        return look
    }

    /// Прозрачность слова при «Уменьшении движения» (только прозрачность).
    static func reducedWordOpacity(progress p: Double, past: Bool, current: Bool) -> Double {
        past ? 1 : current ? 0.5 + 0.5 * p : 0.52
    }

    /// «Задержка» на длинном слове (≥ 1,2 с): лёгкая вспышка или покачивание по анимации.
    static func holdLook(animation: LyricsAnimation, progress p: Double, duration: Double, current: Bool) -> HoldLook {
        guard current, duration >= LyricsClock.longWord else { return .none }
        let r = LyricsClock.pulse(p)
        switch animation.look {
        case .fade: return HoldLook(brightness: 1 + 0.12 * r)
        case .blur: return HoldLook(brightness: 1 + 0.08 * r)
        case .flip3d: return HoldLook(rotateX: -3 * r)
        case .float: return HoldLook(brightness: 1 + 0.06 * r)
        case .drift: return HoldLook(skewX: -1.5 * r)
        case .bounce: return HoldLook(scale: 1 + 0.045 * r)
        case .zoom: return HoldLook(scale: 1 + 0.055 * r)
        default: return HoldLook(brightness: 1 + 0.1 * r)
        }
    }

    /// Заливка слова в «Обычной» (градиент слева направо): до `solid` — полная яркость, после `faded` —
    /// приглушённо (`fadedOpacity`), между — переход. Доли ширины слова, могут выходить за 0…1.
    static func fill(progress p: Double) -> (solid: Double, faded: Double) {
        (p * 1.14 - 0.14, p * 1.14)
    }

    /// Прозрачность ещё не спетой части слова в заливке.
    static let fadedOpacity = 0.55

    /// Строка без пословного тайминга → слова, время делится по длине (как в Dotify).
    /// Конец строки у нас уже известен (`end`), поэтому `next` из TS не нужен.
    static func synthWords(_ line: LyricLine) -> [LyricWord] {
        let parts = line.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !parts.isEmpty else { return [] }
        let fallback = max(2.5, 0.08 * Double(line.text.count))
        let span = max(0.4, min(line.duration > 0 ? line.duration : fallback, 8))
        let weights = parts.map { Double($0.count + 1) }
        let total = weights.reduce(0, +)
        var t = line.start
        return parts.enumerated().map { i, text in
            let duration = span * weights[i] / total
            let word = LyricWord(start: t, end: t + duration, text: text, spaceAfter: i < parts.count - 1, isBackground: false)
            t += duration
            return word
        }
    }

    // MARK: паузы «• • •»

    /// Прозрачность трёх точек паузы по её прогрессу: загораются по очереди (clamp(0.25, 3p − k, 1)).
    static func gapDots(progress p: Double) -> [Double] {
        (0 ..< 3).map { k in min(1, max(0.25, p * 3 - Double(k))) }
    }

    // MARK: прокрутка

    /// Текущая строка встаёт на 32 % высоты экрана текста.
    static let anchor = 0.32
    /// Пользователь прокрутил сам — автопрокрутка ждёт 2,5 с.
    static let userScrollPause = 2.5

    /// Плавный переезд к строке: 0,75 с + 0,6 мс на точку, не дольше 1,3 с.
    static func glideDuration(distance: Double) -> Double {
        min(1.3, 0.75 + abs(distance) * 0.0006)
    }

    /// Кривая переезда (easeInOutCubic).
    static func glideEase(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// «Магнит» («Лесенка»): прокрутка встаёт на место сразу, строки догоняют её сами — первой уходит
    /// только что спетая, каждая следующая на 45 мс позже и чуть быстрее. Кривая — cubic-bezier(0.6, 0, 0.25, 1).
    static let magnetBaseDuration = 0.78
    static let magnetStep = 0.045
    static let magnetShorten = 0.04
    static let magnetMinDuration = 0.54
    static let magnetCurve = (x1: 0.6, y1: 0.0, x2: 0.25, y2: 1.0)

    /// Включается «магнит», если анимация — «Лесенка», строка ушла вперёд на 1–3 и движение не урезано.
    static func usesMagnet(animation: LyricsAnimation, from previous: Int?, to current: Int?, reduced: Bool) -> Bool {
        guard animation == .ladder, !reduced, let previous, let current else { return false }
        return current > previous && current - previous <= 3
    }

    /// Порядок строки в лесенке: 0 — только что спетая, дальше по одной, не больше 6.
    static func magnetOrder(line index: Int, previous: Int) -> Int {
        min(max(0, index - previous), 6)
    }

    static func magnetDelay(order: Int) -> Double { Double(order) * magnetStep }

    static func magnetDuration(order: Int) -> Double {
        max(magnetMinDuration, magnetBaseDuration - Double(order) * magnetShorten)
    }
}
