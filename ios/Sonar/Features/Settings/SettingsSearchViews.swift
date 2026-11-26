import SwiftUI

// Поиск по настройкам в Профиле: значки и экраны для `SettingsPane` (каталог и поиск — `Core/Settings/SettingsSearch.swift`)
// и строка результата. Профиль и результаты поиска открывают экраны отсюда же — один источник на оба места.

extension SettingsPane {
    /// Значок строки — тот же, что в Профиле.
    var icon: IconName {
        switch self {
        case .profile: .edit
        case .stats: .stats
        case .security: .lock
        case .privacy: .shield
        case .subscription: .waveLine
        case .look: .palette
        case .appIcon: .square
        case .tabs: .grid
        case .audio: .sliders
        case .playerView: .play
        case .queue: .queue
        case .taste: .dislike
        case .miniPlayer: .capsule
        case .gestures: .wave
        case .soundcloud: .soundcloud
        case .yandex: Service.yandex.icon
        case .youtube: Service.youtube.icon
        case .apiKey: .link
        case .general: .settings
        case .updates: .download
        case .storage: .album
        }
    }
}

/// Экран настроек по пункту: без сервера «Безопасность» и «Ключ API» — экраны «появится с сервером».
struct SettingsDestination: View {
    let pane: SettingsPane

    var body: some View {
        switch pane {
        case .profile: ProfileEditView()
        case .stats: StatsView()
        case .security:
            if AccountStore.serverEnabled { AccountSecurityView() } else { ServerOnlyView(.security) }
        case .privacy: PrivacySettingsView()
        case .subscription: SonarDeepView()
        case .look: LookSettingsView()
        case .appIcon: AppIconSettingsView()
        case .tabs: TabsSettingsView()
        case .audio: AudioSettingsView()
        case .playerView: PlayerViewSettingsView()
        case .queue: QueueSettingsView()
        case .taste: TasteSettingsView()
        case .miniPlayer: MiniPlayerSettingsView()
        case .gestures: GesturesSettingsView()
        case .soundcloud: ServicesView(only: .soundcloud)
        case .yandex: ServicesView(only: .yandex)
        case .youtube: ServicesView(only: .youtube)
        case .apiKey:
            if AccountStore.serverEnabled { ApiKeyView() } else { ServerOnlyView(.apiKey) }
        case .general: GeneralSettingsView()
        case .updates: UpdatesSettingsView()
        case .storage: StorageSettingsView()
        }
    }
}

/// Строка результата: значок экрана, название с подсветкой совпадений, путь «Раздел → Экран», ›.
struct SettingsHitRow: View {
    let item: SettingsItem
    let query: String

    var body: some View {
        let lang = currentLang()
        NavigationLink {
            SettingsDestination(pane: item.pane)
        } label: {
            HStack(spacing: 16) {
                SonarIcon(item.pane.icon, size: 24)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(highlighted(I18n.translate(item.title, lang: lang)))
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Text(item.path.map { I18n.translate($0, lang: lang) }.joined(separator: " → "))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                SonarIcon(.chevronRight, size: 20)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
    }

    /// Совпавшие со словами запроса куски — акцентом и жирнее.
    private func highlighted(_ text: String) -> AttributedString {
        SettingsSearch.marks(in: text, query: query).reduce(into: AttributedString()) { out, piece in
            var part = AttributedString(piece.text)
            if piece.isMatch {
                part.foregroundColor = Theme.accent
                part.font = .system(size: 17, weight: .semibold)
            }
            out.append(part)
        }
    }
}
