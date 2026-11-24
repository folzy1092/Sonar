import Foundation
import os

// Цепочка дека сведения внутри `AudioTap` (docs/BLEND.md §3, §13) — то же, что `deck-chain.ts` на ПК:
// громкость → изолятор (полки 180 Гц и 3200 Гц, колокол 1000 Гц) → ФВЧ → ФНЧ → эхо (задержка до 4 с, в обратной
// связи ФВЧ 300 Гц) → сдвиг тона. Значения — `BlendDeckAutomation` по времени файла, пересчёт раз в 64 кадра,
// громкость и смесь тона внутри куска — плавно. Без перехода — обход, звук не трогается.
//
// Главный поток пишет команды в ящик под замком, звуковой поток забирает их без ожидания (занят — в следующий
// раз), как `AudioTapParams`.

final class BlendDeckDSP: @unchecked Sendable {
    static let subFrames = 64
    /// Хвост эха после выключения посыла — столько задержек (обратная связь ≤ 0,5 — за 8 повторов затихает).
    static let echoTailRepeats = 8
    private static let maxChannels = 8
    private static let filterSlots = 6
    /// ФНЧ выше этой доли частоты дискретизации — обход (в покое он на Найквисте).
    private static let lpBypassShare = 0.45
    private static let hpBypassHz = BlendChain.hpRestHz + 0.5

    private struct Inbox: Sendable {
        var program: BlendDeckProgram?
        var echoDelaySec = 0.0
        var restart = false
        var ramps: [BlendRamp] = []
        var shift = 1.0
        var version = 0
    }

    private struct Filters {
        var low = FloatBiquad(.identity), mid = FloatBiquad(.identity), high = FloatBiquad(.identity)
        var hp = FloatBiquad(.identity), lp = FloatBiquad(.identity)
        var lowOn = false, midOn = false, highOn = false, hpOn = false, lpOn = false
    }

    /// Кусок блока в 64 кадра: значения на его конце и откуда идём.
    private struct Sub {
        var gain0: Float = 1, gain1: Float = 1
        var filters = Filters()
        var send: Float = 0, feedback: Float = 0
        var echo = false
        var ratio = 1.0
        var mix0: Float = 0, mix1: Float = 0
    }

    private let inbox = OSAllocatedUnfairLock(initialState: Inbox())

    // звуковой поток
    private var seen = 0
    private var ready = false
    private var fresh = false
    private var sampleRate = 44100.0
    private var channels = 0
    private var automation = BlendDeckAutomation()
    private var shift = 1.0
    private var pitchMix: Float = 0
    private var lastValues = BlendDeckAutomation.rest
    private var lastFilters = Filters()
    private var echoHp = FloatBiquad(.identity)
    private var delaySamples = 0
    private var delayLength = 1
    private var delayWrite = 0
    private var writeBase = 0
    private var tailFrames = 0
    private var subCount = 0
    private var subCapacity = 0
    private var subs: UnsafeMutablePointer<Sub>?
    private var delay: UnsafeMutablePointer<Float>?
    private let states = UnsafeMutablePointer<BiquadState>.allocate(capacity: filterSlots * maxChannels)
    private var shifters: [PitchShifter] = []

    init() {
        states.initialize(repeating: BiquadState(), count: Self.filterSlots * Self.maxChannels)
    }

    deinit {
        states.deallocate()
        subs?.deallocate()
        delay?.deallocate()
    }

    // MARK: главный поток

    /// Новый переход (nil — дек снова обычный). Рампы и сдвиг тона сбрасываются.
    func start(_ program: BlendDeckProgram?, echoDelaySec: Double) {
        inbox.withLock {
            $0.program = program
            $0.echoDelaySec = echoDelaySec
            $0.restart = true
            $0.ramps = []
            $0.shift = 1
            $0.version &+= 1
        }
    }

    func ramp(_ ramp: BlendRamp) {
        inbox.withLock {
            $0.ramps.append(ramp)
            $0.version &+= 1
        }
    }

    /// Сдвиг тона, множитель частоты (1 — без сдвига).
    func setShift(_ ratio: Double) {
        inbox.withLock {
            $0.shift = ratio
            $0.version &+= 1
        }
    }

    // MARK: звуковой поток

    func prepare(sampleRate rate: Double, channels count: Int, maxFrames: Int) {
        sampleRate = rate > 0 ? rate : 44100
        channels = min(max(0, count), Self.maxChannels)
        subs?.deallocate()
        subCapacity = max(1, maxFrames / Self.subFrames + 2)
        subs = .allocate(capacity: subCapacity)
        subs?.initialize(repeating: Sub(), count: subCapacity)
        delay?.deallocate()
        delayLength = Int(BlendChain.echoMaxSec * sampleRate) + 1
        delay = .allocate(capacity: delayLength * max(1, channels))
        delay?.initialize(repeating: 0, count: delayLength * max(1, channels))
        shifters = (0 ..< channels).map { _ in PitchShifter() }
        echoHp = FloatBiquad(.highPass(frequency: BlendChain.echoHpHz, q: BlendMix.qRest, sampleRate: sampleRate))
        delaySamples = min(delayLength - 1, delaySamples)
        clear()
        lastFilters = Self.filters(lastValues, sampleRate: sampleRate)
        ready = channels > 0
    }

    func unprepare() {
        ready = false
    }

    /// Начало блока: значения кусков. false — переход не идёт, `process` звать не надо.
    /// startMs — время файла первого кадра (nil — неизвестно), durationMs — сколько файла в блоке.
    func begin(startMs: Double?, durationMs: Double, frames: Int) -> Bool {
        guard ready, frames > 0, let subs else { return false }
        pullInbox()
        guard !automation.isIdle || shift != 1 || pitchMix > 0 || tailFrames > 0 else { return false }
        let msPerFrame = durationMs > 0 ? durationMs / Double(frames) : 1000 / sampleRate
        subCount = min(subCapacity, (frames + Self.subFrames - 1) / Self.subFrames)
        // сразу после новой программы ход громкости — не от покоя (1), а от первого значения: иначе B хлопнет
        var gain: Float? = fresh ? nil : Float(automation.current.gain)
        fresh = false
        for k in 0 ..< subCount {
            let first = k * Self.subFrames
            let count = k == subCount - 1 ? frames - first : Self.subFrames
            let dt = Double(count) / sampleRate
            let values = automation.step(ms: startMs.map { $0 + Double(first + count) * msPerFrame }, dt: dt)
            if values != lastValues {
                lastValues = values
                lastFilters = Self.filters(values, sampleRate: sampleRate)
            }
            let mix0 = pitchMix
            let target: Float = abs(shift - 1) > 0.0005 ? 1 : 0
            let stepMix = Float(dt / BlendChain.pitchXfadeSec)
            pitchMix = target > pitchMix ? min(target, pitchMix + stepMix) : max(target, pitchMix - stepMix)
            let echoOn = values.echoSend > 0 || values.feedback > 0
            tailFrames = echoOn ? delaySamples * Self.echoTailRepeats : max(0, tailFrames - count)
            subs[k] = Sub(
                gain0: gain ?? Float(values.gain), gain1: Float(values.gain), filters: lastFilters,
                send: Float(values.echoSend), feedback: Float(values.feedback),
                echo: delaySamples > 0 && (echoOn || tailFrames > 0),
                ratio: shift, mix0: mix0, mix1: pitchMix
            )
            gain = Float(values.gain)
        }
        writeBase = delayWrite
        delayWrite = (delayWrite + frames) % delayLength
        return true
    }

    /// Один отсчёт канала `channel` на кадре `frame` блока, начатого `begin`.
    @inline(__always)
    func process(_ x: Float, channel: Int, frame: Int) -> Float {
        guard channel < channels, let subs, subCount > 0 else { return x }
        let s = subs[min(frame / Self.subFrames, subCount - 1)]
        let t = Float(frame % Self.subFrames) / Float(Self.subFrames)
        let st = states + channel * Self.filterSlots
        var y = x * (s.gain0 + (s.gain1 - s.gain0) * t)
        let f = s.filters
        if f.lowOn { y = st[0].process(y, f.low) }
        if f.midOn { y = st[1].process(y, f.mid) }
        if f.highOn { y = st[2].process(y, f.high) }
        if f.hpOn { y = st[3].process(y, f.hp) }
        if f.lpOn { y = st[4].process(y, f.lp) }
        if s.echo, let delay {
            let line = delay + channel * delayLength
            let w = (writeBase + frame) % delayLength
            let d = line[(w - delaySamples + delayLength) % delayLength]
            line[w] = y * s.send + s.feedback * st[5].process(d, echoHp)
            y += d
        }
        let mix = s.mix0 + (s.mix1 - s.mix0) * t
        if mix > 0 {
            let wet = shifters[channel].process(y, ratio: s.ratio)
            y += (wet - y) * mix
        }
        return y
    }

    private func pullInbox() {
        let taken = inbox.withLockIfAvailable { (box: inout Inbox) -> Inbox? in
            let out = box
            box.ramps = []
            box.restart = false
            return out
        }
        guard let got = taken, let box = got, box.version != seen else { return }
        seen = box.version
        if box.restart {
            automation.start(box.program)
            fresh = true
            delaySamples = min(delayLength - 1, max(0, Int((box.echoDelaySec * sampleRate).rounded())))
            clear()
        }
        for ramp in box.ramps { automation.enqueue(ramp) }
        shift = box.shift
    }

    private func clear() {
        states.update(repeating: BiquadState(), count: Self.filterSlots * Self.maxChannels)
        delay?.update(repeating: 0, count: delayLength * max(1, channels))
        tailFrames = 0
        pitchMix = 0
        shifters.forEach { $0.reset() }
    }

    private static func filters(_ v: DeckValues, sampleRate sr: Double) -> Filters {
        var f = Filters()
        let iso = { (db: Double) in min(BlendChain.isoMaxDb, max(BlendChain.isoMinDb, db)) }
        if v.low != 0 {
            f.low = FloatBiquad(.lowShelf(frequency: BlendChain.lowHz, gainDb: iso(v.low), sampleRate: sr))
            f.lowOn = true
        }
        if v.mid != 0 {
            f.mid = FloatBiquad(.peaking(frequency: BlendChain.midHz, gainDb: iso(v.mid), q: BlendChain.midQ, sampleRate: sr))
            f.midOn = true
        }
        if v.high != 0 {
            f.high = FloatBiquad(.highShelf(frequency: BlendChain.highHz, gainDb: iso(v.high), sampleRate: sr))
            f.highOn = true
        }
        if v.hpHz > hpBypassHz {
            f.hp = FloatBiquad(.highPass(frequency: min(v.hpHz, sr * lpBypassShare), q: max(0.1, v.hpQ), sampleRate: sr))
            f.hpOn = true
        }
        if v.lpHz < sr * lpBypassShare {
            f.lp = FloatBiquad(.lowPass(frequency: max(20, v.lpHz), q: BlendMix.qRest, sampleRate: sr))
            f.lpOn = true
        }
        return f
    }
}

extension Biquad {
    /// ФВЧ второго порядка (RBJ), как `highpass` Web Audio.
    static func highPass(frequency: Double, q: Double, sampleRate: Double) -> Biquad {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosw = cos(w0), alpha = sin(w0) / (2 * q), a0 = 1 + alpha
        return Biquad(b0: (1 + cosw) / 2 / a0, b1: -(1 + cosw) / a0, b2: (1 + cosw) / 2 / a0,
                      a1: -2 * cosw / a0, a2: (1 - alpha) / a0)
    }

    /// ФНЧ второго порядка (RBJ), как `lowpass` Web Audio.
    static func lowPass(frequency: Double, q: Double, sampleRate: Double) -> Biquad {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosw = cos(w0), alpha = sin(w0) / (2 * q), a0 = 1 + alpha
        return Biquad(b0: (1 - cosw) / 2 / a0, b1: (1 - cosw) / a0, b2: (1 - cosw) / 2 / a0,
                      a1: -2 * cosw / a0, a2: (1 - alpha) / a0)
    }
}
