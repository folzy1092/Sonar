import UserNotifications
import SwiftUI
import UIKit

/// Сервисы (`pc/Screenshot_12, 13`, как Windows «Сервисы»): SoundCloud — client_id и OAuth-токен
/// (без своих ключей поиск и открытые треки идут на публичном client_id с сайта), Яндекс Музыка —
/// токен `y0_…`, YouTube Music — вход Google или cookie music.youtube.com, VK Музыка — вход на oauth.vk.com или
/// ключ `vk1.a.…`, Spotify — `sp_dc` (`SpotifyServiceSection`, только метаданные). Ключи — только в Keychain этого iPhone.
struct ServicesView: View {
    /// Только один сервис (Профиль → SoundCloud / Яндекс Музыка / YouTube Music / VK Музыка — каждый на свой экран);
    /// nil — все.
    var only: Service?
    @State private var status = MusicCore.Status()
    @State private var clientId = ""
    @State private var oauth = ""
    @State private var yandexToken = ""
    @State private var youTubeCookie = ""
    @State private var vkToken = ""
    @State private var busy: Service?
    @State private var error: String?
    /// Вход в Яндекс по коду: код на экране, пока ждём подтверждения на ya.ru/device.
    @State private var deviceCode: YandexLogin.DeviceCode?
    @State private var login: Task<Void, Never>?
    @State private var showSoundCloudLogin = false
    /// SoundCloud отверг сохранённый вход — вместо «Подключено» «Вход устарел» и «Войти заново».
    @State private var soundCloudStale = false
    /// Токен, который SoundCloud уже не принимает, — окно входа его не возьмёт.
    @State private var staleToken: String?
    @State private var showYouTubeLogin = false
    @State private var showVKLogin = false
    @Environment(SettingsStore.self) private var settings
    @Environment(OfflineMode.self) private var offline
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsScreen(title: only?.title ?? "Сервисы") {
            // окна входа (WKWebView) идут в сеть мимо сторожа — в офлайне сервисы не трогаем
            if offline.isOn {
                HintCard(icon: .cloudOff, text: t("Сервисы подключаются только с сетью."))
                    .cascade(0)
            }
            Group {
            if only == nil || only == .soundcloud {
            SettingsSection(title: "SoundCloud", footer: status.soundCloud == nil
                            ? "Без своих ключей поиск и открытые треки работают на публичном client_id с сайта. OAuth-токен нужен для лайков, плейлистов и закрытых треков."
                            : nil) {
                if let account = status.soundCloud {
                    connected(.soundcloud, account, stale: soundCloudStale)
                    if soundCloudStale {
                        RowDivider()
                        Button {
                            error = nil
                            Task {
                                staleToken = await MusicCore.shared.soundCloudToken()
                                showSoundCloudLogin = true
                            }
                        } label: {
                            Text(t("Войти заново"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .disabled(busy != nil)
                        .transition(.opacity)
                    }
                } else {
                    Button { error = nil; showSoundCloudLogin = true } label: {
                        Label("Войти в SoundCloud", systemImage: "person.badge.key")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .disabled(busy != nil)
                    RowDivider()
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
            }

            if only == nil || only == .yandex {
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
            }

            if only == nil || only == .youtube {
            SettingsSection(title: "YouTube Music", footer: status.youtube == nil
                            ? t("Без входа работают поиск, исполнители, альбомы и прослушивание. Вход нужен для «Лайков» и твоих плейлистов. Если Google не пустит во встроенный браузер — вставь cookie music.youtube.com вручную.")
                            : nil) {
                if let account = status.youtube {
                    connected(.youtube, account)
                } else {
                    Button { error = nil; showYouTubeLogin = true } label: {
                        Label(t("Войти в YouTube Music"), systemImage: "person.badge.key")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .disabled(busy != nil)
                    RowDivider()
                    field(t("Cookie music.youtube.com"), text: $youTubeCookie, secure: true)
                    RowDivider()
                    connectButton(.youtube, enabled: !youTubeCookie.isEmpty) {
                        try await MusicCore.shared.connectYouTube(cookie: youTubeCookie)
                    }
                }
            }
            .cascade(2)
            }

            if only == nil || only == .vk {
            SettingsSection(title: t(Service.vk.title), footer: status.vk == nil
                            ? t("ключ Kate Mobile с доступом к музыке. Проще войти кнопкой выше: ключ Sonar возьмёт сам.")
                            : nil) {
                if let account = status.vk {
                    connected(.vk, account)
                } else {
                    Button { error = nil; showVKLogin = true } label: {
                        Label(t("Войти через VK"), systemImage: "person.badge.key")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .disabled(busy != nil)
                    RowDivider()
                    field(t("Токен vk1.a.…"), text: $vkToken, secure: true)
                    RowDivider()
                    connectButton(.vk, enabled: !vkToken.isEmpty) {
                        try await MusicCore.shared.connectVK(token: vkToken)
                    }
                }
            }
            .cascade(3)
            }

            if only == nil {
                SpotifyServiceSection()
                    .cascade(4)
            }

            if let error {
                Label(t(error), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }

            if only != .youtube && only != .vk {
            SettingsSection(title: "Качество") {
                SettingsToggle(title: "SoundCloud в качестве Яндекса",
                               subtitle: "Если тот же трек есть на Яндексе — играть оттуда (FLAC / 320)",
                               isOn: Binding(get: { settings.bool("audio.sc_via_yandex") }, set: { settings.set("audio.sc_via_yandex", $0) }))
            }
            .cascade(5)
            }
            }
            .disabled(offline.isOn)
            .opacity(offline.isOn ? 0.5 : 1)
        }
        .animation(Motion.spring, value: offline.isOn)
        .animation(Motion.spring, value: status)
        .animation(Motion.spring, value: deviceCode)
        .onDisappear { login?.cancel() }
        .animation(Motion.spring, value: error)
        .animation(Motion.spring, value: soundCloudStale)
        .task {
            status = await MusicCore.shared.status()
            guard !offline.isOn else { return }
            // «Подключено» — только если SoundCloud правда принимает вход (а не просто ключи сохранены)
            if status.soundCloud != nil, only == nil || only == .soundcloud {
                soundCloudStale = !(await MusicCore.shared.soundCloudSignedIn())
                status = await MusicCore.shared.status()
            }
        }
        .sheet(isPresented: $showSoundCloudLogin) {
            SoundCloudLoginSheet(ignore: staleToken) { token in
                showSoundCloudLogin = false
                connectSoundCloud(token: token)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showYouTubeLogin) {
            YouTubeLoginSheet { cookie in
                showYouTubeLogin = false
                connectYouTube(cookie: cookie)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showVKLogin) {
            VKLoginSheet { token in
                showVKLogin = false
                connectVK(token: token)
            }
            .presentationDragIndicator(.visible)
        }
        .onChange(of: settings.bool("audio.sc_via_yandex")) { applySettings() }
    }

    /// После входа в окне SoundCloud: публичный client_id с сайта + токен из cookie → подключение.
    private func connectSoundCloud(token: String) {
        busy = .soundcloud
        Task {
            defer { busy = nil }
            do {
                let id = try await SoundCloud.publicClientId()
                _ = try await MusicCore.shared.connectSoundCloud(SoundCloudCreds(clientId: id, oauthToken: token))
                withAnimation(Motion.spring) { error = nil; soundCloudStale = false }
                staleToken = nil
                status = await MusicCore.shared.status()
            } catch {
                withAnimation(Motion.spring) { self.error = error.localizedDescription }
            }
        }
    }

    /// После входа в окне Google: cookie music.youtube.com → проверка аккаунта → Keychain.
    private func connectYouTube(cookie: String) {
        busy = .youtube
        Task {
            defer { busy = nil }
            do {
                _ = try await MusicCore.shared.connectYouTube(cookie: cookie)
                withAnimation(Motion.spring) { error = nil }
                status = await MusicCore.shared.status()
            } catch {
                withAnimation(Motion.spring) { self.error = error.localizedDescription }
            }
        }
    }

    /// После входа в окне VK: ключ из адреса возврата → подключение (проверка ключа — в `connectVK`).
    private func connectVK(token: String) {
        busy = .vk
        Task {
            defer { busy = nil }
            do {
                _ = try await MusicCore.shared.connectVK(token: token)
                withAnimation(Motion.spring) { error = nil }
                status = await MusicCore.shared.status()
            } catch {
                withAnimation(Motion.spring) { self.error = t(error.localizedDescription) }
            }
        }
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
                await LoginCodeNotice.post(code.userCode)
                openURL(code.url)
                let token = try await YandexLogin.waitToken(code)
                LoginCodeNotice.clear()
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
        let youTubeHigh = MusicCore.youTubeHigh(settings.string(YouTubeQuality.key))
        let fallback = FallbackSettings(enabled: settings.bool(FallbackPlan.enabledKey), saved: settings.string(FallbackPlan.orderKey))
        Task { await MusicCore.shared.configure(maxKbps: kbps, soundCloudViaYandex: viaYandex, youTubeHigh: youTubeHigh, fallback: fallback) }
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
                    self.error = t(error.localizedDescription)
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

    private func connected(_ service: Service, _ account: ServiceAccount, stale: Bool = false) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: account.avatarURL, cornerRadius: 18).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name ?? "Подключено")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(stale ? t("Вход устарел") : t("Подключено")).font(.system(size: 13))
                    .foregroundStyle(stale ? Theme.danger : Theme.success)
                    .contentTransition(.opacity)
            }
            Spacer()
            Button("Отключить", role: .destructive) {
                Task {
                    await MusicCore.shared.disconnect(service)
                    if service == .soundcloud { await SoundCloudWebStore.forget() }
                    status = await MusicCore.shared.status()
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.danger)
        }
        .padding(16)
    }
}

/// Пуш с кодом входа Яндекса: пользователь уходит в Safari и видит код сверху, не ищет «СМС».
enum LoginCodeNotice {
    static let id = "sonar.yandex.code"

    static func post(_ code: String) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        let content = UNMutableNotificationContent()
        content.title = "Код для входа в Яндекс"
        content.body = "Ваш код: \(code). Введите его на сайте. Код также можно скопировать в Sonar."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        try? await center.add(request)
    }

    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
}
