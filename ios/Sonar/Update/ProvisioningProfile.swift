import Foundation

/// Поля `.mobileprovision`, важные для переподписи. Файл — CMS SignedData с plist внутри; читаем только
/// plist (подпись CMS не проверяем — профиль выбрал сам пользователь). Порт ShadowProvisioningProfile.
/// Только Foundation — покрыт тестами.
struct ProvisioningProfile: Equatable, Sendable {
    var name: String
    var teamId: String
    var teamName: String
    /// "TEAMID.bundle.id" или "TEAMID.*".
    var applicationIdentifier: String
    var expirationDate: Date?
    var deviceCount: Int
    var provisionsAllDevices: Bool
    var apsEnvironment: String?
    /// DER каждого сертификата, которому профиль разрешает подписывать.
    var developerCertificates: [Data]

    /// Шаблон bundle id без Team ID: "com.folzy.sonar" или "*".
    var bundleIdPattern: String {
        let prefix = teamId + "."
        return applicationIdentifier.hasPrefix(prefix) ? String(applicationIdentifier.dropFirst(prefix.count)) : applicationIdentifier
    }

    var isWildcard: Bool {
        bundleIdPattern == "*" || bundleIdPattern.hasSuffix(".*")
    }

    func isExpired(at date: Date = Date()) -> Bool {
        guard let expirationDate else { return false }
        return expirationDate <= date
    }

    /// Подходит ли профиль к bundle id установленной копии (ESign мог переименовать id).
    func allows(bundleId: String) -> Bool {
        let pattern = bundleIdPattern
        if pattern == "*" { return true }
        if pattern.hasSuffix(".*") { return bundleId.hasPrefix(String(pattern.dropLast())) }
        return pattern == bundleId
    }

    static func plistData(in data: Data) -> Data? {
        guard let start = data.range(of: Data("<?xml".utf8)) ?? data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound ..< data.endIndex) else {
            return nil
        }
        return data.subdata(in: start.lowerBound ..< end.upperBound)
    }

    static func parse(_ data: Data) -> ProvisioningProfile? {
        guard let plistData = plistData(in: data),
              let plist = (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? [String: Any] else {
            return nil
        }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        guard let teamId = (plist["TeamIdentifier"] as? [String])?.first, !teamId.isEmpty,
              let applicationIdentifier = entitlements["application-identifier"] as? String, !applicationIdentifier.isEmpty else {
            return nil
        }
        return ProvisioningProfile(
            name: plist["Name"] as? String ?? "",
            teamId: teamId,
            teamName: plist["TeamName"] as? String ?? "",
            applicationIdentifier: applicationIdentifier,
            expirationDate: plist["ExpirationDate"] as? Date,
            deviceCount: (plist["ProvisionedDevices"] as? [String])?.count ?? 0,
            provisionsAllDevices: plist["ProvisionsAllDevices"] as? Bool ?? false,
            apsEnvironment: entitlements["aps-environment"] as? String,
            developerCertificates: plist["DeveloperCertificates"] as? [Data] ?? []
        )
    }
}
