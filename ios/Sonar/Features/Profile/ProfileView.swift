import SwiftUI

/// Профиль (`photo_1..3`, SETTINGS.md «Меню настроек iOS»): шапка — аватар, имя, «Поделиться» и ✎;
/// ниже разделы в стеклянных карточках, порядок и названия — как вкладки настроек на Windows. Без сервера
/// аккаунта нет: «Безопасность» и «Ключ API» — честные экраны «появится с сервером»; «Приватность» до него —
/// только настройки `privacy.*`, «Подписка» (Sonar Deep) ведёт на оплату на сайте. Сверху — поиск по настройкам
/// (`SettingsSearch`, как на ПК): пока в строке что-то есть, вместо разделов — найденные пункты с путём.
struct ProfileView: View {
    @Environment(ChromeState.self) private var chrome
    @Environment(UpdateChecker.self) private var checker
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @State private var account = AccountStore.shared

    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// Тап по вкладке (и по левому кругу свёрнутой панели) — к профилю наверху, поиск сбрасывается.
    @State private var scroll = ScrollPosition(edge: .top)
    /// Этот экземпляр корня — для `Router.profileOnTop`.
    @State private var instance = UUID()

    /// Идёт поиск — вместо разделов список найденных пунктов.
    private var isSearching: Bool { !SettingsSearch.tokens(query).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                searchField
                    .cascade(0)
                if isSearching {
                    results
                        .transition(.opacity.combined(with: .offset(y: 10)))
                } else {
                    sections
                        .transition(.opacity.combined(with: .offset(y: 10)))
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition($scroll)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            if chrome.tab == .profile { chrome.scrolled(to: offset) }
        }
        .onChange(of: router.topTick[.profile]) {
            searchFocused = false
            withAnimation(Motion.settle) {
                query = ""
                scroll.scrollTo(edge: .top)
            }
        }
        .onAppear { router.profileOnTop = instance }
        .onDisappear { if router.profileOnTop == instance { router.profileOnTop = nil } }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.spring, value: checker.available)
        .animation(Motion.spring, value: isSearching)
    }

    /// Шапка и разделы — обычный Профиль, пока строка поиска пустая.
    private var sections: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
                .cascade(1)
            section("Аккаунт", 2) {
                link(.stats)
                divider
                link(.security)
                divider
                link(.privacy)
                divider
                link(.subscription, value: SonarDeep.name)
            }
            section("Интерфейс", 3) {
                link(.look)
                divider
                link(.tabs)
            }
            section("Плеер", 4) {
                link(.audio)
                divider
                link(.playerView)
                divider
                link(.queue)
                divider
                link(.taste)
                divider
                link(.miniPlayer)
                divider
                link(.gestures)
            }
            section("Сервисы", 5) {
                link(.soundcloud)
                divider
                link(.yandex)
                divider
                link(.youtube)
            }
            section("Интеграции", 6) {
                link(.apiKey)
            }
            section("Система", 7) {
                link(.general)
                divider
                link(.updates, badge: checker.available != nil)
                divider
                link(.storage)
            }
        }
    }

    /// Строка поиска по настройкам (как в Медиатеке); ✕ — очистить и вернуть разделы.
    private var searchField: some View {
        HStack(spacing: 10) {
            SonarIcon(.search, size: 20).foregroundStyle(Theme.textSecondary)
            TextField(t("Найти настройку"), text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .foregroundStyle(Theme.text)
                .accessibilityLabel(t("Поиск по настройкам"))
            if !query.isEmpty {
                Button {
                    withAnimation(Motion.spring) { query = "" }
                } label: {
                    SonarIcon(.close, size: 18)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.85))
                .accessibilityLabel(t("Очистить поиск"))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, query.isEmpty ? 18 : 8)
        .frame(height: 48)
        .background(Theme.raised.opacity(0.92), in: Capsule())
        .animation(Motion.quick, value: query.isEmpty)
    }

    /// Найденные пункты одной карточкой, по очереди каскадом; ничего — подсказка, какие слова пробовать.
    @ViewBuilder
    private var results: some View {
        let lang = currentLang()
        let hits = SettingsSearch.search(query) { I18n.translate($0, lang: lang) }
        if hits.isEmpty {
            HintCard(icon: .search, text: t("Ничего не нашлось — попробуй другое слово: «тема», «эквалайзер» или «кэш»"))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(hits.enumerated()), id: \.element) { index, item in
                    if index > 0 { divider }
                    SettingsHitRow(item: item, query: query)
                        .cascade(index)
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line))
            .animation(Motion.spring, value: hits)
        }
    }

    /// Подпись под именем: кто вошёл. Без входа (сервер недоступен или офлайн) — так и пишем, а не «появится с сервером».
    private var accountLine: String {
        if let user = account.user { return "@\(user.username)" + (user.number.map { " · #\($0)" } ?? "") }
        return account.enabled() ? t("Нет входа в аккаунт Sonar") : t("Аккаунт Sonar выключен")
    }

    /// Разработчик Sonar — значок «Dev» у имени (`SonarDeep.subscriptionOf`, до сервера — по нику).
    private var isDev: Bool {
        SonarDeep.subscriptionOf(username: settings.string(LookKey.profileUsername)).tier == .dev
    }

    /// Шапка (`photo_1`): аватар в обводке акцентом, имя, подпись; «Поделиться» — широкая кнопка акцентом, ✎ — профиль.
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ProfileAvatar(size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(LocalProfile.name(settings))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if isDev { DevBadge(size: 12) }
                    }
                    Text(accountLine)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                ShareLink(item: LocalProfile.shareURL(account: account.user?.username, local: settings.string(LookKey.profileUsername)),
                          message: Text("Слушаю музыку в Sonar")) {
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
                NavigationLink { SettingsDestination(pane: .profile) } label: {
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
            Text(t(title))
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

    /// Строка раздела: значок MingCute, название, значение / бейдж, › — открывает экран (`SettingsDestination`).
    private func link(_ pane: SettingsPane, value: String? = nil, badge: Bool = false) -> some View {
        NavigationLink {
            SettingsDestination(pane: pane)
        } label: {
            HStack(spacing: 16) {
                SonarIcon(pane.icon, size: 24)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28)
                Text(t(pane.title))
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
