import SwiftUI

/// Корень: экран вкладки + свой таб-бар снизу (не системный `TabView` — нужны три стиля и
/// сворачивание, SPEC §4.5). Над таб-баром — всплывашка «Доступно обновление»; мини-плеер и полный
/// плеер добавятся туда же.
struct RootView: View {
    @Environment(ChromeState.self) private var chrome
    @Environment(UpdateChecker.self) private var checker
    @State private var showUpdate = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            Group {
                switch chrome.tab {
                case .home: PlaceholderScreen(title: "Моя волна", note: "Главная: волна, подборки, недавнее")
                case .library: PlaceholderScreen(title: "Медиатека", note: "Все · Плейлисты · Альбомы · Исполнители")
                case .search: PlaceholderScreen(title: "Поиск", note: "SoundCloud и Яндекс Музыка")
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
                TabBar()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.25), value: chrome.tab)
        .animation(Motion.spring, value: checker.popup)
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
                    chrome.tab = tab
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
