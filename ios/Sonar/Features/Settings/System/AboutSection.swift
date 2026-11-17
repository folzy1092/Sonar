import SwiftUI
import UIKit

/// Низ «Общего» — «О приложении» (как Windows `AboutBlock.svelte`): знак Sonar, название и версия,
/// ссылки (Сайт, Телеграм, Соглашение, Конфиденциальность), «Сбросить настройки» с подтверждением.
/// Двойной тап по знаку — проверка обновлений: знак раскручивается; нового нет — на его месте галочка и
/// «Новых обновлений не найдено»; есть — открывается «Обновление».
struct AboutSection: View {
    enum Mark { case idle, spin, done }

    static let site = "https://sonar.folzy.ru"
    static let links: [(title: String, icon: IconName, url: String)] = [
        ("Сайт", .globe, site),
        ("Телеграм", .telegram, "https://t.me/SonarUpdates"),
        ("Соглашение", .document, "\(site)/terms"),
        ("Конфиденциальность", .shield, "\(site)/privacy"),
    ]

    @Environment(UpdateChecker.self) private var checker
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var mark: Mark = .idle
    @State private var turns = 0.0
    @State private var confirmReset = false
    @State private var showUpdate = false

    var body: some View {
        VStack(spacing: 18) {
            Rectangle().fill(Theme.line).frame(height: 1)
                .padding(.bottom, 8)

            ZStack {
                LogoMark(size: 64)
                    .foregroundStyle(Theme.text)
                    .rotationEffect(.degrees(turns * 360))
                    .scaleEffect(mark == .done ? 0.4 : 1)
                    .opacity(mark == .done ? 0 : 1)
                SonarIcon(.check, size: 40)
                    .foregroundStyle(Theme.success)
                    .scaleEffect(mark == .done ? 1 : 0.4)
                    .opacity(mark == .done ? 1 : 0)
            }
            .frame(width: 84, height: 84)
            .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { check() }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(t("Проверить обновления"))
            .accessibilityHint(t("Дважды нажми — проверю обновления"))
            .accessibilityAction { check() }

            VStack(spacing: 4) {
                Text(verbatim: "Sonar")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Text(t("Версия {version}", ["version": UpdateChecker.installedLabel]))
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                Text(t("Дважды нажми на знак — проверю обновления"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Self.links, id: \.title) { link in
                    Button {
                        if let url = URL(string: link.url) { openURL(url) }
                    } label: {
                        HStack(spacing: 8) {
                            SonarIcon(link.icon, size: 18)
                            Text(t(link.title))
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.line))
                    }
                    .buttonStyle(PressableStyle(scale: 0.96))
                }
            }

            Button(role: .destructive) {
                confirmReset = true
            } label: {
                HStack(spacing: 8) {
                    SonarIcon(.refresh, size: 18)
                    Text(t("Сбросить настройки"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.danger.opacity(0.1), in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .confirmationDialog(t("Сбросить все настройки? Лайки, плейлисты и сервисы останутся."),
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button(t("Сбросить"), role: .destructive) { reset() }
                Button(t("Отмена"), role: .cancel) {}
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .navigationDestination(isPresented: $showUpdate) { UpdateView() }
    }

    private func check() {
        guard mark == .idle else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        mark = .spin
        withAnimation(.easeInOut(duration: 1.0)) { turns += 2 }
        Task {
            let started = Date()
            await checker.check()
            // крутится не меньше секунды, даже если ответ пришёл мгновенно
            let left = 1 - Date().timeIntervalSince(started)
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            switch checker.status {
            case let .available(release)?:
                router.say(t("Доступна версия {version}", ["version": release.label]))
                mark = .idle
                showUpdate = true
            case let .failed(message)?:
                router.say(message.isEmpty ? t("Не удалось проверить обновления") : message)
                mark = .idle
            default:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(Motion.spring) { mark = .done }
                router.say(t("Новых обновлений не найдено — у тебя последняя версия"))
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(Motion.spring) { mark = .idle }
            }
        }
    }

    private func reset() {
        settings.resetToDefaults()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        router.say(t("Настройки сброшены"))
    }
}

extension SettingsStore {
    /// «Сбросить настройки»: все ключи с умолчанием — к умолчанию, язык — как в системе. Лайки, плейлисты,
    /// сервисы и пара для подписи хранятся не здесь и остаются.
    func resetToDefaults() {
        for (key, value) in Self.defaults {
            set(key, value)
        }
        set(Lang.settingKey, .string(""))
    }
}
