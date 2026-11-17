import Foundation

// Общий с виджетом файл (ios/project.yml, цель SonarWidget): только Foundation.

/// Что включают виджет, Siri / Команды и ссылки `sonar://play/<цель>`.
enum PlayTarget: String, CaseIterable, Sendable {
    /// Любимые — свои лайки Sonar.
    case liked
    /// «Моя волна».
    case wave
    /// Быстрый плейлист — выбирается в Система → Общее → «Виджет и Siri» (`widget.quick_playlist`).
    case quick

    /// `sonar://play/liked` и т. п. — виджет открывает приложение этой ссылкой.
    var url: URL {
        URL(string: "sonar://play/\(rawValue)")!
    }

    /// Подпись на кнопке виджета (виджет живёт отдельно от приложения и словарей `t()`, поэтому по-русски).
    var title: String {
        switch self {
        case .liked: "Любимые"
        case .wave: "Моя волна"
        case .quick: "Быстрый плейлист"
        }
    }
}

/// Значение настройки `widget.quick_playlist`: `liked`, `downloaded` или ref плейлиста сервиса
/// (`scpl:<id>`, `scpl:likes`, `ympl:<uid>:<kind>`, `ympl:likes`). Пусто или непонятное — Любимые.
enum QuickPlaylist: Equatable, Sendable {
    case liked
    case downloaded
    case service(String)

    static let key = "widget.quick_playlist"
    /// Название выбранного плейлиста сервиса — чтобы показать его в настройках без сети.
    static let titleKey = "widget.quick_playlist_title"

    init(setting value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "downloaded": self = .downloaded
        case _ where value.hasPrefix("scpl:") || value.hasPrefix("ympl:"):
            self = value.count > 5 ? .service(value) : .liked
        default: self = .liked
        }
    }

    var setting: String {
        switch self {
        case .liked: "liked"
        case .downloaded: "downloaded"
        case let .service(ref): ref
        }
    }
}
