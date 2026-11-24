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
    /// Панель спрятана целиком (режим выбора треков: внизу своя капсула действий).
    var barHidden = false

    /// Откуда считаем путь пальца с последнего переключения.
    private var anchor: CGFloat = 0
    /// Развернули кнопкой посреди списка — опору ставим там, где палец двинется дальше.
    private var reanchor = false

    func scrolled(to offset: CGFloat) {
        if reanchor {
            reanchor = false
            anchor = offset
            return
        }
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
        reanchor = true
    }

    /// Новая вкладка — панель развёрнута.
    func select(_ tab: Tab) {
        self.tab = tab
        expand()
    }
}

/// Что делает тап по значку вкладки в нижней панели. Тап по текущей вкладке — в её корень (в настройках —
/// к началу списка), и в свёрнутой панели тоже: левый круг не просто разворачивает панель, а ведёт на
/// вкладку, как значок в развёрнутой (панель при этом разворачивается).
enum TabTap: Equatable {
    case select
    case popToRoot
    case expandAndPopToRoot

    static func of(_ tab: Tab, current: Tab, collapsed: Bool) -> TabTap {
        if tab != current { return .select }
        return collapsed ? .expandAndPopToRoot : .popToRoot
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

    /// Значок MingCute, как в Windows-клиенте; выбранная вкладка — его заливка. Профиль — шестигранник
    /// настроек, как на скринах.
    var icon: IconName {
        switch self {
        case .home: .home
        case .library: .library
        case .search: .search
        case .profile: .settings
        }
    }
}
