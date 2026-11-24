import Foundation

// «Проверка сервисов» (как Windows `Core::check_services`, `services.rs`): у каждого подключённого сервиса —
// обычный поиск одной строки (ключ, сеть и сам сервис разом), все параллельно, не дольше 15 с на сервис.
// Не подключённые не трогаем. Чистая логика: поиск приходит снаружи — в приложении `MusicCore` / `SpotifyCore`,
// в тестах — заглушка.

/// Итог проверки одного сервиса.
struct ServiceCheck: Sendable, Equatable, Identifiable {
    let service: ServiceID
    let ok: Bool
    /// Сколько шёл ответ (или до тайм-аута), мс.
    let ms: Int
    /// Текст ошибки сервиса; у тайм-аута — nil, его показывает `timedOut`.
    let error: String?
    var timedOut = false

    var id: ServiceID { service }
}

enum ServiceChecker {
    /// Строка, которую ищет каждый сервис (та же, что на ПК).
    static let query = "music"
    static let timeout: Duration = .seconds(15)

    /// Сервис не ответил вовремя.
    struct Timeout: Error {}

    /// Проверить подключённые: порядок — как в реестре (`ServiceRegistry`), не как пришли ответы.
    static func run(
        connected: Set<ServiceID>,
        timeout: Duration = timeout,
        search: @escaping @Sendable (ServiceID) async throws -> Void
    ) async -> [ServiceCheck] {
        let order = ServiceRegistry.implemented.map(\.id).filter(connected.contains)
        return await withTaskGroup(of: (Int, ServiceCheck).self) { group in
            for (i, id) in order.enumerated() {
                group.addTask { (i, await check(id, timeout: timeout, search: search)) }
            }
            var out = [ServiceCheck?](repeating: nil, count: order.count)
            for await (i, result) in group { out[i] = result }
            return out.compactMap { $0 }
        }
    }

    /// Один сервис: поиск наперегонки с таймером, время — с начала поиска.
    static func check(
        _ id: ServiceID,
        timeout: Duration,
        search: @escaping @Sendable (ServiceID) async throws -> Void
    ) async -> ServiceCheck {
        let clock = ContinuousClock()
        let started = clock.now
        let elapsed = { Int((clock.now - started) / .milliseconds(1)) }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await search(id) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw Timeout()
                }
                // первый закончивший решает; второго отменяем (URLSession и sleep отмену слышат)
                defer { group.cancelAll() }
                try await group.next()
            }
            return ServiceCheck(service: id, ok: true, ms: elapsed(), error: nil)
        } catch is Timeout {
            return ServiceCheck(service: id, ok: false, ms: elapsed(), error: nil, timedOut: true)
        } catch {
            return ServiceCheck(service: id, ok: false, ms: elapsed(), error: error.localizedDescription)
        }
    }

    /// «0.4» — секунды с одной цифрой после точки, как на ПК.
    static func seconds(_ ms: Int) -> String {
        String(format: "%.1f", Double(ms) / 1000)
    }
}
