import Foundation
import Observation

// Оценки переходов (docs/BLEND.md §8) — зеркало `ratings.svelte.ts` на ПК: после перехода минуту висит 👍/👎,
// ответ пишется один раз, баланс видов — среднее оценок за 60 дней (`blend_rate` / `blend_balance` на ПК).
// До сервера оценки лежат JSON в Application Support (`Sonar/blend/ratings.json`), с сервером уедут в синк.

/// Отложенный вызов на главном потоке через `Task` — для движка и оценок; тесты подставляют свой.
@MainActor
final class BlendTaskTimer: BlendTimer {
    private var task: Task<Void, Never>?

    init(_ sec: Double, _ run: @escaping @MainActor () -> Void) {
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, sec) * 1_000_000_000))
            if !Task.isCancelled { run() }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

struct BlendRatingEntry: Codable, Equatable, Sendable {
    var from: String
    var to: String
    var kind: BlendKind
    /// 1 — 👍, -1 — 👎.
    var score: Int
    /// Миллисекунды с 1970.
    var at: Int
}

enum BlendRatingMath {
    /// Средняя оценка каждого вида с `sinceMs`; вида без оценок в ответе нет.
    static func balance(_ entries: [BlendRatingEntry], sinceMs: Int) -> [BlendKind: Double] {
        var sum: [BlendKind: (total: Int, count: Int)] = [:]
        for e in entries where e.at >= sinceMs {
            let old = sum[e.kind] ?? (0, 0)
            sum[e.kind] = (old.total + e.score, old.count + 1)
        }
        return sum.mapValues { Double($0.total) / Double($0.count) }
    }
}

@MainActor
@Observable
final class BlendRatings {
    static let shared = BlendRatings()
    /// Сколько висит вопрос после перехода.
    static let windowSec = 60.0
    /// За сколько дней считается баланс и хранятся оценки.
    static let days = 60
    private static let dayMs = 86_400_000

    /// Баланс видов для планировщика (`BlendSettings.ratings`).
    private(set) var balance: [BlendKind: Double] = [:]
    /// Переход, о котором спрашиваем; nil — строки 👍/👎 нет.
    private(set) var ask: BlendDone?
    /// Ответ на текущий вопрос.
    private(set) var answer: Int?

    @ObservationIgnored private let file: URL
    @ObservationIgnored private var entries: [BlendRatingEntry] = []
    @ObservationIgnored private var closer: BlendTimer?
    /// Часы и таймер — тесты подставляют свои.
    @ObservationIgnored var now: @MainActor () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }
    @ObservationIgnored var after: @MainActor (Double, @escaping @MainActor () -> Void) -> BlendTimer = { BlendTaskTimer($0, $1) }
    /// Запись на диск; false — не вышло (ответ сбрасывается, можно ответить ещё раз).
    @ObservationIgnored var write: @MainActor (Data, URL) -> Bool = { BlendRatings.writeFile($0, $1) }

    init(file: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.file = file ?? base.appendingPathComponent("Sonar/blend/ratings.json")
        if let data = try? Data(contentsOf: self.file), let saved = try? JSONDecoder().decode([BlendRatingEntry].self, from: data) {
            entries = saved
        }
        reload()
    }

    /// Переход случился — спросить минуту.
    func open(_ done: BlendDone) {
        closer?.cancel()
        ask = done
        answer = nil
        closer = after(Self.windowSec) { [weak self] in self?.close() }
    }

    func close() {
        closer?.cancel()
        closer = nil
        ask = nil
        answer = nil
    }

    /// 👍 (1) или 👎 (-1) — один раз на переход.
    func rate(_ score: Int) {
        guard let ask, answer == nil, score == 1 || score == -1 else { return }
        answer = score
        let stamp = now()
        let since = stamp - Self.days * Self.dayMs
        let next = entries.filter { $0.at >= since } + [BlendRatingEntry(from: ask.from, to: ask.to, kind: ask.kind, score: score, at: stamp)]
        guard let data = try? JSONEncoder().encode(next), write(data, file) else {
            answer = nil
            return
        }
        entries = next
        reload()
    }

    /// Оценки стёрты (Хранилище → «Сведение»).
    func clear() {
        entries = []
        if let data = try? JSONEncoder().encode(entries) { _ = write(data, file) }
        reload()
    }

    private func reload() {
        balance = BlendRatingMath.balance(entries, sinceMs: now() - Self.days * Self.dayMs)
    }

    nonisolated private static func writeFile(_ data: Data, _ file: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
