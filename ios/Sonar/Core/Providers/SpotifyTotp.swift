import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Шифр TOTP веб-плеера на iPhone — порт `TotpStore` из `providers/spotify.rs` (docs/POLISH_PROMPT.md п. 3):
/// вшитый `TotpSecret.default`, пока файл из репо `updates/spotify-totp.json` не дал версию новее. Файл
/// читается при первом токене после запуска и когда Spotify отверг шифр — но не чаще раза в минуту.
actor SpotifyTotp {
    static let shared = SpotifyTotp()

    static let remoteURL = URL(string: "https://raw.githubusercontent.com/folzy1092/Sonar/main/updates/spotify-totp.json")!
    /// Перечитывать файл не чаще.
    static let recheck: Duration = .seconds(60)
    /// Байтов в шифре — с запасом: у Spotify их 17–32.
    static let maxLength = 128

    private(set) var current: Spotify.TotpSecret
    /// Когда последний раз читали файл; `nil` — ещё ни разу после запуска.
    private var checkedAt: ContinuousClock.Instant?

    init(_ secret: Spotify.TotpSecret = .default) {
        current = secret
    }

    /// Файл шифра → шифр, если он годный и новее `current`. Чужое и битое — мимо.
    static func parseRemote(_ data: Data, current: Int) -> Spotify.TotpSecret? {
        guard let secret = try? JSONDecoder().decode(Spotify.TotpSecret.self, from: data),
              secret.version > current, !secret.cipher.isEmpty, secret.cipher.count <= maxLength else { return nil }
        return secret
    }

    /// Принять содержимое файла; `true` — шифр сменился.
    func adopt(_ data: Data) -> Bool {
        guard let fresh = Self.parseRemote(data, current: current.version) else { return false }
        CrashLog.note("Spotify: шифр веб-плеера из репо — версия \(fresh.version) (была \(current.version))")
        current = fresh
        return true
    }

    /// Перечитать файл: `force == false` — только первый раз после запуска, `true` — не чаще `recheck`.
    /// `true` — шифр сменился, токен стоит запросить снова.
    func refresh(force: Bool, session: URLSession) async -> Bool {
        let now = ContinuousClock.now
        let due = switch checkedAt {
        case nil: true
        case let at?: force && now - at >= Self.recheck
        }
        guard due else { return false }
        checkedAt = now
        var request = URLRequest(url: Self.remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await session.data(for: request) else {
            CrashLog.warn("Spotify: файл шифра недоступен (сеть)")
            return false
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            CrashLog.warn("Spotify: файл шифра недоступен (HTTP \(status))")
            return false
        }
        return adopt(data)
    }
}
