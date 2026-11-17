import Foundation
import Observation

/// Синк в приложении: обмен раз в 2 минуты и через несколько секунд после своей правки — **только
/// если `AccountStore.serverEnabled` и вошли**. Без сервера не делает ничего (ни одного запроса, журнал
/// не ведётся). Запуск — `SyncService.shared.start()` при старте приложения.
@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    static let interval: Duration = .seconds(120)
    static let debounce: Duration = .seconds(4)

    private(set) var syncing = false
    private(set) var lastSyncAt: Date?
    private(set) var lastReport: SyncReport?
    private(set) var lastError: String?

    /// Неотправленных строк.
    var pending: Int { engine?.journal.pendingCount ?? 0 }

    @ObservationIgnored private var engine: SyncEngine?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var soon: Task<Void, Never>?
    @ObservationIgnored private let account: AccountStore

    init(account: AccountStore? = nil) {
        self.account = account ?? .shared
    }

    /// Поднять синк, если сервер включён и вошли; иначе — ничего. Можно звать повторно (вход / выход).
    func start() {
        account.onSessionChange = { [weak self] signedIn in
            if signedIn { self?.start() } else { self?.stopAndForget() }
        }
        guard account.enabled(), account.signedIn else {
            stop()
            return
        }
        if engine == nil { engine = makeEngine() }
        hookStores()
        guard loop == nil else { return }
        loop = Task { [weak self] in
            await self?.syncNow()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                await self?.syncNow()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        soon?.cancel()
        soon = nil
    }

    /// Выход из аккаунта: журнал забывается (другой аккаунт — чистое слияние), данные на телефоне остаются.
    private func stopAndForget() {
        stop()
        engine?.reset()
        engine = nil
    }

    /// Обмен сейчас (кнопка «Синхронизировать»).
    func syncNow() async {
        guard !syncing, let engine, let base = account.apiBaseURL, let token = account.sessionToken else { return }
        syncing = true
        defer { syncing = false }
        do {
            let report = try await engine.syncOnce(HTTPSyncTransport(client: APIClient(base: base, token: token)))
            lastReport = report
            lastSyncAt = Date()
            lastError = nil
        } catch let error as APIError where error.isUnauthorized {
            account.signedOut()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Своя правка в хранилище: сразу в журнал (точное `client_ts`), отправка — через несколько секунд.
    func noteLocalChange() {
        guard let engine, !engine.isApplying else { return }
        engine.scan()
        soon?.cancel()
        soon = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private func hookStores() {
        LibraryStore.shared.onChange = { [weak self] in self?.noteLocalChange() }
        SettingsStore.shared.onChange = { [weak self] key in
            if SyncPolicy.settingSyncs(key) { self?.noteLocalChange() }
        }
        PlayHistory.shared.onChange = { [weak self] in self?.noteLocalChange() }
    }

    private func makeEngine() -> SyncEngine {
        let library = LibraryStore.shared
        let lyrics = LyricsStore.shared
        let now = { Int64(Date().timeIntervalSince1970 * 1000) }
        let artist: (String) -> String? = { ref in
            library.liked.first { $0.ref == ref }?.artist
                ?? PlayHistory.shared.recent.first { $0.ref == ref }?.artist
                ?? PlayLog.shared.tracks[ref]?.artist
        }
        let adapters: [SyncAdapter] = [
            LikesSyncAdapter(library: library, now: now),
            DislikesSyncAdapter(library: library, artist: artist, now: now),
            TrackPrefsSyncAdapter(library: library, offsets: { lyrics.offsets },
                                  setOffset: { ref, ms in lyrics.setOffset(LyricsClock.offsetFromMs(ms), for: ref) }),
            SettingsSyncAdapter(settings: .shared),
        ]
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return SyncEngine(deviceId: account.vault.deviceId, adapters: adapters,
                          file: base.appendingPathComponent("Sonar/sync.json"),
                          plays: { since in PlayUpload.from(PlayLog.shared.rows, since: since, now: Date()) },
                          now: now)
    }
}
