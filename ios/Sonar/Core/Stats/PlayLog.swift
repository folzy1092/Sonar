import Foundation
import Observation

/// Одно засчитанное прослушивание — как строка `plays` в docs/DB.md (ref, артист, когда, сколько слушал).
struct PlayRow: Codable, Equatable, Sendable {
    var ref: String
    /// Главный артист (как показан), группировка — без учёта регистра.
    var artist: String
    var at: Date
    /// Реально прослушано, мс (перемотка не считается). Сначала — порог засчитывания, при смене трека —
    /// итог (`PlayLog.ended`).
    var ms: Int

    enum CodingKeys: String, CodingKey {
        case ref = "r", artist = "a", at = "t", ms = "m"
    }
}

/// Журнал прослушиваний для «Статистики» (аналог `plays` в Windows-клиенте, до SQLite и сервера —
/// JSON в Application Support/Sonar/plays.json). Строки — компактно, треки — отдельно по ref (обложка,
/// название, артисты с аватарами), чтобы топ можно было показать и включить. Пишет `PlayHistory`:
/// `record` → `started`, `ended` → `ended`.
@MainActor
@Observable
final class PlayLog {
    static let shared = PlayLog()

    /// Строк не больше — старые уходят (≈ 3–4 МБ JSON).
    static let rowLimit = 50_000

    private(set) var rows: [PlayRow] = []
    @ObservationIgnored private(set) var tracks: [String: Track] = [:]
    /// Меняется на каждую запись — экран статистики пересчитывает.
    private(set) var revision = 0

    private struct Snapshot: Codable {
        var rows: [PlayRow]
        var tracks: [String: Track]
    }

    @ObservationIgnored private let file: URL
    @ObservationIgnored private(set) var existed: Bool

    init(file: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.file = file ?? base.appendingPathComponent("Sonar/plays.json")
        existed = FileManager.default.fileExists(atPath: self.file.path)
        if let data = try? Data(contentsOf: self.file), let snapshot = try? Self.decoder.decode(Snapshot.self, from: data) {
            rows = snapshot.rows
            tracks = snapshot.tracks
        }
    }

    /// Прослушивание засчитано (порог min(30 с, половины трека)).
    func started(_ track: Track, at date: Date, listenedMs: Int) {
        rows.append(PlayRow(ref: track.ref, artist: Self.mainArtist(track), at: date, ms: max(0, listenedMs)))
        tracks[track.ref] = track
        if rows.count > Self.rowLimit { trim() }
        changed()
    }

    /// Трек сменился: итоговое время у последней записи этого трека (если она засчитана недавно).
    func ended(_ track: Track, listenedMs: Int, now: Date) {
        guard let i = rows.lastIndex(where: { $0.ref == track.ref }),
              now.timeIntervalSince(rows[i].at) < 6 * 3600, listenedMs > rows[i].ms else { return }
        rows[i].ms = listenedMs
        changed()
    }

    /// Перенос старой истории (`PlayHistory`: сигналы `play` / `finish` и «Недавнее») — один раз, когда
    /// журнала ещё нет. Время прослушивания — оценка: дослушанный — длительность, иначе порог.
    func backfill(signals: [PlaySignal], recent: [Track]) {
        guard !existed, rows.isEmpty else { return }
        existed = true
        let known = Dictionary(recent.map { ($0.ref, $0) }, uniquingKeysWith: { first, _ in first })
        let finished = Set(signals.filter { $0.kind == .finish }.map { "\($0.ref)@\(Int($0.at.timeIntervalSince1970 / 3600))" })
        for signal in signals where signal.kind == .play {
            let track = known[signal.ref]
            let duration = track?.durationMs ?? 0
            let hour = Int(signal.at.timeIntervalSince1970 / 3600)
            let done = finished.contains("\(signal.ref)@\(hour)") || finished.contains("\(signal.ref)@\(hour + 1)")
            let ms = duration > 0 ? (done ? duration : min(30_000, duration / 2)) : 30_000
            let artist = track.map(Self.mainArtist) ?? signal.artists.first ?? ""
            rows.append(PlayRow(ref: signal.ref, artist: artist, at: signal.at, ms: ms))
            if let track { tracks[track.ref] = track }
        }
        rows.sort { $0.at < $1.at }
        changed()
    }

    func clear() {
        rows = []
        tracks = [:]
        changed()
    }

    /// Размер файла журнала — для «Хранилища».
    var fileBytes: Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func mainArtist(_ track: Track) -> String {
        let name = track.artists.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? track.artist : name
    }

    private func trim() {
        rows.removeFirst(rows.count - Self.rowLimit)
        let alive = Set(rows.map(\.ref))
        tracks = tracks.filter { alive.contains($0.key) }
    }

    private func changed() {
        revision &+= 1
        save()
    }

    private func save() {
        guard let data = try? Self.encoder.encode(Snapshot(rows: rows, tracks: tracks)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        existed = true
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()
}
