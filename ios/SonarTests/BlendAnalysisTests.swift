import Foundation
import XCTest
@testable import Sonar

// Анализ сведения на синтетике (docs/BLEND.md §14) — порт `windows/src/player/blend/analysis.test.ts`:
// щелчки, аккорды синусами, шум. Файлов нет — сигнал собирается здесь же, шум с фиксированным зерном
// (тот же mulberry32, что на ПК), поэтому тесты не плавают. Менять — в обоих местах.

/// mulberry32 — тот же генератор, что `rng` в тестах ПК.
private struct Mulberry32 {
    private var a: UInt32

    init(seed: UInt32) { a = seed }

    mutating func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

private enum Synth {
    static let sr = Double(BlendAnalyzer.sampleRate)

    static func addNoise(_ x: inout [Float], amp: Double, seed: UInt32 = 1) {
        var r = Mulberry32(seed: seed)
        for i in x.indices { x[i] = Float(Double(x[i]) + amp * (r.next() * 2 - 1)) }
    }

    /// Удар: «бочка» 55 Гц с затуханием + короткий щелчок шума сверху.
    static func hit(_ x: inout [Float], atMs: Double, low: Double, click: Double, r: inout Mulberry32) {
        let start = BlendMath.jsRoundInt((atMs / 1000) * sr)
        let len = BlendMath.jsRoundInt(0.15 * sr)
        var i = 0
        while i < len && start + i < x.count {
            defer { i += 1 }
            if start + i < 0 { continue }
            let t = Double(i) / sr
            var v = Double(x[start + i]) + low * sin(2 * Double.pi * 55 * t) * exp(-t / 0.05)
            x[start + i] = Float(v)
            if t < 0.03 {
                v = Double(x[start + i]) + click * (r.next() * 2 - 1) * exp(-t / 0.008)
                x[start + i] = Float(v)
            }
        }
    }

    typealias Gain = (_ k: Int, _ ms: Double) -> (low: Double, click: Double)

    static func clicks(
        seconds: Double,
        bpm: (Double) -> Double,
        offsetMs: Double = 100,
        gain: Gain? = nil,
        mute: ((Double) -> Bool)? = nil,
        noise: Double = 0.01
    ) -> [Float] {
        var x = [Float](repeating: 0, count: BlendMath.jsRoundInt(seconds * sr))
        var r = Mulberry32(seed: 7)
        var ms = offsetMs
        var k = 0
        while ms < seconds * 1000 {
            let g = gain?(k, ms) ?? (low: 0.6, click: 0.4)
            if !(mute?(ms) ?? false) { hit(&x, atMs: ms, low: g.low, click: g.click, r: &r) }
            ms += 60000 / bpm(ms / 1000)
            k += 1
        }
        addNoise(&x, amp: noise)
        return x
    }

    static func clicks(seconds: Double, bpm: Double, offsetMs: Double = 100, gain: Gain? = nil,
                       mute: ((Double) -> Bool)? = nil, noise: Double = 0.01) -> [Float] {
        clicks(seconds: seconds, bpm: { _ in bpm }, offsetMs: offsetMs, gain: gain, mute: mute, noise: noise)
    }

    static func tones(_ chords: [[Int]], secondsEach: Double, repeat count: Int) -> [Float] {
        let n = BlendMath.jsRoundInt(secondsEach * sr)
        var x = [Float](repeating: 0, count: n * chords.count * count)
        for r in 0..<count {
            for (c, midi) in chords.enumerated() {
                let base = (r * chords.count + c) * n
                for m in midi {
                    let hz = 440 * pow(2, Double(m - 69) / 12)
                    for i in 0..<n {
                        let env = min(1, Double(i) / 200, Double(n - i) / 200)
                        let v = 0.15 * sin((2 * Double.pi * hz * Double(i)) / sr) * env
                        x[base + i] = Float(Double(x[base + i]) + v)
                    }
                }
            }
        }
        return x
    }

    static func sine(seconds: Double, hz: Double, dbfs: Double) -> [Float] {
        let amp = pow(10, dbfs / 20)
        return (0..<BlendMath.jsRoundInt(seconds * sr)).map { Float(amp * sin((2 * Double.pi * hz * Double($0)) / sr)) }
    }
}

final class BlendAnalysisTests: XCTestCase {
    // MARK: Темп

    func testClicksTempoWithNoiseIsExactAndNotDoubled() {
        for bpm in [128.0, 90, 174] {
            let a = BlendAnalyzer.analyze(Synth.clicks(seconds: 40, bpm: bpm), ref: "sc:t")
            XCTAssertLessThanOrEqual(abs(a.bpm - bpm), 0.5, "темп \(bpm) → \(a.bpm)")
            XCTAssertGreaterThan(a.bpmConf, 0)
        }
    }

    func testPauseInTheMiddleKeepsTempo() {
        let x = Synth.clicks(seconds: 40, bpm: 128, mute: { $0 > 15000 && $0 < 25000 })
        XCTAssertLessThanOrEqual(abs(BlendAnalyzer.analyze(x, ref: "sc:t").bpm - 128), 0.5)
    }

    // MARK: Сетка

    func testGridOffsetFindsFirstBeat() {
        let a = BlendAnalyzer.analyze(Synth.clicks(seconds: 30, bpm: 128, offsetMs: 137), ref: "sc:t")
        XCTAssertLessThanOrEqual(abs(a.firstBeatMs - 137), 10)
        XCTAssertTrue(a.gridStable)
    }

    func testSteadyTempoIsStableAndRampIsNot() {
        XCTAssertTrue(BlendAnalyzer.analyze(Synth.clicks(seconds: 60, bpm: 120), ref: "sc:t").gridStable)
        let ramp = Synth.clicks(seconds: 60, bpm: { 120 + (6 * $0) / 60 })
        XCTAssertFalse(BlendAnalyzer.analyze(ramp, ref: "sc:t").gridStable)
    }

    // MARK: Такт

    func testLowAccentEveryFourthBeatGivesDownbeat() {
        for d in 0..<4 {
            let gain: Synth.Gain = { k, _ in k % 4 == d ? (0.9, 0.4) : (0.25, 0.4) }
            let a = BlendAnalyzer.analyze(Synth.clicks(seconds: 40, bpm: 124, gain: gain), ref: "sc:t")
            XCTAssertEqual(a.downbeat, d, "акцент с \(d)-й доли")
        }
    }

    // MARK: Фразы

    func testQuietLoudQuietPhrases() {
        let barMs = (4 * 60000) / 120.0
        let gain: Synth.Gain = { k, ms in
            let loud = ms >= 8 * barMs && ms < 16 * barMs
            let accent = k % 4 == 0 ? 1.5 : 1
            return loud ? (0.8 * accent, 0.6) : (0.12 * accent, 0.08)
        }
        let x = Synth.clicks(seconds: 24 * (barMs / 1000) + 0.5, bpm: 120, offsetMs: 0, gain: gain, noise: 0.002)
        let a = BlendAnalyzer.analyze(x, ref: "sc:t")
        XCTAssertEqual(a.downbeat, 0)
        XCTAssertEqual(a.phrases, [
            BlendPhrase(bar: 0, kind: .intro),
            BlendPhrase(bar: 8, kind: .drop),
            BlendPhrase(bar: 16, kind: .outro),
        ])
        XCTAssertEqual(a.bars.energy.count, 24)
        XCTAssertEqual(a.bars.energy.max(), 1)
    }

    // MARK: Тональность

    func testCMajorChords() {
        let x = Synth.tones([[60, 64, 67], [65, 69, 72], [67, 71, 74], [60, 64, 67]], secondsEach: 2, repeat: 3)
        XCTAssertEqual(BlendAnalyzer.analyze(x, ref: "sc:t").key, 0)
    }

    func testAMinorChords() {
        let x = Synth.tones([[69, 72, 76], [62, 65, 69], [64, 68, 71], [69, 72, 76]], secondsEach: 2, repeat: 3)
        XCTAssertEqual(BlendAnalyzer.analyze(x, ref: "sc:t").key, 21)
    }

    func testNoiseHasNoKey() {
        var x = [Float](repeating: 0, count: 20 * BlendAnalyzer.sampleRate)
        Synth.addNoise(&x, amp: 0.3, seed: 3)
        let a = BlendAnalyzer.analyze(x, ref: "sc:t")
        XCTAssertLessThan(a.keyConf, 0.15)
        XCTAssertNil(a.key)
    }

    // MARK: Громкость

    func testLoudnessDifferenceOfTenDb() {
        let diff = BlendLoudness.loudness(of: Synth.sine(seconds: 10, hz: 1000, dbfs: -10))
            - BlendLoudness.loudness(of: Synth.sine(seconds: 10, hz: 1000, dbfs: -20))
        XCTAssertLessThanOrEqual(abs(diff - 10), 0.5)
    }

    // MARK: Края и результат

    func testSilenceAtEdgesIsCut() {
        let sr = BlendAnalyzer.sampleRate
        var x = [Float](repeating: 0, count: 30 * sr)
        let clicks = Synth.clicks(seconds: 20, bpm: 128, noise: 0)
        x.replaceSubrange((5 * sr)..<(5 * sr + clicks.count), with: clicks)
        let a = BlendAnalyzer.analyze(x, ref: "sc:t")
        XCTAssertGreaterThan(a.startMs, 4900)
        XCTAssertLessThan(a.startMs, 5200)
        XCTAssertGreaterThan(a.endMs, 24800)
        XCTAssertLessThan(a.endMs, 25500)
        XCTAssertGreaterThan(a.firstBeatMs, 5000)
    }

    func testFullSilenceDoesNotCrash() {
        let a = BlendAnalyzer.analyze([Float](repeating: 0, count: 5 * BlendAnalyzer.sampleRate), ref: "sc:t")
        XCTAssertNil(a.key)
        XCTAssertEqual(a.loudness, -70)
        XCTAssertLessThanOrEqual(a.phrases.count, 1)
    }

    func testResultShapeAndJsonRoundTrip() throws {
        let a = BlendAnalyzer.analyze(Synth.clicks(seconds: 20, bpm: 128), ref: "ym:42")
        XCTAssertEqual(a.version, blendAnalysisVersion)
        XCTAssertEqual(a.ref, "ym:42")
        XCTAssertEqual(a.durationMs, 20000)
        XCTAssertEqual(a.beatMs, 60000 / a.bpm, accuracy: 0.05)
        for v in a.bars.energy + a.bars.low + a.bars.mid + a.bars.onsets { XCTAssertGreaterThanOrEqual(v, 0) }

        let data = try JSONEncoder().encode(a)
        XCTAssertEqual(try JSONDecoder().decode(BlendAnalysis.self, from: data), a)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for name in ["version", "ref", "durationMs", "startMs", "endMs", "bpm", "bpmConf", "beatMs",
                     "firstBeatMs", "downbeat", "gridStable", "keyConf", "loudness", "bars", "phrases"] {
            XCTAssertNotNil(object[name], "нет ключа \(name)")
        }
        let bars = try XCTUnwrap(object["bars"] as? [String: Any])
        XCTAssertEqual(Set(bars.keys), ["energy", "low", "mid", "onsets"])
    }

    func testDecodesPcJson() throws {
        let json = """
        {"version":1,"ref":"sc:1","durationMs":20000,"startMs":0,"endMs":20000,"bpm":128,"bpmConf":0.5,
         "beatMs":468.75,"firstBeatMs":100.5,"downbeat":2,"gridStable":true,"key":null,"keyConf":0.1,
         "loudness":-9.5,"bars":{"energy":[1],"low":[0.5],"mid":[0],"onsets":[0.25]},
         "phrases":[{"bar":0,"kind":"intro"},{"bar":8,"kind":"drop"}]}
        """
        let a = try JSONDecoder().decode(BlendAnalysis.self, from: Data(json.utf8))
        XCTAssertNil(a.key)
        XCTAssertEqual(a.downbeat, 2)
        XCTAssertEqual(a.phrases, [BlendPhrase(bar: 0, kind: .intro), BlendPhrase(bar: 8, kind: .drop)])
        XCTAssertEqual(a.bars.onsets, [0.25])
    }

    func testStereoIsAveragedToMono() {
        XCTAssertEqual(BlendAnalyzer.toMono([[1, 0], [0, 1]]), [0.5, 0.5])
        XCTAssertEqual(BlendAnalyzer.toMono([[0.25, 1]]), [0.25, 1])
        XCTAssertEqual(BlendAnalyzer.toMono([]), [])
    }

    func testJsRoundMatchesMathRound() {
        XCTAssertEqual(BlendMath.jsRound(2.5), 3)
        XCTAssertEqual(BlendMath.jsRound(-2.5), -2)
        XCTAssertEqual(BlendMath.jsRound(-2.6), -3)
        XCTAssertEqual(BlendMath.jsRound(0.49999999999999994), 0)
    }
}
