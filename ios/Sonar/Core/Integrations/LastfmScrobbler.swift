import Foundation
import Observation

/// Где хранится вход Last.fm: на телефоне — Keychain (`LastfmKeychain`), в тестах — память.
protocol LastfmSessionStoring: Sendable {
    func load() -> LastfmSession?
    func save(_ session: LastfmSession?)
}

/// Скробблинг и «Сейчас играет» (как Windows `commands.rs` → `lastfm.rs`). Плеер зовёт два метода:
/// `trackStarted(_:)` — трек начал играть (новый трек или повтор с начала), `progress(listenedMs:)` —
/// сколько реально прослушано у текущего (перемотка не считается). Скроббл — один раз на
/// прослушивание по `LastfmRules` (половина или 4 мин, трек > 30 с), время — начало прослушивания.
/// Нет сети / Last.fm недоступен — скробблы ждут в очереди (до 14 дней, `pending`) и уходят пачкой
/// со следующим. Выключено настройкой, нет входа или ключа — ничего не делает.
@MainActor
@Observable
final class LastfmScrobbler {
    static let shared = LastfmScrobbler()

    static let scrobbleKey = "integrations.lastfm.scrobble"
    static let nowPlayingKey = "integrations.lastfm.now_playing"
    static let pendingLimit = 500

    /// Ключ приложения есть в сборке — вход возможен.
    let available: Bool
    private(set) var session: LastfmSession?
    /// Скробблы, ещё не отправленные.
    private(set) var pending: [LastfmTrack] = []
    /// Последняя ошибка отправки — для экрана.
    private(set) var lastError: String?
    private(set) var lastSent: Date?

    @ObservationIgnored private let api: LastfmAPI?
    @ObservationIgnored private let store: LastfmSessionStoring
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var current: (track: Track, startedAt: Date, done: Bool)?
    @ObservationIgnored private var flushing = false

    private static let pendingKey = "sonar.lastfm.pending"

    init(keys: LastfmKeys? = LastfmKeys.bundled, transport: LastfmTransport = URLSessionLastfmTransport(),
         store: LastfmSessionStoring? = nil, settings: SettingsStore? = nil, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        api = keys.map { LastfmAPI(keys: $0, transport: transport) }
        available = keys != nil
        self.store = store ?? Self.defaultStore()
        self.settings = settings ?? .shared
        self.defaults = defaults
        self.now = now
        session = self.store.load()
        if let data = defaults.data(forKey: Self.pendingKey), let list = try? JSONDecoder().decode([LastfmTrack].self, from: data) {
            pending = list
        }
    }

    private static func defaultStore() -> LastfmSessionStoring {
        #if canImport(Security)
        LastfmKeychain()
        #else
        MemoryLastfmStore()
        #endif
    }

    var isConnected: Bool { session != nil }
    /// Клиент API — для входа (`LastfmLogin`).
    var client: LastfmAPI? { api }

    private var active: Bool { available && session != nil }

    // MARK: - Плеер

    /// Трек начал играть. Отправляет «Сейчас играет» (если включено).
    func trackStarted(_ track: Track) {
        current = (track, now(), false)
        guard active, settings.bool(Self.nowPlayingKey), let api, let key = session?.key else { return }
        let item = LastfmTrack(track, startedAt: now())
        Task { [weak self] in
            do { try await api.nowPlaying(item, session: key) } catch { self?.handle(error) }
        }
    }

    /// Прослушано у текущего трека, мс. Порог пройден — скроббл (один раз).
    func progress(listenedMs: Int) {
        guard var playing = current, !playing.done,
              LastfmRules.shouldScrobble(listenedMs: listenedMs, durationMs: playing.track.durationMs) else { return }
        playing.done = true
        current = playing
        guard active, settings.bool(Self.scrobbleKey) else { return }
        enqueue(LastfmTrack(playing.track, startedAt: playing.startedAt))
        flush()
    }

    // MARK: - Очередь

    private func enqueue(_ track: LastfmTrack) {
        pending.append(track)
        if pending.count > Self.pendingLimit { pending.removeFirst(pending.count - Self.pendingLimit) }
        savePending()
    }

    /// Отправить ждущие (по 50). Старше 14 дней — выбросить.
    func flush() {
        guard !flushing, active, let api, let key = session?.key else { return }
        let cutoff = Int(now().addingTimeInterval(-LastfmRules.maxAge).timeIntervalSince1970)
        pending.removeAll { $0.startedAt < cutoff }
        let batch = Array(pending.prefix(50))
        guard !batch.isEmpty else {
            savePending()
            return
        }
        flushing = true
        Task { [weak self] in
            do {
                try await api.scrobble(batch, session: key)
                guard let self else { return }
                self.flushing = false
                self.pending.removeFirst(min(batch.count, self.pending.count))
                self.savePending()
                self.lastError = nil
                self.lastSent = self.now()
                if !self.pending.isEmpty { self.flush() }
            } catch {
                guard let self else { return }
                self.flushing = false
                self.handle(error)
                // ошибка не временная (например, трек отклонён) — пачку не держим вечно
                if let lf = error as? LastfmError, !lf.isTemporary, !lf.isInvalidSession {
                    self.pending.removeFirst(min(batch.count, self.pending.count))
                    self.savePending()
                }
            }
        }
    }

    private func handle(_ error: Error) {
        if let lf = error as? LastfmError, lf.isInvalidSession {
            // доступ отозван на last.fm — вход заново
            setSession(nil)
            lastError = "Доступ к Last.fm отозван — войди снова"
        } else {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func savePending() {
        if pending.isEmpty {
            defaults.removeObject(forKey: Self.pendingKey)
        } else if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: Self.pendingKey)
        }
    }

    // MARK: - Вход

    func setSession(_ value: LastfmSession?) {
        session = value
        store.save(value)
        if value == nil {
            pending = []
            savePending()
        } else {
            lastError = nil
            flush()
        }
    }

    func logout() {
        setSession(nil)
    }
}

/// Вход в памяти — тесты и Linux.
final class MemoryLastfmStore: LastfmSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: LastfmSession?

    init(_ value: LastfmSession? = nil) { self.value = value }

    func load() -> LastfmSession? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func save(_ session: LastfmSession?) {
        lock.lock()
        value = session
        lock.unlock()
    }
}
