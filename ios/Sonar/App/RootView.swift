import SwiftUI
import UIKit

/// Корень: четыре вкладки (каждая со своим стеком страниц, состояние живёт при переключении) и снизу
/// своя панель (не системный `TabView`): таб-бар-капсула и мини-плеер, которые при прокрутке вниз
/// перетекают в одну строку (SPEC §4.5, TZ §4.13, `IMG_6768 → 6769`). Сверху — плашка-подсказка,
/// над панелью — «Доступно обновление»; лист трека — один на всё приложение.
struct RootView: View {
    @Environment(ChromeState.self) private var chrome
    @Environment(UpdateChecker.self) private var checker
    @Environment(PlaybackEngine.self) private var engine
    @Environment(Router.self) private var router
    @State private var showUpdate = false
    @State private var showPlayer = false

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            ForEach(Tab.allCases) { tab in
                screen(tab)
                    .opacity(chrome.tab == tab ? 1 : 0)
                    .scaleEffect(chrome.tab == tab ? 1 : 0.985)
                    .allowsHitTesting(chrome.tab == tab)
                    .accessibilityHidden(chrome.tab != tab)
            }

            if let release = checker.popup {
                UpdatePopup(release: release) {
                    // открыл подробности — значит, увидел: для этой сборки больше не всплываем, бейдж остаётся
                    withAnimation(Motion.spring) { checker.dismissPopup() }
                    showUpdate = true
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, BottomChrome.visibleHeight(hasMini: engine.current != nil, collapsed: chrome.collapsed) + 10)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }

            BottomChrome { showPlayer = true }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 2)
                .offset(y: chrome.barHidden ? 190 : 0)
                .opacity(chrome.barHidden ? 0 : 1)
                .allowsHitTesting(!chrome.barHidden)
                .animation(Motion.spring, value: chrome.barHidden)
        }
        .overlay(alignment: .top) {
            if let toast = router.toast {
                Toast(text: toast)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { router.hideToast() }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: chrome.tab)
        .animation(Motion.spring, value: checker.popup)
        .onChange(of: engine.current?.coverURL, initial: true) { _, url in
            ThemeStore.shared.follow(cover: url)
        }
        .onChange(of: engine.message) { _, message in
            // в полном плеере сообщение показывает он сам
            if let message, !showPlayer {
                router.say(message)
                engine.message = nil
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            FullPlayerView()
        }
        .sheet(item: $router.trackMenu) { item in
            TrackSheet(item: item)
                .presentationDetents([.fraction(0.86), .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showUpdate) {
            NavigationStack { UpdateView() }
                .presentationBackground(Theme.background)
        }
    }

    @ViewBuilder
    private func screen(_ tab: Tab) -> some View {
        @Bindable var router = router
        switch tab {
        case .home:
            NavigationStack(path: $router.home) {
                HomeView(active: chrome.tab == .home)
                    .routes()
            }
        case .library:
            NavigationStack(path: $router.library) {
                LibraryView().routes()
            }
        case .search:
            NavigationStack(path: $router.search) {
                SearchView().routes()
            }
        case .profile:
            NavigationStack { ProfileView() }
        }
    }
}

extension View {
    /// Страницы внутри вкладки; системная навигационная панель скрыта — у экранов свои круглые кнопки.
    func routes() -> some View {
        toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                RouteScreen(route: route)
                    .toolbar(.hidden, for: .navigationBar)
            }
    }
}

/// Страница по маршруту.
struct RouteScreen: View {
    let route: Route

    var body: some View {
        switch route {
        case .liked: PlaylistScreen(source: .liked)
        case .downloaded: PlaylistScreen(source: .downloaded)
        case .recent: PlaylistScreen(source: .recent)
        case let .playlist(playlist): PlaylistScreen(source: .service(playlist))
        case let .artist(ref, name): ArtistScreen(ref: ref, name: name)
        case let .album(ref, title): AlbumScreen(ref: ref, title: title)
        }
    }
}

/// Свайп назад от края при скрытой навигационной панели (SwiftUI его иначе выключает).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: - Нижняя панель

/// Таб-бар и мини-плеер — одни и те же элементы в двух раскладках, поэтому переход плавный: капсула
/// таб-бара сжимается в круг текущей вкладки, лупа уезжает вправо в свой круг, мини-плеер опускается
/// между ними, сужается и прячет лайк; прочие значки растворяются в левом круге. Пружина ~0,4 с.
/// Прокрутка вверх или тап по левому кругу — обратно (как список чатов в Shadow).
struct BottomChrome: View {
    let openPlayer: @MainActor () -> Void
    @Environment(ChromeState.self) private var chrome
    @Environment(PlaybackEngine.self) private var engine
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let barHeight: CGFloat = 64
    static let circle: CGFloat = 56
    static let miniHeight: CGFloat = 64
    static let gap: CGFloat = 8
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.84)

    /// Сколько панель занимает снизу (для отступов списков и всплывашек).
    static func visibleHeight(hasMini: Bool, collapsed: Bool) -> CGFloat {
        if !hasMini { return barHeight }
        return collapsed ? circle : barHeight + gap + miniHeight
    }

    var body: some View {
        let hasMini = engine.current != nil
        let collapsed = chrome.collapsed && hasMini
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let tabs = Tab.allCases
            let cell = w / CGFloat(tabs.count)
            let r = Self.circle / 2
            let barCenterY = h - Self.barHeight / 2
            let rowCenterY = h - r
            let searchCircle = collapsed && chrome.tab != .search
            let miniLeft: CGFloat = collapsed ? Self.circle + 10 : 0
            let miniRight: CGFloat = collapsed ? (searchCircle ? w - Self.circle - 10 : w) : w
            let miniHeight = collapsed ? Self.circle : Self.miniHeight
            let miniY = collapsed ? rowCenterY : h - Self.barHeight - Self.gap - Self.miniHeight / 2

            ZStack(alignment: .topLeading) {
                // капсула таб-бара ⇄ круг текущей вкладки
                BarSurface()
                    .frame(width: collapsed ? Self.circle : w, height: collapsed ? Self.circle : Self.barHeight)
                    .position(x: collapsed ? r : w / 2, y: collapsed ? rowCenterY : barCenterY)

                // подсветка выбранной вкладки — едет за выбором
                Capsule()
                    .fill(Theme.text.opacity(0.09))
                    .frame(width: collapsed ? Self.circle - 8 : cell - 12, height: collapsed ? Self.circle - 8 : Self.barHeight - 12)
                    .position(collapsed
                        ? CGPoint(x: r, y: rowCenterY)
                        : CGPoint(x: cell * (CGFloat(tabs.firstIndex(of: chrome.tab) ?? 0) + 0.5), y: barCenterY))
                    .opacity(collapsed ? 0 : 1)
                    .allowsHitTesting(false)

                // круг поиска: вырастает из лупы таб-бара
                BarSurface()
                    .frame(width: Self.circle, height: Self.circle)
                    .scaleEffect(searchCircle ? 1 : 0.5)
                    .opacity(searchCircle ? 1 : 0)
                    .position(searchCircle
                        ? CGPoint(x: w - r, y: rowCenterY)
                        : CGPoint(x: cell * (CGFloat(tabs.firstIndex(of: .search) ?? 2) + 0.5), y: barCenterY))
                    .allowsHitTesting(false)

                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    let selected = chrome.tab == tab
                    let toRight = collapsed && tab == .search && !selected
                    let visible = !collapsed || selected || toRight
                    TabIcon(tab: tab, selected: selected)
                        .frame(width: collapsed ? Self.circle : cell, height: collapsed ? Self.circle : Self.barHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { tapped(tab, collapsed: collapsed) }
                        .scaleEffect(visible ? 1 : 0.5)
                        .opacity(visible ? 1 : 0)
                        .position(collapsed
                            ? CGPoint(x: toRight ? w - r : r, y: rowCenterY)
                            : CGPoint(x: cell * (CGFloat(index) + 0.5), y: barCenterY))
                        .allowsHitTesting(visible)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .zIndex(selected ? 2 : 1)
                }

                if hasMini {
                    MiniPlayer(compact: collapsed, open: openPlayer)
                        .background(MiniPlayerSurface())
                        .frame(width: max(0, miniRight - miniLeft), height: miniHeight)
                        .position(x: (miniLeft + miniRight) / 2, y: miniY)
                        .transition(.offset(y: 40).combined(with: .opacity))
                        .zIndex(3)
                }
            }
        }
        .frame(height: Self.barHeight + Self.gap + Self.miniHeight)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Self.morph, value: collapsed)
        .animation(Self.morph, value: chrome.tab)
        .animation(Self.morph, value: hasMini)
    }

    private func tapped(_ tab: Tab, collapsed: Bool) {
        if collapsed, tab == chrome.tab {
            chrome.expand()
        } else if tab == chrome.tab {
            router.popToRoot(tab)
        } else {
            chrome.select(tab)
        }
    }
}

/// Значок вкладки: выбранная — заливка цветом текста, остальные — контур приглушённо.
private struct TabIcon: View {
    let tab: Tab
    let selected: Bool

    var body: some View {
        SonarIcon(tab.icon, filled: selected, size: 27)
            .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
            .scaleEffect(selected ? 1.04 : 1)
    }
}

/// Стекло панели: размытие + поверхность темы + тонкая обводка; форма — капсула любого размера (круг).
private struct BarSurface: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Theme.surface.opacity(0.62)))
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }
}

/// Мини-плеер в цвет обложки (`IMG_6768`, `IMG_6770`).
struct MiniPlayerSurface: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Theme.accent.opacity(ThemeStore.shared.isMono ? 0.32 : 0.58)))
            .overlay(Capsule().strokeBorder(Theme.text.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }
}
