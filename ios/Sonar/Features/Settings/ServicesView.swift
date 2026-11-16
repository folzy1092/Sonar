import SwiftUI
import UIKit

/// Сервисы (`pc/Screenshot_12, 13`, как Windows «Сервисы»): SoundCloud — client_id и OAuth-токен
/// (без своих ключей поиск и открытые треки идут на публичном client_id с сайта), Яндекс Музыка —
/// токен `y0_…`. Ключи — только в Keychain этого iPhone.
struct ServicesView: View {
    @State private var status = MusicCore.Status()
    @State private var clientId = ""
    @State private var oauth = ""
    @State private var yandexToken = ""
    @State private var busy: Service?
    @State private var error: String?
    /// Вход в Яндекс по коду: код на экране, пока ждём подтверждения на ya.ru/device.
    @State private var deviceCode: YandexLogin.DeviceCode?
    @State private var login: Task<Void, Never>?
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsScreen(title: "Сервисы") {
            SettingsSection(title: "SoundCloud", footer: status.soundCloud == nil
                            ? "Без своих ключей поиск и открытые треки работают на публичном client_id с сайта. OAuth-токен нужен для лайков, плейлистов и закрытых треков."
                            : nil) {
                if let account = status.soundCloud {
                    connected(.soundcloud, account)
                } else {
                    field("client_id", text: $clientId)
                    RowDivider()
                    field("OAuth-токен (необязательно)", text: $oauth, secure: true)
                    RowDivider()
                    connectButton(.soundcloud, enabled: clientId.count >= 20) {
                        try await MusicCore.shared.connectSoundCloud(SoundCloudCreds(clientId: clientId, oauthToken: oauth))
                    }
                }
            }
            .cascade(0)

            SettingsSection(title: "Яндекс Музыка", footer: status.yandex == nil
                            ? "«Войти через Яндекс» покажет код и откроет ya.ru/device — подтверди вход там, Sonar заберёт токен сам. Или вставь токен y0_… вручную."
                            : nil) {
                if let account = status.yandex {
                    connected(.yandex, account)
                } else if let deviceCode {
                    codeView(deviceCode)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    Button(action: startYandexLogin) {
                        Label("Войти через Яндекс", systemImage: "person.badge.key")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .disabled(busy != nil)
                    RowDivider()
                    field("Токен y0_…", text: $yandexToken, secure: true)
                    RowDivider()
                    connectButton(.yandex, enabled: !yandexToken.isEmpty) {
                        try await MusicCore.shared.connectYandex(token: yandexToken)
                    }
                }
            }
            .cascade(1)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }

            SettingsSection(title: "Качество") {
                SettingsToggle(title: "SoundCloud в качестве Яндекса",
                               subtitle: "Если тот же трек есть на Яндексе — играть оттуда (FLAC / 320)",
                               isOn: Binding(get: { settings.bool("audio.sc_via_yandex") }, set: { settings.set("audio.sc_via_yandex", $0) }))
            }
            .cascade(2)
        }
        .animation(Motion.spring, value: status)
        .animation(Motion.spring, value: deviceCode)
        .onDisappear { login?.cancel() }
        .animation(Motion.spring, value: error)
        .task { status = await MusicCore.shared.status() }
        .onChange(of: settings.bool("audio.sc_via_yandex")) { applySettings() }
    }

    /// Код устройства → ya.ru/device в Safari → ждём подтверждения → токен → подключение.
    private func startYandexLogin() {
        error = nil
        busy = .yandex
        login?.cancel()
        login = Task {
            defer {
                busy = nil
                deviceCode = nil
            }
            do {
                let code = try await YandexLogin.start(deviceId: Self.deviceId)
                deviceCode = code
                openURL(code.url)
                let token = try await YandexLogin.waitToken(code)
                _ = try await MusicCore.shared.connectYandex(token: token)
                status = await MusicCore.shared.status()
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Постоянный id этого iPhone для входа по коду (Яндекс показывает его в списке устройств).
    private static var deviceId: String {
        let key = "sonar.device_id"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    private func codeView(_ code: YandexLogin.DeviceCode) -> some View {
        VStack(spacing: 12) {
            Text("Введи код на ya.ru/device")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Text(code.userCode)
                .font(.system(size: 34, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                SecondaryButton(title: "Скопировать", icon: "doc.on.doc") { UIPasteboard.general.string = code.userCode }
                SecondaryButton(title: "Открыть", icon: "safari") { openURL(code.url) }
            }
            HStack(spacing: 8) {
                ProgressView().tint(Theme.textSecondary)
                Text("Жду подтверждения…").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Отмена") { login?.cancel() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(16)
    }

    private func applySettings() {
        let kbps = MusicCore.qualityKbps(settings.string("audio.quality"))
        let viaYandex = settings.bool("audio.sc_via_yandex")
        Task { await MusicCore.shared.configure(maxKbps: kbps, soundCloudViaYandex: viaYandex) }
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool = false) -> some View {
        Group {
            if secure {
                SecureField(title, text: text)
            } else {
                TextField(title, text: text)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.system(size: 15, design: .monospaced))
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func connectButton(_ service: Service, enabled: Bool, _ connect: @escaping @MainActor () async throws -> ServiceAccount) -> some View {
        Button {
            busy = service
            error = nil
            Task {
                do {
                    _ = try await connect()
                    status = await MusicCore.shared.status()
                } catch {
                    self.error = error.localizedDescription
                }
                busy = nil
            }
        } label: {
            HStack {
                if busy == service { ProgressView().tint(Theme.accent) }
                Text(busy == service ? "Проверяю…" : "Подключить")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(enabled ? Theme.accent : Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .disabled(!enabled || busy != nil)
    }

    private func connected(_ service: Service, _ account: ServiceAccount) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: account.avatarURL, cornerRadius: 18).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name ?? "Подключено")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text("Подключено").font(.system(size: 13)).foregroundStyle(Theme.success)
            }
            Spacer()
            Button("Отключить", role: .destructive) {
                Task {
                    await MusicCore.shared.disconnect(service)
                    status = await MusicCore.shared.status()
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.danger)
        }
        .padding(16)
    }
}
