import XCTest
@testable import Sonar

/// Звук трека «Для этого трека» (`TrackSound`): пределы, синк (новый и старый формат) и эффекты `SoundFX`.
final class TrackSoundTests: XCTestCase {
    func testNormalizedClampsAndRounds() throws {
        let wild = try XCTUnwrap(TrackSound(rate: 3, pitch: -20, linked: false, reverb: 1.7, eq: Array(repeating: 40, count: 12)).normalized())
        XCTAssertEqual(wild.rate, 2)
        XCTAssertEqual(wild.pitch, -12)
        XCTAssertEqual(wild.reverb, 1)
        XCTAssertEqual(wild.eq?.first, 12)
        let odd = try XCTUnwrap(TrackSound(rate: 0.8333, pitch: 1.26, reverb: 0.333, eq: [1, 2]).normalized())
        XCTAssertEqual(odd.rate, 0.83)
        XCTAssertEqual(odd.pitch, 1.3)
        XCTAssertEqual(odd.reverb, 0.33)
        XCTAssertNil(odd.eq, "кривая не из 12 полос — общая")
        XCTAssertNil(TrackSound(rate: .nan).normalized())
    }

    func testSyncRoundTripAndOldSpeed() {
        let slowed = TrackSound(rate: 0.8, pitch: 0, linked: true, reverb: 0.4, eq: Array(repeating: 3, count: 12))
        XCTAssertEqual(TrackSound.fromSync(.object(["speed": .double(0.8), "sound": slowed.json])), slowed)
        // старый клиент: только «Запомнить скорость» — та же скорость, тон сохраняется
        XCTAssertEqual(TrackSound.fromSync(.object(["speed": .double(1.25), "lyrics_offset_ms": .int(300)])), TrackSound(rate: 1.25))
        XCTAssertNil(TrackSound.fromSync(.object(["lyrics_offset_ms": .int(300)])))
        XCTAssertNil(TrackSound.fromSync(.null))
    }

    /// Плашка «Свой звук»: только то, что отличается от обычного звука (зеркало ПК `ownSoundParts`).
    func testOwnPartsListOnlyDifferences() {
        XCTAssertEqual(TrackSound(rate: 0.85, reverb: 0.4).ownParts, ["x0.85", "Reverb"])
        XCTAssertEqual(TrackSound(rate: 1, pitch: -2).ownParts, ["−2 st"])
        XCTAssertEqual(TrackSound(rate: 1.5, pitch: 1.5).ownParts, ["x1.5", "+1.5 st"])
        XCTAssertEqual(TrackSound(rate: 0.8, pitch: 3, linked: true).ownParts, ["x0.8"], "связанный тон видно в скорости")
        XCTAssertEqual(TrackSound(rate: 1, eq: Array(repeating: 0, count: 12)).ownParts, [], "плоская кривая — не EQ")
        var curve = Array(repeating: 0.0, count: 12)
        curve[2] = 2
        XCTAssertEqual(TrackSound(rate: 1, eq: curve).ownParts, ["EQ"])
    }

    func testLinkedSemitones() {
        XCTAssertEqual(TrackSound.linkedSemitones(2), 12)
        XCTAssertEqual(TrackSound.linkedSemitones(1), 0)
        XCTAssertEqual(TrackSound.linkedSemitones(0.8), -3.9, accuracy: 0.05)
        XCTAssertEqual(TrackSound(rate: 0.8, pitch: 5, linked: true).semitones, -3.9, accuracy: 0.05, "связан — тон от скорости")
        XCTAssertEqual(TrackSound(rate: 0.8, pitch: 5, linked: false).semitones, 5)
        XCTAssertEqual(TrackSound.pitchRatio(12), 2, accuracy: 1e-9)
    }

    // MARK: - Эффекты

    private func sine(_ frequency: Double, count: Int, rate: Double = 44100) -> [Float] {
        (0 ..< count).map { Float(sin(2 * Double.pi * frequency * Double($0) / rate)) }
    }

    /// Частота по числу переходов через ноль.
    private func frequency(_ samples: ArraySlice<Float>, rate: Double = 44100) -> Double {
        var crossings = 0
        var previous = samples.first ?? 0
        for x in samples.dropFirst() {
            if (previous < 0) != (x < 0) { crossings += 1 }
            previous = x
        }
        return Double(crossings) / 2 / (Double(samples.count) / rate)
    }

    func testPitchShifterWithoutShiftIsPlainDelay() {
        let shifter = PitchShifter()
        let input = sine(441, count: 8000)
        let output = input.map { shifter.process($0, ratio: 1) }
        let delay = Int(PitchShifter.window / 2)
        for n in stride(from: 4000, to: 8000, by: 97) {
            XCTAssertEqual(output[n], input[n - delay], accuracy: 1e-5)
        }
    }

    func testPitchShifterOctaveUpDoublesFrequencyAndKeepsLength() {
        let shifter = PitchShifter()
        let input = sine(441, count: 44100 * 2)
        let output = input.map { shifter.process($0, ratio: 2) }
        XCTAssertEqual(output.count, input.count, "темп не меняется — столько же сэмплов")
        let measured = frequency(output[44100...])
        XCTAssertEqual(measured, 882, accuracy: 882 * 0.05)
        let down = PitchShifter()
        let lower = input.map { down.process($0, ratio: TrackSound.pitchRatio(-12)) }
        XCTAssertEqual(frequency(lower[44100...]), 220.5, accuracy: 220.5 * 0.05)
    }

    func testReverbTailDecaysAndStaysFinite() {
        let reverb = Reverb(sampleRate: 44100, channel: 0)
        var out: [Float] = []
        for n in 0 ..< 44100 * 8 { out.append(reverb.process(n == 0 ? 1 : 0)) }
        XCTAssertTrue(out.allSatisfy(\.isFinite))
        let early = out[4410 ..< 13230].map(abs).max() ?? 0
        let late = out[(44100 * 7)...].map(abs).max() ?? 0
        XCTAssertGreaterThan(early, 1e-4, "хвост слышен через 0.1–0.3 с")
        XCTAssertLessThan(late, early / 100, "и затухает")
        // правый канал — другие длины линий
        let right = Reverb(sampleRate: 44100, channel: 1)
        let r = (0 ..< 4410).map { right.process($0 == 0 ? 1 : 0) }
        XCTAssertNotEqual(Array(out[0 ..< 4410]), r)
    }

    func testReverbMixKeepsDryWhenOff() {
        XCTAssertEqual(Reverb.mix(dry: 0.5, wet: 0.9, amount: 0), 0.5)
        XCTAssertEqual(Reverb.mix(dry: 1, wet: 0, amount: 1), 0.6, accuracy: 1e-6)
    }

    func testSpeedSheetPitchLabel() {
        XCTAssertEqual(SpeedSheet.pitchLabel(0), "0 st")
        XCTAssertEqual(SpeedSheet.pitchLabel(-1.5), "−1.5 st")
        XCTAssertEqual(SpeedSheet.pitchLabel(2), "+2.0 st")
    }

    func testSoundStringsAreTranslated() {
        for key in ["Тон", "Тон ниже", "Тон выше", "Связать тон со скоростью", "Slowed / sped up: скорость меняет высоту звука",
                    "Реверберация", "Атмосферное пространство и объёмная глубина", "Для этого трека",
                    "Скорость, тон, реверб, пространство и эквалайзер — только у этого трека и на всех твоих устройствах",
                    "Пространство ✦", "Звук плавно кружит вокруг головы. Чем больше D — тем шире, глубже и живее движение. Лучше в наушниках",
                    "У этого трека свой звук — кривая сохранится только для него",
                    "Этот трек идёт потоком HLS — свой тон, реверб и пространство на нём не слышны. Slowed со связанным тоном работает"] {
            // «Тон» по-украински тоже «Тон» — совпадение с русским здесь не пропуск перевода
            for lang in Lang.allCases where lang != .ru && !(key == "Тон" && lang == .uk) {
                XCTAssertNotEqual(I18n.translate(key, lang: lang), key, "\(key) — \(lang)")
            }
        }
    }
}
