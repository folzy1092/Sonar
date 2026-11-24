import Foundation
import XCTest
@testable import Sonar

// Кривые сведения (docs/BLEND.md §8, §14) — порт `curves.test.ts`, менять — в обоих местах: в начале B молчит,
// в конце A молчит; после свапа ровно один бас; равная мощность без провалов > 1.5 дБ; B на полной за долю у
// «Эха» и «На дроп»; резкие места ≥ 5 мс. Плюс чистая часть `automation.ts` и `startBar` / `expectedB`.

final class BlendCurvesTests: XCTestCase {
    private typealias F = BlendFixtures
    private let minStepSec = 0.005
    private let eps = 1e-9

    private func curves(_ plan: TransitionPlan) -> BlendCurves {
        BlendMix.curvesFor(plan, nyquist: F.nyquist)
    }

    func testBSilentAtStartASilentAtEndBFull() {
        for kind in BlendKind.allCases {
            let c = curves(F.planOf(kind))
            XCTAssertEqual(BlendMix.paramsAt(c, bar: 0).b.gain, 0, "\(kind)")
            XCTAssertEqual(BlendMix.paramsAt(c, bar: 0).a.gain, 1, "\(kind)")
            let end = BlendMix.paramsAt(c, bar: c.endBar)
            XCTAssertEqual(end.a.gain, 0, "\(kind)")
            XCTAssertEqual(end.b.gain, 1, accuracy: 0.5e-9, "\(kind)")
            // после «промоута» A не звучит сухим ни на такте
            XCTAssertLessThan(BlendMix.paramsAt(c, bar: c.promoteBar + 0.01).a.gain, eps, "\(kind)")
        }
    }

    func testBSilentBeforeItsEntry() {
        for kind in BlendKind.allCases {
            let plan = F.planOf(kind)
            let c = curves(plan)
            for bar in F.sample(Double(plan.inAtBar)) {
                XCTAssertEqual(BlendMix.paramsAt(c, bar: bar).b.gain, 0, "\(kind) @\(bar)")
            }
        }
    }

    func testBassSwapAlwaysExactlyOneBass() {
        for bars in [4, 8, 16] {
            let c = curves(F.planOf(.bass) { $0.bars = bars })
            let swap = Double(bars) / 2
            for bar in F.sample(c.endBar) {
                if abs(bar - swap) < 0.01 { continue } // внутри 8-миллисекундного свапа
                let (a, b) = BlendMix.paramsAt(c, bar: bar)
                XCTAssertEqual([a.low, b.low].filter { $0 == 0 }.count, 1)
                XCTAssertEqual([a.low, b.low].filter { $0 == BlendChain.isoMinDb }.count, 1)
                XCTAssertEqual(a.low == 0, bar < swap)
            }
        }
    }

    func testEqualPowerNoDipOverOneAndHalfDb() {
        for kind in [BlendKind.bass, .filter, .smooth] {
            let c = curves(F.planOf(kind))
            for bar in F.sample(c.endBar) {
                let (a, b) = BlendMix.paramsAt(c, bar: bar)
                XCTAssertGreaterThanOrEqual(10 * log10(a.gain * a.gain + b.gain * b.gain), -1.5, "\(kind) @\(bar)")
            }
        }
    }

    func testDropBFullRightOnDrop() {
        let plan = F.planOf(.drop)
        let c = curves(plan)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: Double(plan.inAtBar) + 0.25).b.gain, 1, accuracy: 0.5e-9)
    }

    func testDropRiserEchoRingsOverDrop() {
        let plan = F.planOf(.drop)
        let c = curves(plan)
        let n = Double(plan.bars)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: n - 1).a.echoSend, 0)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: n - 0.25).a.echoSend, 1)
        XCTAssertGreaterThan(BlendMix.paramsAt(c, bar: n + 1).a.feedback, 0)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: n + 1).a.gain, 0)
        XCTAssertEqual(c.endBar, n + 2)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: c.endBar).a.echoSend, 0)
    }

    func testEchoBFadesInOverBarBassOverTwo() {
        let plan = F.planOf(.echo)
        let c = curves(plan)
        let one = Double(plan.inAtBar)
        XCTAssertGreaterThan(BlendMix.paramsAt(c, bar: one + 0.25).b.gain, 0)
        XCTAssertLessThan(BlendMix.paramsAt(c, bar: one + 0.25).b.gain, 1)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: one + 1).b.gain, 1, accuracy: 0.5e-9)
        XCTAssertLessThan(BlendMix.paramsAt(c, bar: one + 1).b.low, 0)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: one + 2).b.low, 0)
    }

    func testEveryChangeAtLeastFiveMsEvenWhenTempoRises() {
        for kind in BlendKind.allCases {
            let plan = F.planOf(kind) { $0.tempoB = 135 }
            let c = curves(plan)
            let fastest = max(plan.tempoA, plan.tempoB)
            for s in BlendMix.steps(c) {
                XCTAssertGreaterThanOrEqual((s.bars * 240) / fastest, minStepSec - eps, "\(kind) \(s.side) \(s.param)")
            }
        }
    }

    func testFilterHighpassLowpassAndBassHandoff() {
        let c = curves(F.planOf(.filter))
        XCTAssertEqual(BlendMix.paramsAt(c, bar: 0).a.hpHz, 20)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: 8).a.hpHz, 1200, accuracy: 0.5e-6)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: 8).b.lpHz, F.nyquist, accuracy: 0.5e-6)
        for bar in F.sample(8) {
            let (a, b) = BlendMix.paramsAt(c, bar: bar)
            if a.hpHz < 150 { XCTAssertEqual(b.low, -12, "@\(bar)") }
        }
    }

    func testEchoBuildsUpDryAFadesHalfBarAfterOne() {
        let c = curves(F.planOf(.echo))
        XCTAssertEqual(BlendMix.paramsAt(c, bar: 0).a.echoSend, 0)
        let half = BlendMix.paramsAt(c, bar: 0.375).a.echoSend
        XCTAssertGreaterThan(half, 0)
        XCTAssertLessThan(half, 1)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: 0.75).a.echoSend, 1)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: 0.75).a.feedback, 0.55, accuracy: 0.5e-9)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: 1).a.gain, 1)
        // не обрыв: через четверть такта после «раз» сухой A ещё слышен
        XCTAssertGreaterThan(BlendMix.paramsAt(c, bar: 1.25).a.gain, 0.5)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: 1.5).a.gain, 0)
        XCTAssertEqual(BlendMix.paramsAt(c, bar: 3).a.feedback, 0.3, accuracy: 0.5e-9)
        XCTAssertEqual(c.echoDelaySec, (0.75 * 60) / 128, accuracy: 0.5e-9)
        // A отпускают только когда он замолк
        XCTAssertEqual(c.promoteBar, 1.5)
        XCTAssertEqual(c.endBar, 3)
    }

    func testAfterLastKeyRestOrLastValue() {
        let c = curves(F.planOf(.smooth))
        let after = BlendMix.paramsAt(c, bar: 100)
        XCTAssertEqual(after.b, c.rest.with(.gain, after.b.gain))
        XCTAssertEqual(after.a.hpHz, c.rest.hpHz)
        XCTAssertEqual(after.a.lpHz, F.nyquist)
    }

    func testKeyBarsInWindowAndSorted() {
        let c = curves(F.planOf(.bass))
        let bars = BlendMix.keyBars(c, from: 1, to: 5)
        XCTAssertGreaterThan(bars.count, 0)
        for i in bars.indices {
            XCTAssertGreaterThan(bars[i], 1)
            XCTAssertLessThanOrEqual(bars[i], 5)
            if i > 0 { XCTAssertGreaterThan(bars[i], bars[i - 1]) }
        }
    }

    // MARK: - tempoAt

    func testTempoWithoutSyncIsNil() {
        XCTAssertNil(BlendMix.tempoAt(F.planOf(.echo), bar: 1))
    }

    func testTempoSmoothstepFromAToB() throws {
        let plan = F.planOf(.bass) { $0.tempoA = 124; $0.tempoB = 126 }
        XCTAssertEqual(try XCTUnwrap(BlendMix.tempoAt(plan, bar: 0)), 124)
        XCTAssertEqual(try XCTUnwrap(BlendMix.tempoAt(plan, bar: 8)), 126)
        XCTAssertEqual(try XCTUnwrap(BlendMix.tempoAt(plan, bar: 4)), 125, accuracy: 0.5e-9)
        XCTAssertEqual(try XCTUnwrap(BlendMix.tempoAt(plan, bar: 20)), 126)
        var prev = 0.0
        for bar in F.sample(8) {
            let t = try XCTUnwrap(BlendMix.tempoAt(plan, bar: bar))
            XCTAssertGreaterThanOrEqual(t, prev)
            prev = t
        }
    }

    func testTempoHalfGridGoesToDoubledB() throws {
        let plan = F.planOf(.bass) { $0.tempoA = 128; $0.tempoB = 64; $0.beatRatio = 0.5 }
        XCTAssertEqual(try XCTUnwrap(BlendMix.tempoAt(plan, bar: 8)), 128)
    }

    // MARK: - automation.ts и контроллер

    func testDeckValueRestBeforeStartAndGainMulOnB() {
        let c = curves(F.planOf(.bass))
        XCTAssertEqual(BlendTimeline.deckValue(c, side: .a, .gain, bar: -1), c.rest.gain)
        XCTAssertEqual(BlendTimeline.deckValue(c, side: .a, .high, bar: -0.5), c.rest.high)
        XCTAssertEqual(BlendTimeline.deckValue(c, side: .b, .gain, bar: c.endBar, gainMul: 2), 2)
        XCTAssertEqual(BlendTimeline.deckValue(c, side: .a, .gain, bar: 0, gainMul: 2), 1)
        let values = BlendTimeline.deckValues(c, side: .b, bar: c.endBar, gainMul: 0.5)
        XCTAssertEqual(values.gain, 0.5)
        XCTAssertEqual(values.hpHz, c.rest.hpHz)
    }

    func testCurvedParamsOnlyWithCurves() {
        let c = curves(F.planOf(.bass))
        XCTAssertEqual(BlendTimeline.curvedParams(c, side: .a), [.gain, .low, .mid, .high])
        XCTAssertEqual(BlendTimeline.curvedParams(c, side: .b), [.gain, .low, .mid])
    }

    func testSpanBarsSamplesAndKeyBarsInOrder() {
        let c = curves(F.planOf(.bass))
        let span = BlendSpan(bar: 1.5, t0: 0, secPerBar: 1.875, horizonSec: 1.875)
        let bars = BlendTimeline.spanBars(c, span)
        let to = span.bar + span.horizonSec / span.secPerBar
        XCTAssertTrue(bars.contains(2)) // ключевой такт громкости B
        XCTAssertEqual(bars.last ?? -1, to)
        XCTAssertGreaterThan(bars.first ?? -1, span.bar)
        for i in bars.indices.dropFirst() {
            XCTAssertGreaterThan(bars[i], bars[i - 1])
            XCTAssertLessThanOrEqual(bars[i] - bars[i - 1], BlendTimeline.sampleSec / span.secPerBar + eps)
        }
    }

    func testStartBarLeadsTwoBarsButNotBeforeFileStart() {
        let anB = F.track("ym:b", bpm: 128)
        XCTAssertEqual(BlendTimeline.startBar(F.planOf(.bass), anB), 0)
        XCTAssertEqual(BlendTimeline.startBar(F.planOf(.bass) { $0.inMs = 10_000 }, anB), -2)
        XCTAssertEqual(BlendTimeline.startBar(F.planOf(.bass) { $0.inMs = 1875 }, anB), -1, accuracy: 1e-12)
        XCTAssertEqual(BlendTimeline.startBar(F.planOf(.echo) { $0.inMs = 10_000 }, anB), 1)
    }

    func testExpectedBFollowsBGrid() {
        let plan = F.planOf(.bass) { $0.inMs = 10_000 }
        XCTAssertEqual(BlendTimeline.expectedB(plan, F.track("ym:b", bpm: 128), bar: 2), 13_750, accuracy: 1e-9)
        let half = F.planOf(.bass) { $0.inMs = 10_000; $0.beatRatio = 0.5 }
        XCTAssertEqual(BlendTimeline.expectedB(half, F.track("ym:b", bpm: 64), bar: 2), 13_750, accuracy: 1e-9)
        XCTAssertEqual(BlendTimeline.expectedB(plan, F.track("ym:b", bpm: 128), bar: -2), 6_250, accuracy: 1e-9)
    }
}
