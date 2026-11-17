import Foundation

// Звук без AVFoundation: эквалайзер (полосы, пресеты, коэффициенты фильтров), нормализация громкости
// (порт `windows/src/player/leveler.ts`) и громкость переходов. Здесь только числа — их гоняют XCTest
// (в том числе Swift'ом для Linux); к звуку их применяет `AudioTap` (MTAudioProcessingTap) и
// `PlaybackEngine` (громкость плеера).

// MARK: - Эквалайзер

/// Эквалайзер как на ПК (`windows/src/player/eq.svelte.ts`): 12 полос 32 Гц – 20 кГц, ±12 дБ, крайние —
/// полки, остальные — колокол с Q 1.1. Кривая одна на все треки — `audio.eq` (12 чисел через запятую),
/// переключатель — `audio.eq_enabled`.
enum Equalizer {
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 12000, 16000, 20000]
    static let maxDb: Double = 12
    static let q: Double = 1.1
    static let gainsKey = "audio.eq"
    static let enabledKey = "audio.eq_enabled"

    static var flat: [Double] { frequencies.map { _ in 0 } }

    /// 32 → «32», 1000 → «1k», 12000 → «12k».
    static func label(_ frequency: Double) -> String {
        frequency >= 1000 ? "\(formatted(frequency / 1000))k" : formatted(frequency)
    }

    /// ±12 дБ, шаг 0.1.
    static func clamp(_ db: Double) -> Double {
        guard db.isFinite else { return 0 }
        return (max(-maxDb, min(maxDb, db)) * 10).rounded() / 10
    }

    /// «0,1.5,-2,…» → 12 чисел; пусто или не 12 чисел — ровная кривая.
    static func parse(_ raw: String) -> [Double] {
        let parts = raw.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == frequencies.count, parts.allSatisfy({ $0 != nil && $0!.isFinite }) else { return flat }
        return parts.map { clamp($0!) }
    }

    static func encode(_ gains: [Double]) -> String {
        gains.map { formatted(clamp($0)) }.joined(separator: ",")
    }

    static func isFlat(_ gains: [Double]) -> Bool {
        gains.allSatisfy { abs($0) < 0.05 }
    }

    struct Preset: Identifiable, Equatable, Sendable {
        let name: String
        let gains: [Double]
        var id: String { name }
    }

    // те же кривые, что у ПК, — по одной-две из каждой вкладки
    //                                  32   64  125  250  500   1k   2k   4k   8k  12k  16k  20k
    static let presets: [Preset] = [
        Preset(name: "Нейтральный", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        Preset(name: "Hi-Fi", gains: [2, 1.5, 0.5, 0, -0.5, 0, 0.5, 1.5, 2, 2.5, 2.5, 2]),
        Preset(name: "Чёткость", gains: [0, 0, -0.5, -1, 0, 1, 2.5, 3, 2.5, 2, 1.5, 1]),
        Preset(name: "Тепло", gains: [2.5, 3, 2.5, 1.5, 0.5, 0, -0.5, -1, -1.5, -2, -2, -2.5]),
        Preset(name: "Наушники", gains: [3, 2.5, 1, 0, -0.5, -0.5, 0.5, 1, 0.5, 1, 1.5, 1]),
        Preset(name: "Ночь", gains: [-1.5, -1, -0.5, 0, 0.5, 1, 1, 0, -1, -2, -2.5, -3]),
        Preset(name: "Басы", gains: [7, 6, 5, 3, 1, 0, 0, 0, 0, 0, 0, 0]),
        Preset(name: "Вокал", gains: [-2, -2, -1, 0, 2, 4, 4, 3, 1, 0, -1, -1]),
        Preset(name: "Высокие", gains: [0, 0, 0, 0, 0, 0, 1, 2, 4, 5, 6, 6]),
        Preset(name: "Громче", gains: [4, 3, 1, 0, -1, -1, 0, 1, 2, 3, 4, 4]),
        Preset(name: "Рок", gains: [4, 3, 2, 0.5, -1, -0.5, 1, 2.5, 3.5, 3.5, 3, 2.5]),
        Preset(name: "Хип-хоп", gains: [5, 4.5, 3, 1, -0.5, -1, 0.5, 1, 1.5, 1.5, 1, 0.5]),
        Preset(name: "Электроника", gains: [4.5, 4, 1.5, 0, -1, 0, -0.5, 1, 3, 4, 4, 3.5]),
        Preset(name: "Фонк", gains: [6, 5, 3, -0.5, -1.5, -1, 0.5, 2, 3, 2.5, 2, 1.5]),
        Preset(name: "Лоу-фай", gains: [2, 2.5, 2, 1, 0.5, 0, -1, -2, -3, -3.5, -4, -4]),
    ]

    /// Какой пресет сейчас (кривая совпадает до 0.05 дБ), иначе nil — «Свой».
    static func preset(matching gains: [Double]) -> Preset? {
        presets.first { preset in
            preset.gains.count == gains.count && zip(preset.gains, gains).allSatisfy { abs($0 - $1) < 0.05 }
        }
    }

    /// Фильтры кривой для частоты дискретизации. Полоса выше половины частоты — без фильтра.
    static func filters(_ gains: [Double], sampleRate: Double) -> [Biquad] {
        frequencies.indices.map { i in
            let gain = i < gains.count ? gains[i] : 0
            let f = frequencies[i]
            guard abs(gain) >= 0.05, f < sampleRate * 0.5 * 0.98 else { return .identity }
            if i == 0 { return .lowShelf(frequency: f, gainDb: gain, sampleRate: sampleRate) }
            if i == frequencies.count - 1 { return .highShelf(frequency: f, gainDb: gain, sampleRate: sampleRate) }
            return .peaking(frequency: f, gainDb: gain, q: q, sampleRate: sampleRate)
        }
    }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Биквадратный фильтр (RBJ Audio EQ Cookbook, те же формулы, что у `BiquadFilterNode` Web Audio).
/// Коэффициенты уже поделены на a0.
struct Biquad: Equatable, Sendable {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    static let identity = Biquad(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    var isIdentity: Bool { self == .identity }

    static func peaking(frequency: Double, gainDb: Double, q: Double, sampleRate: Double) -> Biquad {
        let a = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosw = cos(w0)
        return normalized(b0: 1 + alpha * a, b1: -2 * cosw, b2: 1 - alpha * a,
                          a0: 1 + alpha / a, a1: -2 * cosw, a2: 1 - alpha / a)
    }

    /// Полка с наклоном S = 1, как `lowshelf` Web Audio.
    static func lowShelf(frequency: Double, gainDb: Double, sampleRate: Double) -> Biquad {
        let a = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / 2 * 2.0.squareRoot()
        let k = 2 * a.squareRoot() * alpha
        return normalized(b0: a * ((a + 1) - (a - 1) * cosw + k),
                          b1: 2 * a * ((a - 1) - (a + 1) * cosw),
                          b2: a * ((a + 1) - (a - 1) * cosw - k),
                          a0: (a + 1) + (a - 1) * cosw + k,
                          a1: -2 * ((a - 1) + (a + 1) * cosw),
                          a2: (a + 1) + (a - 1) * cosw - k)
    }

    static func highShelf(frequency: Double, gainDb: Double, sampleRate: Double) -> Biquad {
        let a = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / 2 * 2.0.squareRoot()
        let k = 2 * a.squareRoot() * alpha
        return normalized(b0: a * ((a + 1) + (a - 1) * cosw + k),
                          b1: -2 * a * ((a - 1) + (a + 1) * cosw),
                          b2: a * ((a + 1) + (a - 1) * cosw - k),
                          a0: (a + 1) - (a - 1) * cosw + k,
                          a1: 2 * ((a - 1) - (a + 1) * cosw),
                          a2: (a + 1) - (a - 1) * cosw - k)
    }

    private static func normalized(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) -> Biquad {
        Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Усиление фильтра на частоте, дБ — для тестов и кривой на экране.
    func responseDb(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        // H(e^jw) = (b0 + b1 e^-jw + b2 e^-2jw) / (1 + a1 e^-jw + a2 e^-2jw)
        let nr = b0 + b1 * cos(w) + b2 * cos(2 * w), ni = -(b1 * sin(w) + b2 * sin(2 * w))
        let dr = 1 + a1 * cos(w) + a2 * cos(2 * w), di = -(a1 * sin(w) + a2 * sin(2 * w))
        let magnitude = ((nr * nr + ni * ni) / (dr * dr + di * di)).squareRoot()
        return 20 * log10(magnitude)
    }
}

/// Память фильтра для одного канала (Direct Form I).
struct BiquadState: Sendable {
    var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    @inline(__always)
    mutating func process(_ x: Float, _ c: FloatBiquad) -> Float {
        let y = c.b0 * x + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        // денормалы на тихих хвостах тормозят процессор — гасим их
        y1 = abs(y) < 1e-20 ? 0 : y
        return y
    }
}

/// Коэффициенты во Float — для звукового потока.
struct FloatBiquad: Sendable {
    var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float

    init(_ c: Biquad) {
        b0 = Float(c.b0)
        b1 = Float(c.b1)
        b2 = Float(c.b2)
        a1 = Float(c.a1)
        a2 = Float(c.a2)
    }
}

// MARK: - Нормализация громкости

/// Выравниватель (порт `leveler.ts`): медленная оценка громкости (RMS в дБ, тишину не считает) и плавное
/// усиление к общей цели. Не компрессор — внутри трека динамика не трогается.
enum Leveler {
    /// Цель — средняя громкость RMS, дБFS (≈ −14 LUFS у обычной музыки).
    static let targetDb: Double = -18
    /// Тише не делаем больше, чем на 9 дБ, громче — больше, чем на 6.
    static let minGainDb: Double = -9
    static let maxGainDb: Double = 6
    /// Тише этого — пауза или затухание, в оценку не идёт.
    static let silenceDb: Double = -55
    /// Первые 4 с трека оценка догоняет быстрее (1.5 с), потом — медленно (6 с).
    static let fastForSeconds: Double = 4
    static let fastTau: Double = 1.5
    static let slowTau: Double = 6
    /// Само усиление идёт к цели с такой постоянной времени.
    static let gainFastTau: Double = 0.3
    static let gainSlowTau: Double = 1.2

    static func gainDb(for levelDb: Double) -> Double {
        max(minGainDb, min(maxGainDb, targetDb - levelDb))
    }

    /// За `dt` к новому замеру с постоянной времени `tau` (секунды).
    static func smooth(_ previous: Double, toward sample: Double, dt: Double, tau: Double) -> Double {
        let k = 1 - exp(-dt / tau)
        return previous + (sample - previous) * k
    }

    /// RMS кадра в дБFS; пустой или нулевой — минус бесконечность.
    static func rmsDb(sumOfSquares: Double, count: Int) -> Double {
        guard count > 0 else { return -.infinity }
        let rms = (sumOfSquares / Double(count)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -.infinity
    }

    static func rmsDb(_ frame: [Float]) -> Double {
        rmsDb(sumOfSquares: frame.reduce(0) { $0 + Double($1) * Double($1) }, count: frame.count)
    }

    /// Состояние для звукового потока: оценка громкости и текущее усиление (линейное).
    struct State: Sendable {
        var level: Double?
        var gain: Double = 1
        /// Сколько секунд звука уже прошло через трек.
        var elapsed: Double = 0

        /// Новый блок: `db` — его RMS, `dt` — длительность. Возвращает усиление, к которому плавно
        /// подойти к концу блока.
        mutating func step(blockDb db: Double, dt: Double, enabled: Bool) -> Double {
            elapsed += dt
            let fast = elapsed < Leveler.fastForSeconds
            var target = 1.0
            if enabled {
                if db.isFinite, db >= Leveler.silenceDb {
                    level = level.map { Leveler.smooth($0, toward: db, dt: dt, tau: fast ? Leveler.fastTau : Leveler.slowTau) } ?? db
                }
                if let level { target = pow(10, Leveler.gainDb(for: level) / 20) }
            }
            gain = Leveler.smooth(gain, toward: target, dt: dt, tau: enabled && fast ? Leveler.gainFastTau : Leveler.gainSlowTau)
            return gain
        }
    }
}

// MARK: - Громкость переходов

/// Кроссфейд и плавное возвращение после звонка — множитель громкости плеера 0…1.
enum Fades {
    /// Кроссфейд `audio.crossfade`: 0 — выключен, иначе 1…12 с.
    static let maxCrossfade = 12

    /// Конец трека затихает за `seconds` до конца (если дальше есть что играть), начало следующего после
    /// перехода нарастает за те же секунды. Квадратичная кривая — на слух ровнее линейной.
    static func crossfadeFactor(position: Double, duration: Double, seconds: Double, fadeIn: Bool, fadeOut: Bool) -> Double {
        guard seconds > 0, duration > 0 else { return 1 }
        // короткий трек — переход не длиннее трети
        let span = min(seconds, duration / 3)
        var factor = 1.0
        if fadeIn, position < span { factor = min(factor, max(0, position / span)) }
        if fadeOut, duration - position < span { factor = min(factor, max(0, (duration - position) / span)) }
        return factor * factor
    }

    /// Нарастание после звонка («Вернуть плавно»): от 0.2 до 1 за `span` секунд.
    static func rampFactor(elapsed: Double, span: Double = 2) -> Double {
        guard span > 0 else { return 1 }
        let t = max(0, min(1, elapsed / span))
        return 0.2 + 0.8 * t * t
    }
}
