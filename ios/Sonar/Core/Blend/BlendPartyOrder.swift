import Foundation

// Порядок «Свести для вечеринки» (docs/BLEND.md §9) — порт `windows/src/player/blend/party-core.ts`, менять — в
// обоих местах и в тестах. Старт — случайный из первых 10, дальше из пула в 8 случайных треков выбирается
// лучший по плану перехода и по дуге энергии. Первые 20 минут энергия растёт, потом держится с короткими
// провалами раз в 5–6 треков. Чистый модуль: обвязка с плеером и анализом — отдельно.

/// Состояние дуги энергии вечеринки.
struct ArcState: Hashable, Sendable {
    var elapsedMs: Double
    /// Треков после разгона с прошлого провала.
    var sinceDip: Int
    var dips: Int
    /// Самая высокая энергия за вечер.
    var peak: Double
}

/// Что известно о кандидате: готовый анализ или nil — ещё считается / сбой.
struct PartyLook: Sendable {
    var analysis: BlendAnalysis?
    var failed: Bool
}

enum BlendParty {
    static let prefix = "party:"
    /// Сколько первых треков плейлиста годятся в старт.
    static let startFrom = 10
    /// Сколько живых (не сбойных) кандидатов держим в пуле и считаем заранее.
    static let pool = 8
    /// Разгон: столько энергия только растёт.
    static let warmupMs = 20.0 * 60_000
    /// На сколько выше текущей целимся в разгон.
    static let rise = 0.08
    /// Глубина провала после разгона.
    static let dip = 0.18
    /// Провал — на 5-м треке после прошлого, следующий — на 6-м, и так по очереди.
    static let dipEvery = [5, 6]
    /// На таком отличии от цели попадание в дугу — ноль.
    static let fitSpan = 0.4
    static let wPlan = 0.6
    static let wArc = 0.4

    static func partyContext(_ base: String) -> String { prefix + base }

    static func isPartyContext(_ ctx: String?) -> Bool { ctx?.hasPrefix(prefix) ?? false }

    static func partyBase(_ ctx: String) -> String { String(ctx.dropFirst(prefix.count)) }

    /// Энергия трека 0…1 для сравнения между треками: громкость (~LUFS) и темп.
    static func trackEnergy(_ a: BlendAnalysis) -> Double {
        0.6 * clamp01((a.loudness + 18) / 12) + 0.4 * clamp01((foldBpm(a.bpm) - 85) / 85)
    }

    /// Куда вести энергию следующим треком.
    static func arcTarget(_ s: ArcState, current: Double) -> (target: Double, dip: Bool) {
        if s.elapsedMs < warmupMs { return (min(1, current + rise), false) }
        if s.sinceDip >= dipEvery[s.dips % 2] - 1 { return (max(0, current - dip), true) }
        return (max(current, s.peak), false)
    }

    static func arcFit(_ energy: Double, _ target: Double) -> Double {
        1 - min(1, abs(energy - target) / fitSpan)
    }

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// Темп в окно 85…170: половинный и двойной — одно и то же для танцпола.
    private static func foldBpm(_ bpm: Double) -> Double {
        var b = bpm > 0 ? bpm : 120
        while b < 85 { b *= 2 }
        while b >= 170 { b /= 2 }
        return b
    }
}

/// Очередь вечеринки. Живёт у одного владельца (контроллера), поэтому класс без `Sendable`.
final class PartyOrder {
    let first: String
    private(set) var pool: [String] = []
    private var rest: [String]
    private let rnd: () -> Double
    private var sinceDip = 0
    private var dips = 0
    private var peak = 0.0
    private var last: Double?

    init(refs: [String], rnd: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        var seen = Set<String>()
        let all = refs.filter { seen.insert($0).inserted }
        self.rnd = rnd
        let i = Int((rnd() * Double(min(BlendParty.startFrom, all.count))).rounded(.down))
        let first = i < all.count ? all[i] : ""
        self.first = first
        rest = all.filter { $0 != first }
        _ = refill { _ in false }
    }

    /// Все сыграны.
    var done: Bool { pool.isEmpty && rest.isEmpty }

    /// Добирает пул случайными до 8 живых; возвращает новых — их отдают на анализ.
    @discardableResult
    func refill(isFailed: (String) -> Bool) -> [String] {
        var added: [String] = []
        var alive = pool.filter { !isFailed($0) }.count
        while alive < BlendParty.pool && !rest.isEmpty {
            let i = Int((rnd() * Double(rest.count)).rounded(.down))
            added.append(rest[i])
            rest = Array(rest[..<i] + rest[(i + 1)...])
            alive += 1
        }
        pool = pool + added
        return added
    }

    /// Лучший следующий, ничего не меняет. Готовые — по плану перехода и дуге; готовых нет — первый ещё
    /// считающийся (заиграет кроссфейдом); сбойные — в самый конец. nil — играть нечего.
    func suggest(
        elapsedMs: Double, look: (String) -> PartyLook, planScore: (BlendAnalysis) -> Double
    ) -> String? {
        guard let head = pool.first else { return nil }
        let looks = pool.map { (ref: $0, look: look($0)) }
        let ready = looks.compactMap { l in l.look.analysis.map { (ref: l.ref, analysis: $0) } }
        guard let firstReady = ready.first else {
            return looks.first { !$0.look.failed }?.ref ?? head
        }
        let target = BlendParty.arcTarget(arc(elapsedMs), current: last ?? BlendParty.trackEnergy(firstReady.analysis)).target
        func score(_ a: BlendAnalysis) -> Double {
            BlendParty.wPlan * planScore(a) + BlendParty.wArc * BlendParty.arcFit(BlendParty.trackEnergy(a), target)
        }
        return ready.dropFirst().reduce(firstReady) { best, c in score(c.analysis) > score(best.analysis) ? c : best }.ref
    }

    /// Трек заиграл: убрать из пула и сдвинуть дугу. energy — nil, если анализа нет.
    func commit(_ ref: String, energy: Double?, elapsedMs: Double) {
        pool = pool.filter { $0 != ref }
        rest = rest.filter { $0 != ref }
        let hold = elapsedMs >= BlendParty.warmupMs
        guard let energy else {
            if hold { sinceDip += 1 }
            return
        }
        let wasDip = hold && last.map { BlendParty.arcTarget(arc(elapsedMs), current: $0).dip } == true
        if wasDip, let last, energy < last - BlendParty.dip / 2 {
            dips += 1
            sinceDip = 0
        } else if hold {
            sinceDip += 1
        }
        peak = max(peak, energy)
        last = energy
    }

    private func arc(_ elapsedMs: Double) -> ArcState {
        ArcState(elapsedMs: elapsedMs, sinceDip: sinceDip, dips: dips, peak: peak)
    }
}
