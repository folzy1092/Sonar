import BackgroundTasks
import Foundation
import Observation
import UserNotifications

/// «Новинки исполнителей» на iPhone — как ПК `lib/new-releases.svelte.ts`, но вместо тоста — уведомление.
/// Фоновое обновление iOS (`BGAppRefreshTask`, `SonarApp` `.backgroundTask`; просим раз в 3 ч, когда
/// именно — решает iOS) и открытие Sonar, если с прошлой проверки прошло 3 ч: ядро собирает ленту
/// (`MusicCore.releaseFeed`), про свежие за неделю, которых ещё не видели, — локальное уведомление
/// «У … вышел «…»» (без APNs; с сервером — пуши). Тап: альбом открывается (`sonar://album/<ref>`),
/// трек играет (`sonar://track/<ref>`, трек — из сохранённой ленты).
/// Выключатель — Система → Общее → «Новинки исполнителей» (`notify.releases`, общий ключ с ПК).
@MainActor
@Observable
final class ReleaseNotifier {
    static let shared = ReleaseNotifier()
    static let key = "notify.releases"
    static let interval: TimeInterval = 3 * 3600
    /// Больше уведомлений за одну проверку не шлём — остальное и так в «Релизах» на Главной.
    static let maxNotices = 3
    private static let seenKey = "sonar.releases.seen"
    private static let checkedKey = "sonar.releases.checked_at"

    /// Id фоновой задачи — из Info.plist: при своей подписи `BundlePreparer` меняет префикс bundle id,
    /// а id, которого нет в Info.plist, iOS не запустит.
    nonisolated static let taskID: String =
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?
            .first { $0.hasSuffix(".releases") } ?? "com.folzy.sonar.releases"

    /// Ссылка из тапа по уведомлению — её забирает `SonarApp` (там роутер).
    var pendingURL: URL?

    @ObservationIgnored private var feed: [ReleaseItem] = []
    @ObservationIgnored private var checking = false
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let file: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Sonar/releases.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([ReleaseItem].self, from: data) {
            feed = saved
        }
    }

    /// Из `SonarApp.init`: делегат ставится до конца запуска — иначе тап по уведомлению,
    /// которое разбудило Sonar с нуля, потеряется.
    nonisolated static func installDelegate() {
        UNUserNotificationCenter.current().delegate = NotificationTap.shared
    }

    /// Следующая фоновая проверка — не раньше чем через 3 ч.
    func schedule() {
        guard SettingsStore.shared.bool(Self.key) else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            CrashLog.note("новинки: фоновая проверка не запланирована — \(error.localizedDescription)")
        }
    }

    /// Sonar на экране: проверить, если с прошлого раза прошло 3 ч, и запланировать фоновую.
    func checkIfStale(now: Date = Date()) async {
        schedule()
        await askQuietly()
        let last = defaults.double(forKey: Self.checkedKey)
        guard now.timeIntervalSince1970 - last >= Self.interval else { return }
        await check(now: now)
    }

    /// Фоновое обновление iOS (`SonarApp` `.backgroundTask`): сразу просим следующее, потом проверяем.
    func runInBackground() async {
        schedule()
        await check()
    }

    /// Выключатель в настройках: включили — спросить разрешение на уведомления (только тут, не при запуске).
    func setEnabled(_ on: Bool) async {
        SettingsStore.shared.set(Self.key, on)
        guard on else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
            return
        }
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            CrashLog.note("новинки: нет разрешения на уведомления — \(error.localizedDescription)")
        }
        schedule()
        await check()
    }

    /// Собрать ленту, про новые свежие — уведомить, запомнить их как увиденные.
    func check(now: Date = Date()) async {
        guard SettingsStore.shared.bool(Self.key), !checking else { return }
        checking = true
        defer { checking = false }
        let artists = Self.artistRefs()
        guard !artists.isEmpty else { return }
        let fresh = await MusicCore.shared.releaseFeed(artists: artists)
        // сеть не ответила (или Keychain заперт в фоне) — проверка не считается сделанной
        guard !fresh.isEmpty else { return }
        defaults.set(now.timeIntervalSince1970, forKey: Self.checkedKey)
        feed = fresh
        save()
        let seen = defaults.stringArray(forKey: Self.seenKey) ?? []
        let unseen = ReleaseMath.unseenFresh(fresh, seen: Set(seen), now: now)
        guard !unseen.isEmpty else { return }
        defaults.set(ReleaseMath.remember(unseen.map(\.ref), in: seen), forKey: Self.seenKey)
        await post(unseen)
    }

    /// Трек из последней ленты — сыграть по тапу на уведомление.
    func track(_ ref: String) -> Track? {
        feed.first { $0.ref == ref }?.track
    }

    /// Ссылка уведомления: альбом — открыть, трек — сыграть.
    nonisolated static func link(_ item: ReleaseItem) -> URL? {
        let host = item.kind == .album ? "album" : "track"
        guard let ref = item.ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "sonar://\(host)/\(ref)")
    }

    // MARK: - Внутри

    /// Исполнители, как ПК `release_artist_refs`: сначала сохранённые в Медиатеку, потом артисты Любимых.
    private static func artistRefs() -> [String] {
        var refs = PlaylistStore.shared.artists.map(\.artist.ref)
        let fromLiked = WaveMath.favoriteArtistRefs(liked: LibraryStore.shared.liked, recent: [],
                                                    limit: MusicCore.releaseArtistLimit)
        for ref in fromLiked where !refs.contains(ref) { refs.append(ref) }
        return refs
    }

    /// Выключатель по умолчанию включён, а спрашивать при запуске нельзя — до явного «да» уведомления
    /// приходят тихо, в Центр уведомлений (provisional, без окна-вопроса).
    private func askQuietly() async {
        guard SettingsStore.shared.bool(Self.key) else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
    }

    private func post(_ items: [ReleaseItem]) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        for item in items.prefix(Self.maxNotices) {
            let content = UNMutableNotificationContent()
            content.title = t("Новинки")
            content.body = t("У {artist} вышел «{title}»", ["artist": item.artist, "title": item.title])
            content.sound = .default
            content.threadIdentifier = "releases"
            if let url = Self.link(item) { content.userInfo = ["url": url.absoluteString] }
            do {
                try await center.add(UNNotificationRequest(identifier: "release-\(item.ref)", content: content, trigger: nil))
            } catch {
                CrashLog.note("новинки: уведомление не показано — \(error.localizedDescription)")
            }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(feed) else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            CrashLog.note("новинки: лента не сохранена — \(error.localizedDescription)")
        }
    }
}

/// Делегат уведомлений: показываются и при открытом Sonar, тап — ссылка в `ReleaseNotifier.pendingURL`.
final class NotificationTap: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationTap()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: raw) else { return }
        await MainActor.run { ReleaseNotifier.shared.pendingURL = url }
    }
}
