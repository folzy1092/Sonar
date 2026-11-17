import Foundation

/// Тот же трек на другом сервисе: трек SoundCloud → Яндекс Музыка, чтобы играть его в FLAC / 320 (без Go+
/// SoundCloud отдаёт максимум AAC 160). Правила строгие — лучше сыграть SoundCloud, чем чужую версию:
/// длительность ±3 с, исполнитель совпадает, название почти одинаковое (≥ 0.9), а «версии» (remix, live,
/// sped up, slowed…) совпадают с обеих сторон. Порт `providers/matching.rs`.
struct TrackMatch: Sendable {
    static let maxDurationDiffMs = 3000
    static let minTitle = 0.9

    /// Исполнители-кандидаты: из «АРТИСТ - ТРЕК», из метаданных, залившего, фиты.
    var artists: [String]
    var titles: [String]
    var durationMs: Int
    /// Слова «версий» исходного названия — у найденного должны быть те же.
    let versions: Set<String>

    static let versionWords: Set<String> = [
        "remix", "rmx", "live", "acoustic", "sped", "speed", "slowed", "reverb", "nightcore", "instrumental", "karaoke",
        "cover", "edit", "mix", "version", "demo", "ремикс", "акустика",
    ]
    static let word = Pattern(#"[\p{L}\p{N}]+"#)
    static let artistSplit = Pattern(#"(?i)\s*,\s*|\s+(?:&|feat\.?|ft\.?|x|\+|×|и|and|with|w/)\s+"#)

    static func versions(_ s: String) -> Set<String> {
        Set(word.findAll(s.lowercased())).intersection(versionWords)
    }

    static func artistNames(_ s: String) -> [String] {
        artistSplit.split(s).map(TrackText.norm).filter { !$0.isEmpty }
    }

    /// uploader — ник залившего на SoundCloud, metaArtist — `publisher_metadata.artist`.
    static func soundCloud(uploader: String, metaArtist: String?, title: String, durationMs: Int) -> TrackMatch {
        var artists: [String] = []
        var titles: [String] = []
        if let reupload = TrackText.reuploadVariant(title) {
            artists.append(reupload.artist)
            titles.append(TrackText.cleanTitle(reupload.title))
        }
        for artist in [metaArtist ?? "", uploader] where !artist.trimmingCharacters(in: .whitespaces).isEmpty {
            artists.append(artist)
        }
        let keyword = TrackText.keywordTitle(title)
        for candidate in [TrackText.cleanTitle(title), keyword.core] where !candidate.isEmpty && !titles.contains(candidate) {
            titles.append(candidate)
        }
        artists.append(contentsOf: keyword.feats)
        return TrackMatch(artists: artists, titles: titles, durationMs: durationMs, versions: versions(title))
    }

    /// Запросы к поиску Яндекса по порядку.
    var queries: [String] {
        var out: [String] = []
        for artist in artists.prefix(2) {
            if let title = titles.first {
                let query = "\(TrackText.firstArtist(artist)) \(title)"
                if !out.contains(query) { out.append(query) }
            }
        }
        return out
    }

    /// Трек Sonar → что искать на другом сервисе: SoundCloud — как `soundCloud(…)` (залил — исполнитель,
    /// «АРТИСТ - ТРЕК» в названии), Яндекс — его артисты и название.
    static func from(_ track: Track) -> TrackMatch {
        if track.service == .soundcloud {
            return soundCloud(uploader: track.artist, metaArtist: nil, title: track.title, durationMs: track.durationMs)
        }
        var artists = track.artists.map(\.name).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if artists.isEmpty { artists = [track.artist] }
        var titles: [String] = []
        let keyword = TrackText.keywordTitle(track.title)
        for candidate in [TrackText.cleanTitle(track.title), keyword.core] where !candidate.isEmpty && !titles.contains(candidate) {
            titles.append(candidate)
        }
        return TrackMatch(artists: artists, titles: titles, durationMs: track.durationMs, versions: versions(track.title))
    }

    /// Лучший кандидат из выдачи или nil.
    func best(_ candidates: [Track]) -> Track? {
        best(candidates, reuploads: false)
    }

    /// reuploads — кандидаты с SoundCloud: у них настоящий артист часто в названии «АРТИСТ - ТРЕК».
    func best(_ candidates: [Track], reuploads: Bool) -> Track? {
        let wanted = Set(artists.flatMap(Self.artistNames))
        var best: (track: Track, score: Double)?
        for candidate in candidates where candidate.available {
            if durationMs > 0, candidate.durationMs > 0, abs(durationMs - candidate.durationMs) > Self.maxDurationDiffMs { continue }
            var names = candidate.artists.map { TrackText.norm($0.name) } + Self.artistNames(candidate.artist)
            var foundTitles = [TrackText.norm(TrackText.cleanTitle(candidate.title))]
            if reuploads, let reupload = TrackText.reuploadVariant(candidate.title) {
                names += Self.artistNames(reupload.artist)
                foundTitles.append(TrackText.norm(TrackText.cleanTitle(reupload.title)))
            }
            let theirs = Set(names.filter { !$0.isEmpty })
            if theirs.isDisjoint(with: wanted) { continue }
            if Self.versions(candidate.title) != versions { continue }
            let score = titles.flatMap { title in foundTitles.map { TrackText.similarity(TrackText.norm(title), $0) } }.max() ?? 0
            if score >= Self.minTitle, best.map({ score > $0.score }) ?? true {
                best = (candidate, score)
            }
        }
        return best?.track
    }
}
