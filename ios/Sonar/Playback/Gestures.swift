import Foundation

/// Действие жеста (SETTINGS.md «Жесты», `photo_18..20`). rawValue — значение настройки.
enum GestureAction: String, CaseIterable, Identifiable, Sendable {
    case off, like, enqueue, play_next, next, previous, delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Ничего"
        case .like: "Лайк"
        case .enqueue: "В конец очереди"
        case .play_next: "Играть следующим"
        case .next: "Следующий трек"
        case .previous: "Предыдущий трек"
        case .delete: "Удалить"
        }
    }

    var icon: IconName {
        switch self {
        case .off: .eyeClosed
        case .like: .heart
        case .enqueue: .queue
        case .play_next: .listCheck
        case .next: .next
        case .previous: .prev
        case .delete: .trash
        }
    }
}

/// Где жест: строка трека в списках, строка очереди, мини-плеер, обложка полного плеера.
enum GestureContext: String, CaseIterable, Identifiable, Sendable {
    case library, queue, mini, player

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Медиатека"
        case .queue: "Очередь"
        case .mini: "Мини-плеер"
        case .player: "Плеер"
        }
    }

    var subtitle: String {
        switch self {
        case .library: "Свайп по треку в Любимых, плейлистах, поиске"
        case .queue: "Свайп по треку в очереди"
        case .mini: "Свайп по мини-плееру"
        case .player: "Свайп по обложке полного плеера"
        }
    }

    var icon: IconName {
        switch self {
        case .library: .library
        case .queue: .queue
        case .mini: .capsule
        case .player: .pic
        }
    }

    /// Что здесь имеет смысл: со строкой трека — очередь, лайк, удалить; с плеером — переключение.
    var allowed: [GestureAction] {
        switch self {
        case .library: [.off, .play_next, .enqueue, .like, .delete]
        case .queue: [.off, .delete, .play_next, .enqueue, .like]
        case .mini, .player: [.off, .next, .previous, .like]
        }
    }
}

/// Направление свайпа: «влево» — палец едет влево.
enum SwipeDirection: String, CaseIterable, Sendable {
    case left, right

    var title: String {
        switch self {
        case .left: "Свайп влево"
        case .right: "Свайп вправо"
        }
    }

    var icon: IconName {
        switch self {
        case .left: .arrowLeft
        case .right: .arrowRight
        }
    }

    /// Свайп засчитан: горизонтально дальше порога и заметно больше, чем по вертикали.
    static func detect(dx: Double, dy: Double, threshold: Double = 70) -> SwipeDirection? {
        guard abs(dx) >= threshold, abs(dx) > abs(dy) * 1.2 else { return nil }
        return dx < 0 ? .left : .right
    }
}

/// Тапы по обложке полного плеера.
enum CoverTap: String, CaseIterable, Sendable {
    case double_tap, triple_tap

    var title: String {
        switch self {
        case .double_tap: "Двойной тап"
        case .triple_tap: "Тройной тап"
        }
    }

    var icon: IconName { .fingerTap }

    static let allowed: [GestureAction] = [.off, .like, .next, .previous]
}

/// Настройки жестов: ключи `gestures.<контекст>.<left|right>` и `gestures.cover.<double_tap|triple_tap>`,
/// умолчания как в SETTINGS.md. Значение не из списка контекста (пришло с другой версии) — умолчание.
enum Gestures {
    static func key(_ context: GestureContext, _ direction: SwipeDirection) -> String {
        "gestures.\(context.rawValue).\(direction.rawValue)"
    }

    static func key(_ tap: CoverTap) -> String {
        "gestures.cover.\(tap.rawValue)"
    }

    static func fallback(_ context: GestureContext, _ direction: SwipeDirection) -> GestureAction {
        switch (context, direction) {
        case (.library, _): .play_next
        case (.queue, _): .delete
        case (.mini, .left), (.player, .left): .next
        case (.mini, .right), (.player, .right): .previous
        }
    }

    static func fallback(_ tap: CoverTap) -> GestureAction {
        switch tap {
        case .double_tap: .like
        case .triple_tap: .next
        }
    }

    static func action(_ raw: String, context: GestureContext, direction: SwipeDirection) -> GestureAction {
        guard let action = GestureAction(rawValue: raw), context.allowed.contains(action) else {
            return fallback(context, direction)
        }
        return action
    }

    static func action(_ raw: String, tap: CoverTap) -> GestureAction {
        guard let action = GestureAction(rawValue: raw), CoverTap.allowed.contains(action) else { return fallback(tap) }
        return action
    }

    /// Все умолчания — для `SettingsDefaults+Player`.
    static var defaults: [String: String] {
        var out: [String: String] = [:]
        for context in GestureContext.allCases {
            for direction in SwipeDirection.allCases {
                out[key(context, direction)] = fallback(context, direction).rawValue
            }
        }
        for tap in CoverTap.allCases { out[key(tap)] = fallback(tap).rawValue }
        return out
    }

    @MainActor
    static func action(_ settings: SettingsStore, _ context: GestureContext, _ direction: SwipeDirection) -> GestureAction {
        action(settings.string(key(context, direction)), context: context, direction: direction)
    }

    @MainActor
    static func action(_ settings: SettingsStore, _ tap: CoverTap) -> GestureAction {
        action(settings.string(key(tap)), tap: tap)
    }

    /// Свайп по треку → действие (nil — жест выключен или не засчитан).
    @MainActor
    static func resolve(_ settings: SettingsStore, _ context: GestureContext, dx: Double, dy: Double) -> GestureAction? {
        guard let direction = SwipeDirection.detect(dx: dx, dy: dy) else { return nil }
        let action = action(settings, context, direction)
        return action == .off ? nil : action
    }
}
