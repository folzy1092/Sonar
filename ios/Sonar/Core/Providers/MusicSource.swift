import Foundation

/// Что волне, Главной и конвертеру нужно от сервисов. В приложении это `MusicCore`
/// (`MusicCore+Shared.swift`), в тестах — заглушка без сети.
protocol MusicSource: Sendable {
    /// Похожие на трек (`sc:` — related SoundCloud, `ym:` — similar Яндекса).
    func similar(to ref: String, limit: Int) async throws -> [Track]
    /// Популярные треки исполнителя (`sca:` / `yma:`).
    func artistTop(_ ref: String, limit: Int) async throws -> [Track]
    /// Альбомы и синглы исполнителя.
    func artistAlbums(_ ref: String) async throws -> [Album]
    /// Новинки Яндекса — когда у своих исполнителей свежего нет. Яндекс не подключён — пусто.
    func newReleases(limit: Int) async throws -> [Album]
    func search(_ query: String, in service: Service, limit: Int) async throws -> [Track]
}

/// Параллельно позвать сервис для каждого элемента, ответы — в том же порядке; ошибка — nil.
func concurrentMap<T: Sendable, R: Sendable>(_ items: [T], _ call: @escaping @Sendable (T) async throws -> R) async -> [R?] {
    await withTaskGroup(of: (Int, R?).self) { group in
        for (i, item) in items.enumerated() {
            group.addTask { (i, try? await call(item)) }
        }
        var out = [R?](repeating: nil, count: items.count)
        for await (i, value) in group { out[i] = value }
        return out
    }
}
