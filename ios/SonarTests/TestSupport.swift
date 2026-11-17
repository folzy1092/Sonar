import Foundation
@testable import Sonar

/// Трек для тестов: ref `sc:…` / `ym:…`, один артист.
func makeTrack(_ ref: String, _ artist: String, title: String? = nil, durationMs: Int = 200_000, plays: Int? = nil,
               artistRef: String? = nil, available: Bool = true) -> Track {
    let prefix = ref.hasPrefix("ym") ? "yma" : "sca"
    return Track(ref: ref, title: title ?? "Song \(ref)", artist: artist,
                 artists: [ArtistRef(ref: artistRef ?? "\(prefix):\(artist.lowercased())", name: artist, avatarURL: nil)],
                 album: nil, durationMs: durationMs, coverURL: nil, url: nil, explicit: false, available: available,
                 plays: plays, tags: nil)
}

func makeAlbum(_ ref: String, _ artist: String, released: String? = nil, year: Int? = nil, title: String? = nil) -> Album {
    Album(ref: ref, title: title ?? "Album \(ref)", artist: artist, artists: [], coverURL: nil, year: year,
          released: released, trackCount: 1, url: nil)
}

/// Временная папка теста.
func tempDirectory() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sonar-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Сервисы без сети: ответы задаются заранее, вызовы считаются.
final class FakeSource: MusicSource, @unchecked Sendable {
    private let lock = NSLock()
    var similarByRef: [String: [Track]] = [:]
    var topByArtist: [String: [Track]] = [:]
    var albumsByArtist: [String: [Album]] = [:]
    var releases: [Album] = []
    /// (сервис, запрос) → выдача.
    var searchResults: [String: [Track]] = [:]
    var failAll = false
    private var counts: [String: Int] = [:]

    func calls(_ name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[name] ?? 0
    }

    private func hit(_ name: String) throws {
        lock.lock()
        counts[name, default: 0] += 1
        lock.unlock()
        if failAll { throw ServiceError(message: "нет сети") }
    }

    func similar(to ref: String, limit: Int) async throws -> [Track] {
        try hit("similar")
        return Array((similarByRef[ref] ?? []).prefix(limit))
    }

    func artistTop(_ ref: String, limit: Int) async throws -> [Track] {
        try hit("artistTop")
        return Array((topByArtist[ref] ?? []).prefix(limit))
    }

    func artistAlbums(_ ref: String) async throws -> [Album] {
        try hit("artistAlbums")
        return albumsByArtist[ref] ?? []
    }

    func newReleases(limit: Int) async throws -> [Album] {
        try hit("newReleases")
        return Array(releases.prefix(limit))
    }

    func search(_ query: String, in service: Service, limit: Int) async throws -> [Track] {
        try hit("search")
        return Array((searchResults["\(service.rawValue)|\(query)"] ?? []).prefix(limit))
    }
}
