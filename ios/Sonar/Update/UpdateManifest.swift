import Foundation

// Проверка обновлений — порт ShadowUpdateCheck. Объявляет сборку человек: с 2026-11-26 — в админке сайта
// (`GET /api/updates/ios/<release|beta>.json`, тот же формат, API.md §8, 404 — в канале ничего нет).
// Сервер молчит — по-старому: `updates/ios-update.json` в main («рубильник», как в Shadow), потом список
// релизов GitHub `ios-build-<N>`.
//
// ios-update.json:
// {
//   "enabled": true,          // false — ничего не предлагать
//   "build": 123,             // объявленный CFBundleVersion
//   "version": "0.1.0",       // Г.О.Ф, показывается рядом со сборкой
//   "minimum_build": 0,       // установлено ниже — обновление «обязательное»
//   "title": "…", "notes": "…",
//   "ipa_url": "https://…",   // по умолчанию releases/download/ios-build-<build>/Sonar.ipa
//   "url": "https://…"        // страница релиза
// }
//
// Только Foundation — проверяется тестами без симулятора.
enum UpdateFeed {
    /// Бета-обновления — только владельцу (решение 2026-11-26). Сборки CI с GitHub отдаёт свой сервер: он проверяет сессию
    /// и логин (`SONAR_BETA_USERS`), остальным отвечает как на релиз. Список здесь — чтобы чужим не показывать переключатель.
    static let betaLogins: Set<String> = ["folzy"]

    static func betaAllowed(login: String?) -> Bool {
        guard let login else { return false }
        return betaLogins.contains(login.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Канал запроса: "beta" — включена в настройках **и** вошёл свой логин, иначе "release" (только то, что выпущено на сайте).
    static func channel(setting: String, login: String?) -> String {
        setting == "beta" && betaAllowed(login: login) ? "beta" : "release"
    }

    static let repo = "https://github.com/folzy1092/Sonar"
    static let manifestURL = URL(string: "https://raw.githubusercontent.com/folzy1092/Sonar/main/updates/ios-update.json")!
    static let changelogURL = URL(string: "https://raw.githubusercontent.com/folzy1092/Sonar/main/updates/changelog.json")!
    static let releasesAPIURL = URL(string: "https://api.github.com/repos/folzy1092/Sonar/releases?per_page=40")!
    static let releasesPageURL = URL(string: "\(repo)/releases")!
    /// Постоянная ссылка на свежую сборку из main (релиз `ios-latest`).
    static let latestIPAURL = URL(string: "\(repo)/releases/download/ios-latest/Sonar.ipa")!
    static let tagPrefix = "ios-build-"
    static let server = "https://try-sonar.ru"

    /// Объявленная в админке сборка канала: `update.channel` "stable" → `release`, "beta" → `beta`.
    static func serverURL(channel: String, lang: String) -> URL {
        let name = channel == "beta" ? "beta" : "release"
        var components = URLComponents(string: "\(server)/api/updates/ios/\(name).json")!
        components.queryItems = [URLQueryItem(name: "lang", value: lang)]
        return components.url!
    }

    /// CI кладёт IPA в каждый релиз под этим именем.
    static func ipaURL(build: Int) -> URL {
        URL(string: "\(repo)/releases/download/\(tagPrefix)\(build)/Sonar.ipa")!
    }

    static func pageURL(build: Int) -> URL {
        URL(string: "\(repo)/releases/tag/\(tagPrefix)\(build)")!
    }

    /// "ios-build-123" → 123; `ios-latest`, `windows-v…` — не сборки iPhone.
    static func buildNumber(fromTag tag: String) -> Int? {
        guard tag.hasPrefix(tagPrefix) else { return nil }
        return Int(tag.dropFirst(tagPrefix.count))
    }
}

struct UpdateManifest: Equatable, Sendable {
    var enabled: Bool
    var build: Int
    var version: String?
    var title: String?
    var notes: String
    var pageURL: URL
    var downloadURL: URL?
    var minimumBuild: Int

    /// Выключенный манифест разбирается тоже (enabled = false), без сборки — «ничего не объявлено».
    static func parse(_ data: Data) -> UpdateManifest? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let enabled = (object["enabled"] as? Bool) ?? true
        let minimumBuild = max(0, (object["minimum_build"] as? Int) ?? 0)
        let build = (object["build"] as? Int) ?? 0
        guard build > 0 else {
            return enabled ? nil : UpdateManifest(
                enabled: false, build: 0, version: nil, title: nil, notes: "",
                pageURL: UpdateFeed.releasesPageURL, downloadURL: nil, minimumBuild: minimumBuild
            )
        }
        return UpdateManifest(
            enabled: enabled,
            build: build,
            version: nonEmpty(object["version"]),
            title: nonEmpty(object["title"]),
            notes: nonEmpty(object["notes"]) ?? "",
            pageURL: httpsURL(object["url"]) ?? UpdateFeed.pageURL(build: build),
            downloadURL: httpsURL(object["ipa_url"]) ?? UpdateFeed.ipaURL(build: build),
            minimumBuild: minimumBuild
        )
    }
}

/// Запись `updates/changelog.json` — общий файл с Windows: массив записей, новые сверху. Сборкам iPhone
/// нужны `platform: "ios"` и `build`; `new` / `fixed` — типизированные пункты (метки НОВОЕ / ИСПРАВЛЕНО),
/// `changes` — просто список.
struct ChangelogEntry: Equatable, Sendable, Identifiable {
    var build: Int
    var date: String
    var version: String?
    var title: String?
    var items: [String]
    var newItems: [String] = []
    var fixedItems: [String] = []
    var ipaURL: URL?

    var id: Int { build }

    /// Записи для iPhone (или общие, без platform) с номером сборки, новые сверху.
    /// Понимает и формат Shadow: `{"entries": [{"build", "date", "items"}]}`.
    static func parse(_ data: Data) -> [ChangelogEntry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let list: [[String: Any]]
        if let array = root as? [[String: Any]] {
            list = array
        } else if let object = root as? [String: Any], let entries = object["entries"] as? [[String: Any]] {
            list = entries
        } else {
            return []
        }
        var result: [ChangelogEntry] = []
        for entry in list {
            if let platform = entry["platform"] as? String, platform != "ios" { continue }
            guard let build = entry["build"] as? Int, build > 0 else { continue }
            let items = strings(entry["changes"]) + strings(entry["items"])
            let newItems = strings(entry["new"])
            let fixedItems = strings(entry["fixed"])
            if items.isEmpty, newItems.isEmpty, fixedItems.isEmpty { continue }
            result.append(ChangelogEntry(
                build: build,
                date: (entry["date"] as? String) ?? "",
                version: nonEmpty(entry["version"]),
                title: nonEmpty(entry["title"]),
                items: items,
                newItems: newItems,
                fixedItems: fixedItems,
                ipaURL: httpsURL(entry["ipa_url"])
            ))
        }
        return result.sorted { $0.build > $1.build }
    }

    /// Пункты для экрана: типизированные с метками, остальные — как есть.
    var lines: [(label: String?, text: String)] {
        newItems.map { ("НОВОЕ", $0) } + fixedItems.map { ("ИСПРАВЛЕНО", $0) } + items.map { (nil, $0) }
    }

    /// Новее установленной и не новее объявленной. Сборка неизвестна (переподписанная IPA без числа в
    /// CFBundleVersion) — только объявленная запись, не вся история. Не больше 20.
    static func changes(installedBuild: Int?, announcedBuild: Int, entries: [ChangelogEntry]) -> [ChangelogEntry] {
        let picked: [ChangelogEntry]
        if let installedBuild {
            picked = entries.filter { $0.build <= announcedBuild && $0.build > installedBuild }
        } else {
            picked = entries.filter { $0.build == announcedBuild }
        }
        return Array(picked.sorted { $0.build > $1.build }.prefix(20))
    }

    /// "16 ноября 2026" из "2026-11-16"; не разобралось — строка как есть.
    static func dateText(_ date: String) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return date }
        let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа",
                      "сентября", "октября", "ноября", "декабря"]
        return "\(parts[2]) \(months[parts[1] - 1]) \(parts[0])"
    }
}

/// Объявленная сборка, которую можно поставить.
struct UpdateRelease: Equatable, Sendable {
    var build: Int
    var version: String?
    var title: String?
    var pageURL: URL
    var notes: String
    var downloadURL: URL?
    /// Установленная сборка ниже `minimum_build`.
    var isRequired = false
    /// Изменения всех сборок новее установленной, новые сверху.
    var changelog: [ChangelogEntry] = []

    /// "0.1.1 (15)" или "сборка 15".
    var label: String {
        if let version { return "\(version) (\(build))" }
        return "сборка \(build)"
    }

    /// Первая версия из GitHub API: самый новый релиз `ios-build-*` из списка.
    static func parseReleases(_ data: Data) -> UpdateRelease? {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        var best: UpdateRelease?
        for object in list {
            if (object["draft"] as? Bool) == true { continue }
            guard let tag = object["tag_name"] as? String, let build = UpdateFeed.buildNumber(fromTag: tag) else { continue }
            if let best, best.build >= build { continue }
            var download: URL?
            for asset in (object["assets"] as? [[String: Any]]) ?? [] {
                if let name = asset["name"] as? String, name.hasSuffix(".ipa"),
                   let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) {
                    download = url
                    break
                }
            }
            // "Sonar 0.1.0 (123) для iPhone" → версия из скобок не нужна, только Г.О.Ф до них
            let name = (object["name"] as? String) ?? ""
            let version = name.split(separator: " ").first(where: { $0.first?.isNumber == true && $0.contains(".") }).map(String.init)
            best = UpdateRelease(
                build: build,
                version: version,
                title: nil,
                pageURL: (object["html_url"] as? String).flatMap(URL.init(string:)) ?? UpdateFeed.pageURL(build: build),
                notes: (object["body"] as? String) ?? "",
                downloadURL: download ?? UpdateFeed.ipaURL(build: build)
            )
        }
        return best
    }
}

enum UpdateStatus: Equatable, Sendable {
    /// nil — ничего не объявлено (манифест выключен).
    case upToDate(UpdateRelease?)
    case available(UpdateRelease)
    case failed(String)

    static func from(manifest: UpdateManifest, installedBuild: Int?) -> UpdateStatus {
        guard manifest.enabled else { return .upToDate(nil) }
        let release = UpdateRelease(
            build: manifest.build,
            version: manifest.version,
            title: manifest.title,
            pageURL: manifest.pageURL,
            notes: manifest.notes,
            downloadURL: manifest.downloadURL,
            isRequired: installedBuild.map { $0 < manifest.minimumBuild } ?? false
        )
        return from(release: release, installedBuild: installedBuild)
    }

    static func from(release: UpdateRelease, installedBuild: Int?) -> UpdateStatus {
        guard let installedBuild else { return .available(release) }
        return release.build > installedBuild ? .available(release) : .upToDate(release)
    }
}

/// «4 новые функции · 4 исправления · 3 выпуска» — шапка экрана «Обновление».
struct UpdateCounts: Equatable {
    var newCount = 0
    var fixedCount = 0
    var otherCount = 0
    var releases = 1

    init(_ release: UpdateRelease) {
        for entry in release.changelog {
            if entry.newItems.isEmpty, entry.fixedItems.isEmpty {
                otherCount += entry.items.count
            } else {
                newCount += entry.newItems.count
                fixedCount += entry.fixedItems.count
            }
        }
        releases = max(1, release.changelog.count)
    }

    var text: String {
        var parts: [String] = []
        if newCount > 0 { parts.append("\(newCount) " + ruPlural(newCount, "новая функция", "новые функции", "новых функций")) }
        if fixedCount > 0 { parts.append("\(fixedCount) " + ruPlural(fixedCount, "исправление", "исправления", "исправлений")) }
        if otherCount > 0 { parts.append("\(otherCount) " + ruPlural(otherCount, "изменение", "изменения", "изменений")) }
        parts.append("\(releases) " + ruPlural(releases, "выпуск", "выпуска", "выпусков"))
        return parts.joined(separator: " · ")
    }
}

/// Русское множественное: 1 трек, 2 трека, 5 треков (как `tn` в Windows-клиенте).
func ruPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let mod10 = abs(n) % 10
    let mod100 = abs(n) % 100
    if mod10 == 1, mod100 != 11 { return one }
    if (2...4).contains(mod10), !(12...14).contains(mod100) { return few }
    return many
}

private func nonEmpty(_ value: Any?) -> String? {
    guard let string = value as? String else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func httpsURL(_ value: Any?) -> URL? {
    guard let string = value as? String, let url = URL(string: string), url.scheme == "https" else { return nil }
    return url
}

/// `"new": [{"text": "…"}]` или `["…"]`.
private func strings(_ value: Any?) -> [String] {
    guard let array = value as? [Any] else { return [] }
    return array.compactMap { element in
        let text = (element as? String) ?? ((element as? [String: Any])?["text"] as? String)
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
