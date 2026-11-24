import Foundation
import Observation

// «Свести для вечеринки» (docs/BLEND.md §9): из очереди — по одному треку вперёд, следующий выбирается по плану
// перехода и дуге энергии (`PartyOrder`). Порт `party.svelte.ts`. В очереди движка — только играющий и следующий,
// остальное ждёт в пуле. Вечеринка идёт, пока контекст движка — её название; сменили очередь — она кончилась.

@MainActor
@Observable
final class BlendPartyStore {
    static let shared = BlendPartyStore()

    /// Не менять следующий, если до конца текущего меньше: он уже грузится на второй дек.
    private static let swapGuardMs = 40_000.0
    /// Оценка перехода, когда у играющего ещё нет анализа.
    private static let unknownScore = 0.5

    /// Название вечеринки — контекст движка, пока она идёт.
    private(set) var title: String?
    @ObservationIgnored private var order: PartyOrder?
    @ObservationIgnored private var tracks: [String: Track] = [:]
    @ObservationIgnored private var played: Set<String> = []
    /// Следующий, которого поставила сама вечеринка (чужой — пользователь выбрал сам, не трогаем).
    @ObservationIgnored private var queued: String?
    @ObservationIgnored private var elapsedMs = 0.0
    @ObservationIgnored private var last: (ref: String, posMs: Double)?
    @ObservationIgnored private var scores: [String: Double] = [:]
    @ObservationIgnored private var scoresFor: PlanOpts?

    private var engine: PlaybackEngine { .shared }
    private var hub: BlendAnalysisHub { .shared }

    var isActive: Bool { title != nil && engine.contextTitle == title }

    /// Трек пула — для анализа (его нет в очереди движка).
    func track(_ ref: String) -> Track? { tracks[ref] }

    /// list — текущая очередь, name — её название.
    func start(_ list: [Track], name: String) {
        let offline = OfflineMode.shared
        let usable = list.filter { $0.available && (!offline.isOn || offline.isAvailable($0.ref)) }
        guard !usable.isEmpty else { return }
        let order = PartyOrder(refs: usable.map(\.ref))
        guard let first = usable.first(where: { $0.ref == order.first }) else { return }
        end()
        let title = t("Вечеринка · {name}", ["name": name])
        self.order = order
        self.title = title
        tracks = Dictionary(usable.map { ($0.ref, $0) }, uniquingKeysWith: { a, _ in a })
        engine.play([first], at: 0, context: title)
        hub.party(order.pool)
    }

    func end() {
        title = nil
        order = nil
        tracks = [:]
        played = []
        queued = nil
        elapsedMs = 0
        last = nil
        scores = [:]
        scoresFor = nil
    }

    /// Тик плеера: отметить играющий и, если надо, поставить следующим лучший из пула.
    func step() {
        guard title != nil else { return }
        guard isActive, let order else { return end() }
        guard let current = engine.current else { return }
        commit(current.ref, posMs: engine.position * 1000)
        let head = engine.upNext.first?.ref
        if let head, head != queued { return }
        let best = order.suggest(
            elapsedMs: elapsedMs + engine.duration * 1000,
            look: look,
            planScore: { self.score(current.ref, $0) }
        )
        guard let best, best != head, let track = tracks[best] else { return }
        guard let head else { return enqueue(track) }
        // сменить уже поставленный — только если у него нет анализа, а у лучшего есть, и переход ещё не начат
        let remainingMs = (engine.duration - engine.position) * 1000
        guard hub.peek(head) == nil, hub.peek(best) != nil, engine.blend.phase == .idle,
              remainingMs > Self.swapGuardMs else { return }
        engine.removeUpcoming(0)
        enqueue(track)
    }

    private func enqueue(_ track: Track) {
        queued = track.ref
        engine.enqueue(track, next: false)
    }

    private func commit(_ ref: String, posMs: Double) {
        if let last, last.ref != ref { elapsedMs += last.posMs }
        last = (ref, posMs)
        guard !played.contains(ref), tracks[ref] != nil, let order else { return }
        played.insert(ref)
        if queued == ref { queued = nil }
        order.commit(ref, energy: hub.peek(ref).map(BlendParty.trackEnergy), elapsedMs: elapsedMs)
        hub.party(order.refill { self.hub.state($0) == .failed })
    }

    private func look(_ ref: String) -> PartyLook {
        let analysis = hub.peek(ref)
        return PartyLook(analysis: analysis, failed: analysis == nil && hub.state(ref) == .failed)
    }

    private func score(_ current: String, _ next: BlendAnalysis) -> Double {
        guard let a = hub.peek(current) else { return Self.unknownScore }
        let s = engine.settings()
        let opts = PlanOpts(
            type: s.type, lengthSec: s.lengthSec, cutSec: s.cutSec, tempoTolPct: s.tempoTolPct, keyShift: s.keyShift,
            rateA: Double(engine.rate), rateB: 1, linkedA: engine.pitchLinked, linkedB: engine.pitchLinked,
            ratings: s.ratings
        )
        if opts != scoresFor {
            scores = [:]
            scoresFor = opts
        }
        let key = "\(current)>\(next.ref)"
        if let cached = scores[key] { return cached }
        let value = BlendPlanner.plan(a, next, opts: opts).first?.score ?? 0
        scores[key] = value
        return value
    }
}
