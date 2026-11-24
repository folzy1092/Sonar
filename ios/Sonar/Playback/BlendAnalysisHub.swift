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

    /// Уже решали, склеивать ли трек заранее, — в эту сессию не повторять (и не листать папку на каждом тике).
    @ObservationIgnored private var stitchTried: Set<String> = []

    /// Следующий трек со сведением: анализ есть, а склеенного файла нет — склеить заранее, чтобы дек сыграл
    /// файл (`BlendStitchCache`). Пока анализа нет, склейку сделает сам анализ.
    func prefetchStitch(_ track: Track) {
        let ref = track.ref
        // по сотовой с «Только по Wi‑Fi» или в офлайне — не отмечаем: попробуем снова, когда сеть сменится
        let mayDownload = !SettingsStore.shared.bool(DownloadStore.wifiOnlyKey) || NetworkStatus.shared.isUnmetered
        guard mayDownload, !OfflineFlag.isOn, !stitchTried.contains(ref), queue.peek(ref) != nil else { return }
        stitchTried.insert(ref)
        let hasFile = DownloadStore.shared.localURL(ref) != nil || WaveCache.shared.localURL(ref) != nil
            || BlendStitchCache.shared.localURL(ref) != nil
        guard BlendStitchPlan.shouldPrefetch(ref: ref, durationMs: track.durationMs, offline: false,
                                             mayDownload: true, hasFile: hasFile, attempted: false) else { return }
        Task.detached(priority: .utility) { await BlendAnalysisStore.prefetchStitch(track) }
    }

    /// Хранилище → «Сведение»: стереть анализы и склеенные файлы с диска и из памяти.
    func clear() {
        queue.reset()
        stitchTried = []
        Task.detached(priority: .utility) {
            BlendAnalysisFiles.clear()
            BlendStitchCache.shared.clear()
        }
    }
}
