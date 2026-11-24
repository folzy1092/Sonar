import XCTest
@testable import Sonar

// Настройки сведения — порт `settings.test.ts`, менять — в обоих местах.

final class BlendSettingsTests: XCTestCase {
    private func keys(
        type: Any? = "auto", length: Any? = 10, cut: Any? = 16, tempo: Any? = 8, key: Any? = true
    ) -> BlendKeys {
        BlendKeys(type: type, length: length, cut: cut, tempo: tempo, key: key)
    }

    func testDefaultsMatchSpec() {
        let s = BlendPrefs.blendSettings(keys())
        XCTAssertEqual(s, BlendSettings(type: .auto, lengthSec: 10, cutSec: 16, tempoTolPct: 8, keyShift: true))
        XCTAssertEqual(s, BlendSettings.defaults)
    }

    func testBrokenAndOldValuesDoNotBreakPlanner() {
        let s = BlendPrefs.blendSettings(keys(type: "wobble", length: 12, cut: 99, tempo: -3, key: "да"))
        XCTAssertEqual(s, BlendSettings(type: .auto, lengthSec: 10, cutSec: 45, tempoTolPct: 0, keyShift: true))
    }

    func testLengthIsNearestOfThree() {
        XCTAssertEqual(BlendPrefs.blendSettings(keys(length: 7)).lengthSec, 6)
        XCTAssertEqual(BlendPrefs.blendSettings(keys(length: 20)).lengthSec, 16)
        XCTAssertEqual(BlendPrefs.blendSettings(keys(length: Double.nan)).lengthSec, 10)
    }

    func testKeyShiftOffOnlyByExplicitFalse() {
        XCTAssertFalse(BlendPrefs.blendSettings(keys(key: false)).keyShift)
        XCTAssertTrue(BlendPrefs.blendSettings(keys(key: nil)).keyShift)
    }

    func testBoolIsNotANumber() {
        // на ПК `typeof true !== 'number'` — логическое значение не превращается в 1
        XCTAssertEqual(BlendPrefs.blendSettings(keys(cut: true)).cutSec, 16)
        XCTAssertEqual(BlendPrefs.blendSettings(keys(tempo: "12")).tempoTolPct, 8)
    }

    func testModeReadFromBlendAndCrossfade() {
        XCTAssertEqual(BlendPrefs.transitionMode(blend: false, crossfadeSec: 0), .normal)
        XCTAssertEqual(BlendPrefs.transitionMode(blend: false, crossfadeSec: 6), .crossfade)
        XCTAssertEqual(BlendPrefs.transitionMode(blend: true, crossfadeSec: 0), .blend)
        XCTAssertEqual(BlendPrefs.transitionMode(blend: true, crossfadeSec: 4), .blend)
    }

    func testBlendKeepsSafetyCrossfade() {
        let a = BlendPrefs.applyMode(.blend, crossfadeSec: 4)
        XCTAssertTrue(a.blend)
        XCTAssertEqual(a.crossfade, 4)
        let b = BlendPrefs.applyMode(.blend, crossfadeSec: 0)
        XCTAssertTrue(b.blend)
        XCTAssertEqual(b.crossfade, 0)
    }

    func testCrossfadeWithoutLengthTakesSixSeconds() {
        let a = BlendPrefs.applyMode(.crossfade, crossfadeSec: 0)
        XCTAssertFalse(a.blend)
        XCTAssertEqual(a.crossfade, 6)
        let b = BlendPrefs.applyMode(.crossfade, crossfadeSec: 9)
        XCTAssertFalse(b.blend)
        XCTAssertEqual(b.crossfade, 9)
    }

    func testNormalTurnsBothOff() {
        let r = BlendPrefs.applyMode(.normal, crossfadeSec: 9)
        XCTAssertFalse(r.blend)
        XCTAssertEqual(r.crossfade, 0)
    }

    func testModeRoundTrips() {
        for mode in TransitionMode.allCases {
            let r = BlendPrefs.applyMode(mode, crossfadeSec: 0)
            XCTAssertEqual(BlendPrefs.transitionMode(blend: r.blend, crossfadeSec: r.crossfade), mode)
        }
    }
}
