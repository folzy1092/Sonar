import Foundation
import XCTest
@testable import Sonar

// Дек сведения на iPhone (docs/BLEND.md §13): автоматизация по времени файла, рампы поверх кривых, цепочка в тапе.

final class BlendDeckDSPTests: XCTestCase {
    private let eps = 1e-6

    private func key(_ bar: Double, _ v: Double) -> BlendCurveKey {
        BlendCurveKey(bar: bar, v: v, shape: .lin)
    }

    private func curves(b: BlendDeckCurves) -> BlendCurves {
        BlendCurves(a: [:], b: b, promoteBar: 4, endBar: 4, echoDelaySec: 0.01, rest: BlendDeckAutomation.rest)
    }

    /// B: такт 0 — 0 мс файла, такт — секунда.
    private func program(_ b: BlendDeckCurves) -> BlendDeckProgram {
        BlendDeckProgram(curves: curves(b: b), side: .b, gainMul: 1, map: BlendBarMap(bar0: 0, ms0: 0, msPerBar: 1000))
    }

    // MARK: автоматизация

    func testBarMapFollowsPlanTempo() {
        let map = BlendBarMap(bar0: 4, ms0: 10_000, msPerBar: 2000)
        XCTAssertEqual(map.bar(atMs: 14_000), 6, accuracy: eps)
        XCTAssertEqual(map.bar(atMs: 9000), 3.5, accuracy: eps)
    }

    func testIdleWithoutProgram() {
        var auto = BlendDeckAutomation()
        XCTAssertTrue(auto.isIdle)
        XCTAssertEqual(auto.step(ms: 1000, dt: 0.1), BlendDeckAutomation.rest)
        XCTAssertTrue(auto.isIdle)
    }

    func testProgramReadsCurveByFileTime() {
        var auto = BlendDeckAutomation()
        auto.start(program([.gain: [key(0, 0), key(4, 1)]]))
        XCTAssertFalse(auto.isIdle)
        XCTAssertEqual(auto.step(ms: 2000, dt: 0.1).gain, 0.5, accuracy: eps)
        // перемотка назад — кривая назад, без накопления
        XCTAssertEqual(auto.step(ms: 1000, dt: 0.1).gain, 0.25, accuracy: eps)
        // время неизвестно — значение стоит
        XCTAssertEqual(auto.step(ms: nil, dt: 0.1).gain, 0.25, accuracy: eps)
    }

    func testRampOverridesCurveThenHolds() {
        var auto = BlendDeckAutomation()
        auto.start(program([.gain: [key(0, 1), key(4, 1)]]))
        _ = auto.step(ms: 0, dt: 0.1)
        auto.enqueue(.gain(0, seconds: 1))
        XCTAssertEqual(auto.step(ms: 500, dt: 0.5).gain, 0.5, accuracy: eps)
        XCTAssertEqual(auto.step(ms: 1000, dt: 0.5).gain, 0, accuracy: eps)
        XCTAssertEqual(auto.step(ms: 2000, dt: 0.5).gain, 0, accuracy: eps)
    }

    func testRampToValuesAndNewProgramResets() {
        var auto = BlendDeckAutomation()
        auto.start(program([.lpHz: [key(0, 500)]]))
        XCTAssertEqual(auto.step(ms: 0, dt: 0.1).lpHz, 500, accuracy: eps)
        auto.enqueue(.values(BlendDeckAutomation.rest, seconds: 0.2))
        _ = auto.step(ms: 100, dt: 0.2)
        XCTAssertEqual(auto.current, BlendDeckAutomation.rest)
        auto.start(nil)
        XCTAssertTrue(auto.isIdle)
    }

    func testFinishedRampToRestGoesIdle() {
        var auto = BlendDeckAutomation()
        auto.start(program([.gain: [key(0, 1)]]))
        _ = auto.step(ms: 0, dt: 0.1)
        auto.enqueue(.values(BlendDeckAutomation.rest, seconds: 0.1))
        _ = auto.step(ms: 100, dt: 0.2)
        XCTAssertTrue(auto.isIdle)
    }

    func testMixIsGeometricForFrequencies() {
        let from = BlendDeckAutomation.rest.with(.hpHz, 100).with(.gain, 0)
        let to = from.with(.hpHz, 10_000).with(.gain, 1)
        let mid = BlendDeckAutomation.mix(from, to, 0.5)
        XCTAssertEqual(mid.hpHz, 1000, accuracy: 1e-6)
        XCTAssertEqual(mid.gain, 0.5, accuracy: eps)
    }

    // MARK: цепочка

    private func dsp(_ program: BlendDeckProgram?, echoDelaySec: Double = 0.01, sampleRate: Double = 1000) -> BlendDeckDSP {
        let d = BlendDeckDSP()
        d.prepare(sampleRate: sampleRate, channels: 1, maxFrames: 512)
        d.start(program, echoDelaySec: echoDelaySec)
        return d
    }

    private func run(_ d: BlendDeckDSP, _ input: [Float], startMs: Double = 0, sampleRate: Double = 1000) -> [Float]? {
        let ms = Double(input.count) * 1000 / sampleRate
        guard d.begin(startMs: startMs, durationMs: ms, frames: input.count) else { return nil }
        return input.enumerated().map { d.process($0.element, channel: 0, frame: $0.offset) }
    }

    func testBypassWhenIdle() {
        let d = dsp(nil)
        XCTAssertNil(run(d, [Float](repeating: 0.5, count: 128)))
    }

    func testNeutralProgramLeavesSignalUntouched() {
        let d = dsp(program([.gain: [key(0, 1)]]))
        let input = (0 ..< 256).map { Float(sin(Double($0) * 0.3)) }
        let out = run(d, input)
        XCTAssertEqual(out, input)
    }

    func testGainCurveSilencesDeck() {
        let d = dsp(program([.gain: [key(0, 0)]]))
        let out = run(d, [Float](repeating: 1, count: 256)) ?? []
        // новая программа начинается сразу с её значения, без хода от покоя (B не хлопает на старте)
        XCTAssertEqual(out.count, 256)
        XCTAssertTrue(out.allSatisfy { abs($0) < 1e-6 })
    }

    func testEchoRepeatsImpulseAfterDelay() {
        let d = dsp(program([.echoSend: [key(0, 1)]]))
        var input = [Float](repeating: 0, count: 128)
        input[0] = 1
        let out = run(d, input) ?? []
        XCTAssertEqual(out[0], 1, accuracy: 1e-6)
        XCTAssertEqual(out[10], 1, accuracy: 1e-6)
        XCTAssertEqual(out[5], 0, accuracy: 1e-6)
    }

    func testLowPassCutsHighTone() {
        let d = dsp(program([.lpHz: [key(0, 50)]]))
        // 400 Гц при 1 кГц — далеко за срезом 50 Гц
        let input = (0 ..< 512).map { Float(sin(2 * Double.pi * 400 * Double($0) / 1000)) }
        let out = run(d, input) ?? []
        let tail = out[256...].map { abs($0) }.max() ?? 1
        XCTAssertLessThan(tail, 0.05)
    }

    func testCancelRampFadesOutAndHolds() {
        let d = dsp(program([.gain: [key(0, 1)]]))
        _ = run(d, [Float](repeating: 1, count: 64))
        d.ramp(.gain(0, seconds: 0.064))
        let out = run(d, [Float](repeating: 1, count: 128), startMs: 64) ?? []
        XCTAssertEqual(out.last ?? 1, 0, accuracy: 1e-6)
    }

    func testFilterFormulasAtDc() {
        let hp = Biquad.highPass(frequency: 200, q: 0.707, sampleRate: 44100)
        let lp = Biquad.lowPass(frequency: 200, q: 0.707, sampleRate: 44100)
        // усиление на нуле частот: (b0+b1+b2)/(1+a1+a2)
        XCTAssertEqual((hp.b0 + hp.b1 + hp.b2) / (1 + hp.a1 + hp.a2), 0, accuracy: 1e-9)
        XCTAssertEqual((lp.b0 + lp.b1 + lp.b2) / (1 + lp.a1 + lp.a2), 1, accuracy: 1e-9)
    }
}
