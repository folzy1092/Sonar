import Foundation
import XCTest
@testable import Sonar

// Тональности сведения (docs/BLEND.md §7.4, §14) — порт `camelot.test.ts`, менять — в обоих местах.

final class BlendCamelotTests: XCTestCase {
    private let keyC = 0
    private let keyCSharp = 1
    private let keyD = 2
    private let keyF = 5
    private let keyG = 7
    private let aMinor = 21
    private let eMinor = 16

    func testNamesOnWheel() {
        XCTAssertEqual(BlendCamelot.name(keyC), "8B")
        XCTAssertEqual(BlendCamelot.name(aMinor), "8A")
        XCTAssertEqual(BlendCamelot.name(keyG), "9B")
        XCTAssertEqual(BlendCamelot.name(keyF), "7B")
        XCTAssertEqual(BlendCamelot.name(eMinor), "9A")
        XCTAssertEqual(BlendCamelot.name(nil), "—")
    }

    func testAll24KeysAreDistinctCells() {
        let cells = Set((0..<24).map { BlendCamelot.name($0) })
        XCTAssertEqual(cells.count, 24)
        for k in 0..<24 { XCTAssertGreaterThanOrEqual(BlendCamelot.camelot(k).num, 1) }
    }

    func testCompatSameAndNeighbours() {
        XCTAssertEqual(BlendCamelot.compat(keyC, keyC), 1)
        XCTAssertEqual(BlendCamelot.compat(keyC, keyG), 1)
        XCTAssertEqual(BlendCamelot.compat(keyC, keyF), 1)
        XCTAssertEqual(BlendCamelot.compat(keyC, keyD), 0.6)
        XCTAssertEqual(BlendCamelot.compat(keyC, keyCSharp), 0)
    }

    func testCompatMajorMinorOnlySameNumber() {
        XCTAssertEqual(BlendCamelot.compat(keyC, aMinor), 1)
        XCTAssertEqual(BlendCamelot.compat(aMinor, keyC), 1)
        XCTAssertEqual(BlendCamelot.compat(keyC, eMinor), 0)
    }

    func testUnknownKeyIsMiddleWithoutShiftOrClash() {
        let unknown = CamelotMatch(score: BlendCamelot.unknownScore, shift: 0, clash: false)
        XCTAssertEqual(BlendCamelot.keyMatch(nil, keyC, allowShift: true), unknown)
        XCTAssertEqual(BlendCamelot.keyMatch(keyC, nil, allowShift: false), unknown)
    }

    func testCompatibleWithoutShift() {
        XCTAssertEqual(BlendCamelot.keyMatch(keyC, keyG, allowShift: true), CamelotMatch(score: 1, shift: 0, clash: false))
    }

    func testIncompatibleNeedsShiftOrClashes() {
        XCTAssertEqual(BlendCamelot.keyMatch(keyC, keyCSharp, allowShift: true), CamelotMatch(score: 1, shift: -1, clash: false))
        XCTAssertEqual(BlendCamelot.keyMatch(keyC, keyCSharp, allowShift: false), CamelotMatch(score: 0, shift: 0, clash: true))
    }

    func testShiftNeverExceedsMax() {
        for b in 0..<24 {
            let m = BlendCamelot.keyMatch(keyC, b, allowShift: true)
            XCTAssertLessThanOrEqual(abs(m.shift), BlendCamelot.maxShift)
        }
    }

    func testLinkedSpeedShiftsPitchItself() {
        let rate = pow(2, -1.0 / 12)
        let m = BlendCamelot.keyMatch(keyC, keyCSharp, driftB: 12 * log2(rate), allowShift: false)
        XCTAssertEqual(m, CamelotMatch(score: 1, shift: 0, clash: false))
    }

    func testFractionalDriftGivesFractionalShift() {
        let m = BlendCamelot.keyMatch(keyC, keyC, driftB: 0.5, allowShift: true)
        XCTAssertFalse(m.clash)
        XCTAssertEqual(m.shift, -0.5, accuracy: 0.005)
    }

    func testJsArithmetic() {
        XCTAssertEqual(BlendMath.mod(-1, 12), 11)
        XCTAssertEqual(BlendMath.mod(-0.5, 12), 11.5)
        XCTAssertEqual(BlendMath.jsRound(2.5), 3)
        XCTAssertEqual(BlendMath.jsRound(-2.5), -2)
        XCTAssertEqual(BlendMath.round(1.23456, 2), 1.23)
    }
}
