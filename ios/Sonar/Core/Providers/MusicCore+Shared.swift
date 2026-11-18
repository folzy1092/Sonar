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
    static let shared = DownloadStore(fetcher: CoreDownloadFetcher())
}

/// Загрузки через `MusicCore` (ссылка) и `FileDownloader` (файл с прогрессом).
struct CoreDownloadFetcher: DownloadFetcher {
    func source(for track: Track) async throws -> DownloadSource {
        try await MusicCore.shared.downloadSource(track.ref)
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
                try await FileDownloader.shared.download(Self.request(url, range: span), to: part) { p in
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
