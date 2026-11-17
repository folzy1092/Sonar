import Foundation

/// Где лежат секреты: на iPhone — Keychain (`KeychainSecrets`), в тестах — память.
protocol SecretStore: Sendable {
    func string(_ account: String) -> String?
    /// nil — удалить.
    func set(_ value: String?, _ account: String)
}

/// Секреты в памяти — тесты и Linux.
final class MemorySecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func string(_ account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func set(_ value: String?, _ account: String) {
        lock.lock()
        values[account] = value
        lock.unlock()
    }
}

/// Сессия Sonar и id устройства. Токен сессии — только здесь (Keychain «только это устройство»), не в
/// настройках и не в синке. Пользователь хранится рядом, чтобы профиль был виден до ответа `GET /me`.
struct SessionVault: Sendable {
    let secrets: SecretStore

    static let tokenAccount = "session"
    static let userAccount = "user"
    static let deviceAccount = "device_id"

    var token: String? {
        secrets.string(Self.tokenAccount).flatMap { $0.isEmpty ? nil : $0 }
    }

    var user: AccountUser? {
        secrets.string(Self.userAccount).flatMap { try? JSONDecoder().decode(AccountUser.self, from: Data($0.utf8)) }
    }

    func save(_ result: AuthResult) {
        secrets.set(result.session, Self.tokenAccount)
        saveUser(result.user)
    }

    func saveUser(_ user: AccountUser) {
        if let data = try? JSONEncoder().encode(user) {
            secrets.set(String(decoding: data, as: UTF8.self), Self.userAccount)
        }
    }

    /// Выход: токен и профиль стираются, id устройства остаётся.
    func clear() {
        secrets.set(nil, Self.tokenAccount)
        secrets.set(nil, Self.userAccount)
    }

    /// Постоянный id устройства: UUID, создаётся один раз. В Keychain он переживает переустановку
    /// Sonar (как в Shadow) — сервер узнаёт тот же iPhone и не плодит записей в «Устройствах».
    var deviceId: String {
        if let id = secrets.string(Self.deviceAccount), !id.isEmpty { return id }
        let id = UUID().uuidString.lowercased()
        secrets.set(id, Self.deviceAccount)
        return id
    }
}
