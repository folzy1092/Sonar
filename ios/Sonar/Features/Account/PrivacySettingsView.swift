import SwiftUI

/// Аккаунт → Приватность (как ПК `pages/settings/Privacy.svelte`): кто может позвать в друзья и кто что
/// видит по ссылке на профиль, кто может писать и звать в комнату. До сервера — только настройки `privacy.*`; правила — `Core/Account/Privacy.swift`.
struct PrivacySettingsView: View {
    @Environment(SettingsStore.self) private var settings

    private var audiences: [SystemSegments<Audience>.Option] {
        Audience.allCases.map { .init(id: $0, title: t($0.title)) }
    }

    var body: some View {
        SystemScreen(title: t("Приватность")) {
            SystemSection(title: t("Друзья"), footer: t("Друзья и заявки заработают вместе с сервером")) {
                SystemChoiceRow(
                    icon: .userAdd,
                    title: t("Кто может добавить в друзья"),
                    subtitle: t("Остальные не смогут отправить заявку"),
                    options: FriendRequests.allCases.map { .init(id: $0, title: t($0.title)) },
                    selection: friendRequests
                )
            }
            .cascade(0)
            SystemSection(title: t("Профиль"), footer: t("Кто что видит по ссылке на твой профиль")) {
                ForEach(Array(PrivacyKey.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { RowDivider() }
                    SystemChoiceRow(icon: icon(row.key), title: t(row.title), subtitle: t(row.hint),
                                    options: audiences, selection: audience(row.key))
                }
            }
            .cascade(1)
            SystemSection(title: t("Комнаты и сообщения"), footer: t("Заработают вместе с сервером и друзьями")) {
                ForEach(Array(PrivacyKey.social.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { RowDivider() }
                    SystemChoiceRow(icon: icon(row.key), title: t(row.title), subtitle: t(row.hint),
                                    options: row.audiences.map { .init(id: $0, title: t($0.title)) },
                                    selection: audience(row.key, friendsOnly: row.friendsOnly))
                }
                RowDivider()
                NavigationLink {
                    SocialPreviewView()
                } label: {
                    SystemRow(icon: .userHeart, title: t("Как это будет выглядеть"), chevron: true)
                }
                .buttonStyle(PressableStyle(scale: 0.99))
            }
            .cascade(2)
        }
    }

    private var friendRequests: Binding<FriendRequests> {
        Binding(
            get: { FriendRequests.of(settings.value(PrivacyKey.friendRequests)) },
            set: { settings.set(PrivacyKey.friendRequests, .string($0.rawValue)) }
        )
    }

    private func audience(_ key: String, friendsOnly: Bool = false) -> Binding<Audience> {
        Binding(get: {
            let value = Audience.of(settings.value(key))
            return friendsOnly && value == .everyone ? .friends : value
        }, set: { settings.set(key, .string($0.rawValue)) })
    }

    private func icon(_ key: String) -> IconName {
        switch key {
        case "privacy.playlists": .library
        case "privacy.likes": .heart
        case "privacy.now_playing": .headphone
        case "privacy.messages": .share
        case "privacy.room_invites": .enterDoor
        case "privacy.room_visible": .globe
        default: .stats
        }
    }
}
