import SwiftUI
import WebKit

/// Вход в YouTube Music как на ПК (`login.rs`): страница входа Google внутри Sonar, после входа браузер
/// возвращается на music.youtube.com — забираем cookie домена youtube.com (нужен `SAPISID` для подписи
/// запросов) и закрываем окно. Хранилище cookie — временное, cookie уходит только в Keychain.
/// Если Google не пустит во встроенный браузер — остаётся вставка cookie руками (Профиль → YouTube Music).
struct YouTubeLoginSheet: View {
    let done: @MainActor (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t("Вход в YouTube Music"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button(t("Отмена")) { dismiss() }
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            YouTubeWebView(done: done)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

private struct YouTubeWebView: UIViewRepresentable {
    let done: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        // мобильный Safari: «встроенный браузер» Google иногда не пускает
        view.customUserAgent = HTTP.browserAgent
        view.navigationDelegate = context.coordinator
        context.coordinator.start(view)
        view.load(URLRequest(url: YouTubeAuth.loginURL))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        /// Как часто смотреть cookie, пока открыто окно (секунды).
        private static let pollInterval: TimeInterval = 1
        let done: @MainActor (String) -> Void
        private var timer: Timer?
        private weak var view: WKWebView?
        private var finished = false

        init(done: @escaping @MainActor (String) -> Void) {
            self.done = done
        }

        func start(_ view: WKWebView) {
            self.view = view
            timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
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

        /// Вход завершён, когда окно снова на music.youtube.com и среди cookie есть `SAPISID`.
        private func check() {
            guard !finished, let view, view.url?.host == YouTubeAuth.musicHost else { return }
            view.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                let pairs = cookies
                    .filter { $0.domain.hasSuffix("youtube.com") }
                    .map { ($0.name, $0.value) }
                guard let header = YouTubeAuth.cookieHeader(pairs) else { return }
                MainActor.assumeIsolated {
                    guard let self, !self.finished else { return }
                    self.finished = true
                    self.stop()
                    self.done(header)
                }
            }
        }
    }
}
