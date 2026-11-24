import XCTest
@testable import Sonar

// Планировщик сведения (docs/BLEND.md §7, §14) — порт `planner.test.ts`, менять — в обоих местах: детерминизм,
// откат на «Эхо» вне допуска темпа и без устойчивой сетки, срез не больше настройки, топ-8 без повторов.

final class BlendPlannerTests: XCTestCase {
    private typealias F = BlendFixtures

    private struct PlanID: Hashable {
        var kind: BlendKind
        var outMs: Double
        var inMs: Double
    }

    private func plan(_ a: BlendAnalysis, _ b: BlendAnalysis, _ opts: PlanOpts = F.opts) -> [TransitionPlan] {
        BlendPlanner.plan(a, b, opts: opts)
    }

    func testLengthBarsNearestOfOptions() {
        XCTAssertEqual(BlendPlanner.lengthBars(16, tempo: 128), 8)
        XCTAssertEqual(BlendPlanner.lengthBars(30, tempo: 128), 16)
        XCTAssertEqual(BlendPlanner.lengthBars(4, tempo: 128), 4)
    }

    func testAutoWithoutSyncOnlyEchoAndSmooth() {
        XCTAssertEqual(BlendPlanner.kindsFor(.auto, syncOk: true), [.bass, .filter, .echo, .smooth, .drop])
        XCTAssertEqual(BlendPlanner.kindsFor(.auto, syncOk: false), [.echo, .smooth])
    }

    func testManualSyncKindFallsBackToEcho() {
        XCTAssertEqual(BlendPlanner.kindsFor(.bass, syncOk: false), [.echo])
        XCTAssertEqual(BlendPlanner.kindsFor(.drop, syncOk: false), [.echo])
        XCTAssertEqual(BlendPlanner.kindsFor(.smooth, syncOk: false), [.smooth])
        XCTAssertEqual(BlendPlanner.kindsFor(.filter, syncOk: true), [.filter])
    }

    func testDeterministic() {
        let a = F.track("sc:a")
        let b = F.track("ym:b", key: 7)
        XCTAssertEqual(plan(a, b), plan(a, b))
    }

    func testAtMostEightUniqueBestFirst() {
        let plans = plan(F.track("sc:a"), F.track("ym:b"))
        XCTAssertGreaterThan(plans.count, 0)
        XCTAssertLessThanOrEqual(plans.count, BlendPlanner.topPlans)
        XCTAssertEqual(Set(plans.map { PlanID(kind: $0.kind, outMs: $0.outMs, inMs: $0.inMs) }).count, plans.count)
        for i in plans.indices.dropFirst() { XCTAssertGreaterThanOrEqual(plans[i - 1].score, plans[i].score) }
        for p in plans {
            XCTAssertGreaterThanOrEqual(p.score, 0)
            XCTAssertLessThanOrEqual(p.score, 1)
        }
    }

    func testSameTempoAndKeySyncsWithoutShift() throws {
        let best = try XCTUnwrap(plan(F.track("sc:a"), F.track("ym:b")).first)
        XCTAssertTrue(best.sync)
        XCTAssertEqual(best.shift, 0)
        XCTAssertEqual(best.parts[.tempo] ?? -1, 1)
        XCTAssertEqual(best.beatRatio, 1)
    }

    func testTempoOutOfToleranceFallsBackToEcho() throws {
        let a = F.track("sc:a", bpm: 128)
        let b = F.track("ym:b", bpm: 140)
        let manual = plan(a, b, F.opts { $0.type = .bass })
        XCTAssertGreaterThan(manual.count, 0)
        XCTAssertTrue(manual.allSatisfy { $0.kind == .echo && !$0.sync })
        let auto = plan(a, b)
        XCTAssertEqual(try XCTUnwrap(auto.first).kind, .echo)
        XCTAssertTrue(auto.allSatisfy { !$0.sync })
    }

    func testUnstableGridNeverSyncs() throws {
        let plans = plan(F.track("sc:a"), F.track("ym:b", gridStable: false))
        XCTAssertGreaterThan(plans.count, 0)
        XCTAssertFalse(plans.contains { $0.sync })
        let filter = plan(F.track("sc:a", gridStable: false), F.track("ym:b"), F.opts { $0.type = .filter })
        XCTAssertEqual(try XCTUnwrap(filter.first).kind, .echo)
    }

    func testHalfTempoBSyncsInDoubleGrid() throws {
        let best = try XCTUnwrap(plan(F.track("sc:a", bpm: 128), F.track("ym:b", bpm: 64)).first)
        XCTAssertEqual(best.beatRatio, 0.5)
        XCTAssertTrue(best.sync)
    }

    func testCutNeverExceedsSetting() {
        for cutSec in [0.0, 4, 8, 20] {
            let plans = plan(F.track("sc:a"), F.track("ym:b"), F.opts { $0.cutSec = cutSec })
            XCTAssertGreaterThan(plans.count, 0)
            for p in plans {
                XCTAssertLessThanOrEqual(p.cutOutMs, cutSec * 1000)
                XCTAssertLessThanOrEqual(p.cutInMs, cutSec * 1000)
            }
        }
    }

    func testEchoStartsBOnSecondBarWithoutSync() {
        let plans = plan(F.track("sc:a"), F.track("ym:b"), F.opts { $0.type = .echo })
        XCTAssertGreaterThan(plans.count, 0)
        for p in plans {
            XCTAssertEqual(p.kind, .echo)
            XCTAssertEqual(p.inAtBar, 1)
            XCTAssertFalse(p.sync)
            XCTAssertGreaterThan(p.endAMs, p.outMs)
        }
    }

    func testGainMatchesAWithinNineDb() throws {
        let six = try XCTUnwrap(plan(F.track("sc:a", loudness: -8), F.track("ym:b", loudness: -14)).first)
        XCTAssertEqual(six.gainDb, 6)
        let capped = try XCTUnwrap(plan(F.track("sc:a", loudness: -4), F.track("ym:b", loudness: -30)).first)
        XCTAssertEqual(capped.gainDb, 9)
        let silent = try XCTUnwrap(plan(F.track("sc:a", loudness: -80), F.track("ym:b")).first)
        XCTAssertEqual(silent.gainDb, 0)
    }

    func testIncompatibleKeyWithoutShiftLosesBassSwap() throws {
        let a = F.track("sc:a", key: 0)
        let b = F.track("ym:b", key: 1)
        let free = try XCTUnwrap(plan(a, b, F.opts { $0.type = .bass }).first)
        let locked = try XCTUnwrap(plan(a, b, F.opts { $0.type = .bass; $0.keyShift = false }).first)
        XCTAssertEqual(free.shift, -1)
        XCTAssertEqual(locked.shift, 0)
        XCTAssertLessThan(locked.score, free.score)
    }

    func testDislikeLowersKindScore() throws {
        let a = F.track("sc:a")
        let b = F.track("ym:b")
        let plain = try XCTUnwrap(plan(a, b, F.opts { $0.type = .echo }).first)
        let disliked = try XCTUnwrap(plan(a, b, F.opts { $0.type = .echo; $0.ratings = [.echo: -1] }).first)
        XCTAssertLessThan(disliked.score, plain.score)
        XCTAssertEqual(disliked.parts[.rating] ?? -1, 0)
    }

    func testBrokenTempoOrRateGivesNothing() {
        XCTAssertEqual(plan(F.track("sc:a", bpm: 0), F.track("ym:b")), [])
        XCTAssertEqual(plan(F.track("sc:a"), F.track("ym:b"), F.opts { $0.rateB = 0 }), [])
    }
}
