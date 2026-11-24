import Foundation
import Observation

// Контроллер сведения на iPhone (docs/BLEND.md §6, §13) — порт `windows/src/player/blend/controller.svelte.ts`,
// менять — в обоих местах и в тестах (`BlendControllerTests` ↔ `controller.test.ts`).
//
// Отличия от ПК: кривые не кладутся рампами по часам, а считаются в деке по времени файла (`BlendDeckProgram`),
// поэтому нет `schedule` / `freeze`; при уходе фазы B — просто перемотка (провал громкости на ПК закрывает
// щелчок рамп Web Audio, тут дек сам плавный); свой звук трека B (`sound`) берётся сразу, без ожидания.

enum BlendPhase: String, Sendable {
    case idle, planned, prerolling, running, promoting, fallback
}

/// Свой звук трека (`track_pref.sound`): скорость, тон в полутонах, связана ли высота со скоростью.
struct BlendSound: Hashable, Sendable {
    var rate: Double
    var pitch: Double
    var linked: Bool

    static let none = BlendSound(rate: 1, pitch: 0, linked: false)
}

@MainActor
protocol BlendTimer: AnyObject {
    func cancel()
}

/// Дек плеера глазами контроллера: элемент со временем и скоростью плюс цепочка сведения.
@MainActor
protocol BlendDeckControl: AnyObject {
    var currentTime: Double { get set }
    var rate: Double { get set }
    /// Скорость без смены высоты (у связанного трека — как пластинка).
    var preservesPitch: Bool { get set }
    var isPaused: Bool { get }
    func play()
    func pause()
    /// Новая программа кривых (nil — дек снова обычный).
    func blendStart(_ program: BlendDeckProgram?, echoDelaySec: Double)
    func blendRamp(_ ramp: BlendRamp)
    /// Сдвиг тона сведения, множитель частоты.
    func blendShift(_ ratio: Double)
}

@MainActor
protocol BlendHost: AnyObject {
    /// Монотонные часы, с.
    func now() -> Double
    func after(_ sec: Double, _ run: @escaping @MainActor () -> Void) -> BlendTimer
    func settings() -> BlendSettings
    /// Готовый анализ или nil (тогда хозяин сам ставит трек в очередь анализа).
    func analysis(_ ref: String) -> BlendAnalysis?
    func sound(_ ref: String) -> BlendSound
    /// Загрузить трек во второй дек на паузе с позиции `startSec`; nil — не вышло.
    func load(_ ref: String, startSec: Double, done: @escaping @MainActor ((any BlendDeckControl)?) -> Void)
    /// B стал текущим; он играет уже `listenedMs`.
    func promote(_ deck: any BlendDeckControl, listenedMs: Double)
    /// Дек больше не нужен: остановить (хвост эха уже отзвучал или срезан рампой).
    func release(_ deck: any BlendDeckControl)
    /// Выравниватель громкости не трогает деки, пока идёт переход.
    func hold(_ on: Bool)
}

/// Что плеер знает на каждом тике текущего трека.
struct BlendConsider {
    var a: String
    var b: String?
    var deckA: any BlendDeckControl
    var posMs: Double
    var durMs: Double
    var enabled: Bool
    var rateA: Double
    var linkedA: Bool
}

struct BlendCurrent: Hashable, Sendable {
    var from: String
    var to: String
    var plan: TransitionPlan
}

struct BlendNext: Hashable, Sendable {
    var from: String
    var to: String
    var plan: TransitionPlan
    /// Место в топе планировщика, с 1.
    var rank: Int
    var total: Int
}

struct BlendDone: Hashable, Sendable {
    var from: String
    var to: String
    var kind: BlendKind
}

@Observable
@MainActor
final class BlendController {
    static let tickSec = 0.05
    static let prerollSec = 8.0
    static let minLeadSec = 1.5
    static let playLeadSec = 0.15
    static let minTrackMs = 60_000.0
    static let phaseOkMs = 8.0
    static let phaseSeekMs = 120.0
    static let corrMin = 0.005
    static let corrMax = 0.02
    static let cancelSec = 0.3
    static let gainSettleSec = 2.0
    static let shiftSettleBars = 8.0
    static let aRestSec = 1.0
    static let rateEps = 1e-4

    /// Пара A → B с выбранным планом.
    private struct Pair {
        let a: String
        let b: String
        let deckA: any BlendDeckControl
        let anA: BlendAnalysis
        let anB: BlendAnalysis
        /// Пара, скорость A и настройки — поменялось что-то из этого, план считается заново.
        let key: String
        let settings: BlendSettings
        let rateA: Double
        let soundB: BlendSound
        let plan: TransitionPlan
        let curves: BlendCurves
        let gainMul: Double
        let bStartBar: Double

        var pairKey: String { "\(a)>\(b)" }

        func with(plan: TransitionPlan) -> Pair {
            Pair(
                a: a, b: b, deckA: deckA, anA: anA, anB: anB, key: key, settings: settings, rateA: rateA,
                soundB: soundB, plan: plan,
                curves: BlendMix.curvesFor(plan, nyquist: BlendDeckAutomation.nyquist),
                gainMul: pow(10, plan.gainDb / 20),
                bStartBar: BlendTimeline.startBar(plan, anB)
            )
        }
    }

    /// Идущий переход. Класс, как объект на ПК: отложенные дела держат его и после `reset()`.
    private final class Live {
        var deckB: (any BlendDeckControl)?
        var bPlaying = false
        var bStartedAt = 0.0
        var promoted = false
        var aReleased = false
        var bar: Double
        var lastNow: Double
        var settleFrom: Double?
        var paused = false
        var bWasPlaying = false

        init(bar: Double, lastNow: Double) {
            self.bar = bar
            self.lastNow = lastNow
        }
    }

    private(set) var phase = BlendPhase.idle
    private(set) var current: BlendCurrent?
    private(set) var next: BlendNext?
    private(set) var phaseErrMs = 0.0
    private(set) var done: BlendDone?

    @ObservationIgnored private unowned let host: any BlendHost
    @ObservationIgnored private var pair: Pair?
    @ObservationIgnored private var live: Live?
    @ObservationIgnored private var failed: String?
    @ObservationIgnored private var options: [TransitionPlan] = []
    @ObservationIgnored private var prefer: (pairKey: String, plan: TransitionPlan)?
    @ObservationIgnored private var token = 0
    @ObservationIgnored private var timer: BlendTimer?
    @ObservationIgnored private var jobs: [Int: (timer: BlendTimer, run: @MainActor () -> Void)] = [:]
    @ObservationIgnored private var jobSeq = 0

    init(host: any BlendHost) {
        self.host = host
    }

    static func ratio(semitones: Double) -> Double {
        pow(2, semitones / 12)
    }

    // MARK: - снаружи

    /// Каждый тик текущего трека. true — переход запланирован или идёт.
    @discardableResult
    func consider(_ c: BlendConsider) -> Bool {
        if started() {
            // очередь поменяли, пока B ещё не текущий: B уже не следующий — переход гасим
            if live?.promoted != true && c.b != pair?.b {
                cancel()
                return false
            }
            return true
        }
        guard c.enabled, let b = c.b, c.durMs >= Self.minTrackMs else { return drop() }
        let pairKey = "\(c.a)>\(b)"
        if failed == pairKey { return false }
        let key = "\(pairKey)|\(c.rateA)|\(c.linkedA)"
        let settings = host.settings()
        if let pair, pair.key != key || pair.settings != settings { drop() }
        guard pair != nil else { return prepare(c, b: b, key: key, settings: settings) }
        if phase == .planned && prerollDue(c.posMs) { preroll() }
        return true
    }

    /// Пауза: деки и часы перехода стоят (кривые идут по времени файла — им стоять не надо).
    func pause() {
        guard let l = live, !l.paused, l.settleFrom == nil else { return }
        l.paused = true
        stopTimer()
        l.bWasPlaying = l.deckB != nil && !l.promoted && l.deckB?.isPaused == false
        if l.bWasPlaying { l.deckB?.pause() }
    }

    func resume() {
        guard let l = live, l.paused else { return }
        l.paused = false
        l.lastNow = host.now()
        if l.bWasPlaying { l.deckB?.play() }
        loop()
    }

    /// Отменить переход (перемотка, «Следующий», выключили): A возвращается, B затихает.
    func cancel() {
        guard let pair, let l = live else {
            reset()
            return
        }
        if l.settleFrom != nil { return }
        if l.promoted {
            wrapUp(Self.cancelSec)
            return
        }
        if let deckB = l.deckB {
            deckB.blendRamp(.gain(0, seconds: Self.cancelSec))
            later(Self.cancelSec) { [weak self] in self?.host.release(deckB) }
        }
        pair.deckA.blendRamp(.values(pair.curves.rest, seconds: Self.cancelSec))
        setRate(pair.deckA, pair.rateA)
        reset()
    }

    /// «Сразу к B»: false — B ещё не играет (тогда переход отменён) или уже текущий.
    @discardableResult
    func finishNow() -> Bool {
        if live?.promoted == true { return false }
        guard live?.bPlaying == true else {
            cancel()
            return false
        }
        promote()
        wrapUp(Self.cancelSec)
        return true
    }

    /// Жёсткий стоп (трек сменили вручную после промоута): всё в покой сразу.
    func abort() {
        guard let pair, let l = live, l.promoted else {
            cancel()
            return
        }
        releaseA(l, pair.deckA)
        pair.deckA.blendStart(nil, echoDelaySec: 0)
        l.deckB?.blendStart(nil, echoDelaySec: 0)
        l.deckB?.blendShift(1)
        reset()
    }

    /// Ошибка элемента дека. true — сведение обработало её само.
    @discardableResult
    func onDeckError(_ deck: any BlendDeckControl) -> Bool {
        guard let pair, let l = live else { return false }
        if let deckB = l.deckB, deckB === deck, !l.promoted {
            failed = pair.pairKey
            cancel()
            return true
        }
        if pair.deckA === deck && l.promoted {
            releaseA(l, pair.deckA)
            return true
        }
        return false
    }

    /// «Другой момент»: следующий план из топа, у которого старт ещё впереди.
    @discardableResult
    func another() -> Bool {
        guard let pair, !started() else { return false }
        let posMs = pair.deckA.currentTime * 1000
        let plans = options
        let n = plans.count
        guard let from = plans.firstIndex(of: pair.plan), n > 1 else { return false }
        for k in 1 ..< n {
            let p = plans[(from + k) % n]
            guard Self.ahead(p, pair.anA, pair.anB, posMs: posMs, rateA: pair.rateA) else { continue }
            prefer = (pair.pairKey, p)
            if live != nil {
                drop()
            } else {
                setPair(pair.with(plan: p))
            }
            return true
        }
        return false
    }

    /// С какой мс A слушать предпросмотр перехода (за 8 с до старта B).
    func previewAtMs() -> Double? {
        guard let pair, !started() else { return nil }
        return max(0, Self.prerollAtMs(pair))
    }

    /// Переход идёт (B играет или уже текущий).
    var isActive: Bool { started() }

    func failedFor(_ a: String, _ b: String) -> Bool {
        failed == "\(a)>\(b)"
    }

    // MARK: - план

    private func started() -> Bool {
        phase == .running || phase == .promoting
    }

    private func prepare(_ c: BlendConsider, b: String, key: String, settings: BlendSettings) -> Bool {
        guard let anA = host.analysis(c.a), let anB = host.analysis(b) else { return false }
        let soundB = host.sound(b)
        let opts = PlanOpts(
            type: settings.type, lengthSec: settings.lengthSec, cutSec: settings.cutSec,
            tempoTolPct: settings.tempoTolPct, keyShift: settings.keyShift,
            rateA: c.rateA, rateB: soundB.rate, linkedA: c.linkedA, linkedB: soundB.linked, ratings: settings.ratings
        )
        options = BlendPlanner.plan(anA, anB, opts: opts)
        let pairKey = "\(c.a)>\(b)"
        // первый из топа, у которого старт B ещё впереди (§7.1), или момент, выбранный «Другим моментом»
        let fits = options.filter { Self.ahead($0, anA, anB, posMs: c.posMs, rateA: c.rateA) }
        let wanted = prefer.flatMap { p in p.pairKey == pairKey ? fits.first { Self.sameMoment($0, p.plan) } : nil }
        guard let plan = wanted ?? fits.first else {
            setPair(nil)
            failed = pairKey
            return true
        }
        let chosen = Pair(
            a: c.a, b: b, deckA: c.deckA, anA: anA, anB: anB, key: key, settings: settings, rateA: c.rateA,
            soundB: soundB, plan: plan,
            curves: BlendMix.curvesFor(plan, nyquist: BlendDeckAutomation.nyquist),
            gainMul: pow(10, plan.gainDb / 20),
            bStartBar: BlendTimeline.startBar(plan, anB)
        )
        setPair(chosen)
        phase = .planned
        return true
    }

    private func setPair(_ p: Pair?) {
        pair = p
        next = p.map { p in
            BlendNext(
                from: p.a, to: p.b, plan: p.plan,
                rank: (options.firstIndex(of: p.plan) ?? 0) + 1, total: options.count
            )
        }
    }

    private static func prerollAtMs(_ pair: Pair) -> Double {
        pair.plan.outMs + pair.bStartBar * BlendPlanner.barMs(pair.anA) - prerollSec * 1000 * pair.rateA
    }

    private func prerollDue(_ posMs: Double) -> Bool {
        guard let pair else { return false }
        return posMs >= Self.prerollAtMs(pair)
    }

    static func sameMoment(_ x: TransitionPlan, _ y: TransitionPlan) -> Bool {
        x.kind == y.kind && x.outMs == y.outMs && x.inMs == y.inMs
    }

    /// Старт B ещё впереди хотя бы на полторы секунды.
    static func ahead(_ plan: TransitionPlan, _ anA: BlendAnalysis, _ anB: BlendAnalysis, posMs: Double, rateA: Double) -> Bool {
        plan.outMs + BlendTimeline.startBar(plan, anB) * BlendPlanner.barMs(anA) - posMs >= minLeadSec * 1000 * rateA
    }

    // MARK: - ход перехода

    private func preroll() {
        guard let pair else { return }
        flush()
        phase = .prerolling
        current = BlendCurrent(from: pair.a, to: pair.b, plan: pair.plan)
        live = Live(bar: barOfA(pair), lastNow: host.now())
        host.hold(true)
        let token = token
        let startSec = BlendTimeline.expectedB(pair.plan, pair.anB, bar: pair.bStartBar) / 1000
        host.load(pair.b, startSec: max(0, startSec)) { [weak self] deck in
            self?.loaded(token, deck)
        }
        loop()
    }

    private func loaded(_ token: Int, _ deck: (any BlendDeckControl)?) {
        guard token == self.token, let pair, let l = live else {
            if let deck { host.release(deck) }
            return
        }
        // не загрузился или загрузился, когда старт B уже прошёл, — обычная смена трека
        guard let deck, l.bar <= pair.bStartBar else {
            if let deck { host.release(deck) }
            failed = pair.pairKey
            reset()
            phase = .fallback
            return
        }
        l.deckB = deck
        pair.deckA.blendStart(
            BlendDeckProgram(curves: pair.curves, side: .a, gainMul: 1, map: .a(pair.plan, pair.anA)),
            echoDelaySec: pair.curves.echoDelaySec
        )
        deck.blendStart(
            BlendDeckProgram(curves: pair.curves, side: .b, gainMul: pair.gainMul, map: .b(pair.plan, pair.anB)),
            echoDelaySec: pair.curves.echoDelaySec
        )
        deck.preservesPitch = !pair.soundB.linked
        setRate(deck, rateB(pair, bar: max(0, pair.bStartBar)))
        deck.blendShift(Self.ratio(semitones: pair.plan.shift))
    }

    private func loop() {
        stopTimer()
        timer = host.after(Self.tickSec) { [weak self] in
            guard let self else { return }
            self.timer = nil
            self.tick()
            if let l = self.live, !l.paused, self.timer == nil { self.loop() }
        }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard let pair, let l = live else { return }
        let now = host.now()
        if let from = l.settleFrom {
            settle(pair, from: from, now: now)
            return
        }
        let secPerBar = advance(pair, l, now: now)
        if !l.promoted { syncA(pair, bar: l.bar) }
        guard let deckB = l.deckB else { return }
        if !l.bPlaying && (pair.bStartBar - l.bar) * secPerBar <= Self.playLeadSec {
            startB(pair, deckB)
        }
        guard let after = live else { return }
        if after.bPlaying && phase == .prerolling && after.bar >= min(0, pair.bStartBar) { phase = .running }
        if after.bPlaying && !after.promoted { syncB(pair, deckB, bar: after.bar) }
        if after.bPlaying && !after.promoted && after.bar >= pair.curves.promoteBar { promote() }
        if let end = live, end.promoted, end.settleFrom == nil, end.bar >= pair.curves.endBar {
            wrapUp(Self.aRestSec)
        }
    }

    /// Такт сейчас: до промоута — по A, после — по часам и темпу перехода. Возвращает секунд на такт.
    private func advance(_ pair: Pair, _ l: Live, now: Double) -> Double {
        if !l.promoted {
            l.bar = barOfA(pair)
            l.lastNow = now
            let rate = pair.deckA.rate
            return BlendPlanner.barMs(pair.anA) / 1000 / (rate > 0 ? rate : 1)
        }
        let secPerBar = 240 / (BlendMix.tempoAt(pair.plan, bar: l.bar) ?? pair.plan.tempoA)
        l.bar += (now - l.lastNow) / secPerBar
        l.lastNow = now
        return secPerBar
    }

    private func barOfA(_ pair: Pair) -> Double {
        (pair.deckA.currentTime * 1000 - pair.plan.outMs) / BlendPlanner.barMs(pair.anA)
    }

    private func syncA(_ pair: Pair, bar: Double) {
        guard let tempo = BlendMix.tempoAt(pair.plan, bar: bar) else { return }
        setRate(pair.deckA, tempo / pair.anA.bpm)
    }

    private func rateB(_ pair: Pair, bar: Double) -> Double {
        guard let tempo = BlendMix.tempoAt(pair.plan, bar: bar) else { return pair.soundB.rate }
        return tempo * pair.plan.beatRatio / pair.anB.bpm
    }

    private func startB(_ pair: Pair, _ deck: any BlendDeckControl) {
        guard let l = live else { return }
        let atMs = BlendTimeline.expectedB(pair.plan, pair.anB, bar: l.bar)
        if atMs < 0 { return }
        deck.currentTime = atMs / 1000
        l.bPlaying = true
        l.bStartedAt = host.now()
        deck.play()
    }

    /// Доли B держатся за сеткой перехода: мелкий уход — подстройкой скорости, крупный — перемоткой.
    private func syncB(_ pair: Pair, _ deck: any BlendDeckControl, bar: Double) {
        let base = rateB(pair, bar: bar)
        guard pair.plan.sync else {
            setRate(deck, base)
            return
        }
        let wantMs = BlendTimeline.expectedB(pair.plan, pair.anB, bar: bar)
        let rate = deck.rate > 0 ? deck.rate : 1
        let errMs = (deck.currentTime * 1000 - wantMs) / rate
        phaseErrMs = errMs
        if abs(errMs) > Self.phaseSeekMs && wantMs >= 0 {
            deck.currentTime = wantMs / 1000
            setRate(deck, base)
            return
        }
        if abs(errMs) <= Self.phaseOkMs {
            setRate(deck, base)
            return
        }
        let corr = BlendMath.clamp(errMs / 1000, -Self.corrMax, Self.corrMax)
        let sign: Double = corr > 0 ? 1 : -1
        setRate(deck, base * (1 - sign * max(Self.corrMin, abs(corr))))
    }

    /// B стал текущим: плеер принимает играющий дек; A догорает по кривой и через 300 мс освобождается.
    private func promote() {
        guard let pair, let l = live, let deckB = l.deckB else { return }
        let deckA = pair.deckA
        l.promoted = true
        phase = .promoting
        done = BlendDone(from: pair.a, to: pair.b, kind: pair.plan.kind)
        host.promote(deckB, listenedMs: (host.now() - l.bStartedAt) * 1000)
        later(Self.cancelSec) { [weak self] in self?.releaseA(l, deckA) }
    }

    private func releaseA(_ l: Live, _ deckA: any BlendDeckControl) {
        if l.aReleased { return }
        l.aReleased = true
        host.release(deckA)
    }

    /// Конец перехода: A уходит в тишину и отпускается, B — к полной громкости и своей скорости.
    private func wrapUp(_ sec: Double) {
        guard let pair, let l = live else { return }
        let deckA = pair.deckA
        deckA.blendRamp(.gain(0, seconds: sec))
        later(sec) { [weak self] in
            self?.releaseA(l, deckA)
            deckA.blendStart(nil, echoDelaySec: 0)
        }
        if let deckB = l.deckB {
            deckB.blendRamp(.values(pair.curves.rest.with(.gain, pair.gainMul), seconds: sec))
            deckB.blendRamp(.gain(1, seconds: Self.gainSettleSec))
            setRate(deckB, pair.soundB.rate)
        }
        host.hold(false)
        l.settleFrom = host.now()
        l.paused = false
        if timer == nil { loop() }
    }

    /// После перехода сдвиг тона B плавно уходит за 8 тактов.
    private func settle(_ pair: Pair, from: Double, now: Double) {
        let sec = Self.shiftSettleBars * 240 / pair.plan.tempoB
        let x = pair.plan.shift != 0 ? (now - from) / sec : 1
        live?.deckB?.blendShift(x >= 1 ? 1 : Self.ratio(semitones: pair.plan.shift * (1 - x)))
        if x >= 1 { reset() }
    }

    // MARK: - отложенные дела

    private func later(_ sec: Double, _ run: @escaping @MainActor () -> Void) {
        jobSeq += 1
        let id = jobSeq
        let t = host.after(sec) { [weak self] in self?.runJob(id) }
        jobs[id] = (t, run)
    }

    private func runJob(_ id: Int) {
        guard let job = jobs.removeValue(forKey: id) else { return }
        job.run()
    }

    /// Отложенное прошлого перехода — сейчас (новый не ждёт, пока старый B отпустят).
    private func flush() {
        for id in jobs.keys.sorted() {
            guard let job = jobs.removeValue(forKey: id) else { continue }
            job.timer.cancel()
            job.run()
        }
    }

    @discardableResult
    private func drop() -> Bool {
        if let deckB = live?.deckB { host.release(deckB) }
        reset()
        return false
    }

    private func reset() {
        let held = live != nil && live?.settleFrom == nil
        token += 1
        stopTimer()
        setPair(nil)
        live = nil
        current = nil
        phase = .idle
        phaseErrMs = 0
        if held { host.hold(false) }
    }

    private func setRate(_ deck: any BlendDeckControl, _ rate: Double) {
        if abs(deck.rate - rate) > Self.rateEps { deck.rate = rate }
    }
}
