import SwiftUI
import UIKit
import WebKit

/// Вход в сервис обычной страницей сайта внутри Sonar (как `login.rs` на ПК): после входа сайт ставит
/// cookie — забираем её и закрываем окно. Так входим в SoundCloud (`oauth_token`) и Spotify (`sp_dc`):
/// своего OAuth-приложения с адресом возврата у них нет. Хранилище cookie — временное (не путается со
/// старым входом), значение cookie никуда, кроме `done`, не уходит.
struct CookieLoginSheet: View {
    /// Заголовок уже переведён (`t(...)`).
    let title: String
    let url: URL
    /// Имя cookie и домен, на котором её ждём (`soundcloud.com`, `spotify.com`).
    let cookie: String
    let domain: String
    let done: @MainActor (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button(t("Отмена")) { dismiss() }
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            CookieLoginWebView(url: url, cookie: cookie, domain: domain, done: done)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

/// Вход в SoundCloud: cookie `oauth_token` с soundcloud.com.
struct SoundCloudLoginSheet: View {
    let done: @MainActor (String) -> Void

    var body: some View {
        CookieLoginSheet(title: t("Вход в SoundCloud"), url: URL(string: "https://soundcloud.com/signin")!,
                         cookie: "oauth_token", domain: "soundcloud.com", done: done)
    }
}

private struct CookieLoginWebView: UIViewRepresentable {
    let url: URL
    let cookie: String
    let domain: String
    let done: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(cookie: cookie, domain: domain, done: done) }

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
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let cookie: String
        let domain: String
        let done: @MainActor (String) -> Void
        /// Всплывающее окно входа (Google / Apple / Facebook) — поверх страницы сервиса.
        private var popup: WKWebView?
        private var timer: Timer?
        private weak var view: WKWebView?
        private var finished = false

        init(cookie: String, domain: String, done: @escaping @MainActor (String) -> Void) {
            self.cookie = cookie
            self.domain = domain
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
            let name = cookie
            let domain = domain
            store.getAllCookies { [weak self] cookies in
                let value = cookies.first { $0.name == name && $0.domain.hasSuffix(domain) && !$0.value.isEmpty }?.value
                guard let value else { return }
                MainActor.assumeIsolated {
                    guard let self, !self.finished else { return }
                    self.finished = true
                    self.stop()
                    self.done(value)
                }
            }
        }
    }
}
