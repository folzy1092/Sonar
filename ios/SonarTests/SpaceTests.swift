import XCTest
@testable import Sonar

/// Пространство 1D–16D (`Playback/Space.swift`): таблица — зеркало ПК `player/space.ts`, процессор при выключенном
/// пространстве пропускает сигнал как есть, на 8D звук гуляет между ушами без скачка громкости.
final class SpaceTests: XCTestCase {
    func testTableMatchesPCAndInterpolates() {
        XCTAssertEqual(SpaceParams.presets, [1, 2, 3, 8, 12, 16])
        XCTAssertEqual(SpaceParams.of(0), .off)
        XCTAssertEqual(SpaceParams.of(8).rate, 0.14)
        XCTAssertEqual(SpaceParams.of(16).send, 0.4)
        XCTAssertEqual(SpaceParams.of(5).rate, 0.104, accuracy: 1e-9, "между 3D и 8D — линейно")
        XCTAssertEqual(SpaceParams.of(40), SpaceParams.of(16))
        var previous = SpaceParams.of(1)
        for d in 2 ... 16 {
            let p = SpaceParams.of(d)
            XCTAssertGreaterThanOrEqual(p.rate, previous.rate)
            XCTAssertGreaterThanOrEqual(p.send, previous.send)
            XCTAssertLessThanOrEqual(p.rate, 0.3)
            previous = p
        }
    }

    func testClampLabelAndReverb() {
        XCTAssertEqual(SpaceParams.clamp(7.6), 8)
        XCTAssertEqual(SpaceParams.clamp(-2), 0)
        XCTAssertEqual(SpaceParams.clamp(.nan), 0)
        XCTAssertEqual(SpaceParams.label(0), "")
        XCTAssertEqual(SpaceParams.label(12), "12D")
        XCTAssertEqual(SpaceParams.reverb(0, space: 8), 0.22)
        XCTAssertEqual(SpaceParams.reverb(0.5, space: 16), 0.7)
        XCTAssertEqual(SpaceParams.reverb(0.3, space: 0), 0.3)
    }

    private func tone(_ count: Int, _ frequency: Double, rate: Double = 48000, phase: Double = 0) -> [Float] {
        (0 ..< count).map { Float(0.5 * sin(2 * Double.pi * frequency * Double($0) / rate + phase)) }
    }

    private func rms(_ a: ArraySlice<Float>) -> Double {
        (a.reduce(0) { $0 + Double($1) * Double($1) } / Double(a.count)).squareRoot()
    }

    private func run(_ space: Spatializer, _ left: [Float], _ right: [Float]) -> ([Float], [Float]) {
        var l = left, r = right
        for i in l.indices { space.process(&l[i], &r[i]) }
        return (l, r)
    }

    func testOffPassesSignalUnchanged() {
        let space = Spatializer(sampleRate: 48000)
        XCTAssertTrue(space.idle)
        // выключили после работы — через полсекунды снова сухой сигнал
        space.set(on: true, params: .of(12))
        _ = run(space, tone(48000, 300), tone(48000, 300))
        space.set(on: false, params: .off)
        let dry = tone(48000, 300)
        let (l, _) = run(space, dry, dry)
        XCTAssertEqual(Array(l[40000...]), Array(dry[40000...]))
        XCTAssertTrue(space.idle)
    }

    func test8DMovesBetweenEarsWithoutLevelJump() {
        let space = Spatializer(sampleRate: 48000)
        space.set(on: true, params: .of(8))
        let n = 48000 * 8
        let input = tone(n, 300)
        let (l, r) = run(space, input, input)
        XCTAssertTrue(l.allSatisfy { $0.isFinite && abs($0) < 1 })
        let window = 24000
        var leftLouder = false, rightLouder = false
        var i = window
        while i + window <= n {
            let a = rms(l[i ..< i + window]), b = rms(r[i ..< i + window])
            if a > b * 1.4 { leftLouder = true }
            if b > a * 1.4 { rightLouder = true }
            i += window
        }
        XCTAssertTrue(leftLouder && rightLouder, "звук кружит")
        let before = rms(input[...]) * 2.0.squareRoot()
        let after = (pow(rms(l[window...]), 2) + pow(rms(r[window...]), 2)).squareRoot()
        XCTAssertLessThan(abs(20 * log10(after / before)), 3)
    }

    func testSwitchingOnIsSmooth() {
        let space = Spatializer(sampleRate: 48000)
        space.set(on: true, params: .of(16))
        let left = tone(4800, 200), right = tone(4800, 200, phase: 1)
        let (l, _) = run(space, left, right)
        for i in 0 ..< 64 { XCTAssertLessThan(abs(l[i] - left[i]), 0.02) }
    }

    func testTrackSoundKeepsSpaceAndReadsOldRecords() throws {
        let sound = TrackSound(rate: 1, reverb: 0.2, space: 12)
        XCTAssertEqual(TrackSound.fromSync(.object(["sound": sound.json])), sound)
        XCTAssertEqual(sound.ownParts, ["12D", "Reverb"])
        // старая запись без поля — без пространства
        let old = try JSONDecoder().decode(TrackSound.self, from: Data(#"{"rate":0.8,"pitch":0,"linked":true,"reverb":0}"#.utf8))
        XCTAssertEqual(old.space, 0)
        XCTAssertEqual(TrackSound(rate: 1, space: 40).normalized()?.space, 16)
    }
}
