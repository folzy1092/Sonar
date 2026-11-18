import SwiftUI

/// Spotify в «Сервисах» (как Windows «Сервисы»): вход в окне accounts.spotify.com (Sonar сам заберёт cookie
/// `sp_dc`) или ключ `sp_dc` вручную — с `sp_dc=` или без. На iPhone Spotify — только медиатека и ссылки:
/// трек играет резервный сервис (этап 4). Ключ — только в Keychain, на экран и в ошибки не попадает.
struct SpotifyServiceSection: View {
    @State private var account: ServiceAccount?
    @State private var spDc = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSection(title: "Spotify", footer: t("На iPhone Spotify не играет: лайки, плейлисты и поиск — отсюда, а трек сыграет резервный сервис. На ПК с Premium Spotify играет сам.")) {
                if let account {
                    connectedRow(account)
                        .transition(.opacity)
                } else {
                    loginForm
                        .transition(.opacity)
                }
            }
            if let error {
                Label {
                    Text(error)
                } icon: {
                    SonarIcon(.info, size: 16)
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
        }
        .animation(Motion.spring, value: account)
        .animation(Motion.spring, value: error)
        .task { account = await SpotifyCore.shared.account }
        .sheet(isPresented: $showLogin) {
            CookieLoginSheet(title: t("Вход в Spotify"), url: Spotify.loginURL, cookie: "sp_dc", domain: "spotify.com") { value in
                showLogin = false
                connect(value)
            }
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder private var loginForm: some View {
        Button { error = nil; showLogin = true } label: {
            HStack(spacing: 8) {
                SonarIcon(.enterDoor, size: 20)
                Text(t("Войти в Spotify"))
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .disabled(busy)
        RowDivider()
        SecureField(t("Ключ sp_dc"), text: $spDc)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 15, design: .monospaced))
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        RowDivider()
        Button { connect(spDc) } label: {
            HStack {
                if busy { ProgressView().tint(Theme.accent) }
                Text(busy ? t("Проверяю…") : t("Подключить"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(spDc.isEmpty ? Theme.textTertiary : Theme.accent)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .disabled(spDc.isEmpty || busy)
    }

    private func connectedRow(_ account: ServiceAccount) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: account.avatarURL, cornerRadius: 18).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name ?? t("Подключено"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(account.premium == true ? t("Подключено · Premium") : t("Подключено"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.success)
            }
            Spacer()
            Button(t("Отключить"), role: .destructive) {
                Task {
                    await SpotifyCore.shared.disconnect()
                    account = nil
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.danger)
        }
        .padding(16)
    }

    /// Ключ из окна входа или из поля → проверка токеном и `/me` → Keychain; после подключения поле очищается.
    private func connect(_ raw: String) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                account = try await SpotifyCore.shared.connect(spDc: raw)
                spDc = ""
            } catch {
                self.error = t(error.localizedDescription)
            }
        }
    }
}
