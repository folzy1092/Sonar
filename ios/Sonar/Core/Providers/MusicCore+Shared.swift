import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Связка общих объектов с `MusicCore`. Отдельным файлом: подборки, волна, загрузки и конвертер
// написаны против протоколов (`MusicSource`, `DownloadFetcher`) и проверяются без сети и без
// Keychain — а здесь им дают настоящий источник.

extension MusicCore: MusicSource {}

extension HomeFeed {
    static let shared = HomeFeed(source: MusicCore.shared, library: .shared, history: .shared)
}

extension DownloadStore {
    /// Только Wi‑Fi (`storage.download_wifi_only`) — по сотовой очередь ждёт; текст песни — рядом с треком.
    static let shared: DownloadStore = {
        let store = DownloadStore(fetcher: CoreDownloadFetcher()) {
            !SettingsStore.shared.bool(wifiOnlyKey) || NetworkStatus.shared.isUnmetered
        }
        store.onSaved = { track in Task { await LyricsStore.shared.pin(track) } }
        store.onRemoved = { ref in LyricsStore.shared.unpin(ref) }
        return store
    }()

    static let wifiOnlyKey = "storage.download_wifi_only"
}

/// Загрузки через `MusicCore` (ссылка) и `FileDownloader` (файл с прогрессом).
struct CoreDownloadFetcher: DownloadFetcher {
    func source(for track: Track) async throws -> DownloadSource {
        try await MusicCore.shared.downloadSource(track.ref)
    }

    func fetch(_ source: DownloadSource, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard source.isHLS else {
            try await fetch(source.url, to: destination, progress: progress)
            return
        }
        try await fetchHLS(source.url, to: destination, progress: progress)
    }

    func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        // YouTube Music: без диапазона googlevideo режет скорость — кусками (`GVideo`)
        if GVideo.isGVideo(url), let total = GVideo.contentLength(url) {
            try await fetchInChunks(url, total: total, to: destination, progress: progress)
            return
        }
        try await FileDownloader.shared.download(Self.request(url), to: destination, progress: progress)
    }

    private static func request(_ url: URL, range: ClosedRange<Int64>? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(HTTP.browserAgent, forHTTPHeaderField: "User-Agent")
        if let range { request.setValue(GVideo.rangeHeader(range), forHTTPHeaderField: "Range") }
        return request
    }

    /// Файл `total` байт кусками по `GVideo.chunk`, каждый — во временный файл и в конец `destination`.
    /// Оборвалось — недописанный файл удаляется.
    private func fetchInChunks(_ url: URL, total: Int64, to destination: URL,
                               progress: @escaping @Sendable (Double) -> Void) async throws {
        let files = FileManager.default
        let part = destination.appendingPathExtension("part")
        try? files.removeItem(at: destination)
        guard files.createFile(atPath: destination.path, contents: nil) else {
            throw ServiceError(message: "Не удалось сохранить файл")
        }
        do {
            let out = try FileHandle(forWritingTo: destination)
            defer { try? out.close() }
            for span in GVideo.spans(total: total) {
                let done = Double(span.lowerBound)
                let size = Double(GVideo.length(span))
                try await FileDownloader.segments.download(Self.request(url, range: span), to: part) { p in
                    progress((done + p * size) / Double(total))
                }
                let data = try Data(contentsOf: part)
                try? files.removeItem(at: part)
                guard Int64(data.count) == GVideo.length(span) else {
                    throw ServiceError(message: "YouTube Music: файл скачался не целиком")
                }
                try out.write(contentsOf: data)
            }
        } catch {
            try? files.removeItem(at: part)
            try? files.removeItem(at: destination)
            throw error
        }
    }

    private static func playlist(_ url: URL) async throws -> HLSPlaylist? {
        let text = String(decoding: try await HTTP.data(request(url), service: "SoundCloud"), as: UTF8.self)
        return HLSPlaylist.parse(text, base: url)
    }

    /// HLS SoundCloud → один файл (`docs/OFFLINE.md` §8.1, как ПК `cache_hls`): init fMP4 (если есть) и куски
    /// подряд. Мастер-плейлист — первый вариант; шифрованный и MPEG-TS — «нельзя скачать».
    private func fetchHLS(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        var playlist = try await Self.playlist(url)
        if case let .variant(next) = playlist { playlist = try await Self.playlist(next) }
        let parts: [URL]
        switch playlist {
        case let .mp3(segments): parts = segments
        case let .fmp4(initial, segments): parts = [initial] + segments
        case .variant, nil: parts = []
        }
        guard !parts.isEmpty else { throw ServiceError(message: "Этот трек нельзя скачать") }
        let files = FileManager.default
        let part = destination.appendingPathExtension("seg")
        try? files.removeItem(at: destination)
        guard files.createFile(atPath: destination.path, contents: nil) else {
            throw ServiceError(message: "Не удалось сохранить файл")
        }
        do {
            let out = try FileHandle(forWritingTo: destination)
            defer { try? out.close() }
            for (index, segment) in parts.enumerated() {
                try await FileDownloader.segments.download(Self.request(segment), to: part) { p in
                    progress((Double(index) + p) / Double(parts.count))
                }
                try out.write(contentsOf: try Data(contentsOf: part))
                try? files.removeItem(at: part)
            }
        } catch {
            try? files.removeItem(at: part)
            try? files.removeItem(at: destination)
            throw error
        }
    }
}

extension Converter {
    /// Через сервисы телефона (`MusicCore`).
    static func convert(_ tracks: [Track], to service: Service) async -> (found: [Track], missing: [Track]) {
        await convert(tracks, to: service, using: MusicCore.shared)
    }
}

extension MusicCore {
    /// «Конвертировать на другой сервис» (см. `Converter`).
    func convert(_ tracks: [Track], to service: Service) async -> (found: [Track], missing: [Track]) {
        await Converter.convert(tracks, to: service, using: self)
    }
}
