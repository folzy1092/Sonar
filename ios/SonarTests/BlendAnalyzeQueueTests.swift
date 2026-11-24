import Foundation
import XCTest
@testable import Sonar

// Очередь анализа (docs/BLEND.md §4.1) — порт `analyze-queue.test.ts`, менять — в обоих местах: два одновременно,
// «сейчас» раньше вечеринки, без двойного счёта, база раньше расчёта, упавшие не долбим, очистка сбрасывает память.

private struct Fail: Error, CustomStringConvertible {
    let description: String
}

/// Расчёт, который завершается вручную: видно, сколько идёт одновременно и в каком порядке.
@MainActor
private final class Manual {
    var stored: [String: BlendAnalysis]
    private(set) var started: [String] = []
    private(set) var saved: [BlendAnalysis] = []
    private var pending: [String: @MainActor (Result<BlendAnalysis, Error>) -> Void] = [:]

    init(_ stored: [String: BlendAnalysis] = [:]) {
        self.stored = stored
    }

    var deps: BlendAnalyzeDeps {
        BlendAnalyzeDeps(
            load: { [unowned self] refs, done in
                done(self.stored.filter { refs.contains($0.key) })
            },
            compute: { [unowned self] ref, done in
                self.started.append(ref)
                self.pending[ref] = done
            },
            save: { [unowned self] a in self.saved.append(a) }
        )
    }

    func ok(_ ref: String) {
        pending.removeValue(forKey: ref)?(.success(result(ref)))
    }

    func fail(_ ref: String, _ message: String) {
        pending.removeValue(forKey: ref)?(.failure(Fail(description: message)))
    }
}

private func result(_ ref: String, version: Int = blendAnalysisVersion) -> BlendAnalysis {
    var a = BlendFixtures.an(ref, -10)
    a.version = version
    return a
}

@MainActor
final class BlendAnalyzeQueueTests: XCTestCase {
    func testTwoAtOnceAndNowBeforeParty() {
        let m = Manual()
        let q = BlendAnalyzeQueue(deps: m.deps)
        q.request("p1", priority: .party)
        q.request("p2", priority: .party)
        q.request("p3", priority: .party)
        q.request("n1", priority: .now)
        XCTAssertEqual(m.started, ["p1", "p2"])
        m.ok("p1")
        XCTAssertEqual(m.started, ["p1", "p2", "n1"])
        XCTAssertEqual(q.stats(), .init(ready: 1, waiting: 1, running: 2, failed: 0, computed: 1))
    }

    func testSameTrackOnceAndPartyPromotedToNow() {
        let m = Manual()
        let q = BlendAnalyzeQueue(deps: m.deps, concurrency: 1)
        q.request("a")
        q.request("p", priority: .party)
        q.request("b", priority: .party)
        var got: [BlendAnalysis?] = []
        q.request("b", priority: .now) { got.append($0) }
        q.request("b", priority: .party) { got.append($0) }
        m.ok("a")
        XCTAssertEqual(m.started, ["a", "b"])
        m.ok("b")
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got[0]?.ref, "b")
        XCTAssertEqual(got[0], got[1])
        XCTAssertEqual(m.started, ["a", "b", "p"])
    }

    func testStoredSameVersionSkipsComputeOldVersionRecomputes() {
        let m = Manual(["a": result("a"), "old": result("old", version: blendAnalysisVersion - 1)])
        let q = BlendAnalyzeQueue(deps: m.deps)
        var hit: BlendAnalysis?
        q.request("a") { hit = $0 }
        XCTAssertEqual(hit?.ref, "a")
        XCTAssertTrue(m.started.isEmpty)
        var fresh: BlendAnalysis?
        q.request("old") { fresh = $0 }
        m.ok("old")
        XCTAssertEqual(fresh?.version, blendAnalysisVersion)
        XCTAssertEqual(m.saved, [result("old")])
        XCTAssertEqual(q.peek("old"), result("old"))
    }

    func testFailureRememberedUntilForget() {
        let m = Manual()
        var changes = 0
        let q = BlendAnalyzeQueue(deps: m.deps) { changes += 1 }
        var first: BlendAnalysis? = result("sentinel")
        q.request("x") { first = $0 }
        m.fail("x", "offline")
        XCTAssertNil(first)
        XCTAssertEqual(q.failure("x"), "offline")
        XCTAssertEqual(q.state("x"), .failed)
        var again: BlendAnalysis? = result("sentinel")
        q.request("x") { again = $0 }
        XCTAssertNil(again)
        XCTAssertEqual(m.started.count, 1)
        q.forgetFailures()
        XCTAssertNil(q.failure("x"))
        q.request("x")
        XCTAssertEqual(m.started.count, 2)
        XCTAssertGreaterThan(changes, 0)
    }

    func testWarmLoadsOnlyCurrentVersion() {
        let m = Manual(["a": result("a"), "old": result("old", version: blendAnalysisVersion - 1)])
        let q = BlendAnalyzeQueue(deps: m.deps)
        var warmed = false
        q.warm(["a", "old", "none"]) { warmed = true }
        XCTAssertTrue(warmed)
        XCTAssertNotNil(q.peek("a"))
        XCTAssertNil(q.peek("old"))
        XCTAssertTrue(m.started.isEmpty)
    }

    func testResetDropsWaitersAndRunningWritesNothing() {
        let m = Manual()
        let q = BlendAnalyzeQueue(deps: m.deps, concurrency: 1)
        var running: BlendAnalysis? = result("sentinel")
        var waiting: BlendAnalysis? = result("sentinel")
        q.request("a") { running = $0 }
        q.request("b") { waiting = $0 }
        q.reset()
        XCTAssertNil(waiting)
        m.ok("a")
        XCTAssertNil(running)
        XCTAssertNil(q.peek("a"))
        XCTAssertTrue(m.saved.isEmpty)
        XCTAssertFalse(q.pending("a"))
    }
}
