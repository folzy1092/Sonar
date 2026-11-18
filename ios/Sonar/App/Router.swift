import SwiftUI

/// Куда можно перейти внутри вкладки: страницы плейлистов, артиста, альбома.
enum Route: Hashable {
    case liked
    case downloaded
    /// Вся история «Недавнее».
    case recent
    case playlist(ServicePlaylist)
    /// Свой плейлист Sonar (`PlaylistStore`).
    case sonarPlaylist(id: String)
    /// Умный плейлист (`SmartPlaylistStore`, `sm_…`).
    case smartPlaylist(id: String)
    case artist(ref: String, name: String)
    case album(ref: String, title: String)
}

/// Лист трека: какой трек и можно ли убрать его из списка, где он показан.
struct TrackMenuItem: Identifiable {
    let id = UUID()
    let track: Track
    var remove: (@MainActor () -> Void)?
}

/// Переходы и общие листы: у каждой вкладки свой стек (как в Shadow — вкладка помнит, где была), лист
/// трека один на всё приложение, плашка-подсказка сверху.
@MainActor
@Observable
final class Router {
    var home = NavigationPath()
    var library = NavigationPath()
    var search = NavigationPath()
    var trackMenu: TrackMenuItem?
    /// Открыт полный плеер.
    var playerOpen = false
    /// Стек Профиля без пути (экраны настроек открываются ссылками-видами) — к началу его возвращает новый id.
    var profileRoot = UUID()
    private(set) var toast: String?

    @ObservationIgnored private var toastTask: Task<Void, Never>?

    func showMenu(_ track: Track, remove: (@MainActor () -> Void)? = nil) {
        trackMenu = TrackMenuItem(track: track, remove: remove)
    }

    /// Открыть страницу во вкладке; из Профиля — в Медиатеке.
    func push(_ route: Route, on tab: Tab, chrome: ChromeState) {
        switch tab {
        case .home: home.append(route)
        case .search: search.append(route)
        case .library: library.append(route)
        case .profile:
            chrome.select(.library)
            library.append(route)
        }
    }

    /// Второй тап по выбранной вкладке — к её началу.
    func popToRoot(_ tab: Tab) {
        switch tab {
        case .home: home = NavigationPath()
        case .library: library = NavigationPath()
        case .search: search = NavigationPath()
        case .profile: profileRoot = UUID()
        }
    }

    func say(_ text: String) {
        toastTask?.cancel()
        withAnimation(Motion.spring) { toast = text }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.spring) { self?.toast = nil }
        }
    }

    func hideToast() {
        withAnimation(Motion.spring) { toast = nil }
    }
}
