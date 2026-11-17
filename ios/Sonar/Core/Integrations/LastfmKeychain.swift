#if canImport(Security)
import Foundation

/// Вход Last.fm в Keychain («только это устройство», как токены сервисов).
struct LastfmKeychain: LastfmSessionStoring {
    static let service = "com.folzy.sonar.lastfm"
    static let account = "session"

    func load() -> LastfmSession? {
        guard let data = Keychain.data(service: Self.service, account: Self.account) else { return nil }
        return try? JSONDecoder().decode(LastfmSession.self, from: data)
    }

    func save(_ session: LastfmSession?) {
        let json = session.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        Keychain.set(json, service: Self.service, account: Self.account)
    }
}
#endif
