import Foundation

/// Автоскачивание Любимых на iPhone (`docs/OFFLINE.md` §8.3, как ПК `fillLiked` в `lib/downloads.svelte.ts`):
/// при запуске, после лайка и когда вернулся Wi‑Fi недостающие лайки встают в очередь «Скачать» — свежие первыми,
/// пока всё скачанное влезает в `storage.auto_download_limit_gb`. Только по Wi‑Fi, в офлайне — ничего.
@MainActor
enum LikedAutoDownload {
    static let enabledKey = "storage.auto_download_liked"
    static let limitKey = "storage.auto_download_limit_gb"

    private static let gigabyte: Int64 = 1 << 30

    /// Что поставить в очередь: недостающие лайки по порядку, пока скачанное + стоящее в очереди + новое ≤ лимита.
    static func plan(
        liked: [Track],
        isDownloaded: (String) -> Bool,
        isQueued: (String) -> Bool,
        downloadedBytes: Int64,
        limitGB: Int,
        quality: String
    ) -> [Track] {
        let queued = liked.filter { isQueued($0.ref) }
        let missing = liked.filter { !isDownloaded($0.ref) && !isQueued($0.ref) }
        let used = downloadedBytes + DownloadPlan.batchBytes(queued, quality: quality)
        return DownloadPlan.fitToLimit(missing, used: used, limit: Int64(limitGB) * gigabyte, quality: quality)
    }

    /// Чего из Любимых нет на телефоне — для подтверждения при включении.
    static func missing(_ liked: [Track], store: DownloadStore = .shared) -> [Track] {
        liked.filter { !store.isDownloaded($0.ref) && !store.isQueued($0.ref) }
    }

    static func limitGB(_ settings: SettingsStore = .shared) -> Int {
        max(1, Int(settings.double(limitKey)))
    }

    /// Докачать Любимые в пределах лимита. Тихо: без сообщений, выключено / офлайн / не Wi‑Fi — ничего.
    static func fill(
        library: LibraryStore = .shared,
        store: DownloadStore = .shared,
        settings: SettingsStore = .shared
    ) {
        guard settings.bool(enabledKey), !OfflineFlag.isOn, NetworkStatus.shared.isUnmetered else { return }
        let tracks = plan(
            liked: library.liked,
            isDownloaded: store.isDownloaded,
            isQueued: store.isQueued,
            downloadedBytes: store.totalBytes,
            limitGB: limitGB(settings),
            quality: settings.string("audio.quality")
        )
        tracks.forEach(store.download)
    }
}
