import UserNotifications
import SwiftUI
import UIKit
import WebKit

/// Сервисы (`pc/Screenshot_12, 13`, как Windows «Сервисы»): SoundCloud — client_id и OAuth-токен
/// (без своих ключей поиск и открытые треки идут на публичном client_id с сайта), Яндекс Музыка —
/// токен `y0_…`. Ключи — только в Keychain этого iPhone.
struct ServicesView: View {
    /// Только один сервис (Профиль → SoundCloud / Яндекс Музыка ведут каждый на свой экран); nil — оба.
    var only: Service?
    @State private var status = MusicCore.Status()
    @State private var clientId = ""
    @State private var oauth = ""
    @State private var yandexToken = ""
    @State private var busy: Service?
    @State private var error: String?
    /// Вход в Яндекс по коду: код на экране, пока ждём подтверждения на ya.ru/device.
    @State private var deviceCode: YandexLogin.DeviceCode?
    @State private var login: Task<Void, Never>?
    @State private var showSoundCloudLogin = false
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsScreen(title: only?.title ?? "Сервисы") {
            if only != .yandex {
            SettingsSection(title: "SoundCloud", footer: status.soundCloud == nil
                            ? "Без своих ключей поиск и открытые треки работают на публичном client_id с сайта. OAuth-токен нужен для лайков, плейлистов и закрытых треков."
                            : nil) {
                if let account = status.soundCloud {
                    connected(.soundcloud, account)
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

            if only != .soundcloud {
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
        .sheet(isPresented: $showSoundCloudLogin) {
            SoundCloudLoginSheet { token in
                showSoundCloudLogin = false
                connectSoundCloud(token: token)
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
                withAnimation(Motion.spring) { error = nil }
                status = await MusicCore.shared.status()
            } catch {
                withAnimation(Motion.spring) { self.error = error.localizedDescription }
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

/// Вход в SoundCloud как на ПК (`login.rs`): обычная страница входа soundcloud.com внутри Sonar; после входа
/// сайт ставит cookie `oauth_token` — забираем её и закрываем окно. Своего OAuth-приложения SoundCloud с
/// адресом возврата нет, поэтому так. Хранилище cookie — временное (не путается со старым входом).
struct SoundCloudLoginSheet: View {
    let done: @MainActor (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Вход в SoundCloud")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("Отмена") { dismiss() }
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            SoundCloudWebView(done: done)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

private struct SoundCloudWebView: UIViewRepresentable {
    let done: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        // Google / Apple / Facebook открывают вход всплывающим окном — разрешаем
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let view = WKWebView(frame: .zero, configuration: config)
        // мобильный Safari: со «встроенным браузером» Google и Apple вход иногда не пускают
        view.customUserAgent = HTTP.browserAgent
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.start(view)
        view.load(URLRequest(url: URL(string: "https://soundcloud.com/signin")!))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let done: @MainActor (String) -> Void
        /// Всплывающее окно входа (Google / Apple / Facebook) — поверх страницы SoundCloud.
        private var popup: WKWebView?
        private var timer: Timer?
        private weak var view: WKWebView?
        private var finished = false

        init(done: @escaping @MainActor (String) -> Void) {
            self.done = done
        }

        /// Cookie проверяем раз в секунду и после каждой загрузки страницы.
        func start(_ view: WKWebView) {
            self.view = view
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            check()
        }

        /// window.open → своё окно поверх: та же конфигурация (общие cookie), закроется само по window.close.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            let child = WKWebView(frame: webView.bounds, configuration: configuration)
            child.customUserAgent = webView.customUserAgent
            child.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            child.navigationDelegate = self
            child.uiDelegate = self
            webView.addSubview(child)
            popup?.removeFromSuperview()
            popup = child
            return child
        }

        func webViewDidClose(_ webView: WKWebView) {
            guard webView === popup else { return }
            webView.removeFromSuperview()
            popup = nil
            check()
        }

        private func check() {
            guard !finished, let store = view?.configuration.websiteDataStore.httpCookieStore else { return }
            store.getAllCookies { [weak self] cookies in
                let token = cookies.first { $0.name == "oauth_token" && $0.domain.hasSuffix("soundcloud.com") && !$0.value.isEmpty }?.value
                guard let token else { return }
                MainActor.assumeIsolated {
                    guard let self, !self.finished else { return }
                    self.finished = true
                    self.stop()
                    self.done(token)
                }
            }
        }
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
