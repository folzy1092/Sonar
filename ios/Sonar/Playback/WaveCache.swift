import Foundation
import Network
import Observation

/// Сеть телефона: есть ли связь и безлимитная ли она (Wi‑Fi — не «дорогая» и не «экономия трафика»).
@MainActor
@Observable
final class NetworkStatus {
    static let shared = NetworkStatus()

    private(set) var isOnline = true
    private(set) var isUnmetered = false

    @ObservationIgnored private let monitor = NWPathMonitor()
    /// Кто ждёт смены сети (кэш волны).
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    init() {
        Self.start(monitor) { [weak self] online, unmetered in
            Task { @MainActor in self?.update(online: online, unmetered: unmetered) }
        }
    }

    private func update(online: Bool, unmetered: Bool) {
        guard online != isOnline || unmetered != isUnmetered else { return }
        isOnline = online
        isUnmetered = unmetered
        onChange?()
    }

    /// Вне главного актора: монитор зовёт обработчик со своей очереди, замыкание с главного актора упало
    /// бы на проверке изоляции.
    nonisolated private static func start(_ monitor: NWPathMonitor, _ handler: @escaping @Sendable (Bool, Bool) -> Void) {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            handler(online, online && !path.isExpensive && !path.isConstrained)
        }
        monitor.start(queue: DispatchQueue(label: "com.folzy.sonar.network"))
    }
}

/// Волна без сети (`wave.offline`): на Wi‑Fi следующие 15 треков волны подкачиваются в кэш
/// (Caches/Sonar/WaveCache — в бэкап не идёт, iOS может почистить при нехватке места), без сети плеер играет
/// их оттуда. Качает так же, как «Скачать» (`DownloadStore` — файл, не HLS: у SoundCloud — Яндекс-двойник или
/// прямой mp3), по два за раз. Сыгранное и ушедшее из «Далее» удаляется. План — `WaveCachePlan`.
@MainActor
final class WaveCache {
    static let shared = WaveCache()

    private let store: DownloadStore
    private let network = NetworkStatus.shared
    /// Что ещё скачать, по порядку.
    private var queue: [Track] = []
    /// Уже пробовали в эту сессию — не повторять (HLS без файла, ошибки).
    private var attempted: Set<String> = []
    private var pump: Task<Void, Never>?
    private var lastUpcoming: [Track] = []
    private var lastCurrent: Track?
    private var lastEnabled = false

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        store = DownloadStore(fetcher: CoreDownloadFetcher(), directory: base.appendingPathComponent("Sonar/WaveCache", isDirectory: true))
        network.onChange = { [weak self] in self?.reapply() }
    }

    var isOnline: Bool { network.isOnline }

    func localURL(_ ref: String) -> URL? {
        store.localURL(ref)
    }

    func quality(_ ref: String) -> String? {
        store.quality(ref).map { "\($0) · офлайн" }
    }

    /// Сколько места занято (для Хранилища).
    var totalBytes: Int64 { store.totalBytes }

    /// Плеер зовёт при смене трека и догрузке волны. Не волна — ничего (кэш ждёт следующей волны);
    /// выключено — очистить.
    func update(upcoming: [Track], current: Track?, isWave: Bool, enabled: Bool) {
        guard isWave || !enabled else { return }
        lastUpcoming = upcoming
        lastCurrent = current
        lastEnabled = enabled
        let plan = WaveCachePlan.plan(upcoming: upcoming.map(\.ref), current: current?.ref,
                                      cached: Set(store.downloaded.map(\.ref)),
                                      downloaded: Set(DownloadStore.shared.downloaded.map(\.ref)),
                                      attempted: attempted, enabled: enabled)
        for ref in plan.evict { store.remove(ref) }
        let byRef = Dictionary(upcoming.map { ($0.ref, $0) }, uniquingKeysWith: { first, _ in first })
        queue = plan.fetch.compactMap { byRef[$0] }
        startPump()
    }

    /// Сеть сменилась (пришёл Wi‑Fi) — продолжить с тем же «Далее».
    private func reapply() {
        guard lastEnabled else { return }
        update(upcoming: lastUpcoming, current: lastCurrent, isWave: true, enabled: true)
    }

    /// Качать по `parallel` за раз и только на безлимитной сети; ушли с Wi‑Fi — ждать.
    private func startPump() {
        guard pump == nil, !queue.isEmpty else { return }
        pump = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.step() else { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Шаг подкачки: false — очередь пуста, подкачка закончилась.
    private func step() -> Bool {
        guard !queue.isEmpty else {
            pump = nil
            return false
        }
        if network.isUnmetered {
            while store.progress.count < WaveCachePlan.parallel, !queue.isEmpty {
                let track = queue.removeFirst()
                attempted.insert(track.ref)
                store.download(track)
            }
        }
        return true
    }
}
