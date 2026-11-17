import SwiftUI

/// Аккаунт → Безопасность (когда есть сервер; до него в Профиле — `ServerOnlyView(.security)`): пароль,
/// привязанный Telegram, устройства, выход. Структура — как на ПК (PLATFORMS.md «Аккаунт»).
struct AccountSecurityView: View {
    @State private var account = AccountStore.shared
    @State private var editingPassword = false
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var repeatPassword = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var linking: Task<Void, Never>?
    @State private var confirmUnlink = false
    @State private var confirmLogout = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        SystemScreen(title: t("Безопасность")) {
            if let user = account.user {
                SystemSection(title: t("Аккаунт")) {
                    SystemRow(icon: .user, title: "@\(user.username)", subtitle: t("Логин: {login}", ["login": user.login]),
                              value: user.number.map { "#\($0)" })
                }
                .cascade(0)

                SystemSection(title: t("Пароль"), footer: user.hasPassword ? nil : t("Пароля ещё нет — ты входил только через Telegram.")) {
                    if editingPassword {
                        passwordForm(hasPassword: user.hasPassword)
                            .transition(.opacity)
                    } else {
                        SystemButtonRow(icon: .lock, title: user.hasPassword ? t("Сменить пароль") : t("Задать пароль"), chevron: true) {
                            withAnimation(Motion.spring) { editingPassword = true }
                        }
                    }
                }
                .cascade(1)

                SystemSection(title: "Telegram", footer: telegramFooter(user)) {
                    if let tg = user.telegram {
                        SystemRow(icon: .telegram, title: tg.username.map { "@\($0)" } ?? t("Привязан"), subtitle: t("Быстрый вход на новых устройствах"))
                        RowDivider()
                        SystemButtonRow(icon: .close, title: t("Отвязать Telegram"), tint: Theme.danger, enabled: user.hasPassword && !busy) {
                            confirmUnlink = true
                        }
                    } else if linking != nil {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.textSecondary)
                            Text(t("Подтверди привязку в боте @SonarMusicApp"))
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Button(t("Отмена")) {
                                linking?.cancel()
                                linking = nil
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                        }
                        .padding(16)
                    } else {
                        SystemButtonRow(icon: .telegram, title: t("Привязать Telegram"), subtitle: t("Откроется бот @SonarMusicApp"), chevron: true) {
                            linkTelegram()
                        }
                    }
                }
                .cascade(2)

                SystemSection(title: t("Устройства")) {
                    NavigationLink {
                        DevicesView()
                    } label: {
                        SystemRow(icon: .cellphone, title: t("Где ты вошёл"), subtitle: t("Выйти на любом устройстве"),
                                  value: account.devices.isEmpty ? nil : String(account.devices.count), chevron: true)
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                }
                .cascade(3)

                if let error { AccountError(text: error) }
                if let notice {
                    Text(notice)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.success)
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                }

                SystemSection {
                    SystemButtonRow(icon: .exit, title: t("Выйти из аккаунта"), tint: Theme.danger) { confirmLogout = true }
                }
                .cascade(4)
            }
        }
        .animation(Motion.spring, value: account.user)
        .animation(Motion.spring, value: error)
        .animation(Motion.spring, value: notice)
        .task {
            try? await account.refreshMe()
            try? await account.loadDevices()
        }
        .onDisappear { linking?.cancel() }
        .alert(t("Отвязать Telegram?"), isPresented: $confirmUnlink) {
            Button(t("Отвязать"), role: .destructive) { unlink() }
            Button(t("Отмена"), role: .cancel) {}
        } message: {
            Text(t("Входить можно будет только логином и паролем."))
        }
        .alert(t("Выйти из аккаунта?"), isPresented: $confirmLogout) {
            Button(t("Выйти"), role: .destructive) { Task { await account.logout() } }
            Button(t("Отмена"), role: .cancel) {}
        } message: {
            Text(t("Придётся авторизоваться заново. Музыка и скачанное на телефоне останутся."))
        }
    }

    private func telegramFooter(_ user: AccountUser) -> String? {
        if user.telegram != nil, !user.hasPassword { return t("Сначала задай пароль — без него Telegram отвязать нельзя.") }
        return nil
    }

    private func passwordForm(hasPassword: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if hasPassword {
                AccountField(title: t("Текущий пароль"), text: $oldPassword, secure: true, contentType: .password)
            }
            AccountField(title: t("Новый пароль"), text: $newPassword, secure: true, contentType: .newPassword,
                         problem: newPassword.isEmpty ? nil : AccountValidation.passwordProblem(newPassword).map { t($0) })
            AccountField(title: t("Пароль ещё раз"), text: $repeatPassword, secure: true, contentType: .newPassword,
                         problem: repeatPassword.isEmpty || repeatPassword == newPassword ? nil : t("Пароли не совпадают"))
            HStack(spacing: 10) {
                SecondaryButton(title: t("Отмена")) { closeForm() }
                PrimaryButton(title: busy ? t("Сохраняю…") : t("Сохранить"), enabled: canSave(hasPassword: hasPassword)) {
                    savePassword(hasPassword: hasPassword)
                }
            }
        }
        .padding(16)
    }

    private func canSave(hasPassword: Bool) -> Bool {
        !busy && (!hasPassword || !oldPassword.isEmpty) && AccountValidation.passwordProblem(newPassword) == nil && newPassword == repeatPassword
    }

    private func closeForm() {
        withAnimation(Motion.spring) { editingPassword = false }
        oldPassword = ""
        newPassword = ""
        repeatPassword = ""
    }

    private func savePassword(hasPassword: Bool) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await account.changePassword(old: hasPassword ? oldPassword : nil, new: newPassword)
                closeForm()
                notice = t("Пароль сохранён")
                Haptics.tap()
            } catch {
                self.error = t(error.localizedDescription)
            }
        }
    }

    private func linkTelegram() {
        error = nil
        linking = Task {
            defer { linking = nil }
            do {
                if try await account.linkTelegram(open: { openURL($0) }) {
                    notice = t("Telegram привязан")
                    Haptics.tap()
                } else {
                    error = t("Ссылка истекла — попробуй ещё раз")
                }
            } catch is CancellationError {
            } catch {
                self.error = t(error.localizedDescription)
            }
        }
    }

    private func unlink() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await account.unlinkTelegram()
            } catch {
                self.error = t(error.localizedDescription)
            }
        }
    }
}
