import Foundation
import XCTest
@testable import Sonar

// Оценки переходов (docs/BLEND.md §8) — порт `ratings.test.ts`, менять — в обоих местах: окно закрывается через
// минуту, ответ пишется один раз и обновляет баланс, после сбоя записи можно ответить снова, новый переход
// сбрасывает ответ и окно, без вопроса ничего не пишется.

@MainActor
private final class ManualTimer: BlendTimer {
    let sec: Double
    let run: @MainActor () -> Void
    private(set) var cancelled = false

    init(_ sec: Double, _ run: @escaping @MainActor () -> Void) {
        self.sec = sec
        self.run = run
    }

    func cancel() { cancelled = true }

    func fire() {
        if !cancelled { run() }
    }
}

@MainActor
final class BlendRatingsTests: XCTestCase {
    private var timers: [ManualTimer] = []
    private var writes = 0
    private var writeOK = true
    private var clock = 1_000_000_000_000

    private func make() -> BlendRatings {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("blend-ratings-\(UUID().uuidString).json")
        let r = BlendRatings(file: file)
        r.now = { [unowned self] in self.clock }
        r.after = { [unowned self] sec, run in
            let t = ManualTimer(sec, run)
            self.timers.append(t)
            return t
        }
        r.write = { [unowned self] _, _ in
            self.writes += 1
            return self.writeOK
        }
        return r
    }

    private let ab = BlendDone(from: "sc:1", to: "ym:2", kind: .bass)

    func testWindowClosesAfterMinute() {
        let r = make()
        r.open(ab)
        XCTAssertEqual(r.ask, ab)
        XCTAssertEqual(timers.last?.sec, BlendRatings.windowSec)
        timers.last?.fire()
        XCTAssertNil(r.ask)
    }

    func testAnswerWrittenOnceAndBalanceUpdates() {
        let r = make()
        r.open(ab)
        r.rate(-1)
        r.rate(1)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(r.answer, -1)
        XCTAssertEqual(r.balance[.bass], -1)
        r.open(BlendDone(from: "ym:2", to: "sc:3", kind: .bass))
        r.rate(1)
        XCTAssertEqual(r.balance[.bass] ?? 9, 0, accuracy: 1e-9)
    }

    func testFailedWriteLetsAnswerAgain() {
        let r = make()
        r.open(ab)
        writeOK = false
        r.rate(1)
        XCTAssertNil(r.answer)
        XCTAssertNil(r.balance[.bass])
        writeOK = true
        r.rate(1)
        XCTAssertEqual(r.answer, 1)
        XCTAssertEqual(r.balance[.bass], 1)
    }

    func testNewTransitionResetsAnswerAndWindow() {
        let r = make()
        r.open(ab)
        r.rate(1)
        let first = timers.last
        let next = BlendDone(from: "ym:2", to: "sc:3", kind: .echo)
        r.open(next)
        XCTAssertTrue(first?.cancelled ?? false)
        XCTAssertNil(r.answer)
        XCTAssertEqual(r.ask, next)
        first?.fire()
        XCTAssertEqual(r.ask, next)
    }

    func testNothingWrittenWithoutQuestion() {
        let r = make()
        r.rate(1)
        XCTAssertEqual(writes, 0)
        XCTAssertNil(r.answer)
    }

    func testBalanceIgnoresOldEntries() {
        let day = 86_400_000
        let now = 100 * day
        let entries = [
            BlendRatingEntry(from: "a", to: "b", kind: .drop, score: -1, at: now - 61 * day),
            BlendRatingEntry(from: "a", to: "b", kind: .drop, score: 1, at: now - day),
            BlendRatingEntry(from: "a", to: "b", kind: .smooth, score: -1, at: now),
        ]
        let b = BlendRatingMath.balance(entries, sinceMs: now - BlendRatings.days * day)
        XCTAssertEqual(b, [.drop: 1, .smooth: -1])
    }
}
