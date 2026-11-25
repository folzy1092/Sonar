import XCTest
@testable import Sonar

/// «Удержи, чтобы послушать» без SwiftUI: ядро `HoldGate` (порт `windows/src/lib/hold-preview.test.ts`)
/// и выбор кривой на экране эквалайзера (`Core/Settings/HoldPreview.swift`).
final class HoldPreviewTests: XCTestCase {
    func testDelayMatchesDesktop() {
        XCTAssertEqual(HoldGate.delay, 0.35, accuracy: 0.0001, "на ПК HOLD_DELAY = 350 мс")
    }

    func testShortTapDoesNotPreviewAndIsNotEaten() {
        var gate = HoldGate()
        XCTAssertNil(gate.pressChanged(true))
        XCTAssertNil(gate.pressChanged(false), "порог не дошёл — звук не трогали")
        XCTAssertFalse(gate.peeking)
        XCTAssertFalse(gate.consumeTap(), "короткое касание применяет пресет")
    }

    func testHoldPreviewsThenReleaseRestoresOnceAndEatsTheTap() {
        var gate = HoldGate()
        XCTAssertNil(gate.pressChanged(true))
        XCTAssertEqual(gate.fired(), .begin)
        XCTAssertTrue(gate.peeking)
        XCTAssertEqual(gate.pressChanged(false), .end)
        XCTAssertFalse(gate.peeking)
        XCTAssertNil(gate.pressChanged(false), "отпускание и отмена приходят подряд — вернуть звук один раз")
        XCTAssertTrue(gate.consumeTap(), "касание, которым закончилось удержание, пресет не применяет")
        XCTAssertFalse(gate.consumeTap(), "съедается ровно один раз")
    }

    func testHoldWithoutTapEventStillDoesNotEatTheNextTap() {
        var gate = HoldGate()
        _ = gate.pressChanged(true)
        _ = gate.fired()
        _ = gate.pressChanged(false)
        // система касание после удержания не прислала; следующее — настоящее короткое
        XCTAssertNil(gate.pressChanged(true))
        XCTAssertFalse(gate.consumeTap())
    }

    func testFiringTwiceDoesNotBeginTwice() {
        var gate = HoldGate()
        _ = gate.pressChanged(true)
        XCTAssertEqual(gate.fired(), .begin)
        XCTAssertNil(gate.fired())
    }

    func testCancelDuringHoldRestoresAndDropsTheEatenTap() {
        var gate = HoldGate()
        _ = gate.pressChanged(true)
        _ = gate.fired()
        XCTAssertEqual(gate.cancel(), .end, "закрыли лист посреди удержания — чужая кривая не остаётся")
        XCTAssertFalse(gate.peeking)
        XCTAssertFalse(gate.consumeTap())
        XCTAssertNil(gate.cancel(), "второй раз — ничего")
    }

    func testCancelWithoutHoldDoesNothing() {
        var gate = HoldGate()
        _ = gate.pressChanged(true)
        XCTAssertNil(gate.cancel())
    }

    func testShownCurveIsPresetWhileHeldAndWorkingOtherwise() {
        let working: [Double] = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -2]
        let bass = Equalizer.presets.first { $0.name == "Басы" }!.gains
        XCTAssertEqual(EqualizerPeek.shown(peek: bass, working: working), bass)
        XCTAssertEqual(EqualizerPeek.shown(peek: nil, working: working), working, "несохранённая кривая возвращается как была")
        XCTAssertEqual(EqualizerPeek.shown(peek: [1, 2], working: working), working, "кривая не из 12 полос не показывается")
    }
}
