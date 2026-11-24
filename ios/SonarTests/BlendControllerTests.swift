import Foundation
import XCTest
@testable import Sonar

// Контроллер сведения на iPhone (docs/BLEND.md §6, §13, §14) — порт `controller.test.ts`, менять — в обоих местах:
// преролл и тихий старт B, A текущий до промоута, промоут без `load()`, пауза, «Следующий», ошибка B, откат при
// поздней загрузке, фаза сходится, выключение не рвёт идущий переход, «Другой момент», «К переходу».

private let step = 0.05

private struct Timeout: Error {}

@MainActor
private final class FakeTimer: BlendTimer {
    private let onCancel: @MainActor () -> Void

    init(_ onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}

/// Дек с ручками сведения: время файла идёт только при игре, кривые — по времени файла, рампы — всегда.
@MainActor
private final class FakeDeck: BlendDeckControl {
    var currentTime = 0.0
    var rate = 1.0
    var preservesPitch = true
    private(set) var isPaused = true
    private(set) var shift = 1.0
    private(set) var ramps: [BlendRamp] = []
    private var automation = BlendDeckAutomation()

    var gain: Double { automation.current.gain }

    func play() { isPaused = false }
    func pause() { isPaused = true }

    func blendStart(_ program: BlendDeckProgram?, echoDelaySec: Double) {
        automation.start(program)
        // как `BlendDeckDSP`: новая программа сразу со своего значения, B не хлопает на старте
        _ = automation.step(ms: currentTime * 1000, dt: 0)
    }

    func blendRamp(_ ramp: BlendRamp) {
        ramps.append(ramp)
        automation.enqueue(ramp)
    }

    func blendShift(_ ratio: Double) { shift = ratio }

    func tick(_ dt: Double) {
        if !isPaused { currentTime += dt * rate }
        _ = automation.step(ms: currentTime * 1000, dt: dt)
    }
}

/// Плеер и часы вокруг контроллера: A играет трек `a`, следующий — `b`.
@MainActor
private final class Rig: BlendHost {
    struct Setup {
        var type = BlendType.bass
        var loadDelaySec = 0.0
        var bpmA = 128.0
        var bpmB = 128.0
        /// Громкость B, LUFS (у A −10): разница даёт поправку громкости B.
        var loudB = -10.0
        /// Тональность B (у A — 0): другая даёт сдвиг тона, который снимается после перехода.
        var keyB = 0
    }

    let setup: Setup
    let analyses: [String: BlendAnalysis]
    let deckA = FakeDeck()
    private(set) var loaded: [FakeDeck] = []
    private(set) var held: [Bool] = []
    private(set) var loads = 0
    private(set) var promoted: [(deck: FakeDeck, listenedMs: Double)] = []
    private(set) var released: [FakeDeck] = []
    var enabled = true
    var nextRef = "b"
    private(set) var ctl: BlendController!
    private var ticks = 0
    private var timers: [Int: (at: Double, run: @MainActor () -> Void)] = [:]
    private var timerSeq = 0
    private var currentDeck: FakeDeck

    init(_ setup: Setup = Setup()) {
        self.setup = setup
        analyses = [
            "a": BlendFixtures.track("a", bpm: setup.bpmA),
            "b": BlendFixtures.track("b", bpm: setup.bpmB, key: setup.keyB, loudness: setup.loudB),
        ]
        currentDeck = deckA
        deckA.play()
        ctl = BlendController(host: self)
    }

    var durMs: Double { analyses["a"]?.durationMs ?? 0 }
    var deckB: FakeDeck? { loaded.first }
    var bPlaying: Bool { deckB.map { !$0.isPaused } ?? false }

    // MARK: BlendHost

    func now() -> Double { Double(ticks) * step }

    func after(_ sec: Double, _ run: @escaping @MainActor () -> Void) -> BlendTimer {
        timerSeq += 1
        let id = timerSeq
        timers[id] = (now() + sec, run)
        return FakeTimer { [weak self] in self?.timers[id] = nil }
    }

    func settings() -> BlendSettings {
        var s = BlendSettings.defaults
        s.type = setup.type
        return s
    }

    func analysis(_ ref: String) -> BlendAnalysis? { analyses[ref] }
    func sound(_ ref: String) -> BlendSound { .none }

    func load(_ ref: String, startSec: Double, done: @escaping @MainActor ((any BlendDeckControl)?) -> Void) {
        loads += 1
        let deck = FakeDeck()
        deck.currentTime = startSec
        loaded.append(deck)
        _ = after(setup.loadDelaySec) { done(deck) }
    }

    func promote(_ deck: any BlendDeckControl, listenedMs: Double) {
        promoted.append((deck as! FakeDeck, listenedMs))
    }

    func release(_ deck: any BlendDeckControl) {
        let d = deck as! FakeDeck
        d.pause()
        released.append(d)
    }

    func hold(_ on: Bool) { held.append(on) }

    // MARK: ход времени

    @discardableResult
    func consider() -> Bool {
        ctl.consider(BlendConsider(
            a: "a", b: nextRef, deckA: deckA, posMs: deckA.currentTime * 1000, durMs: durMs,
            enabled: enabled, rateA: 1, linkedA: false
        ))
    }

    /// Как плеер: шаг времени, тик текущего трека → `consider`, пока A текущий; потом таймеры контроллера.
    /// `player: false` — только часы и таймеры (как `vi.advanceTimersByTimeAsync` на ПК).
    func advance(_ sec: Double, player: Bool = true) {
        for _ in 0 ..< Int((sec / step).rounded()) {
            ticks += 1
            for deck in [deckA] + loaded { deck.tick(step) }
            if player && currentDeck === deckA { consider() }
            fireTimers()
            if let last = promoted.last { currentDeck = last.deck }
        }
    }

    func until(maxSec: Double = 60, _ done: () -> Bool) throws {
        var t = 0.0
        while !done() {
            if t > maxSec { throw Timeout() }
            advance(step)
            t += step
        }
    }

    /// Встать на середину A, дождаться плана и промотать A к самому прероллу.
    func toPreroll() throws {
        deckA.currentTime = 60
        advance(step)
        guard ctl.phase == .planned else { throw Timeout() }
        while ctl.phase == .planned {
            deckA.currentTime += 0.5
            advance(step)
        }
        guard ctl.phase == .prerolling else { throw Timeout() }
    }

    private func fireTimers() {
        let limit = now() + 1e-9
        while let due = timers.filter({ $0.value.at <= limit }).min(by: { ($0.value.at, $0.key) < ($1.value.at, $1.key) }) {
            timers[due.key] = nil
            due.value.run()
        }
    }
}

@MainActor
final class BlendControllerTests: XCTestCase {
    func testNotTakenWithoutAnalysisShortTrackNoNextOrDisabled() {
        let s = Rig()
        let base = BlendConsider(
            a: "a", b: "b", deckA: s.deckA, posMs: 0, durMs: 200_000, enabled: true, rateA: 1, linkedA: false
        )
        var noAnalysis = base
        noAnalysis.a = "x"
        var short = base
        short.durMs = 30_000
        var off = base
        off.enabled = false
        var noNext = base
        noNext.b = nil
        for c in [noAnalysis, short, off, noNext] {
            XCTAssertFalse(s.ctl.consider(c))
        }
        XCTAssertEqual(s.ctl.phase, .idle)
    }

    func testFullRunSilentBPromoteWithoutLoadThenRest() throws {
        let s = Rig()
        try s.toPreroll()
        XCTAssertEqual(s.held, [true])
        XCTAssertEqual(s.loads, 1)
        let plan = try XCTUnwrap(s.ctl.current).plan
        XCTAssertEqual(plan.kind, .bass)
        var maxEarlyGain = 0.0
        try s.until {
            if s.bPlaying, s.deckA.currentTime * 1000 < plan.outMs, let b = s.deckB {
                maxEarlyGain = max(maxEarlyGain, b.gain)
            }
            return !s.promoted.isEmpty
        }
        // до начала перехода B уже играет (синк сходится), но не слышен
        XCTAssertLessThan(maxEarlyGain, 0.05)
        XCTAssertEqual(s.loads, 1)
        XCTAssertEqual(s.promoted.count, 1)
        let first = try XCTUnwrap(s.promoted.first)
        XCTAssertTrue(first.deck === s.deckB)
        XCTAssertGreaterThan(first.listenedMs, 1000)
        // доведённый переход просят оценить
        XCTAssertEqual(s.ctl.done?.from, "a")
        XCTAssertEqual(s.ctl.done?.to, "b")
        XCTAssertEqual(s.ctl.done?.kind, plan.kind)
        XCTAssertGreaterThanOrEqual(s.deckA.currentTime * 1000, plan.endAMs - 60)
        s.advance(1)
        XCTAssertTrue(s.released.contains { $0 === s.deckA })
        XCTAssertTrue(s.deckA.isPaused)
        s.advance(1)
        XCTAssertEqual(s.ctl.phase, .idle)
        XCTAssertEqual(s.held, [true, false])
        XCTAssertTrue(s.bPlaying)
        let b = try XCTUnwrap(s.deckB)
        XCTAssertEqual(b.rate, 1)
        XCTAssertEqual(b.shift, 1)
        s.advance(3)
        XCTAssertEqual(b.gain, 1, accuracy: 1e-6)
    }

    func testPhaseConvergesAfterThirtyMsDrift() throws {
        let s = Rig(.init(bpmB: 126))
        try s.toPreroll()
        try s.until { s.bPlaying }
        s.advance(0.5)
        let b = try XCTUnwrap(s.deckB)
        b.currentTime += 0.03
        s.advance(step)
        XCTAssertGreaterThan(s.ctl.phaseErrMs, 20)
        s.advance(3)
        XCTAssertTrue(s.promoted.isEmpty)
        XCTAssertLessThanOrEqual(abs(s.ctl.phaseErrMs), 10)
    }

    func testBigPhaseErrorSeeksInsteadOfChasingByRate() throws {
        let s = Rig()
        try s.toPreroll()
        try s.until { s.bPlaying }
        let b = try XCTUnwrap(s.deckB)
        b.currentTime += 0.5
        s.advance(step)
        s.advance(step)
        XCTAssertLessThan(abs(s.ctl.phaseErrMs), 30)
    }

    func testPauseStopsBAndResumePlaysB() throws {
        let s = Rig()
        try s.toPreroll()
        try s.until { s.bPlaying }
        s.deckA.pause()
        s.ctl.pause()
        let b = try XCTUnwrap(s.deckB)
        XCTAssertTrue(b.isPaused)
        let at = b.currentTime
        s.advance(2)
        XCTAssertEqual(b.currentTime, at)
        XCTAssertTrue(s.promoted.isEmpty)
        s.deckA.play()
        s.ctl.resume()
        s.advance(step)
        XCTAssertFalse(b.isPaused)
    }

    func testCancelBeforePromoteFadesBAndRestoresA() throws {
        let s = Rig(.init(bpmB: 124))
        try s.toPreroll()
        try s.until { s.bPlaying }
        s.advance(3)
        XCTAssertNotEqual(s.deckA.rate, 1)
        s.ctl.cancel()
        XCTAssertEqual(s.ctl.phase, .idle)
        XCTAssertEqual(s.held.last, false)
        XCTAssertEqual(s.deckA.rate, 1)
        s.advance(0.3, player: false)
        XCTAssertEqual(s.deckA.gain, 1, accuracy: 1e-9)
        s.advance(0.1, player: false)
        let b = try XCTUnwrap(s.deckB)
        XCTAssertTrue(s.released.contains { $0 === b })
        XCTAssertTrue(s.promoted.isEmpty)
        // сорванный переход оценить не просят
        XCTAssertNil(s.ctl.done)
    }

    func testNextBeforeBStartsIsPlainSkip() throws {
        let s = Rig()
        try s.toPreroll()
        XCTAssertFalse(s.ctl.finishNow())
        XCTAssertEqual(s.ctl.phase, .idle)
        XCTAssertTrue(s.promoted.isEmpty)
    }

    func testNextWhileBPlaysPromotesAndFadesA() throws {
        let s = Rig()
        try s.toPreroll()
        try s.until { s.bPlaying }
        XCTAssertTrue(s.ctl.finishNow())
        XCTAssertEqual(s.promoted.count, 1)
        XCTAssertEqual(s.deckA.ramps.last, .gain(0, seconds: BlendController.cancelSec))
        // A гаснет за 300 мс; на 300-й мс его отпускают и кладут цепочку в покой (дек уже на паузе)
        s.advance(0.25, player: false)
        XCTAssertLessThan(s.deckA.gain, 0.2)
        s.advance(0.25, player: false)
        XCTAssertTrue(s.released.contains { $0 === s.deckA })
        XCTAssertTrue(s.deckA.isPaused)
    }

    func testNextAfterPromoteAbortRestsBothChains() throws {
        let s = Rig(.init(type: .echo))
        try s.toPreroll()
        try s.until { !s.promoted.isEmpty }
        XCTAssertEqual(s.ctl.phase, .promoting)
        XCTAssertFalse(s.ctl.finishNow())
        s.ctl.abort()
        XCTAssertEqual(s.ctl.phase, .idle)
        XCTAssertTrue(s.released.contains { $0 === s.deckA })
        let b = try XCTUnwrap(s.deckB)
        XCTAssertEqual(s.deckA.gain, 1)
        XCTAssertEqual(b.gain, 1)
        XCTAssertEqual(b.shift, 1)
        XCTAssertEqual(s.held, [true, false])
    }

    func testDelayedReleaseOfOldBDoesNotTouchNewPreroll() throws {
        let s = Rig()
        try s.toPreroll()
        try s.until { s.bPlaying }
        let old = try XCTUnwrap(s.deckB)
        s.ctl.cancel()
        s.ctl.abort()
        XCTAssertFalse(s.released.contains { $0 === old })
        s.deckA.currentTime = 60
        s.advance(step)
        while s.ctl.phase == .planned {
            s.deckA.currentTime += 0.5
            s.advance(step)
        }
        XCTAssertEqual(s.released.count, 1)
        XCTAssertTrue(s.released.first === old)
        s.advance(1)
        XCTAssertEqual(s.released.count, 1)
        XCTAssertTrue(s.released.first === old)
    }

    func testBErrorBeforePromoteKeepsAAndSkipsPair() throws {
        let s = Rig()
        try s.toPreroll()
        try s.until { s.bPlaying }
        let b = try XCTUnwrap(s.deckB)
        XCTAssertTrue(s.ctl.onDeckError(b))
        XCTAssertEqual(s.ctl.phase, .idle)
        XCTAssertFalse(s.deckA.isPaused)
        XCTAssertFalse(s.consider())
    }

    func testLateLoadFallsBackToCrossfade() throws {
        let s = Rig(.init(loadDelaySec: 12))
        try s.toPreroll()
        try s.until { s.ctl.phase == .fallback }
        XCTAssertTrue(s.promoted.isEmpty)
        XCTAssertEqual(s.held, [true, false])
        XCTAssertEqual(s.released.count, 1)
        XCTAssertFalse(s.consider())
    }

    func testDisablingDuringTransitionLetsItFinish() throws {
        let s = Rig()
        try s.toPreroll()
        try s.until { s.ctl.phase == .running }
        s.enabled = false
        try s.until { !s.promoted.isEmpty }
        XCTAssertEqual(s.promoted.count, 1)
    }

    func testCancelWhileShiftSettlesKeepsBGainAndPitch() throws {
        let s = Rig(.init(loudB: -6, keyB: 2))
        try s.toPreroll()
        try s.until { s.held.count == 2 }
        // рампы B после перехода: 1 с к своей громкости и 2 с к полной (запас на шаг)
        s.advance(3.1)
        XCTAssertEqual(s.ctl.phase, .promoting)
        let b = try XCTUnwrap(s.deckB)
        XCTAssertEqual(b.gain, 1, accuracy: 1e-6)
        s.ctl.cancel()
        s.advance(0.3, player: false)
        XCTAssertEqual(b.gain, 1, accuracy: 1e-6)
        XCTAssertEqual(s.held, [true, false])
    }

    func testBRemovedFromQueueDuringTransitionFadesOut() throws {
        let s = Rig()
        try s.toPreroll()
        try s.until { s.bPlaying }
        s.nextRef = "c"
        s.advance(step)
        XCTAssertEqual(s.ctl.phase, .idle)
        s.advance(1)
        XCTAssertTrue(s.promoted.isEmpty)
        let b = try XCTUnwrap(s.deckB)
        XCTAssertTrue(s.released.contains { $0 === b })
    }

    func testAnotherMomentTakesNextPlanAndKeepsItAfterSeek() throws {
        let s = Rig()
        s.deckA.currentTime = 60
        s.advance(step)
        let first = try XCTUnwrap(s.ctl.next)
        XCTAssertEqual(first.rank, 1)
        XCTAssertGreaterThan(first.total, 1)
        XCTAssertTrue(s.ctl.another())
        let second = try XCTUnwrap(s.ctl.next)
        XCTAssertGreaterThan(second.rank, 1)
        XCTAssertFalse(BlendController.sameMoment(first.plan, second.plan))
        // перемотка сбрасывает план, следующий расчёт берёт выбранный момент
        s.ctl.cancel()
        XCTAssertNil(s.ctl.next)
        s.deckA.currentTime = 61
        s.advance(step)
        let again = try XCTUnwrap(s.ctl.next)
        XCTAssertEqual(again.plan.outMs, second.plan.outMs)
        XCTAssertEqual(again.plan.inMs, second.plan.inMs)
    }

    func testAnotherMomentDuringPrerollRebuildsPair() throws {
        let s = Rig()
        try s.toPreroll()
        let before = try XCTUnwrap(s.ctl.next).plan
        XCTAssertTrue(s.ctl.another())
        XCTAssertEqual(s.ctl.phase, .idle)
        s.advance(step)
        let after = try XCTUnwrap(s.ctl.next).plan
        XCTAssertNotEqual(after, before)
    }

    func testPreviewStandsEightSecondsBeforeBStartSamePlan() throws {
        for bpm in [128.0, 64.0] {
            let s = Rig(.init(bpmA: bpm, bpmB: bpm))
            s.deckA.currentTime = 30
            s.advance(step)
            let plan = try XCTUnwrap(s.ctl.next).plan
            let at = try XCTUnwrap(s.ctl.previewAtMs())
            let barMs = 240_000 / bpm
            let startBar = BlendTimeline.startBar(plan, BlendFixtures.track("b", bpm: bpm))
            XCTAssertEqual(at, plan.outMs + startBar * barMs - 8000, accuracy: 1e-6, "\(bpm)")
            s.ctl.cancel()
            s.deckA.currentTime = at / 1000
            s.advance(step)
            XCTAssertEqual(try XCTUnwrap(s.ctl.next).plan.outMs, plan.outMs, "\(bpm)")
            XCTAssertFalse(s.ctl.failedFor("a", "b"))
        }
    }

    func testAnotherAndPreviewOffOnceRunning() throws {
        let s = Rig()
        try s.toPreroll()
        try s.until { s.ctl.phase == .running }
        XCTAssertFalse(s.ctl.another())
        XCTAssertNil(s.ctl.previewAtMs())
    }

    func testBErrorMarksPairForCrossfadeCard() throws {
        let s = Rig()
        try s.toPreroll()
        try s.until { s.bPlaying }
        XCTAssertFalse(s.ctl.failedFor("a", "b"))
        s.ctl.onDeckError(try XCTUnwrap(s.deckB))
        XCTAssertTrue(s.ctl.failedFor("a", "b"))
        XCTAssertFalse(s.ctl.failedFor("a", "c"))
    }

    func testDisablingBeforeBStartsDropsPlanQuietly() throws {
        let s = Rig(.init(loadDelaySec: 5))
        try s.toPreroll()
        s.enabled = false
        s.advance(step)
        XCTAssertEqual(s.ctl.phase, .idle)
        XCTAssertEqual(s.held, [true, false])
    }

    func testSemitoneRatio() {
        XCTAssertEqual(BlendController.ratio(semitones: 12), 2, accuracy: 1e-12)
        XCTAssertEqual(BlendController.ratio(semitones: 0), 1)
    }
}
