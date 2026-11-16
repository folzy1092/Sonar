import SwiftUI

/// Корень: экран вкладки + свой таб-бар снизу (не системный `TabView` — нужны три стиля и
/// сворачивание, SPEC §4.5). Мини-плеер и полный плеер добавятся над таб-баром.
struct RootView: View {
    @Environment(ChromeState.self) private var chrome

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            Group {
                switch chrome.tab {
                case .home: PlaceholderScreen(title: "Моя волна", note: "Главная: волна, подборки, недавнее")
                case .library: PlaceholderScreen(title: "Медиатека", note: "Все · Плейлисты · Альбомы · Исполнители")
                case .search: PlaceholderScreen(title: "Поиск", note: "SoundCloud и Яндекс Музыка")
                case .profile: PlaceholderScreen(title: "Профиль", note: "Шапка и меню настроек")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            TabBar()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.25), value: chrome.tab)
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
