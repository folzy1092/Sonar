import SwiftUI

/// Профиль (`photo_1..3`, SETTINGS.md «Меню настроек iOS»): шапка — аватар, имя, «Поделиться» и ✎;
/// ниже разделы в стеклянных карточках, порядок и названия — как вкладки настроек на Windows. Без сервера
/// аккаунта нет: «Безопасность», «Приватность», «Ключ API» — честные экраны «появится с сервером».
struct ProfileView: View {
    @Environment(ChromeState.self) private var chrome
    @Environment(UpdateChecker.self) private var checker
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                    .cascade(0)
                section("Аккаунт", 1) {
                    link("Статистика", .stats) { StatsView() }
                    divider
                    link("Безопасность", .lock) {
                        if AccountStore.serverEnabled { AccountSecurityView() } else { ServerOnlyView(.security) }
                    }
                    divider
                    link("Приватность", .shield, value: "В разработке") {
                        ServerOnlyView(.privacy)
                    }
                }
                section("Интерфейс", 2) {
                    link("Вид", .palette) { LookSettingsView() }
                    divider
                    link("Вкладки", .grid) { TabsSettingsView() }
                }
                section("Плеер", 3) {
                    link("Аудио", .sliders) { AudioSettingsView() }
                    divider
                    link("Вид плеера", .play) { PlayerViewSettingsView() }
                    divider
                    link("Очередь", .queue) { QueueSettingsView() }
                    divider
                    link("Мини-плеер", .capsule) { MiniPlayerSettingsView() }
                    divider
                    link("Жесты", .wave) { GesturesSettingsView() }
                }
                section("Сервисы", 4) {
                    link("SoundCloud", .soundcloud) { ServicesView() }
                    divider
                    link("Яндекс Музыка", .music) { ServicesView() }
                }
                section("Интеграции", 5) {
                    link("Last.fm", .wave) { LastfmSettingsView() }
                    divider
                    link("Ключ API", .link) {
                        ServerOnlyView(.apiKey)
                    }
                }
                section("Система", 6) {
                    link("Общее", .settings) { GeneralSettingsView() }
                    divider
                    link("Обновления", .download, badge: checker.available != nil) { UpdatesSettingsView() }
                    divider
                    link("Хранилище", .album) { StorageSettingsView() }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            if chrome.tab == .profile { chrome.scrolled(to: offset) }
        }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.spring, value: checker.available)
    }

    /// Шапка (`photo_1`): аватар в обводке акцентом, имя, подпись; «Поделиться» — широкая кнопка акцентом, ✎ — профиль.
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ProfileAvatar(size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalProfile.name(settings))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("Аккаунт Sonar появится вместе с сервером")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                ShareLink(item: URL(string: "https://sonar.folzy.ru")!, message: Text("Слушаю музыку в Sonar")) {
                    HStack(spacing: 10) {
                        SonarIcon(.share, size: 22)
                        Text("Поделиться")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                NavigationLink { ProfileEditView() } label: {
                    SonarIcon(.edit, size: 24)
                        .foregroundStyle(Theme.text)
                        .frame(width: 52, height: 52)
                        .background(Theme.raised, in: Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("Изменить профиль")
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.line))
    }

    private func section<Content: View>(_ title: String, _ index: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 8)
            VStack(spacing: 0) { content() }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line))
        }
        .cascade(index)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 58)
    }

    /// Строка раздела: значок MingCute, название, значение / бейдж, › — открывает экран.
    private func link<Destination: View>(_ title: String, _ icon: IconName, value: String? = nil, badge: Bool = false,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 16) {
                SonarIcon(icon, size: 24)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                if badge {
                    Circle().fill(Theme.accent).frame(width: 9, height: 9)
                        .transition(.scale.combined(with: .opacity))
                }
                if let value {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                }
                SonarIcon(.chevronRight, size: 20)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
    }
}
