import Foundation

/// «Конвертировать на другой сервис»: для каждого трека — тот же на SoundCloud или Яндексе по строгим
/// правилам `TrackMatch` (исполнитель, название ≥ 0.9, длительность ±3 с, одинаковые «версии»). Куда
/// сохранить найденное — решает экран. Трек уже на нужном сервисе — сразу в found.
enum Converter {
    /// Сколько треков искать одновременно — не долбить сервис.
    static let parallel = 4

    /// found — пары в порядке исходного списка, missing — что не нашлось.
    static func convert(_ tracks: [Track], to service: Service, using source: MusicSource) async -> (found: [Track], missing: [Track]) {
        var results: [Track?] = []
        for start in stride(from: 0, to: tracks.count, by: parallel) {
            let chunk = Array(tracks[start ..< min(start + parallel, tracks.count)])
            results += await concurrentMap(chunk) { track in
                try await counterpart(track, on: service, using: source)
            }.map { $0 ?? nil }
        }
        var found: [Track] = []
        var missing: [Track] = []
        for (track, match) in zip(tracks, results) {
            if let match { found.append(match) } else { missing.append(track) }
        }
        return (found, missing)
    }

    /// Тот же трек на service или nil.
    static func counterpart(_ track: Track, on service: Service, using source: MusicSource) async throws -> Track? {
        if track.service == service { return track }
        let wanted = TrackMatch.from(track)
        for query in wanted.queries {
            let found = try await source.search(query, in: service, limit: 10)
            if let match = wanted.best(found, reuploads: service == .soundcloud) { return match }
        }
        return nil
    }
}
