import Foundation

// Эффекты листа скорости на iPhone без AVFoundation: сдвиг тона без смены темпа и реверб. Только числа — их
// гоняют XCTest (и Swift для Linux); к звуку их применяет `AudioTap` (по каналу на экземпляр, память
// выделяется заранее — в звуковом потоке ничего не создаётся).

/// Сдвиг тона — тот же алгоритм, что AudioWorklet ПК (`windows/src/player/effects.ts`): кольцевой буфер,
/// читающая головка едет быстрее или медленнее пишущей, две головки со сдвигом в полпериода плавно сменяют
/// друг друга (окно sin², сумма весов всегда 1). Темп не меняется.
final class PitchShifter {
    static let window = 2048.0
    private static let size = 4096
    private static let mask = size - 1

    private let buffer: UnsafeMutablePointer<Float>
    private var write = 0
    private var phase = 0.0

    init() {
        buffer = .allocate(capacity: Self.size)
        buffer.initialize(repeating: 0, count: Self.size)
    }

    deinit {
        buffer.deallocate()
    }

    func reset() {
        buffer.update(repeating: 0, count: Self.size)
        write = 0
        phase = 0
    }

    /// ratio — множитель частоты (2 — октава вверх, 1 — без сдвига).
    @inline(__always)
    func process(_ x: Float, ratio: Double) -> Float {
        buffer[write] = x
        phase += (1 - ratio) / Self.window
        phase -= phase.rounded(.down)
        let p1 = phase
        let p2 = p1 + 0.5 >= 1 ? p1 - 0.5 : p1 + 0.5
        let s = sin(Double.pi * p1)
        let g1 = Float(s * s)
        let y = read(Double(write + Self.size) - p1 * Self.window) * g1
            + read(Double(write + Self.size) - p2 * Self.window) * (1 - g1)
        write = (write + 1) & Self.mask
        return y
    }

    @inline(__always)
    private func read(_ position: Double) -> Float {
        let i = Int(position)
        let f = Float(position - Double(i))
        return buffer[i & Self.mask] * (1 - f) + buffer[(i + 1) & Self.mask] * f
    }
}

/// Реверб как Freeverb (Jezar): 8 гребенчатых фильтров с затуханием и 4 всепропускающих, длины под частоту
/// дискретизации, у правого канала чуть длиннее (ширина). Свёртка с откликом зала, как на ПК, звуковому потоку
/// телефона не по силам; смешение сухого и мокрого — как на ПК (`Effects.setReverb`).
final class Reverb {
    private static let combTunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    private static let allpassTunings = [556, 441, 341, 225]
    private static let spread = 23
    private static let feedback: Float = 0.84
    private static let damp: Float = 0.2
    private static let inputGain: Float = 0.015
    private static let wetScale: Float = 3

    private final class Line {
        let data: UnsafeMutablePointer<Float>
        let length: Int
        var index = 0
        var store: Float = 0

        init(_ length: Int) {
            self.length = max(1, length)
            data = .allocate(capacity: self.length)
            data.initialize(repeating: 0, count: self.length)
        }

        deinit { data.deallocate() }

        func reset() {
            data.update(repeating: 0, count: length)
            index = 0
            store = 0
        }
    }

    private let combs: [Line]
    private let allpasses: [Line]

    /// channel — номер канала: у нечётных линии длиннее на `spread`, звук шире.
    init(sampleRate: Double, channel: Int) {
        let scale = sampleRate / 44100
        let extra = channel % 2 == 1 ? Self.spread : 0
        combs = Self.combTunings.map { Line(Int(Double($0 + extra) * scale)) }
        allpasses = Self.allpassTunings.map { Line(Int(Double($0 + extra) * scale)) }
    }

    func reset() {
        combs.forEach { $0.reset() }
        allpasses.forEach { $0.reset() }
    }

    /// Только мокрый сигнал (хвост) — смешивает `mix`.
    @inline(__always)
    func process(_ x: Float) -> Float {
        let input = x * Self.inputGain
        var out: Float = 0
        for comb in combs {
            let y = comb.data[comb.index]
            comb.store = y * (1 - Self.damp) + comb.store * Self.damp
            comb.data[comb.index] = input + comb.store * Self.feedback
            comb.index += 1
            if comb.index == comb.length { comb.index = 0 }
            out += y
        }
        for allpass in allpasses {
            let buffered = allpass.data[allpass.index]
            allpass.data[allpass.index] = out + buffered * 0.5
            out = buffered - out
            allpass.index += 1
            if allpass.index == allpass.length { allpass.index = 0 }
        }
        return out * Self.wetScale
    }

    /// Сухой + мокрый по силе 0…1: мокрый растёт, сухой чуть уходит — громкость почти не меняется (как ПК).
    @inline(__always)
    static func mix(dry: Float, wet: Float, amount: Float) -> Float {
        dry * (1 - amount * 0.4) + wet * amount * 0.85
    }
}
