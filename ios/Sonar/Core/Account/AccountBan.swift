import Foundation

/// Блокировка аккаунта (`403 account_banned`, API.md §1): до когда и почему. Сервер не стирает сессию, а отвечает этим
/// кодом на любой запрос; приложение выходит из аккаунта само и показывает «учётная запись заблокирована» (`AuthGateView`).
struct BanInfo: Equatable, Sendable {
    /// До какого момента (мс Unix); `nil` — навсегда.
    var until: Int64?
    var reason: String?

    init(until: Int64?, reason: String?) {
        self.until = until
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.reason = trimmed.isEmpty ? nil : String(trimmed.prefix(200))
    }

    /// Из ошибки API; не блокировка — `nil`.
    init?(_ error: APIError) {
        guard error.isBanned else { return nil }
        self.init(until: error.until, reason: error.reason)
    }

    var isForever: Bool { until == nil }

    /// Срок вышел (на случай, когда экран открыт долго): ворота тогда просто просят войти заново.
    func isOver(now: Date = Date()) -> Bool {
        guard let until else { return false }
        return Int64(now.timeIntervalSince1970 * 1000) >= until
    }

    /// «27.11.2026, 14:05» в языке интерфейса; `nil` — навсегда.
    func untilText(locale: Locale, timeZone: TimeZone = .current) -> String? {
        guard let until else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: Double(until) / 1000))
    }
}
