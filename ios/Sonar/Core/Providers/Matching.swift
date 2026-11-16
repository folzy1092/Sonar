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

    /// Лучший кандидат из выдачи или nil.
    func best(_ candidates: [Track]) -> Track? {
        let wanted = Set(artists.flatMap(Self.artistNames))
        var best: (track: Track, score: Double)?
        for candidate in candidates where candidate.available {
            if durationMs > 0, candidate.durationMs > 0, abs(durationMs - candidate.durationMs) > Self.maxDurationDiffMs { continue }
            let theirs = Set((candidate.artists.map { TrackText.norm($0.name) } + Self.artistNames(candidate.artist)).filter { !$0.isEmpty })
            if theirs.isDisjoint(with: wanted) { continue }
            if Self.versions(candidate.title) != versions { continue }
            let found = TrackText.norm(TrackText.cleanTitle(candidate.title))
            let score = titles.map { TrackText.similarity(TrackText.norm($0), found) }.max() ?? 0
            if score >= Self.minTitle, best.map({ score > $0.score }) ?? true {
                best = (candidate, score)
            }
        }
        return best?.track
    }
}
