import SwiftUI

/// Корень: экран вкладки + свой таб-бар снизу (не системный `TabView` — нужны три стиля и
/// сворачивание, SPEC §4.5). Над таб-баром — всплывашка «Доступно обновление»; мини-плеер и полный
/// плеер добавятся туда же.
struct RootView: View {
    @Environment(ChromeState.self) private var chrome
    @Environment(UpdateChecker.self) private var checker
    @Environment(PlaybackEngine.self) private var engine
    @State private var showUpdate = false
    @State private var showPlayer = false
    @Namespace private var bar

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            Group {
                switch chrome.tab {
                case .home: PlaceholderScreen(title: "Моя волна", note: "Главная: волна, подборки, недавнее")
                case .library: LibraryView()
                case .search: SearchView()
                case .profile: NavigationStack { ProfileView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            VStack(spacing: 10) {
                if let release = checker.popup {
                    UpdatePopup(release: release) {
                        // открыл подробности — значит, увидел: для этой сборки больше не всплываем, бейдж остаётся
                        withAnimation(Motion.spring) { checker.dismissPopup() }
                        showUpdate = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .bottom)))
                }
                if chrome.collapsed, engine.current != nil {
                    // свёрнуто (SPEC §4.5, photo_29): [вкладка ○] [мини-плеер] [поиск ○]
                    HStack(spacing: 10) {
                        RoundBarButton(symbol: chrome.tab.selectedSymbol) { withAnimation(Motion.spring) { chrome.expand() } }
                            .matchedGeometryEffect(id: "tabs", in: bar)
                        MiniPlayer(compact: true) { showPlayer = true }
                            .matchedGeometryEffect(id: "mini", in: bar)
                        RoundBarButton(symbol: "magnifyingglass") {
                            withAnimation(Motion.spring) { chrome.select(.search) }
                        }
                    }
                } else {
                    if engine.current != nil {
                        MiniPlayer { showPlayer = true }
                            .matchedGeometryEffect(id: "mini", in: bar)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    TabBar()
                        .matchedGeometryEffect(id: "tabs", in: bar)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.25), value: chrome.tab)
        .animation(Motion.spring, value: checker.popup)
        .animation(Motion.spring, value: engine.current == nil)
        .animation(Motion.spring, value: chrome.collapsed)
        .fullScreenCover(isPresented: $showPlayer) {
            FullPlayerView()
        }
        .sheet(isPresented: $showUpdate) {
            NavigationStack { UpdateView() }
                .presentationBackground(Theme.background)
        }
    }
}

/// Нижняя панель-капсула. Выбранная вкладка — залитая иконка цветом темы (как в ПК-клиенте).
struct TabBar: View {
    @Environment(ChromeState.self) private var chrome

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    chrome.select(tab)
                } label: {
                    Image(systemName: chrome.tab == tab ? tab.selectedSymbol : tab.symbol)
                        .font(.system(size: 21, weight: chrome.tab == tab ? .bold : .medium))
                        .foregroundStyle(chrome.tab == tab ? Theme.accent : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                        .symbolEffect(.bounce, value: chrome.tab == tab)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Круглая кнопка свёрнутой панели.
struct RoundBarButton: View {
    let symbol: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 54, height: 54)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}

/// Временный экран вкладки — пока раздел не написан.
struct PlaceholderScreen: View {
    let title: String
    let note: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(Theme.text)
            Text(note)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding()
    }
}
