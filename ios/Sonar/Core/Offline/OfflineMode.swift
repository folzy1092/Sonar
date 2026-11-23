import Foundation
import Observation

/// Офлайн-режим на iPhone (`general.offline`, `docs/OFFLINE.md` §4, §9): ни байта в сеть, видно и играет
/// только то, что лежит на телефоне файлом. Не синхронизируется (`SyncPolicy.localSettings`).
/// Экраны читают `isOn` и фильтруют через `filter`; сеть держат `OfflineGuard` и `PlaybackEngine`.
@MainActor
@Observable
final class OfflineMode {
    static let shared = OfflineMode()

    private(set) var isOn: Bool
    /// Плашка «Сеть пропала · Включить офлайн-режим» (`general.offline_suggest`).
    private(set) var suggesting = false

    @ObservationIgnored private var suggested = false

    @ObservationIgnored private let settings: SettingsStore

    init(settings: SettingsStore = .shared, storage: UserDefaults = .standard) {
        self.settings = settings
        isOn = OfflineFlag.read(from: storage)
        OfflineFlag.set(isOn)
    }

    /// Самое начало запуска (`SonarApp.init`): флаг — до проверки обновлений, новинок и синка (§4.1).
    static func bootstrap() {
        URLProtocol.registerClass(OfflineGuard.self)
        _ = shared
    }

    /// Включить / выключить. Включили — оборвать начатое в сети и убрать недоступное из очереди (§9);
    /// выключили — ничего не догоняем пачкой: проверки идут по своему расписанию.
    func set(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        suggesting = false
        OfflineFlag.set(on)
        settings.set(OfflineFlag.key, on)
        guard on else {
            // сеть вернули: только синк (свой таймер); проверки обновлений и новинок — по своему расписанию
            SyncService.shared.start()
            DownloadStore.shared.resume()
            return
        }
        SyncService.shared.stop()
        URLSession.shared.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        FileDownloader.stopAll()
        PlaybackEngine.shared.offlineChanged()
    }

    /// Сеть пропала / вернулась (`NetworkStatus`): одна плашка на одну пропажу, сам режим не включается.
    func networkChanged(online: Bool) {
        let next = OfflineSuggest.next(shown: suggested, online: online, modeOn: isOn, enabled: settings.bool(OfflineSuggest.key))
        suggested = next.shown
        if next.show { suggesting = true }
        if online { suggesting = false }
    }

    func dismissSuggestion() {
        suggesting = false
    }

    /// Трек играет без сети: скачан или лежит в кэше волны.
    func isAvailable(_ ref: String) -> Bool {
        DownloadStore.shared.isDownloaded(ref) || WaveCache.shared.has(ref)
    }

    /// Всё, что играет без сети: скачанное, затем кэш волны (без повторов).
    var availableTracks: [Track] {
        var seen = Set<String>()
        return (DownloadStore.shared.downloaded + WaveCache.shared.tracks).filter { seen.insert($0.ref).inserted }
    }

    /// Фильтр для экранов: в офлайне — только доступное, иначе — всё.
    var filter: OfflineFilter {
        isOn ? OfflineFilter(isAvailable: isAvailable) : OfflineFilter(isAvailable: { _ in true })
    }
}
