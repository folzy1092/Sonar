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
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var showUpdate = false
    /// Нижний системный отступ (полоска «домой»): панели во всю ширину заходят под него.
    @State private var bottomInset: CGFloat = 0

    var body: some View {
        // с сервером вход обязателен: без аккаунта — экран входа (сейчас сервер выключен — сразу приложение)
        if AccountStore.shared.needsSignIn {
            AuthGateView()
                .transition(.opacity)
        } else {
            app
        }
    }

    @ViewBuilder
    private var app: some View {
        @Bindable var router = router
        let animationsOn = settings.bool(LookKey.animations)
        ZStack(alignment: .bottom) {
            // фон приложения (Интерфейс → Вид → Фон): тема, цвет обложки, сама обложка или своя картинка
            AppBackdrop().ignoresSafeArea()

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

            BottomChrome(bottomInset: bottomInset) { router.playerOpen = true }
                .padding(.bottom, BottomChrome.edgePadding)
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
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { bottomInset = proxy.safeAreaInsets.bottom }
                    .onChange(of: proxy.safeAreaInsets.bottom) { _, inset in bottomInset = inset }
            }
        }
        // тема: тёмная / светлая / как в системе — весь интерфейс, системные листы и стекло тоже
        .preferredColorScheme(ThemeStore.shared.colorScheme)
        // «Анимации» выключены — движения короткие и мягкие, без пружин (PLATFORMS.md «Анимации»)
        .transaction { transaction in
            if !animationsOn, transaction.animation != nil {
                transaction.animation = .easeInOut(duration: 0.16)
            }
        }
        .onChange(of: LookInputs(settings), initial: true) { _, _ in syncTheme() }
        .onChange(of: colorScheme) { _, _ in syncTheme() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { syncTheme() }
        }
        .animation(.easeInOut(duration: 0.22), value: chrome.tab)
        .animation(Motion.spring, value: checker.popup)
        .onChange(of: engine.current?.coverURL, initial: true) { _, url in
            ThemeStore.shared.follow(cover: url)
        }
        .onChange(of: engine.message) { _, message in
            // в полном плеере сообщение показывает он сам
            if let message, !router.playerOpen {
                router.say(message)
                engine.message = nil
            }
        }
        .onChange(of: DownloadStore.shared.message) { _, message in
            if let message {
                router.say(message)
                DownloadStore.shared.message = nil
            }
        }
        .fullScreenCover(isPresented: $router.playerOpen) {
            FullPlayerView()
        }
        .crashReportSheet()
        .approveLoginOverlay()
        .onChange(of: chrome.tab) { _, tab in CrashLog.note("экран: \(tab.rawValue)") }
        .onChange(of: engine.current?.ref) { _, ref in if let ref { CrashLog.note("трек: \(ref)") } }
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

    /// Настройки Вида → `ThemeStore` (поверхность, светлая / тёмная, готовая тема).
    private func syncTheme() {
        ThemeStore.shared.update(LookInputs(settings), systemDark: systemIsDark)
    }

    /// Системная тема телефона — по экрану (окно приложения может быть переопределено настройкой).
    private var systemIsDark: Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return (scene?.screen.traitCollection.userInterfaceStyle ?? .dark) != .light
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

/// Таб-бар и мини-плеер — одни и те же элементы в двух раскладках, поэтому переход плавный: панель
/// вкладок сжимается в круг текущей вкладки, лупа уезжает вправо в свой круг, мини-плеер опускается
/// между ними, сужается и прячет лайк; прочие значки растворяются в левом круге. Пружина ~0,4 с.
/// Прокрутка вверх или тап по левому кругу — обратно (как список чатов в Shadow).
/// Стиль панели — Интерфейс → Вкладки (`appearance.tab_style`): плавающая капсула (умолчание),
/// стандартная во всю ширину у края, закруглённая сверху, компактная узкая капсула. Сворачивается — во всех.
struct BottomChrome: View {
    var bottomInset: CGFloat = 0
    let openPlayer: @MainActor () -> Void
    @Environment(ChromeState.self) private var chrome
    @Environment(PlaybackEngine.self) private var engine
    @Environment(Router.self) private var router
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let barHeight: CGFloat = 64
    static let circle: CGFloat = 56
    static let miniHeight: CGFloat = 64
    static let gap: CGFloat = 8
    /// Отступ панели от нижней границы безопасной зоны.
    static let edgePadding: CGFloat = 2
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.84)

    /// Сколько панель занимает снизу (для отступов списков и всплывашек).
    static func visibleHeight(hasMini: Bool, collapsed: Bool) -> CGFloat {
        if !hasMini { return barHeight }
        return collapsed ? circle : barHeight + gap + miniHeight
    }

    var body: some View {
        let style = TabBarStyle(rawValue: settings.string(LookKey.tabStyle)) ?? .floating
        let hasMini = engine.current != nil
        let collapsed = chrome.collapsed && hasMini && settings.bool(LookKey.tabsCollapse)
        let tint: Color? = settings.bool(LookKey.tabsAdapt) ? Theme.tint : nil
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let g = Theme.gutter
            let tabs = Tab.allCases
            let barH = CGFloat(style.barHeight)
            let barW = CGFloat(style.barWidth(screen: Double(w), gutter: Double(g), tabs: tabs.count))
            let barLeft = (w - barW) / 2
            let cell = barW / CGFloat(tabs.count)
            let r = Self.circle / 2
            let leftX = g + r
            let rightX = w - g - r
            let barCenterY = h - barH / 2
            let rowCenterY = h - r
            let searchCircle = collapsed && chrome.tab != .search
            let miniLeft: CGFloat = collapsed ? g + Self.circle + 10 : g
            let miniRight: CGFloat = collapsed ? (searchCircle ? w - g - Self.circle - 10 : w - g) : w - g
            let miniHeight = collapsed ? Self.circle : Self.miniHeight
            let miniY = collapsed ? rowCenterY : h - barH - Self.gap - Self.miniHeight / 2
            // панель во всю ширину уходит под полоску «домой» до края экрана
            let extra: CGFloat = style.fullWidth && !collapsed ? bottomInset + Self.edgePadding : 0
            let corners = style.radii(height: Double(barH))
            let top: CGFloat = collapsed ? r : CGFloat(corners.top)
            let bottom: CGFloat = collapsed ? r : CGFloat(corners.bottom)
            let titles = style.showsTitles && !collapsed
            let selectedIndex = tabs.firstIndex(of: chrome.tab) ?? 0
            let searchIndex = tabs.firstIndex(of: .search) ?? 2

            ZStack(alignment: .topLeading) {
                // панель вкладок ⇄ круг текущей вкладки
                BarSurface(top: top, bottom: bottom, tint: tint, edge: style.fullWidth && !collapsed)
                    .frame(width: collapsed ? Self.circle : barW, height: collapsed ? Self.circle : barH + extra)
                    .position(x: collapsed ? leftX : w / 2, y: collapsed ? rowCenterY : barCenterY + extra / 2)

                // подсветка выбранной вкладки — едет за выбором
                Capsule()
                    .fill(Theme.text.opacity(0.09))
                    .frame(width: collapsed ? Self.circle - 8 : cell - 12, height: collapsed ? Self.circle - 8 : barH - 12)
                    .position(collapsed
                        ? CGPoint(x: leftX, y: rowCenterY)
                        : CGPoint(x: barLeft + cell * (CGFloat(selectedIndex) + 0.5), y: barCenterY))
                    .opacity(collapsed ? 0 : 1)
                    .allowsHitTesting(false)

                // круг поиска: вырастает из лупы панели
                BarSurface(top: r, bottom: r, tint: tint)
                    .frame(width: Self.circle, height: Self.circle)
                    .scaleEffect(searchCircle ? 1 : 0.5)
                    .opacity(searchCircle ? 1 : 0)
                    .position(searchCircle
                        ? CGPoint(x: rightX, y: rowCenterY)
                        : CGPoint(x: barLeft + cell * (CGFloat(searchIndex) + 0.5), y: barCenterY))
                    .allowsHitTesting(false)

                ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                    let selected = chrome.tab == tab
                    let toRight = collapsed && tab == .search && !selected
                    let visible = !collapsed || selected || toRight
                    TabIcon(tab: tab, selected: selected, title: titles, small: style == .compact || titles)
                        .frame(width: collapsed ? Self.circle : cell, height: collapsed ? Self.circle : barH)
                        .contentShape(Rectangle())
                        .onTapGesture { tapped(tab, collapsed: collapsed) }
                        .scaleEffect(visible ? 1 : 0.5)
                        .opacity(visible ? 1 : 0)
                        .position(collapsed
                            ? CGPoint(x: toRight ? rightX : leftX, y: rowCenterY)
                            : CGPoint(x: barLeft + cell * (CGFloat(index) + 0.5), y: barCenterY))
                        .allowsHitTesting(visible)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .zIndex(selected ? 2 : 1)
                }

                if hasMini {
                    MiniPlayer(compact: collapsed, open: openPlayer)
                        .background(MiniPlayerSurface(height: miniHeight))
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
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Self.morph, value: style)
    }

    private func tapped(_ tab: Tab, collapsed: Bool) {
        Haptics.tap()
        if collapsed, tab == chrome.tab {
            chrome.expand()
        } else if tab == chrome.tab {
            router.popToRoot(tab)
        } else {
            chrome.select(tab)
        }
    }
}

/// Значок вкладки: выбранная — заливка цветом текста, остальные — контур приглушённо. В панелях во всю
/// ширину — с подписью снизу.
private struct TabIcon: View {
    let tab: Tab
    let selected: Bool
    var title = false
    var small = false

    var body: some View {
        VStack(spacing: 3) {
            SonarIcon(tab.icon, filled: selected, size: small ? 24 : 27)
            if title {
                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
            }
        }
        .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
        .scaleEffect(selected ? 1.04 : 1)
    }
}

/// Стекло панели (Интерфейс → Вид → Прозрачность и Тип стекла) и тонкая обводка. Форма — прямоугольник
/// со своими радиусами сверху и снизу: капсула, круг, закруглённые сверху или прямые углы.
private struct BarSurface: View {
    let top: CGFloat
    let bottom: CGFloat
    var tint: Color?
    /// Панель у края экрана: тень вверх, а не вниз.
    var edge = false

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                           bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
        GlassFill(shape: shape, tint: tint)
            .overlay(shape.stroke(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(Theme.isLight ? 0.1 : 0.28), radius: edge ? 10 : 14, y: edge ? -2 : 6)
    }
}
