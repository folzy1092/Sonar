import XCTest
@testable import Sonar

// Карточка «Следующий переход» (docs/BLEND.md §10.1) — порт `view.test.ts`: какое состояние показать и числа плана.

final class BlendViewTests: XCTestCase {
    private let aMinor = 21
    private let eMinor = 16

    private lazy var anA = BlendFixtures.track("a", key: aMinor)
    private lazy var anB = BlendFixtures.track("b", key: eMinor)
    private lazy var plans = BlendPlanner.plan(anA, anB, opts: BlendFixtures.opts {
        $0.type = .bass
        $0.cutSec = 16
        $0.tempoTolPct = 8
    })

    private func input(_ edit: (inout BlendView.CardInput) -> Void = { _ in }) -> BlendView.CardInput {
        var c = BlendView.CardInput(
            on: true, repeatOne: false, a: "a", b: "b", stateA: .ready, stateB: .ready, failed: false,
            next: BlendNext(from: "a", to: "b", plan: plans[0], rank: 1, total: plans.count),
            anA: anA, anB: anB, rateA: 1
        )
        edit(&c)
        return c
    }

    private func planCard(_ c: BlendView.CardInput) -> BlendView.PlanCard? {
        if case .plan(let card) = BlendView.card(c) { return card }
        return nil
    }

    func testPlanCardNumbers() throws {
        XCTAssertFalse(plans.isEmpty)
        let c = try XCTUnwrap(planCard(input()))
        XCTAssertEqual(c.kind, plans[0].kind)
        XCTAssertTrue(c.sync)
        // 128 BPM: такт 1.875 с
        XCTAssertEqual(c.sec, Double(plans[0].bars) * 1.875, accuracy: 0.05)
        XCTAssertEqual([c.rank, c.total], [1, plans.count])
        XCTAssertEqual([c.tempoA, c.tempoB], [128, 128])
        XCTAssertEqual([c.keyA, c.keyB], ["8A", "9A"])
        XCTAssertEqual([c.outMs, c.inMs], [plans[0].outMs, plans[0].inMs])
    }

    func testOwnRateShortensSeconds() throws {
        let fast = try XCTUnwrap(planCard(input { $0.rateA = 2 }))
        let normal = try XCTUnwrap(planCard(input()))
        XCTAssertEqual(fast.sec, normal.sec / 2, accuracy: 0.05)
    }

    func testUnknownKeyIsDash() throws {
        let c = try XCTUnwrap(planCard(input { $0.anB = BlendFixtures.track("b", key: nil) }))
        XCTAssertEqual(c.keyB, "—")
    }

    func testStateOrder() {
        XCTAssertEqual(BlendView.card(input { $0.on = false }), .off)
        XCTAssertEqual(BlendView.card(input { $0.a = nil; $0.repeatOne = true }), .idle)
        XCTAssertEqual(BlendView.card(input { $0.repeatOne = true; $0.b = nil }), .repeatOne)
        XCTAssertEqual(BlendView.card(input { $0.b = nil; $0.failed = true }), .last)
        XCTAssertEqual(BlendView.card(input { $0.failed = true; $0.stateB = .failed }), .noPlan)
        XCTAssertEqual(BlendView.card(input { $0.stateB = .failed }), .noAnalysis)
    }

    func testCountingThenWaiting() {
        XCTAssertEqual(BlendView.card(input { $0.stateB = .pending; $0.next = nil; $0.anB = nil }), .counting)
        XCTAssertEqual(BlendView.card(input { $0.stateA = .none; $0.next = nil }), .counting)
        XCTAssertEqual(BlendView.card(input { $0.next = nil }), .waiting)
    }

    func testStalePlanHidden() {
        let plan = plans[0]
        let stale = input { $0.next = BlendNext(from: "a", to: "c", plan: plan, rank: 1, total: 8) }
        XCTAssertEqual(BlendView.card(stale), .waiting)
    }

    func testButtonLabel() {
        XCTAssertEqual(BlendView.buttonLabel(on: true, type: .auto), "Авто")
        XCTAssertEqual(BlendView.buttonLabel(on: true, type: .bass), "Бас")
        XCTAssertEqual(BlendView.buttonLabel(on: false, type: .bass), "")
    }

    func testLengthNames() {
        XCTAssertEqual(BlendPrefs.lengths.map(BlendView.lengthText), ["Коротко", "Норм", "Длинно"])
    }

    func testAnalysisLine() {
        var a = BlendFixtures.track("a", key: aMinor)
        a.loudness = -9.84
        XCTAssertEqual(BlendView.analysisLine(a), "128.0 BPM · \(String(format: "%.2f", a.bpmConf)) · 8A · \(String(format: "%.2f", a.keyConf)) · −9.8 LUFS")
        a.key = nil
        XCTAssertTrue(BlendView.analysisLine(a).contains(" · — · "))
    }

    func testMinusSign() {
        XCTAssertEqual(BlendView.minus(-9.84, 1), "−9.8")
        XCTAssertEqual(BlendView.minus(-0.01, 1), "0.0")
        XCTAssertEqual(BlendView.minus(3), "3")
    }

    func testPhaseText() {
        XCTAssertEqual(BlendView.phaseText(.running), "Отладка::идёт")
        XCTAssertEqual(BlendView.phaseText(.fallback), "Отладка::кроссфейд")
    }
}
