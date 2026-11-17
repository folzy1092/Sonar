#if canImport(AuthenticationServices) && canImport(UIKit)
import AuthenticationServices
import UIKit

/// Вход в Last.fm в один клик (как Windows: `auth.getToken` → страница «Разрешить доступ» → ключ
/// сессии). Страница открывается в системном окне входа (`ASWebAuthenticationSession`, cookie Safari —
/// если уже вошёл на last.fm, хватит одного нажатия). Ждём двумя путями сразу: возврат на
/// `sonar://lastfm` с токеном и опрос `auth.getSession` раз в 2 с (если Last.fm не перенаправит, окно
/// закроется само, как только доступ разрешён). Ключ сессии — в Keychain (`LastfmScrobbler.setSession`).
@MainActor
final class LastfmLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let callbackScheme = "sonar"
    static let callback = "sonar://lastfm"

    private var webSession: ASWebAuthenticationSession?
    private var poll: Task<Void, Never>?
    private var continuation: CheckedContinuation<LastfmSession, Error>?

    /// Войти; по окончании — сессия с именем и аватаром. Отмена — `LastfmError` с кодом -2.
    func signIn(api: LastfmAPI) async throws -> LastfmSession {
        let token = try await api.getToken()
        var session = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<LastfmSession, Error>) in
            continuation = cont
            start(api: api, token: token)
        }
        session.avatarURL = await api.avatar(user: session.name)
        return session
    }

    func cancel() {
        finish(.failure(LastfmError(code: -2, message: "Вход в Last.fm отменён")))
    }

    private func start(api: LastfmAPI, token: String) {
        let web = ASWebAuthenticationSession(url: api.authURL(token: token, callback: Self.callback),
                                             callbackURLScheme: Self.callbackScheme) { [weak self] url, _ in
            Task { @MainActor in
                guard let self, self.continuation != nil else { return }
                // вернулись на sonar://lastfm (или окно закрыли) — последняя попытка забрать сессию
                let returned = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "token" }?.value } ?? token
                if let session = try? await api.getSession(token: returned) {
                    self.finish(.success(session))
                } else {
                    self.cancel()
                }
            }
        }
        web.presentationContextProvider = self
        web.prefersEphemeralWebBrowserSession = false
        webSession = web
        guard web.start() else {
            finish(.failure(LastfmError(code: 0, message: "Не удалось открыть окно входа Last.fm")))
            return
        }
        poll = Task { [weak self] in
            let deadline = Date().addingTimeInterval(600)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                if let session = try? await api.getSession(token: token) {
                    self?.finish(.success(session))
                    return
                }
            }
            if !Task.isCancelled { self?.cancel() }
        }
    }

    private func finish(_ result: Result<LastfmSession, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        poll?.cancel()
        poll = nil
        webSession?.cancel()
        webSession = nil
        cont.resume(with: result)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first {
                return window
            }
            return ASPresentationAnchor()
        }
    }
}
#endif
