import SwiftUI
import WebKit

/// Вход в VK как на ПК (`login.rs`): страница oauth.vk.com с client_id Kate Mobile внутри Sonar
/// (двухфакторка и капча — там же). VK уводит на `oauth.vk.com/blank.html#access_token=vk1.a.…` —
/// этот переход перехватываем (`VKLogin.outcome`), токен в историю и cookie не попадает.
/// Хранилище — временное: каждый вход с чистого листа.
struct VKLoginSheet: View {
    let done: @MainActor (String) -> Void
    @State private var denied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t("Вход в VK"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button(t("Отмена")) { dismiss() }
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            if denied {
                Label(t("VK не дал доступ — попробуй ещё раз"), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
            VKWebView(done: done) { withAnimation(Motion.spring) { denied = true } }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

private struct VKWebView: UIViewRepresentable {
    let done: @MainActor (String) -> Void
    let denied: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done, denied: denied) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = HTTP.browserAgent
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: VKLogin.authURL))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let done: @MainActor (String) -> Void
        let denied: @MainActor () -> Void
        private var finished = false

        init(done: @escaping @MainActor (String) -> Void, denied: @escaping @MainActor () -> Void) {
            self.done = done
            self.denied = denied
        }

        /// Переход на blank.html не грузим: токен забираем из адреса, ошибку показываем, окно VK остаётся.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, let outcome = VKLogin.outcome(url) else { return .allow }
            switch outcome {
            case let .token(token):
                if !finished {
                    finished = true
                    done(token)
                }
            case .denied:
                denied()
                webView.load(URLRequest(url: VKLogin.authURL))
            }
            return .cancel
        }
    }
}
