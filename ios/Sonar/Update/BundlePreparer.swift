import Foundation

/// Делает распакованную сборку из CI похожей на установленную копию до переподписи — тогда iOS считает её
/// обновлением этого же приложения (данные, лайки и настройки остаются). Порт ShadowBundlePreparer:
/// - главный bundle id = установленный (ESign мог его переименовать); id расширений и BGTask — на тот же
///   префикс;
/// - остаются только расширения, которые есть у установленной копии (что установщик оставил, то и
///   работает с этим сертификатом), то же для Watch; новые расширения (виджет Sonar) — только при
///   профиле на «*» (`keepNewPlugIns`): он подходит и к id `<приложение>.widget`, иначе установка бы упала;
/// - в каждое оставшееся расширение кладётся тот же профиль, что и в приложение.
/// Только Foundation — покрыт тестами.
enum BundlePreparer {
    struct Installed: Equatable, Sendable {
        var bundleId: String
        /// Папки в PlugIns: "Widgets.appex".
        var plugIns: Set<String>
        var hasWatch: Bool

        static func current(bundle: Bundle = .main) -> Installed {
            var plugIns = Set<String>()
            if let url = bundle.builtInPlugInsURL, let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                plugIns = Set(names.filter { $0.hasSuffix(".appex") })
            }
            let hasWatch = FileManager.default.fileExists(atPath: bundle.bundleURL.appendingPathComponent("Watch").path)
            return Installed(bundleId: bundle.bundleIdentifier ?? "", plugIns: plugIns, hasWatch: hasWatch)
        }
    }

    struct Summary: Equatable, Sendable {
        var previousBundleId: String
        var removedPlugIns: [String]
        var keptPlugIns: [String]
        var removedWatch: Bool
    }

    enum PrepareError: LocalizedError, Equatable {
        case noApp
        case badInfoPlist
        case noInstalledBundleId

        var errorDescription: String? {
            switch self {
            case .noApp: "В IPA нет Payload/*.app."
            case .badInfoPlist: "Не удалось прочитать Info.plist сборки."
            case .noInstalledBundleId: "Не удалось определить bundle ID установленного Sonar."
            }
        }
    }

    static func findApp(inPayloadParent root: URL) -> URL? {
        let payload = root.appendingPathComponent("Payload", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: payload.path) else { return nil }
        return names.sorted().first { $0.hasSuffix(".app") }.map { payload.appendingPathComponent($0, isDirectory: true) }
    }

    /// "old.id.Widgets" → "new.id.Widgets"; id вне старого префикса не трогаем.
    static func rebase(_ identifier: String, from oldPrefix: String, to newPrefix: String) -> String {
        if identifier == oldPrefix { return newPrefix }
        if identifier.hasPrefix(oldPrefix + ".") { return newPrefix + identifier.dropFirst(oldPrefix.count) }
        return identifier
    }

    @discardableResult
    static func prepare(app: URL, installed: Installed, profileURL: URL?, keepNewPlugIns: Bool = false) throws -> Summary {
        guard !installed.bundleId.isEmpty else { throw PrepareError.noInstalledBundleId }
        let fileManager = FileManager.default
        let infoURL = app.appendingPathComponent("Info.plist")
        guard let (mainInfo, format) = readPlist(infoURL), let previous = mainInfo["CFBundleIdentifier"] as? String else {
            throw PrepareError.badInfoPlist
        }
        var info = mainInfo
        let target = installed.bundleId
        info["CFBundleIdentifier"] = target
        if let tasks = info["BGTaskSchedulerPermittedIdentifiers"] as? [String] {
            info["BGTaskSchedulerPermittedIdentifiers"] = tasks.map { rebase($0, from: previous, to: target) }
        }
        try writePlist(info, format: format, to: infoURL)

        var removed: [String] = []
        var kept: [String] = []
        let plugInsURL = app.appendingPathComponent("PlugIns", isDirectory: true)
        if let names = try? fileManager.contentsOfDirectory(atPath: plugInsURL.path) {
            for name in names.sorted() where name.hasSuffix(".appex") {
                let appex = plugInsURL.appendingPathComponent(name, isDirectory: true)
                guard installed.plugIns.contains(name) || keepNewPlugIns else {
                    try fileManager.removeItem(at: appex)
                    removed.append(name)
                    continue
                }
                kept.append(name)
                let appexInfoURL = appex.appendingPathComponent("Info.plist")
                if let (appexInfo, appexFormat) = readPlist(appexInfoURL) {
                    var updated = appexInfo
                    if let identifier = updated["CFBundleIdentifier"] as? String {
                        updated["CFBundleIdentifier"] = rebase(identifier, from: previous, to: target)
                    }
                    if let companion = updated["WKCompanionAppBundleIdentifier"] as? String {
                        updated["WKCompanionAppBundleIdentifier"] = rebase(companion, from: previous, to: target)
                    }
                    if var ext = updated["NSExtension"] as? [String: Any],
                       var attributes = ext["NSExtensionAttributes"] as? [String: Any],
                       let watchApp = attributes["WKAppBundleIdentifier"] as? String {
                        attributes["WKAppBundleIdentifier"] = rebase(watchApp, from: previous, to: target)
                        ext["NSExtensionAttributes"] = attributes
                        updated["NSExtension"] = ext
                    }
                    try writePlist(updated, format: appexFormat, to: appexInfoURL)
                }
                let embedded = appex.appendingPathComponent("embedded.mobileprovision")
                try? fileManager.removeItem(at: embedded)
                if let profileURL {
                    try fileManager.copyItem(at: profileURL, to: embedded)
                }
            }
            if kept.isEmpty {
                try fileManager.removeItem(at: plugInsURL)
            }
        }

        var removedWatch = false
        if !installed.hasWatch {
            for name in ["Watch", "com.apple.WatchPlaceholder"] {
                let url = app.appendingPathComponent(name, isDirectory: true)
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                    removedWatch = true
                }
            }
        }
        return Summary(previousBundleId: previous, removedPlugIns: removed, keptPlugIns: kept, removedWatch: removedWatch)
    }

    private static func readPlist(_ url: URL) -> ([String: Any], PropertyListSerialization.PropertyListFormat)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: &format)) as? [String: Any] else {
            return nil
        }
        return (dict, format)
    }

    private static func writePlist(_ dict: [String: Any], format: PropertyListSerialization.PropertyListFormat, to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0)
        try data.write(to: url, options: .atomic)
    }
}
