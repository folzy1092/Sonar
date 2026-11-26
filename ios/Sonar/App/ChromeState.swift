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
    /// Левый круг свёрнутой панели: экран сам едет к началу, а панель остаётся свёрнутой, пока список не двинет палец.
    private var held = false
    /// Прошлое смещение — по нему видно, куда едет список, пока панель придержана.
    private var lastOffset: CGFloat = 0

    func scrolled(to offset: CGFloat) {
        defer { lastOffset = offset }
        if held {
            // Прокрутка к началу идёт только вверх и не ниже нуля; вниз или потянули за верх — это уже палец.
            if offset >= 0, offset <= lastOffset { return }
            held = false
            if offset > 0 {
                anchor = offset
                return
            }
        }
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
        held = false
        reanchor = true
    }

    /// Панель не разворачивается, пока экран сам едет к началу (тап по левому кругу свёрнутой панели).
    func holdCollapsed() {
        guard collapsed else { return }
        held = true
    }

    /// Новая вкладка — панель развёрнута.
    func select(_ tab: Tab) {
        self.tab = tab
        expand()
    }
}

/// Что делает тап по значку вкладки в нижней панели. Тап по текущей вкладке — в её корень и к началу
/// (Главная — наверх, настройки — к профилю). Левый круг свёрнутой панели делает то же, но панель остаётся
/// свёрнутой (решение владельца 2026-11-26): разворачивает её только прокрутка вверх.
enum TabTap: Equatable {
    case select
    case toTop
    case toTopCollapsed

    static func of(_ tab: Tab, current: Tab, collapsed: Bool) -> TabTap {
        if tab != current { return .select }
        return collapsed ? .toTopCollapsed : .toTop
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
