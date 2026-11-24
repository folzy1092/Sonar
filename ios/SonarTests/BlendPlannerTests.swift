import XCTest
@testable import Sonar

// Планировщик сведения (docs/BLEND.md §7, §14) — порт `planner.test.ts`, менять — в обоих местах: детерминизм,
// выбранный вид без синка остаётся собой, срез не больше настройки, A доигрывает до конца файла, топ-8 без повторов.

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

    func testLengthBarsWholeBarsTwoToThirtyTwo() {
        XCTAssertEqual(BlendPlanner.lengthBars(15, tempo: 128), 8)
        XCTAssertEqual(BlendPlanner.lengthBars(30, tempo: 128), 16)
        XCTAssertEqual(BlendPlanner.lengthBars(1, tempo: 128), 2)
        XCTAssertEqual(BlendPlanner.lengthBars(120, tempo: 128), 32)
    }

    func testShortNormLongDifferAtAnyTempo() {
        for bpm in [60.0, 70, 93, 128, 145, 174] {
            let bars = BlendPrefs.lengths.map { BlendPlanner.lengthBars($0, tempo: bpm) }
            XCTAssertLessThan(bars[0], bars[1], "\(bpm)")
            XCTAssertLessThan(bars[1], bars[2], "\(bpm)")
        }
    }

    func testLengthChangesEveryKind() {
        for kind in BlendKind.allCases {
            let bars = BlendPrefs.lengths.map { BlendPlanner.shapeOf(kind, base: BlendPlanner.lengthBars($0, tempo: 145)).bars }
            XCTAssertLessThan(bars[0], bars[2], "\(kind)")
        }
    }

    func testAutoWithoutSyncFilterEchoSmooth() {
        XCTAssertEqual(BlendPlanner.kindsFor(.auto, syncOk: true), [.bass, .filter, .echo, .smooth, .drop])
        XCTAssertEqual(BlendPlanner.kindsFor(.auto, syncOk: false), [.filter, .echo, .smooth])
    }

    func testManualKindAlwaysItself() {
        for kind in BlendKind.allCases {
            guard let type = BlendType(rawValue: kind.rawValue) else { return XCTFail("\(kind)") }
            XCTAssertEqual(BlendPlanner.kindsFor(type, syncOk: false), [kind])
            XCTAssertEqual(BlendPlanner.kindsFor(type, syncOk: true), [kind])
        }
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

    func testTempoOutOfToleranceKeepsChosenKindWithoutSync() throws {
        let a = F.track("sc:a", bpm: 145)
        let b = F.track("ym:b", bpm: 93)
        for type in [BlendType.bass, .filter, .drop, .echo] {
            let manual = plan(a, b, F.opts { $0.type = type })
            XCTAssertGreaterThan(manual.count, 0, "\(type)")
            XCTAssertTrue(manual.allSatisfy { $0.kind == type.kind && !$0.sync }, "\(type)")
        }
        let auto = plan(a, b)
        XCTAssertEqual(try XCTUnwrap(auto.first).kind, .filter)
        XCTAssertTrue(auto.allSatisfy { !$0.sync })
    }

    func testAPlaysItsPartBeforeFileEnds() {
        // музыка до самого конца файла — такт «за концом музыки» вышел бы за файл
        let a = F.track("sc:a", tailMs: 0)
        for type in BlendType.allCases {
            for p in plan(a, F.track("ym:b"), F.opts { $0.type = type; $0.cutSec = 20 }) {
                let silentMs = p.endAMs + (p.kind == .echo ? BlendPlanner.echoDryFadeBars * 1875 : 0)
                XCTAssertLessThanOrEqual(silentMs, a.durationMs - 300, "\(type)")
            }
        }
    }

    func testWiderCutCanLeaveBeforeOutro() {
        let a = F.track("sc:a", nBars: 64)
        let b = F.track("ym:b")
        let outro = 48.0 * 1875
        let narrow = plan(a, b, F.opts { $0.type = .filter; $0.cutSec = 8 })
        let wide = plan(a, b, F.opts { $0.type = .filter; $0.cutSec = 45 })
        XCTAssertFalse(narrow.contains { $0.endAMs == outro })
        XCTAssertTrue(wide.contains { $0.endAMs == outro })
    }

    func testUnstableGridNeverSyncs() throws {
        let plans = plan(F.track("sc:a"), F.track("ym:b", gridStable: false))
        XCTAssertGreaterThan(plans.count, 0)
        XCTAssertFalse(plans.contains { $0.sync })
        let filter = try XCTUnwrap(plan(F.track("sc:a", gridStable: false), F.track("ym:b"), F.opts { $0.type = .filter }).first)
        XCTAssertEqual(filter.kind, .filter)
        XCTAssertFalse(filter.sync)
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

    func testEchoBuildsTwoBarsThenBWithoutSync() {
        XCTAssertEqual(BlendPlanner.shapeOf(.echo, base: 4).inAtBar, 1)
        let plans = plan(F.track("sc:a"), F.track("ym:b"), F.opts { $0.type = .echo })
        XCTAssertGreaterThan(plans.count, 0)
        for p in plans {
            XCTAssertEqual(p.kind, .echo)
            XCTAssertEqual(p.inAtBar, 2)
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
