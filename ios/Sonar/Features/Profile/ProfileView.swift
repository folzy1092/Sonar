import SwiftUI

/// Профиль (`photo_1..3`, SETTINGS.md «Меню настроек iOS»): шапка и меню разделов — тот же порядок и
/// названия, что вкладки настроек в Windows. Разделы, которых ещё нет на iPhone, видны приглушёнными
/// с пометкой «Скоро»; Приватность — с замком (не делаем).
struct ProfileView: View {
    @Environment(ChromeState.self) private var chrome
    @Environment(UpdateChecker.self) private var checker

    private struct Item: Identifiable {
        let icon: String
        let title: String
        var locked = false
        var id: String { title }
    }

    private let sections: [(String, [Item])] = [
        ("Аккаунт", [Item(icon: "chart.bar", title: "Статистика"), Item(icon: "lock.shield", title: "Безопасность"),
                     Item(icon: "hand.raised", title: "Приватность", locked: true)]),
        ("Интерфейс", [Item(icon: "paintpalette", title: "Вид"), Item(icon: "square.grid.2x2", title: "Вкладки")]),
        ("Плеер", [Item(icon: "speaker.wave.2", title: "Аудио"), Item(icon: "play.rectangle", title: "Вид плеера"),
                   Item(icon: "list.bullet", title: "Очередь"), Item(icon: "rectangle.bottomthird.inset.filled", title: "Мини-плеер"),
                   Item(icon: "hand.tap", title: "Жесты")]),
    ]
    private let integrations = [Item(icon: "dot.radiowaves.left.and.right", title: "Last.fm"), Item(icon: "key.horizontal", title: "Ключ API")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                    .cascade(0)
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    SettingsSection(title: section.0) {
                        ForEach(Array(section.1.enumerated()), id: \.element.id) { row, item in
                            if row > 0 { RowDivider() }
                            if item.title == "Мини-плеер" {
                                NavigationLink { MiniPlayerSettingsView() } label: {
                                    SettingsRowLabel(icon: item.icon, title: item.title)
                                }
                                .buttonStyle(PressableStyle(scale: 0.99))
                            } else {
                                SettingsRowLabel(icon: item.icon, title: item.title, value: item.locked ? "В разработке" : "Скоро",
                                                 chevron: false, locked: item.locked, dimmed: true)
                            }
                        }
                    }
                    .cascade(index + 1)
                }
                SettingsSection(title: "Сервисы") {
                    NavigationLink { ServicesView() } label: {
                        SettingsRowLabel(icon: "cloud", title: "SoundCloud")
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    RowDivider()
                    NavigationLink { ServicesView() } label: {
                        SettingsRowLabel(icon: "music.note", title: "Яндекс Музыка")
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                }
                .cascade(sections.count)
                SettingsSection(title: "Интеграции") {
                    ForEach(Array(integrations.enumerated()), id: \.element.id) { row, item in
                        if row > 0 { RowDivider() }
                        SettingsRowLabel(icon: item.icon, title: item.title, value: "Скоро", chevron: false, dimmed: true)
                    }
                }
                .cascade(sections.count + 1)
                SettingsSection(title: "Система") {
                    SettingsRowLabel(icon: "gearshape", title: "Общее", value: "Скоро", chevron: false, dimmed: true)
                    RowDivider()
                    NavigationLink {
                        UpdatesSettingsView()
                    } label: {
                        SettingsRowLabel(icon: "arrow.down.circle", title: "Обновления", badge: checker.available != nil)
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    RowDivider()
                    SettingsRowLabel(icon: "internaldrive", title: "Хранилище", value: "Скоро", chevron: false, dimmed: true)
                }
                .cascade(sections.count + 2)
                about
                    .cascade(sections.count + 3)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            chrome.scrolled(to: offset)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.spring, value: checker.available)
    }

    /// Шапка: только аватар, имя, @username (без баннера и значков). Аккаунт появится с сервером —
    /// до тех пор локальный профиль.
    private var header: some View {
        HStack(spacing: 14) {
            Text("S")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Theme.accentInk)
                .frame(width: 72, height: 72)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Sonar")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Аккаунт появится вместе с сервером")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line))
    }

    /// «О приложении» — внизу, как в «Общем» на Windows.
    private var about: some View {
        VStack(spacing: 6) {
            Text("Sonar \(UpdateChecker.installedLabel)")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 18) {
                Link("Сайт", destination: URL(string: "https://sonar.folzy.ru")!)
                Link("Телеграм", destination: URL(string: "https://t.me/SonarUpdates")!)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}
