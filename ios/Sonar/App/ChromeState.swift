import Observation
import CoreGraphics

/// Свёрнут ли таб-бар с мини-плеером (SPEC §4.5, `photo_28 → 29`). Экраны-списки сообщают смещение
/// прокрутки; вниз больше 24 pt — свернуть, вверх больше 24 pt или у верхнего края — развернуть.
/// Гистерезис: мелкие подёргивания пальца ничего не переключают.
@MainActor
@Observable
final class ChromeState {
    static let threshold: CGFloat = 24

    private(set) var collapsed = false
    var tab: Tab = .home

    /// Откуда считаем путь пальца с последнего переключения.
    private var anchor: CGFloat = 0

    func scrolled(to offset: CGFloat) {
        if offset <= 0 {
            collapsed = false
            anchor = 0
            return
        }
        let delta = offset - anchor
        if !collapsed, delta > Self.threshold {
            collapsed = true
            anchor = offset
        } else if collapsed, delta < -Self.threshold {
            collapsed = false
            anchor = offset
        } else if collapsed ? offset > anchor : offset < anchor {
            // продолжаем в ту же сторону — опора едет за пальцем
            anchor = offset
        }
    }

    func expand() {
        collapsed = false
    }
}

/// Вкладки нижней панели (SPEC §4.5): Главная · Медиатека · Поиск · Профиль.
enum Tab: String, CaseIterable, Identifiable {
    case home, library, search, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Главная"
        case .library: "Медиатека"
        case .search: "Поиск"
        case .profile: "Профиль"
        }
    }

    /// SF Symbols — временно; по решению владельца иконки — MingCute (как в Windows-клиенте).
    var symbol: String {
        switch self {
        case .home: "house"
        case .library: "folder"
        case .search: "magnifyingglass"
        case .profile: "person.crop.circle"
        }
    }

    /// Выбранная вкладка — залитая иконка (у лупы залитого варианта нет — она жирнее).
    var selectedSymbol: String {
        self == .search ? symbol : symbol + ".fill"
    }
}
