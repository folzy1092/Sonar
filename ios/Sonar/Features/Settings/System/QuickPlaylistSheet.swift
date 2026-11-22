import SwiftUI
import UIKit

/// Лист выбора «Быстрого плейлиста» (Система → Общее → «Виджет и Siri», `widget.quick_playlist`): Любимые,
/// Скачанные и плейлисты сервисов из Медиатеки. Выбранный — галочкой; выбор сразу сохраняется. Его играют
/// кнопка виджета `sonar://play/quick` и команда Siri «Включи быстрый плейлист».
struct QuickPlaylistSheet: View {
    @Environment(SettingsStore.self) private var settings
    @State private var playlists: [ServicePlaylist] = []
    @State private var loading = true

    /// Подпись выбранного — для строки в настройках.
    static func title(of settings: SettingsStore) -> String {
        switch QuickPlaylist(setting: settings.string(QuickPlaylist.key)) {
        case .liked: t("Любимые")
        case .downloaded: t("Скачанные")
        case .service:
            settings.string(QuickPlaylist.titleKey).isEmpty ? t("Плейлист") : settings.string(QuickPlaylist.titleKey)
        }
    }

    private var selected: QuickPlaylist { QuickPlaylist(setting: settings.string(QuickPlaylist.key)) }

    private func choose(_ choice: QuickPlaylist, title: String) {
        withAnimation(Motion.spring) {
            settings.set(QuickPlaylist.key, .string(choice.setting))
            settings.set(QuickPlaylist.titleKey, .string(title))
        }
        Haptics.select()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(t("Быстрый плейлист"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 26)
                VStack(spacing: 0) {
                    row(.liked, title: t("Любимые"), icon: .heart, index: 0)
                    RowDivider()
                    row(.downloaded, title: t("Скачанные"), icon: .download, index: 1)
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

                Text(t("Плейлисты сервисов"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 4)
                if loading {
                    ProgressView()
                        .tint(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .transition(.opacity)
                } else if playlists.isEmpty {
                    Text(t("Подключи SoundCloud или Яндекс Музыку в Сервисах — здесь появятся их плейлисты"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(playlists.enumerated()), id: \.element.ref) { index, playlist in
                            if index > 0 { RowDivider() }
                            row(.service(playlist.ref), title: playlist.title, icon: .music, index: index + 2)
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .transition(.opacity)
                }
                if Features.widgetsVisible {
                    Text(t("Играет кнопка «Быстрый плейлист» в виджете и команда Siri"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .task {
            let found = await MusicCore.shared.myPlaylists()
            withAnimation(Motion.spring) {
                playlists = found
                loading = false
            }
        }
    }

    private func row(_ choice: QuickPlaylist, title: String, icon: IconName, index: Int) -> some View {
        let on = selected == choice
        return Button { choose(choice, title: title) } label: {
            HStack(spacing: 14) {
                SonarIcon(icon, filled: on, size: 22)
                    .foregroundStyle(on ? Theme.accent : Theme.textSecondary)
                    .frame(width: 26)
                Text(title)
                    .font(.system(size: 17, weight: on ? .semibold : .regular))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                SonarIcon(.check, size: 20)
                    .foregroundStyle(Theme.accent)
                    .opacity(on ? 1 : 0)
                    .scaleEffect(on ? 1 : 0.6)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .animation(Motion.spring, value: on)
        .cascade(index)
    }
}
