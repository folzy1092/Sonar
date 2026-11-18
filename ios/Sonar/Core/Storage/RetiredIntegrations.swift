import Foundation

/// Что осталось на телефоне от интеграций, которых больше нет. Last.fm убран 2026-11-18
/// (docs/LASTFM_EXIT.md): его вход лежал в Keychain, неотправленные прослушивания — в UserDefaults.
/// Стираются при запуске; после первого раза стирать нечего, и это одно чтение Keychain.
enum RetiredIntegrations {
    struct SecretRef: Hashable {
        let service: String
        let account: String
    }

    /// Записи Keychain (как было в `LastfmKeychain`).
    static let secrets = [SecretRef(service: "com.folzy.sonar.lastfm", account: "session")]
    /// Ключи UserDefaults: очередь неотправленных скробблов (прежние переключатели — в общем блоке
    /// настроек, их просто больше никто не читает).
    static let defaultsKeys = ["sonar.lastfm.pending"]

    /// Стирает всё, что найдёт. `read` / `remove` — доступ к секретам (на телефоне — Keychain).
    /// Возвращает, сколько записей стёрто, — чтобы было что проверить в тестах.
    @discardableResult
    static func forget(read: (SecretRef) -> Data?, remove: (SecretRef) -> Void, defaults: UserDefaults) -> Int {
        var removed = 0
        for ref in secrets where read(ref) != nil {
            remove(ref)
            removed += 1
        }
        for key in defaultsKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            removed += 1
        }
        return removed
    }
}

#if canImport(Security)
extension RetiredIntegrations {
    /// На телефоне: Keychain и стандартные UserDefaults.
    @discardableResult
    static func forgetOnDevice() -> Int {
        forget(read: { Keychain.data(service: $0.service, account: $0.account) },
               remove: { Keychain.set(nil, service: $0.service, account: $0.account) },
               defaults: .standard)
    }
}
#endif
