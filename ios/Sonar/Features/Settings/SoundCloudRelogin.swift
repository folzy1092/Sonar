import SwiftUI
import UIKit
import WebKit

/// Плашка «Войди в SoundCloud заново» (docs/POLISH_PROMPT.md п. 8): ядро не смогло починить ключи
/// (`SoundCloudRepair.reloginNeeded`) — показываем одну плашку сверху, по кнопке — окно входа SoundCloud.
@MainActor @Observable
final class SoundCloudRelogin {
    static let shared = SoundCloudRelogin()

    /// Плашка видна.
    private(set) var needed = false
    /// Окно входа открыто.
    var signingIn = false
    /// Токен, который SoundCloud больше не принимает, — окно входа его не возьмёт.
    private(set) var staleToken: String?

    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    private init() {}

    /// Ядру — тихий вход, приложению — плашка. Зовётся один раз при запуске.
    func start() async {
        await MusicCore.shared.setSoundCloudRelogin({ old in
            await SoundCloudSilentLogin.run(ignore: old)
        }, ready: {
            await MainActor.run { UIApplication.shared.applicationState == .active }
        })
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: SoundCloudRepair.reloginNeeded, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated { SoundCloudRelogin.shared.show() }
        }
    }

    private func show() {
        Task {
            staleToken = await MusicCore.shared.soundCloudToken()
            withAnimation(Motion.spring) { needed = true }
        }
    }

    func dismiss() {
        withAnimation(Motion.spring) { needed = false }
    }

    func signIn() {
        dismiss()
        signingIn = true
    }

    /// Окно входа отдало новый `oauth_token`: свежий публичный client_id + токен → подключение.
    func connect(token: String, router: Router) {
        signingIn = false
        Task {
            do {
                let id = try await SoundCloud.publicClientId()
                _ = try await MusicCore.shared.connectSoundCloud(SoundCloudCreds(clientId: id, oauthToken: token))
                CrashLog.note("SoundCloud: вход заново по плашке — подключено")
                router.say(t("SoundCloud снова подключён"))
            } catch {
                router.say(error.localizedDescription)
            }
        }
    }
}

/// Тихий вход: скрытое окно soundcloud.com на постоянном хранилище входа (`SoundCloudWebStore`). Если
/// SoundCloud ещё помнит сессию, сайт сам ставит свежую cookie `oauth_token` — забираем её.
@MainActor
enum SoundCloudSilentLogin {
    private static let wait: Duration = .seconds(20)
    private static let poll: Duration = .seconds(1)

    static func run(ignore: String?) async -> String? {
        let store = SoundCloudWebStore.shared
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        view.customUserAgent = HTTP.browserAgent
        view.alpha = 0
        view.isUserInteractionEnabled = false
        // вне окна WebKit может не выполнять скрипты страницы — вешаем невидимым в окно приложения
        keyWindow()?.addSubview(view)
        defer {
            view.stopLoading()
            view.removeFromSuperview()
        }
        view.load(URLRequest(url: URL(string: "https://soundcloud.com/")!))
        let deadline = ContinuousClock.now + wait
        while ContinuousClock.now < deadline {
            if let token = await SoundCloudWebStore.token(in: store, ignore: ignore) { return token }
            try? await Task.sleep(for: poll)
        }
        return nil
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

extension SoundCloudWebStore {
    /// «Отключить» SoundCloud — забываем и вход на сайте, иначе следующее окно входа сразу возьмёт его.
    static func forget() async {
        await shared.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
}

/// Сама плашка — сверху, закрывается только кнопкой.
struct SoundCloudReloginBanner: View {
    let relogin: SoundCloudRelogin

    var body: some View {
        HStack(spacing: 12) {
            Text(t("Войди в SoundCloud заново"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(t("Войти заново")) { relogin.signIn() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(PressableStyle(scale: 0.95))
            Button { relogin.dismiss() } label: {
                SonarIcon(.close, size: 16)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(t("Закрыть"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line))
    }
}
