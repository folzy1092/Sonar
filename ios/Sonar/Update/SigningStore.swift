import Foundation
import Zsign

/// Пара для подписи, выбранная в «Обновлениях» (порт ShadowSigningStore). Принадлежит устройству:
/// `.p12` и `.mobileprovision` — в `Application Support/SonarSigning` (исключено из бэкапа iCloud/iTunes),
/// пароль — в Keychain «только это устройство». Не синхронизируется и не экспортируется с настройками.
final class SigningStore: Sendable {
    static let shared = SigningStore()

    /// Настоящий `.p12` — несколько КБ, профиль — десятки КБ.
    static let maximumFileSize = 2 * 1024 * 1024
    private static let keychainService = "SonarSigning"
    private static let keychainAccount = "p12-password"

    enum ImportError: LocalizedError {
        case unreadable
        case tooLarge
        case notProfile

        var errorDescription: String? {
            switch self {
            case .unreadable: "Не удалось прочитать файл."
            case .tooLarge: "Файл слишком большой для сертификата или профиля."
            case .notProfile: "Это не .mobileprovision: в файле нет Team ID или App ID."
            }
        }
    }

    let directory: URL

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = directory ?? base.appendingPathComponent("SonarSigning", isDirectory: true)
    }

    var certificateURL: URL { directory.appendingPathComponent("signing.p12") }
    var profileURL: URL { directory.appendingPathComponent("signing.mobileprovision") }

    var hasCertificate: Bool { FileManager.default.fileExists(atPath: certificateURL.path) }
    var hasProfile: Bool { FileManager.default.fileExists(atPath: profileURL.path) }
    /// Оба файла выбраны; пароль может быть и пустым.
    var isConfigured: Bool { hasCertificate && hasProfile }

    var profile: ProvisioningProfile? {
        (try? Data(contentsOf: profileURL)).flatMap(ProvisioningProfile.parse)
    }

    var password: String? {
        Keychain.string(service: Self.keychainService, account: Self.keychainAccount)
    }

    func setPassword(_ value: String?) {
        Keychain.set(value, service: Self.keychainService, account: Self.keychainAccount)
    }

    func importCertificate(from url: URL) throws {
        try store(readPicked(url), at: certificateURL)
    }

    @discardableResult
    func importProfile(from url: URL) throws -> ProvisioningProfile {
        let data = try readPicked(url)
        guard let profile = ProvisioningProfile.parse(data) else { throw ImportError.notProfile }
        try store(data, at: profileURL)
        return profile
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        setPassword(nil)
    }

    /// Открывает `.p12` сохранённым паролем и проверяет, что сертификат есть в профиле. Медленно (вывод
    /// ключа PKCS#12) — не на главном потоке. nil — парой можно подписывать.
    func check() -> String? {
        guard hasCertificate else { return "Не выбран сертификат .p12" }
        guard hasProfile else { return "Не выбран профиль .mobileprovision" }
        return AppSigner.check(profile: profileURL, p12: certificateURL, password: password ?? "")
    }

    private func readPicked(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.maximumFileSize else { throw ImportError.tooLarge }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { throw ImportError.unreadable }
        guard data.count <= Self.maximumFileSize else { throw ImportError.tooLarge }
        return data
    }

    private func store(_ data: Data, at destination: URL) throws {
        var directory = self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Подпись распакованного `.app` парой пользователя — тонкая обёртка над zsign.
enum AppSigner {
    struct Failure: LocalizedError {
        let reason: String
        var errorDescription: String? { "Подпись: \(reason)" }
    }

    static func sign(app: URL, store: SigningStore) throws {
        try sign(app: app, profile: store.profileURL, p12: store.certificateURL, password: store.password ?? "")
    }

    static func sign(app: URL, profile: URL, p12: URL, password: String) throws {
        if let reason = ZsignSigner.sign(appPath: app.path, provisionPath: profile.path, p12Path: p12.path, password: password) {
            throw Failure(reason: reason)
        }
    }

    /// nil — парой можно подписывать.
    static func check(profile: URL, p12: URL, password: String) -> String? {
        ZsignSigner.check(provisionPath: profile.path, p12Path: p12.path, password: password)
    }
}
