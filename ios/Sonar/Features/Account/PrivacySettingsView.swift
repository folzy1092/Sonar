import SwiftUI

/// Аккаунт → Приватность (как ПК `pages/settings/Privacy.svelte`): кто может позвать в друзья и кто что
/// видит по ссылке на профиль. До сервера — только настройки `privacy.*`; правила — `Core/Account/Privacy.swift`.
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
        }
    }

    private var friendRequests: Binding<FriendRequests> {
        Binding(
            get: { FriendRequests.of(settings.value(PrivacyKey.friendRequests)) },
            set: { settings.set(PrivacyKey.friendRequests, .string($0.rawValue)) }
        )
    }

    private func audience(_ key: String) -> Binding<Audience> {
        Binding(get: { Audience.of(settings.value(key)) }, set: { settings.set(key, .string($0.rawValue)) })
    }

    private func icon(_ key: String) -> IconName {
        switch key {
        case "privacy.playlists": .library
        case "privacy.likes": .heart
        case "privacy.now_playing": .headphone
        default: .stats
        }
    }
}
