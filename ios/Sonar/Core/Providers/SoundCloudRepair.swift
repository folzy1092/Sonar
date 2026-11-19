import Foundation

/// SoundCloud ответил 401/403 на своих ключах (docs/POLISH_PROMPT.md п. 8, как ПК `services/sc_repair.rs`).
/// Ключи при входе — публичный client_id с soundcloud.com и cookie `oauth_token`; SoundCloud время от
/// времени меняет публичный client_id, и старый начинает отвечать 401. Порядок починки:
/// 1. взять публичный client_id заново и повторить запрос — помогло, сохраняем новый id;
/// 2. не помогло — тихо обновить вход: скрытый WKWebView с постоянным хранилищем входа SoundCloud
///    отдаёт свежий `oauth_token` (`SoundCloudSilentLogin`);
/// 3. и это не помогло — одна плашка «Войди в SoundCloud заново» (`SoundCloudRepair.reloginNeeded`).
/// Каждое обновление — строка в журнале сбоев, без значений ключей.
enum SoundCloudRepair {
    /// Что обновили — для строки журнала.
    enum Fix: Equatable, Sendable {
        case clientId
        case token

        var journal: String {
            switch self {
            case .clientId: "SoundCloud: 401 — взял новый публичный client_id, запрос прошёл"
            case .token: "SoundCloud: 401 — вход обновлён тихо (новый oauth_token), запрос прошёл"
            }
        }
    }

    static let journalRelogin = "SoundCloud: 401 — ни новый client_id, ни тихий вход не помогли, нужен вход заново"

    /// Текст ошибки, когда починить не вышло.
    static let reloginMessage = "SoundCloud: вход устарел — войди в SoundCloud заново"

    /// Ядро не починило ключи — показать плашку входа (слушает `SoundCloudRelogin`).
    static let reloginNeeded = Notification.Name("sonar.soundcloud.relogin")

    struct Outcome<T: Sendable>: Sendable {
        var result: Result<T, any Error>
        /// Новые ключи, которые сработали, — сохранить.
        var save: (creds: SoundCloudCreds, fix: Fix)?
        /// Починить не вышло — показать плашку входа.
        var relogin: Bool
    }

    /// Ключи сработали, если ответ — не 401/403 (404 и прочее — уже не про ключи).
    static func passed<T>(_ result: Result<T, any Error>) -> Bool {
        if case .failure(let error) = result { return !MusicCore.isAuthError(error) }
        return true
    }

    /// Починка после 401/403 на ключах `old`. `call` — сам запрос; `freshId` — публичный client_id с
    /// сайта; `relogin` — тихий вход (прежний токен → новый или nil).
    static func repair<T: Sendable>(old: SoundCloudCreds, error: any Error,
                          call: @Sendable (SoundCloudCreds) async throws -> T,
                          freshId: @Sendable () async throws -> String,
                          relogin: @Sendable (String?) async -> String?) async -> Outcome<T> {
        let id = (try? await freshId()) ?? old.clientId
        if id != old.clientId {
            let creds = SoundCloudCreds(clientId: id, oauthToken: old.oauthToken)
            let result = await attempt(call, creds)
            if passed(result) { return Outcome(result: result, save: (creds, .clientId), relogin: false) }
        }
        guard let oldToken = old.oauthToken else {
            // без токена входить нечем — ошибка как есть
            return Outcome(result: .failure(error), save: nil, relogin: false)
        }
        if let token = await relogin(oldToken), !token.isEmpty, token != oldToken {
            let creds = SoundCloudCreds(clientId: id, oauthToken: token)
            let result = await attempt(call, creds)
            if passed(result) { return Outcome(result: result, save: (creds, .token), relogin: false) }
        }
        return Outcome(result: .failure(ServiceError(message: reloginMessage)), save: nil, relogin: true)
    }

    private static func attempt<T: Sendable>(_ call: @Sendable (SoundCloudCreds) async throws -> T,
                                   _ creds: SoundCloudCreds) async -> Result<T, any Error> {
        do { return .success(try await call(creds)) } catch { return .failure(error) }
    }
}
