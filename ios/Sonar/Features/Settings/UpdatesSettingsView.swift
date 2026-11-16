import SwiftUI

/// Система → «Обновления» (SETTINGS.md «Автообновление», как вкладка «Обновления» в Windows): версия и
/// статус, «Проверять автоматически», канал, сертификат для подписи, архив версий.
struct UpdatesSettingsView: View {
    @Environment(UpdateChecker.self) private var checker
    @Environment(SelfUpdater.self) private var updater
    @Environment(SigningModel.self) private var signing
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        SettingsScreen(title: "Обновления") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .frame(width: 52, height: 52)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sonar \(UpdateChecker.installedLabel)")
                            .font(.system(size: 18, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                        Text("для iPhone")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if SelfUpdateText.row(updater) != nil {
                    NavigationLink { UpdateView() } label: { ProgressCard() }
                        .buttonStyle(PressableStyle(scale: 0.99))
                        .transition(.opacity)
                } else if let release = checker.available {
                    NavigationLink {
                        UpdateView()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Доступно обновление")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text("\(release.label) · \(UpdateCounts(release).text)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(16)
                        .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.accent.opacity(0.5)))
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    StatusLine()
                }
            }
            .cascade(0)

            SettingsSection(title: "Автообновление") {
                SettingsToggle(title: "Проверять автоматически", subtitle: "При запуске и раз в 6 часов",
                               isOn: Binding(get: { settings.bool("update.auto_check") },
                                             set: { settings.set("update.auto_check", $0) }))
            }
            .cascade(1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Канал")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 4)
                HStack(spacing: 10) {
                    OptionTile(icon: "checkmark.shield", title: "Стабильный", subtitle: "Объявленные сборки",
                               selected: settings.string("update.channel") == "stable") {
                        settings.set("update.channel", .string("stable"))
                    }
                    OptionTile(icon: "flask", title: "Бета", subtitle: "Скоро", soon: true)
                }
            }
            .cascade(2)

            SettingsSection(title: "Установка", footer: "Сертификат нужен, чтобы Sonar сам ставил обновления, без ESign. Без него «Обновить» откроет ссылку на IPA.") {
                NavigationLink { SigningPairView() } label: {
                    SettingsRowLabel(icon: "key", title: "Сертификат для подписи", value: signing.summary)
                }
                .buttonStyle(PressableStyle(scale: 0.99))
                RowDivider()
                NavigationLink { VersionArchiveView() } label: {
                    SettingsRowLabel(icon: "clock.arrow.circlepath", title: "Архив версий")
                }
                .buttonStyle(PressableStyle(scale: 0.99))
            }
            .cascade(3)
        }
        .animation(Motion.spring, value: checker.status)
        .animation(Motion.spring, value: updater.stage)
        .onAppear {
            signing.reload()
            if signing.isConfigured, signing.check == .idle { signing.recheck() }
        }
        .task {
            if checker.status == nil { await checker.check() }
        }
    }
}
