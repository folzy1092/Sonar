import Foundation
import Observation

// Один на приложение: очередь анализа сведения (docs/BLEND.md §4) поверх файлов и расчёта `BlendAnalysisStore`.
// На ПК — `analyze.svelte.ts`. Экраны читают `tick` через `peek`/`state`/`stats`, чтобы обновиться, когда что-то
// досчиталось. Трек по ref даёт плеер (очередь, текущий, вечеринка) — `trackOf`.

@MainActor
@Observable
final class BlendAnalysisHub {
    static let shared = BlendAnalysisHub()

    /// Растёт на каждое изменение очереди — повод перечитать.
    private(set) var tick = 0

    @ObservationIgnored var trackOf: @MainActor (String) -> Track? = { _ in nil }
    @ObservationIgnored private lazy var queue = BlendAnalyzeQueue(
        deps: BlendAnalysisStore.deps(track: { [weak self] ref in self?.trackOf(ref) }),
        onChange: { [weak self] in self?.tick += 1 }
    )

    func peek(_ ref: String) -> BlendAnalysis? {
        _ = tick
        return queue.peek(ref)
    }

    func state(_ ref: String) -> BlendAnalysisState {
        _ = tick
        return queue.state(ref)
    }

    func failure(_ ref: String) -> String? {
        _ = tick
        return queue.failure(ref)
    }

    func stats() -> BlendAnalyzeQueue.Stats {
        _ = tick
        return queue.stats()
    }

    func request(_ ref: String, done: (@MainActor (BlendAnalysis?) -> Void)? = nil) {
        queue.request(ref, priority: .now, done: done)
    }

    /// Вечеринка: пул — с низким приоритетом, после текущего и следующего.
    func party(_ refs: [String]) {
        for ref in refs { queue.request(ref, priority: .party) }
    }

    /// Сеть вернулась — сбойные из-за офлайна можно пробовать снова.
    func forgetFailures() {
        queue.forgetFailures()
    }

    /// Хранилище → «Сведение»: стереть анализы с диска и из памяти.
    func clear() {
        queue.reset()
        Task.detached(priority: .utility) { BlendAnalysisFiles.clear() }
    }
}
