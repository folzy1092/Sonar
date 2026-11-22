import XCTest
@testable import Sonar

/// Поле точек героя: кадровые таблицы считают то же, что формулы на точку, а касания не копятся.
@MainActor
final class SonarFieldTests: XCTestCase {
    private let grid = FieldGrid(size: CGSize(width: 390, height: 290), step: 8)

    func testDriftTablesMatchFormula() {
        for t in [0.0, 1.7, 12.25, 700_000_003.5] {
            let frame = FieldFrame(grid: grid, t: t, playing: false)
            for (col, row) in [(0, 0), (5, 9), (grid.cols - 1, grid.rows - 1), (24, 17)] {
                let table = frame.drift(col: col, row: row)
                let formula = SonarField.drift(col: col, row: row, t: t)
                XCTAssertEqual(table.dx, formula.dx, accuracy: 1e-6)
                XCTAssertEqual(table.dy, formula.dy, accuracy: 1e-6)
                XCTAssertEqual(table.scale, formula.scale, accuracy: 1e-6)
            }
        }
    }

    func testLogoPhaseDrawsOnlyTheMark() {
        // t = 0 — знак без перетекания: пустая маска — ни одной точки, полная — центр яркий
        let frame = FieldFrame(grid: grid, t: 0, playing: false)
        XCTAssertEqual(frame.index, 0)
        XCTAssertEqual(frame.k, 0)
        let empty = [Float](repeating: 0, count: grid.cols * grid.rows)
        let full = [Float](repeating: 1, count: grid.cols * grid.rows)
        let mid = (col: grid.cols / 2, row: grid.rows / 2)
        XCTAssertEqual(frame.value(col: mid.col, row: mid.row, logo: empty), 0)
        XCTAssertGreaterThan(frame.value(col: mid.col, row: mid.row, logo: full), 0.5)
    }

    func testValuesStayInRangeThroughAllShapes() {
        let logo = [Float](repeating: 1, count: grid.cols * grid.rows)
        for t in stride(from: 0.0, to: 27.0, by: 1.3) {
            for playing in [false, true] {
                let frame = FieldFrame(grid: grid, t: t, playing: playing)
                for row in stride(from: 0, to: grid.rows, by: 3) {
                    for col in stride(from: 0, to: grid.cols, by: 3) {
                        let v = frame.value(col: col, row: row, logo: logo)
                        XCTAssertTrue((0 ... 1).contains(v), "t=\(t) col=\(col) row=\(row) v=\(v)")
                    }
                }
            }
        }
    }

    func testWavesPhaseLightsTheMiddle() {
        // 2 × (6.5 + 2.5) + 1 — третья фигура, волны, без перетекания
        let frame = FieldFrame(grid: grid, t: 19, playing: false)
        XCTAssertEqual(frame.index, 2)
        let lit = (0 ..< grid.rows).map { frame.value(col: grid.cols / 2, row: $0, logo: []) }.filter { $0 > 0.3 }
        XCTAssertFalse(lit.isEmpty)
    }

    func testPokesAreCappedAndExpire() {
        let now = 100.0
        let old = SonarField.Poke(point: .zero, time: now - SonarField.pokeLife - 0.1)
        var pokes = [old]
        for i in 0 ..< 6 {
            pokes = SonarField.addPoke(SonarField.Poke(point: .zero, time: now + Double(i) * 0.01), to: pokes, now: now)
        }
        XCTAssertEqual(pokes.count, SonarField.maxPokes)
        XCTAssertFalse(pokes.contains { $0.time == old.time }, "отжившее касание выпало")
        XCTAssertEqual(pokes.last?.time ?? 0, now + 0.05, accuracy: 1e-9, "новое касание — последним")
    }

    func testPokeWaitsForFrontAndFades() {
        let poke = SonarField.Poke(point: .zero, time: 0)
        // фронт (~420 pt/с) ещё не дошёл до точки в 200 pt
        let early = SonarField.play(poke, at: CGPoint(x: 200, y: 0), t: 0.1)
        XCTAssertEqual(early.dx, 0)
        XCTAssertEqual(early.scale, 1)
        // дошёл — точка сдвигается
        let live = SonarField.play(poke, at: CGPoint(x: 20, y: 0), t: 0.15)
        XCTAssertNotEqual(live.dx, 0)
        // касание отыграло
        let gone = SonarField.play(poke, at: CGPoint(x: 20, y: 0), t: SonarField.pokeLife + 0.01)
        XCTAssertEqual(gone.dx, 0)
        XCTAssertEqual(gone.scale, 1)
    }
}
