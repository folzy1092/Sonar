import Foundation
import Observation

/// Треки, которые SoundCloud удалил (HTTP 404 на потоке) — часто по жалобе правообладателя. Строка
/// трека подписана значком, чтобы не думали, что сломался Sonar. Помнится на устройстве; заиграл — метка снимается.
@Observable
@MainActor
final class RemovedTracks {
    static let shared = RemovedTracks()
    private static let key = "sonar.removed_tracks"
    private static let limit = 500

    private(set) var refs: Set<String>
    private var order: [String]

    init(defaults: UserDefaults = .standard) {
        // @Observable: читать `order` до инициализации всех полей нельзя — через локальную
        let saved = defaults.stringArray(forKey: Self.key) ?? []
        order = saved
        refs = Set(saved)
        self.defaults = defaults
    }

    private let defaults: UserDefaults

    /// Ошибка потока — «трек удалён» (текст `ServiceError.http`, 404 у SoundCloud).
    nonisolated static func isRemoved(ref: String, error: Error) -> Bool {
        ref.hasPrefix("sc:") && (error as? ServiceError).map { $0.message.hasPrefix("SoundCloud: ") && $0.message.hasSuffix("(HTTP 404)") } == true
    }

    func mark(_ ref: String, _ on: Bool) {
        guard refs.contains(ref) != on else { return }
        if on {
            order.append(ref)
            if order.count > Self.limit { order.removeFirst(order.count - Self.limit) }
        } else {
            order.removeAll { $0 == ref }
        }
        refs = Set(order)
        defaults.set(order, forKey: Self.key)
    }
}
