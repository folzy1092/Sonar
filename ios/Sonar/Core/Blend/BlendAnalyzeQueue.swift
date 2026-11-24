import Foundation

// Очередь анализа сведения (docs/BLEND.md §4.1, §4.5) — зеркало `analyze-queue.ts` на ПК: не больше двух треков
// одновременно, текущий и следующий — раньше пула вечеринки, один трек не считается дважды. Сначала смотрим в
// хранилище (готовый анализ той же версии), нет — считаем и сохраняем. Не вышло — помним причину до
// `forgetFailures` (сеть вернулась), чтобы не долбить один и тот же трек на каждом тике.
// Чистая логика: загрузка, расчёт и сохранение приходят снаружи (`Playback/BlendAnalysisStore.swift`, тесты);
// ответы — колбэками на главном потоке, чтобы тесты шли без ожиданий.

enum BlendAnalyzePriority: Sendable {
    /// Играет или следующий.
    case now
    /// Пул «Свести для вечеринки».
    case party
}

struct BlendAnalyzeDeps {
    /// Готовые анализы из хранилища — любой версии, отбор здесь.
    var load: @MainActor (_ refs: [String], _ done: @escaping @MainActor ([String: BlendAnalysis]) -> Void) -> Void
    /// Скачать, декодировать и посчитать.
    var compute: @MainActor (_ ref: String, _ done: @escaping @MainActor (Result<BlendAnalysis, Error>) -> Void) -> Void
    var save: @MainActor (BlendAnalysis) -> Void
}

/// `ready` — есть, `pending` — считается, `failed` — не вышло (будет обычный кроссфейд), `none` — не просили.
enum BlendAnalysisState: Sendable {
    case ready, pending, failed, none
}

@MainActor
final class BlendAnalyzeQueue {
    static let concurrency = 2

    struct Stats: Equatable {
        var ready: Int
        var waiting: Int
        var running: Int
        var failed: Int
        var computed: Int
    }

    private final class Job {
        let ref: String
        var priority: BlendAnalyzePriority
        var waiters: [@MainActor (BlendAnalysis?) -> Void] = []

        init(ref: String, priority: BlendAnalyzePriority) {
            self.ref = ref
            self.priority = priority
        }
    }

    private let deps: BlendAnalyzeDeps
    private let onChange: @MainActor () -> Void
    private let limit: Int
    private var ready: [String: BlendAnalysis] = [:]
    private var failed: [String: String] = [:]
    private var waiting: [Job] = []
    private var running: [String: Job] = [:]
    /// Растёт на `reset`: задачи старого поколения результат не записывают.
    private var generation = 0
    private var computed = 0

    init(deps: BlendAnalyzeDeps, concurrency: Int = BlendAnalyzeQueue.concurrency, onChange: @escaping @MainActor () -> Void = {}) {
        self.deps = deps
        self.limit = max(1, concurrency)
        self.onChange = onChange
    }

    /// Готовый анализ из памяти, без ожидания.
    func peek(_ ref: String) -> BlendAnalysis? {
        ready[ref]
    }

    /// Почему анализа нет (nil — не падал).
    func failure(_ ref: String) -> String? {
        failed[ref]
    }

    func pending(_ ref: String) -> Bool {
        running[ref] != nil || waiting.contains { $0.ref == ref }
    }

    func state(_ ref: String) -> BlendAnalysisState {
        if ready[ref] != nil { return .ready }
        if pending(ref) { return .pending }
        return failed[ref] != nil ? .failed : .none
    }

    func stats() -> Stats {
        Stats(ready: ready.count, waiting: waiting.count, running: running.count, failed: failed.count, computed: computed)
    }

    /// Анализ трека: из памяти, хранилища или посчитать. nil — не вышло (причина — `failure`).
    func request(_ ref: String, priority: BlendAnalyzePriority = .now, done: (@MainActor (BlendAnalysis?) -> Void)? = nil) {
        if let hit = ready[ref] {
            done?(hit)
            return
        }
        if failed[ref] != nil {
            done?(nil)
            return
        }
        if let live = running[ref] {
            if let done { live.waiters.append(done) }
            return
        }
        if let queued = waiting.first(where: { $0.ref == ref }) {
            if let done { queued.waiters.append(done) }
            if priority == .now && queued.priority == .party { promote(queued) }
            return
        }
        let job = Job(ref: ref, priority: priority)
        if let done { job.waiters.append(done) }
        if priority == .now {
            waiting.insert(job, at: firstParty())
        } else {
            waiting.append(job)
        }
        pump()
    }

    /// Поднять в память всё, что уже есть в хранилище (вечеринка: план без ожидания каждого трека).
    func warm(_ refs: [String], done: (@MainActor () -> Void)? = nil) {
        let missing = refs.filter { ready[$0] == nil }
        guard !missing.isEmpty else {
            done?()
            return
        }
        let gen = generation
        deps.load(missing) { [weak self] rows in
            guard let self, gen == self.generation else { return }
            var changed = false
            for (ref, a) in rows where a.version == blendAnalysisVersion {
                self.ready[ref] = a
                changed = true
            }
            if changed { self.onChange() }
            done?()
        }
    }

    /// Сеть вернулась или файл появился — упавшие треки можно пробовать снова.
    func forgetFailures() {
        guard !failed.isEmpty else { return }
        failed = [:]
        onChange()
    }

    /// Хранилище очищено: память тоже. Идущие задачи доработают, но ничего не запишут.
    func reset() {
        generation += 1
        ready = [:]
        failed = [:]
        let dropped = waiting
        waiting = []
        for job in dropped { job.waiters.forEach { $0(nil) } }
        onChange()
    }

    private func firstParty() -> Int {
        waiting.firstIndex { $0.priority == .party } ?? waiting.count
    }

    private func promote(_ job: Job) {
        waiting.removeAll { $0 === job }
        job.priority = .now
        waiting.insert(job, at: firstParty())
    }

    private func pump() {
        while running.count < limit, !waiting.isEmpty {
            let job = waiting.removeFirst()
            running[job.ref] = job
            run(job)
        }
    }

    private func run(_ job: Job) {
        let gen = generation
        deps.load([job.ref]) { [weak self] rows in
            guard let self else { return }
            if let stored = rows[job.ref], stored.version == blendAnalysisVersion {
                self.finish(job, gen: gen, .success(stored))
                return
            }
            self.deps.compute(job.ref) { [weak self] result in
                guard let self else { return }
                if case let .success(a) = result {
                    self.computed += 1
                    if gen == self.generation { self.deps.save(a) }
                }
                self.finish(job, gen: gen, result)
            }
        }
    }

    private func finish(_ job: Job, gen: Int, _ result: Result<BlendAnalysis, Error>) {
        running[job.ref] = nil
        let current = gen == generation
        var out: BlendAnalysis?
        switch result {
        case let .success(a) where current:
            ready[job.ref] = a
            out = a
        case let .failure(error) where current:
            failed[job.ref] = String(describing: error)
        default:
            break
        }
        job.waiters.forEach { $0(out) }
        onChange()
        pump()
    }
}
