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
        var request = URLRequest(url: url)
        request.setValue(HTTP.browserAgent, forHTTPHeaderField: "User-Agent")
        try await FileDownloader.shared.download(request, to: destination, progress: progress)
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
