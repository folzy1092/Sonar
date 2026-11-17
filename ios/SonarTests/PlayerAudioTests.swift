import XCTest
@testable import Sonar

/// Звук без AVFoundation: эквалайзер, фильтры, нормализация громкости, громкость переходов
/// (`Playback/PlayerDSP.swift`; на ПК — `eq.svelte.ts`, `leveler.test.ts`).
final class PlayerAudioTests: XCTestCase {
    // MARK: - Эквалайзер

    func testEqualizerParseEncodeAndClamp() {
        XCTAssertEqual(Equalizer.parse(""), Equalizer.flat)
        XCTAssertEqual(Equalizer.parse("1,2,3"), Equalizer.flat, "не 12 чисел — ровно")
        XCTAssertEqual(Equalizer.parse("0,0,0,0,0,0,0,0,0,0,0,x"), Equalizer.flat)
        let gains: [Double] = [7, 6, 5, 3, 1, 0, 0, 0, 0, 0, -1.5, 30]
        let parsed = Equalizer.parse(Equalizer.encode(gains))
        XCTAssertEqual(parsed.count, 12)
        XCTAssertEqual(parsed[0], 7)
        XCTAssertEqual(parsed[10], -1.5)
        XCTAssertEqual(parsed[11], 12, "больше ±12 дБ не бывает")
        XCTAssertEqual(Equalizer.encode([1, 0.25, -3]), "1,0.3,-3")
        XCTAssertEqual(Equalizer.clamp(.nan), 0)
    }

    func testEqualizerLabelsAndPresets() {
        XCTAssertEqual(Equalizer.frequencies.count, 12)
        XCTAssertEqual(Equalizer.label(32), "32")
        XCTAssertEqual(Equalizer.label(1000), "1k")
        XCTAssertEqual(Equalizer.label(12000), "12k")
        XCTAssertTrue(Equalizer.presets.allSatisfy { $0.gains.count == 12 }, "у каждого пресета 12 полос")
        XCTAssertEqual(Set(Equalizer.presets.map(\.name)).count, Equalizer.presets.count)
        XCTAssertEqual(Equalizer.preset(matching: Equalizer.flat)?.name, "Нейтральный")
        XCTAssertEqual(Equalizer.preset(matching: [7, 6, 5, 3, 1, 0, 0, 0, 0, 0, 0, 0])?.name, "Басы")
        XCTAssertNil(Equalizer.preset(matching: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), "своя кривая")
        XCTAssertTrue(Equalizer.isFlat(Equalizer.flat))
        XCTAssertFalse(Equalizer.isFlat([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]))
    }

    func testFlatCurveHasNoFilters() {
        XCTAssertTrue(Equalizer.filters(Equalizer.flat, sampleRate: 44100).allSatisfy(\.isIdentity))
    }

    func testPeakingFilterHitsGainAtCenter() {
        let rate = 44100.0
        let peak = Biquad.peaking(frequency: 1000, gainDb: 6, q: Equalizer.q, sampleRate: rate)
        XCTAssertEqual(peak.responseDb(at: 1000, sampleRate: rate), 6, accuracy: 0.01)
        XCTAssertEqual(peak.responseDb(at: 30, sampleRate: rate), 0, accuracy: 0.2, "далеко от центра — почти ноль")
        let cut = Biquad.peaking(frequency: 4000, gainDb: -9, q: Equalizer.q, sampleRate: rate)
        XCTAssertEqual(cut.responseDb(at: 4000, sampleRate: rate), -9, accuracy: 0.01)
    }

    func testShelvesBoostTheirEnd() {
        let rate = 48000.0
        let low = Biquad.lowShelf(frequency: 32, gainDb: 8, sampleRate: rate)
        XCTAssertEqual(low.responseDb(at: 5, sampleRate: rate), 8, accuracy: 0.3, "ниже полки — полное усиление")
        XCTAssertEqual(low.responseDb(at: 32, sampleRate: rate), 4, accuracy: 0.3, "на частоте полки — половина")
        XCTAssertEqual(low.responseDb(at: 2000, sampleRate: rate), 0, accuracy: 0.1)
        let high = Biquad.highShelf(frequency: 12000, gainDb: -6, sampleRate: rate)
        XCTAssertEqual(high.responseDb(at: 22000, sampleRate: rate), -6, accuracy: 0.6)
        XCTAssertEqual(high.responseDb(at: 200, sampleRate: rate), 0, accuracy: 0.1)
    }

    func testBandAboveNyquistIsSkipped() {
        var gains = Equalizer.flat
        gains[11] = 6
        // 20 кГц при 32 кГц дискретизации — выше половины частоты: фильтр не ставится
        XCTAssertTrue(Equalizer.filters(gains, sampleRate: 32000)[11].isIdentity)
        XCTAssertFalse(Equalizer.filters(gains, sampleRate: 48000)[11].isIdentity)
    }

    func testBiquadStateFiltersSignal() {
        // постоянный сигнал через колокол на 1 кГц выходит почти без изменений (на нуле частоты усиление 0 дБ)
        let filter = FloatBiquad(.peaking(frequency: 1000, gainDb: 12, q: 1.1, sampleRate: 44100))
        var state = BiquadState()
        var last: Float = 0
        for _ in 0 ..< 2000 { last = state.process(0.5, filter) }
        XCTAssertEqual(last, 0.5, accuracy: 0.001)
        // тождественный фильтр ничего не меняет
        var identity = BiquadState()
        XCTAssertEqual(identity.process(0.3, FloatBiquad(.identity)), 0.3)
    }

    // MARK: - Нормализация

    func testLevelerGainLimits() {
        XCTAssertEqual(Leveler.gainDb(for: Leveler.targetDb), 0)
        XCTAssertEqual(Leveler.gainDb(for: Leveler.targetDb - 4), 4, "тихое поднимает")
        XCTAssertEqual(Leveler.gainDb(for: -60), Leveler.maxGainDb)
        XCTAssertEqual(Leveler.gainDb(for: 0), Leveler.minGainDb, "громкое опускает, но не больше чем на 9 дБ")
    }

    func testRmsOfSineAndSilence() {
        let sine = (0 ..< 4800).map { Float(sin(2 * Double.pi * 440 * Double($0) / 48000)) }
        XCTAssertEqual(Leveler.rmsDb(sine), -3.01, accuracy: 0.05)
        XCTAssertEqual(Leveler.rmsDb([Float](repeating: 0, count: 16)), -.infinity)
        XCTAssertEqual(Leveler.rmsDb([]), -.infinity)
    }

    func testSmoothingApproachesWithoutOvershoot() {
        let a = Leveler.smooth(-30, toward: -10, dt: 0.2, tau: 6)
        XCTAssertGreaterThan(a, -30)
        XCTAssertLessThan(a, -29)
        var value = -30.0
        for _ in 0 ..< 300 { value = Leveler.smooth(value, toward: -10, dt: 0.2, tau: 6) }
        XCTAssertEqual(value, -10, accuracy: 0.1)
    }

    func testLevelerStateRaisesQuietTrackAndIgnoresSilence() {
        var state = Leveler.State()
        // тихий трек −30 дБ: усиление тянется к +6 дБ (≈ ×2)
        for _ in 0 ..< 200 { _ = state.step(blockDb: -30, dt: 0.05, enabled: true) }
        XCTAssertEqual(state.gain, pow(10, 6.0 / 20), accuracy: 0.02)
        // тишина в оценку не идёт — уровень не падает
        let level = state.level
        for _ in 0 ..< 50 { _ = state.step(blockDb: -80, dt: 0.05, enabled: true) }
        XCTAssertEqual(state.level, level)
        // выключили — плавно назад к 1
        for _ in 0 ..< 400 { _ = state.step(blockDb: -30, dt: 0.05, enabled: false) }
        XCTAssertEqual(state.gain, 1, accuracy: 0.01)
    }

    func testLevelerStateLowersLoudTrack() {
        var state = Leveler.State()
        for _ in 0 ..< 400 { _ = state.step(blockDb: -6, dt: 0.05, enabled: true) }
        XCTAssertEqual(state.gain, pow(10, -9.0 / 20), accuracy: 0.02, "громкий −6 дБ опускается на 9 дБ (предел)")
    }

    // MARK: - Переходы

    func testCrossfadeFactor() {
        // выключен — всегда 1
        XCTAssertEqual(Fades.crossfadeFactor(position: 199, duration: 200, seconds: 0, fadeIn: true, fadeOut: true), 1)
        // середина трека — 1
        XCTAssertEqual(Fades.crossfadeFactor(position: 100, duration: 200, seconds: 6, fadeIn: true, fadeOut: true), 1)
        // конец: за 3 из 6 секунд — (0.5)² ; без следующего — не затихает
        XCTAssertEqual(Fades.crossfadeFactor(position: 197, duration: 200, seconds: 6, fadeIn: false, fadeOut: true), 0.25, accuracy: 1e-9)
        XCTAssertEqual(Fades.crossfadeFactor(position: 197, duration: 200, seconds: 6, fadeIn: false, fadeOut: false), 1)
        // начало после перехода нарастает; ручной переход — сразу громко
        XCTAssertEqual(Fades.crossfadeFactor(position: 0, duration: 200, seconds: 6, fadeIn: true, fadeOut: true), 0)
        XCTAssertEqual(Fades.crossfadeFactor(position: 0, duration: 200, seconds: 6, fadeIn: false, fadeOut: true), 1)
        // короткий трек: переход не длиннее трети
        XCTAssertEqual(Fades.crossfadeFactor(position: 2, duration: 12, seconds: 12, fadeIn: true, fadeOut: false), 0.25, accuracy: 1e-9)
    }

    func testRampAfterCall() {
        XCTAssertEqual(Fades.rampFactor(elapsed: 0), 0.2, accuracy: 1e-9)
        XCTAssertEqual(Fades.rampFactor(elapsed: 2), 1)
        XCTAssertEqual(Fades.rampFactor(elapsed: 10), 1)
        XCTAssertLessThan(Fades.rampFactor(elapsed: 0.5), Fades.rampFactor(elapsed: 1.5))
    }
}
