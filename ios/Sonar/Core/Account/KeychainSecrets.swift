import Foundation

/// Секреты аккаунта в Keychain (`Core/Storage/Keychain.swift`, сервис `com.folzy.sonar.account`).
/// Отдельный файл: Security есть только на устройстве, логика аккаунта гоняется и на Linux.
struct KeychainSecrets: SecretStore {
    var service = "com.folzy.sonar.account"

    func string(_ account: String) -> String? {
        Keychain.string(service: service, account: account)
    }

    func set(_ value: String?, _ account: String) {
        Keychain.set(value, service: service, account: account)
    }
}
