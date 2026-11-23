import Foundation

/// Чистые правила «Скачать» на iPhone (`docs/OFFLINE.md` §8, зеркало ПК `windows/src/lib/downloads-core.ts`):
/// оценка размера пачки, когда спрашивать, что из Любимых влезает в лимит, свободное место.
enum DownloadPlan {
    /// Больше — спросить перед пачкой (§8.2), как на ПК.
    static let confirmTracks = 50
    static let confirmBytes: Int64 = 1 << 30
    /// По скольку треков качать за раз.
    static let parallel = 2
    /// Лимит автоскачивания Любимых, ГБ (`storage.auto_download_limit_gb`).
    static let limitOptions = [2, 5, 10, 20, 50]

    /// Битрейт Яндекса по `audio.quality`; lossless — FLAC, в среднем ~1000 кбит/с.
    private static let yandexKbps = ["low": 192, "medium": 256, "high": 320, "lossless": 1000]
    /// Остальные сервисы отдают свой максимум — берём среднее.
    private static let otherKbps = 160
    /// Длительность неизвестна — средняя песня.
    private static let fallbackMs = 210_000

    /// Примерный размер трека в байтах: длительность × битрейт.
    static func trackBytes(_ track: Track, quality: String) -> Int64 {
        let kbps = track.ref.hasPrefix("ym:") ? (yandexKbps[quality] ?? 1000) : otherKbps
        let ms = track.durationMs > 0 ? track.durationMs : fallbackMs
        return Int64(ms) * Int64(kbps) / 8
    }

    static func batchBytes(_ tracks: [Track], quality: String) -> Int64 {
        tracks.reduce(0) { $0 + trackBytes($1, quality: quality) }
    }

    static func needsConfirm(count: Int, bytes: Int64) -> Bool {
        count > confirmTracks || bytes > confirmBytes
    }

    /// Автоскачивание Любимых: что по порядку (свежие лайки первыми) влезает в лимит поверх уже скачанного.
    /// Первый не влезший останавливает подбор — иначе мелкие старые треки обгоняли бы свежие лайки.
    static func fitToLimit(_ tracks: [Track], used: Int64, limit: Int64, quality: String) -> [Track] {
        var total = used
        var out: [Track] = []
        for track in tracks {
            total += trackBytes(track, quality: quality)
            if total > limit { break }
            out.append(track)
        }
        return out
    }

    /// Пачка для «Скачать всё» / Любимых: сколько займёт и сколько свободно.
    struct Batch: Identifiable {
        let id = UUID()
        let tracks: [Track]
        let bytes: Int64
        let free: Int64?

        init(_ tracks: [Track], quality: String, free: Int64?) {
            self.tracks = tracks
            bytes = DownloadPlan.batchBytes(tracks, quality: quality)
            self.free = free
        }

        /// Место не узнали — пробуем: упрёмся — трек вернёт ошибку.
        var fits: Bool { free.map { bytes < $0 } ?? true }
        var needsConfirm: Bool { DownloadPlan.needsConfirm(count: tracks.count, bytes: bytes) }

        /// «120 треков · ~1.4 ГБ · свободно 20.3 ГБ» — как на ПК.
        @MainActor var summary: String {
            var parts = [tracksCount(tracks.count), "~" + DownloadPlan.bytesText(bytes)]
            if let free { parts.append(t("свободно {n}", ["n": DownloadPlan.bytesText(free)])) }
            return parts.joined(separator: " · ")
        }
    }

    /// Свободно на диске для «важного» (iOS сама почистит кэши других приложений). Не узнали — nil.
    /// Папки ещё нет (первое скачивание) — смотрим ближайшую существующую выше.
    static func freeBytes(at url: URL) -> Int64? {
        var url = url
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        #if os(iOS)
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
        #else
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
        #endif
    }

    /// «340 МБ» / «1.2 ГБ».
    @MainActor static func bytesText(_ bytes: Int64) -> String {
        let gb = Double(bytes) / Double(1 << 30)
        if gb >= 1 { return t("{n} ГБ", ["n": String(format: "%.1f", gb)]) }
        return t("{n} МБ", ["n": "\(max(1, Int((Double(bytes) / Double(1 << 20)).rounded())))"])
    }
}

/// Плейлист HLS SoundCloud → что склеить в один файл (как ПК `cache_hls`). Шифрованное и `.ts` — не склеиваем.
enum HLSPlaylist: Equatable {
    /// Куски mp3 подряд.
    case mp3([URL])
    /// fMP4: инициализация + куски.
    case fmp4(initial: URL, segments: [URL])
    /// Мастер-плейлист — взять первый вариант.
    case variant(URL)

    static func parse(_ text: String, base: URL) -> HLSPlaylist? {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first?.hasPrefix("#EXTM3U") == true else { return nil }
        func resolve(_ ref: String) -> URL? { URL(string: ref, relativeTo: base)?.absoluteURL }
        var initial: URL?
        var segments: [URL] = []
        var nextIsVariant = false
        for line in lines where !line.isEmpty {
            if line.hasPrefix("#EXT-X-KEY"), !line.contains("METHOD=NONE") { return nil }
            if line.hasPrefix("#EXT-X-MAP") {
                guard let uri = attribute("URI", in: line), let url = resolve(uri) else { return nil }
                initial = url
            } else if line.hasPrefix("#EXT-X-STREAM-INF") {
                nextIsVariant = true
            } else if !line.hasPrefix("#") {
                guard let url = resolve(line) else { return nil }
                if nextIsVariant { return .variant(url) }
                segments.append(url)
            }
        }
        guard !segments.isEmpty else { return nil }
        if let initial { return .fmp4(initial: initial, segments: segments) }
        // MPEG-TS AVPlayer из файла не сыграет
        if segments.contains(where: { $0.pathExtension.lowercased() == "ts" }) { return nil }
        return .mp3(segments)
    }

    /// `URI="…"` из строки тега.
    private static func attribute(_ name: String, in line: String) -> String? {
        guard let range = line.range(of: "\(name)=\"") else { return nil }
        let rest = line[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}
