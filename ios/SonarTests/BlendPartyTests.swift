import XCTest
@testable import Sonar

// Порядок «Свести для вечеринки» (docs/BLEND.md §9) — порт `party-core.test.ts`, менять — в обоих местах.

final class BlendPartyTests: XCTestCase {
    private typealias F = BlendFixtures
    private let flat: (BlendAnalysis) -> Double = { _ in 0.5 }

    func testPartyContextRoundTrip() {
        let ctx = BlendParty.partyContext("playlist:42")
        XCTAssertTrue(BlendParty.isPartyContext(ctx))
        XCTAssertEqual(BlendParty.partyBase(ctx), "playlist:42")
        XCTAssertFalse(BlendParty.isPartyContext("playlist:42"))
        XCTAssertFalse(BlendParty.isPartyContext(nil))
    }

    func testLouderAndFasterIsHigherWithinUnit() {
        XCTAssertGreaterThan(BlendParty.trackEnergy(F.an("a", -8, bpm: 128)), BlendParty.trackEnergy(F.an("b", -14, bpm: 128)))
        XCTAssertGreaterThan(BlendParty.trackEnergy(F.an("a", -10, bpm: 140)), BlendParty.trackEnergy(F.an("b", -10, bpm: 100)))
        for l in [-70.0, -30, 0, 5] {
            let e = BlendParty.trackEnergy(F.an("x", l, bpm: 90))
            XCTAssertGreaterThanOrEqual(e, 0)
            XCTAssertLessThanOrEqual(e, 1)
        }
    }

    func testHalfTempoCountsAsDouble() {
        XCTAssertEqual(
            BlendParty.trackEnergy(F.an("a", -10, bpm: 64)), BlendParty.trackEnergy(F.an("b", -10, bpm: 128)), accuracy: 0.5e-5
        )
    }

    func testWarmupTargetsAboveCurrent() {
        let r = BlendParty.arcTarget(ArcState(elapsedMs: 5 * 60_000, sinceDip: 0, dips: 0, peak: 0.5), current: 0.5)
        XCTAssertFalse(r.dip)
        XCTAssertGreaterThan(r.target, 0.5)
    }

    func testHoldPeakThenDipOnFifthThenSixth() {
        let hold = { (sinceDip: Int, dips: Int) in
            ArcState(elapsedMs: BlendParty.warmupMs + 1, sinceDip: sinceDip, dips: dips, peak: 0.8)
        }
        XCTAssertEqual(BlendParty.arcTarget(hold(0, 0), current: 0.7).target, 0.8, accuracy: 0.005)
        XCTAssertFalse(BlendParty.arcTarget(hold(3, 0), current: 0.8).dip)
        let down = BlendParty.arcTarget(hold(4, 0), current: 0.8)
        XCTAssertTrue(down.dip)
        XCTAssertLessThan(down.target, 0.8)
        XCTAssertFalse(BlendParty.arcTarget(hold(4, 1), current: 0.8).dip)
        XCTAssertTrue(BlendParty.arcTarget(hold(5, 1), current: 0.8).dip)
    }

    func testFirstFromFirstTenPoolOfEightOthers() {
        for seed in 1..<30 {
            let o = PartyOrder(refs: F.refs(50), rnd: F.seeded(seed))
            XCTAssertTrue(F.refs(BlendParty.startFrom).contains(o.first))
            XCTAssertEqual(o.pool.count, BlendParty.pool)
            XCTAssertFalse(o.pool.contains(o.first))
        }
    }

    func testShortPlaylistPoolIsTheRest() {
        let o = PartyOrder(refs: F.refs(3), rnd: F.seeded())
        XCTAssertEqual(o.pool.count, 2)
    }

    func testEmptyPlaylistIsDone() {
        let o = PartyOrder(refs: [], rnd: F.seeded())
        XCTAssertEqual(o.first, "")
        XCTAssertTrue(o.done)
        XCTAssertNil(o.suggest(elapsedMs: 0, look: { _ in PartyLook(analysis: nil, failed: true) }, planScore: flat))
    }

    func testWholePlaylistExactlyOnce() {
        let all = F.refs(40)
        let o = PartyOrder(refs: all, rnd: F.seeded(7))
        let look = { (r: String) in
            PartyLook(analysis: F.an(r, -12 + Double((Int(r.dropFirst()) ?? 0) % 7)), failed: false)
        }
        var played = [o.first]
        o.commit(o.first, energy: 0.5, elapsedMs: 0)
        while true {
            o.refill { _ in false }
            guard let next = o.suggest(elapsedMs: 0, look: look, planScore: flat) else { break }
            played.append(next)
            o.commit(next, energy: 0.5, elapsedMs: 0)
        }
        XCTAssertEqual(played.count, all.count)
        XCTAssertEqual(Set(played).count, all.count)
        XCTAssertTrue(o.done)
    }

    func testPoolRefillsToEightAliveIgnoringFailed() {
        let o = PartyOrder(refs: F.refs(30), rnd: F.seeded(3))
        let bad = Set(o.pool.prefix(3))
        let added = o.refill { bad.contains($0) }
        XCTAssertEqual(added.count, 3)
        XCTAssertEqual(o.pool.filter { !bad.contains($0) }.count, BlendParty.pool)
    }

    func testPendingAndFailedGoLast() {
        let o = PartyOrder(refs: F.refs(12), rnd: F.seeded(5))
        let failed = o.pool[0]
        let pending = o.pool[1]
        let ready = o.pool[2]
        let look = { (r: String) in
            r == ready ? PartyLook(analysis: F.an(r, -10), failed: false) : PartyLook(analysis: nil, failed: r == failed)
        }
        // есть готовый — берём его, хоть он и третий
        XCTAssertEqual(o.suggest(elapsedMs: 0, look: look, planScore: flat), ready)
        // готовых нет — первый ещё считающийся, сбойный пропускаем
        let noReady = { (r: String) in r == ready ? PartyLook(analysis: nil, failed: true) : look(r) }
        XCTAssertEqual(o.suggest(elapsedMs: 0, look: noReady, planScore: flat), pending)
        // одни сбойные — всё равно играем, по порядку пула
        XCTAssertEqual(o.suggest(elapsedMs: 0, look: { _ in PartyLook(analysis: nil, failed: true) }, planScore: flat), o.pool[0])
    }

    func testBetterPlanWinsAtEqualEnergy() {
        let o = PartyOrder(refs: F.refs(12), rnd: F.seeded(2))
        let a = o.pool[0]
        let b = o.pool[1]
        let look = { (r: String) in PartyLook(analysis: r == a || r == b ? F.an(r, -10) : nil, failed: false) }
        let score = { (n: BlendAnalysis) in n.ref == b ? 0.9 : 0.2 }
        XCTAssertEqual(o.suggest(elapsedMs: 0, look: look, planScore: score), b)
    }

    func testEnergyFollowsArc() throws {
        // 80 треков, энергия вразнобой от тихих до громких; любой переход одинаково хорош
        let all = F.refs(80)
        let loud = Dictionary(uniqueKeysWithValues: all.enumerated().map { i, r in (r, -20 + Double((i * 37) % 80) / 5) })
        let look = { (r: String) in PartyLook(analysis: F.an(r, loud[r] ?? 0), failed: false) }
        let energyOf = { (r: String) in BlendParty.trackEnergy(F.an(r, loud[r] ?? 0)) }
        let o = PartyOrder(refs: all, rnd: F.seeded(11))
        let trackMs = 4.0 * 60_000
        var energies = [energyOf(o.first)]
        o.commit(o.first, energy: energies[0], elapsedMs: 0)
        for i in 1...24 {
            o.refill { _ in false }
            let next = try XCTUnwrap(o.suggest(elapsedMs: Double(i) * trackMs, look: look, planScore: flat))
            energies.append(energyOf(next))
            o.commit(next, energy: energyOf(next), elapsedMs: Double(i) * trackMs)
        }
        // разгон — первые 20 минут (треки 1…5): в среднем растёт и не проваливается
        let warm = Array(energies.prefix(6))
        XCTAssertGreaterThan(warm[5], warm[0])
        for i in 1..<warm.count { XCTAssertGreaterThan(warm[i], warm[i - 1] - 0.05) }
        // дальше — держим, но с провалами: между спадами 5–6 треков
        let hold = Array(energies.dropFirst(6))
        let dropsAt = hold.indices.filter { $0 > 0 && hold[$0] < hold[$0 - 1] - 0.08 }
        XCTAssertGreaterThanOrEqual(dropsAt.count, 2)
        for i in dropsAt.indices.dropFirst() { XCTAssertGreaterThanOrEqual(dropsAt[i] - dropsAt[i - 1], 4) }
    }
}
