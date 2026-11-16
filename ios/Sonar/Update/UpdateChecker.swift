import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // тесты логики на Linux
#endif
import Observation

/// Проверка обновлений (SETTINGS.md «Автообновление»): при запуске и раз в 6 часов, если включено
/// `update.auto_check`. Сначала `ios-update.json`, не скачался — список релизов GitHub. Нашлась новая
/// сборка — всплывашка снизу (один раз на сборку) и бейдж на «Обновлениях» в профиле.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let interval: TimeInterval = 6 * 60 * 60

    private(set) var status: UpdateStatus?
    private(set) var isChecking = false
    private(set) var lastChecked: Date?
    /// «Архив версий» — все сборки iPhone из changelog.json; nil — ещё не загружен.
    private(set) var archive: [ChangelogEntry]?
    /// Всплывашка «Доступно обновление».
    var popup: UpdateRelease?

    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let dismissedKey = "sonar.update.dismissed_build"

    var available: UpdateRelease? {
        if case let .available(release) = status { return release }
        return nil
    }

    static var installedBuild: Int? {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap { Int($0) }
    }

    static var installedVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    /// "0.1.0 (12)"
    static var installedLabel: String {
        installedVersion + (installedBuild.map { " (\($0))" } ?? "")
    }

    /// Автопроверка: сразу и дальше раз в 6 часов, пока приложение живо.
    func startAutomatic(settings: SettingsStore) {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                if settings.bool("update.auto_check") {
                    await self?.check(silent: true)
                }
                try? await Task.sleep(for: .seconds(UpdateChecker.interval))
            }
        }
    }

    /// Вернулись в приложение — проверить, если прошлая проверка старше интервала.
    func checkIfStale(settings: SettingsStore) {
        guard settings.bool("update.auto_check") else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.interval { return }
        Task { await check(silent: true) }
    }

    /// silent — фоновая: при находке показывает всплывашку (кроме уже закрытой для этой сборки).
    func check(silent: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let installed = Self.installedBuild
        var result: UpdateStatus
        if let (data, code) = await Self.fetch(UpdateFeed.manifestURL), (200 ..< 300).contains(code),
           let manifest = UpdateManifest.parse(data) {
            result = .from(manifest: manifest, installedBuild: installed)
        } else if let (data, code) = await Self.fetch(UpdateFeed.releasesAPIURL) {
            if code == 404 {
                result = .failed("Релизов пока нет")
            } else if !(200 ..< 300).contains(code) {
                result = .failed("GitHub ответил \(code)")
            } else if let release = UpdateRelease.parseReleases(data) {
                result = .from(release: release, installedBuild: installed)
            } else {
                result = .failed("Сборок для iPhone пока нет")
            }
        } else {
            result = .failed("Нет связи с GitHub")
        }
        // что изменилось с установленной сборки; не скачалось — обновление всё равно показываем
        if case var .available(release) = result {
            if let entries = await loadChangelog() {
                release.changelog = ChangelogEntry.changes(installedBuild: installed, announcedBuild: release.build, entries: entries)
            }
            result = .available(release)
        }
        status = result
        lastChecked = Date()
        if case let .available(release) = result, silent, defaults.integer(forKey: Self.dismissedKey) != release.build {
            popup = release
        }
    }

    /// «Позже» — больше не показывать всплывашку для этой сборки (бейдж остаётся).
    func dismissPopup() {
        if let popup { defaults.set(popup.build, forKey: Self.dismissedKey) }
        popup = nil
    }

    func loadArchive() async {
        if let entries = await loadChangelog() { archive = entries }
        else if archive == nil { archive = [] }
    }

    private func loadChangelog() async -> [ChangelogEntry]? {
        guard let (data, code) = await Self.fetch(UpdateFeed.changelogURL), (200 ..< 300).contains(code) else { return nil }
        let entries = ChangelogEntry.parse(data)
        archive = entries
        return entries
    }

    /// Параметр-метка мимо кэша CDN raw.githubusercontent (~5 мин): только что объявленная сборка видна сразу.
    private static func fetch(_ url: URL) async -> (Data, Int)? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970))))
        components?.queryItems = items
        var request = URLRequest(url: components?.url ?? url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
