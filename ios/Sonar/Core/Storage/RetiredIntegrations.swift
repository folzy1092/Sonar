import Foundation

/// Что осталось на телефоне от интеграций, которых больше нет. Last.fm убран 2026-11-18
/// (docs/LASTFM_EXIT.md): его вход лежал в Keychain, неотправленные прослушивания — в UserDefaults.
/// VK убран 2026-11-25 (решение владельца): вход — в Keychain `SonarServices`, ключи треков — файл
/// `Application Support/Sonar/vk-keys.json` (как `forget_retired` и `vk-keys.json` в `lib.rs` на ПК).
/// Стираются при запуске; после первого раза стирать нечего — пара чтений Keychain и одна проверка файла.
enum RetiredIntegrations {
    struct SecretRef: Hashable {
        let service: String
        let account: String
    }

    /// Записи Keychain (как было в `LastfmKeychain`).
    static let secrets = [
        SecretRef(service: "com.folzy.sonar.lastfm", account: "session"),
        SecretRef(service: "SonarServices", account: "vk"),
    ]
    /// Файлы в `Application Support` (путь от него).
    static let files = ["Sonar/vk-keys.json"]
    /// Ключи UserDefaults: очередь неотправленных скробблов (прежние переключатели — в общем блоке
    /// настроек, их просто больше никто не читает).
    static let defaultsKeys = ["sonar.lastfm.pending"]

    /// Стирает всё, что найдёт. `read` / `remove` — доступ к секретам (на телефоне — Keychain).
    /// Возвращает, сколько записей стёрто, — чтобы было что проверить в тестах.
    @discardableResult
    static func forget(read: (SecretRef) -> Data?, remove: (SecretRef) -> Void, defaults: UserDefaults,
                       support: URL? = nil) -> Int {
        var removed = 0
        for ref in secrets where read(ref) != nil {
            remove(ref)
            removed += 1
        }
        for key in defaultsKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            removed += 1
        }
        for path in files {
            guard let file = support?.appendingPathComponent(path), FileManager.default.fileExists(atPath: file.path) else { continue }
            if (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
        }
        return removed
    }

    /// Есть ли в медиатеке треки убранных сервисов — тогда «Сервисы» честно объясняют, куда делся VK.
    static func hasRetiredTracks(_ refs: some Sequence<String>) -> Bool {
        refs.contains { ServiceRegistry.service(of: $0).map(ServiceRegistry.retired.contains) ?? false }
    }
}

#if canImport(Security)
extension RetiredIntegrations {
    /// На телефоне: Keychain и стандартные UserDefaults.
    @discardableResult
    static func forgetOnDevice() -> Int {
        forget(read: { Keychain.data(service: $0.service, account: $0.account) },
               remove: { Keychain.set(nil, service: $0.service, account: $0.account) },
               defaults: .standard,
               support: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
    }
}
#endif
