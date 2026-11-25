import XCTest
@testable import Sonar

/// Жест «барабана»: пока палец на ленте — только вид, наружу ровно одно значение при отпускании.
final class DrumRulerGestureTests: XCTestCase {
    /// Скорость, как в листе: 0.5–2×, шаг 0.01, деление каждые 5, 7 точек на шаг.
    private let speed = DrumRulerGeometry(range: 0.5 ... 2, step: 0.01, spacing: 7, medium: 5)

    private func drag(_ g: DrumRulerGeometry, from value: Double, translations: [Double])
        -> (session: DrumRulerSession?, frames: Int, haptics: Int) {
        var session: DrumRulerSession?
        var frames = 0
        var haptics = 0
        for x in translations {
            guard let moved = g.move(session, from: value, translation: x) else { continue }
            session = moved.session
            frames += 1
            if moved.crossedMedium { haptics += 1 }
        }
        return (session, frames, haptics)
    }

    func testValueFollowsFingerWithoutDrift() {
        // палец вправо на 3 шага — под меткой меньшее значение (как на ПК)
        let moved = speed.move(nil, from: 1.0, translation: 21)
        XCTAssertEqual(moved?.session.current ?? 0, 0.97, accuracy: 1e-9)
        XCTAssertEqual(moved?.session.start ?? 0, 1.0, accuracy: 1e-9)
    }

    func testManyFramesGiveExactlyOneCommit() throws {
        // 120 кадров жеста: «1.03 ↔ 1.04» из-за дрожи пальца не должны выдавать ничего наружу, кроме итога
        let jitter: [Double] = (1 ... 120).map { (i: Int) -> Double in
            let wobble: Double = i % 2 == 0 ? 1.2 : -1.2
            return Double(i) * 0.5 + wobble
        }
        let result = drag(speed, from: 1.0, translations: jitter)
        let session = try XCTUnwrap(result.session)
        let commit = try XCTUnwrap(speed.commit(session))
        XCTAssertEqual(commit, session.current)
        XCTAssertEqual(commit, speed.snapped(commit), accuracy: 1e-9, "значение лежит на шаге")
        XCTAssertGreaterThan(result.frames, 1, "вид обновлялся по ходу")
    }

    func testReturnToStartCommitsNothing() throws {
        let result = drag(speed, from: 1.0, translations: [14, 28, 14, 0])
        let session = try XCTUnwrap(result.session)
        XCTAssertNil(speed.commit(session))
    }

    func testTapWithoutMoveCommitsNothing() throws {
        let moved = try XCTUnwrap(speed.move(nil, from: 1.0, translation: 2))
        XCTAssertNil(speed.commit(moved.session))
    }

    func testClampsToRange() throws {
        let up = try XCTUnwrap(drag(speed, from: 1.9, translations: [-100, -600]).session)
        XCTAssertEqual(up.current, 2.0, accuracy: 1e-9)
        let down = try XCTUnwrap(drag(speed, from: 0.6, translations: [100, 900]).session)
        XCTAssertEqual(down.current, 0.5, accuracy: 1e-9)
    }

    func testStartIsTakenOnceEvenIfValueChangesMidGesture() throws {
        var session = try XCTUnwrap(speed.move(nil, from: 1.0, translation: 14)).session
        // снаружи значение уже другое (например, прилетел синк) — лента считает от места касания
        session = try XCTUnwrap(speed.move(session, from: 1.5, translation: 28)).session
        XCTAssertEqual(session.start, 1.0, accuracy: 1e-9)
        XCTAssertEqual(session.current, 0.96, accuracy: 1e-9)
    }

    func testHapticOnlyOnMediumTicks() {
        // от 1.00 до 0.90: границы 0.95 и 0.90 — две вибрации, а не по одной на шаг
        let result = drag(speed, from: 1.0, translations: (1 ... 10).map { Double($0) * 7 })
        XCTAssertEqual(result.session?.current ?? 0, 0.90, accuracy: 1e-9)
        XCTAssertEqual(result.haptics, 2)
    }

    func testPitchRulerNegativeBlocks() {
        // тон −12…12, шаг 0.1, деление каждые 5 шагов: через ноль вибрация тоже на каждом делении
        let pitch = DrumRulerGeometry(range: -12 ... 12, step: 0.1, spacing: 7, medium: 5)
        let result = drag(pitch, from: 0.2, translations: (1 ... 6).map { Double($0) * 7 })
        XCTAssertEqual(result.session?.current ?? 0, -0.4, accuracy: 1e-9)
        XCTAssertEqual(result.haptics, 1, "пересекли только 0")
    }

    func testSnappedKeepsStepGrid() {
        XCTAssertEqual(speed.snapped(1.034), 1.03, accuracy: 1e-9)
        XCTAssertEqual(speed.snapped(9), 2.0, accuracy: 1e-9)
        XCTAssertEqual(speed.snapped(-3), 0.5, accuracy: 1e-9)
    }
}
