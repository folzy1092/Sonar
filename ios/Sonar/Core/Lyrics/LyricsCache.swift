import Foundation

/// Кэш текстов на телефоне (docs/LYRICS.md §7, как `lyrics_cache` в Windows): файл JSON на трек в
/// Caches/Sonar/Lyrics. Хранится **неделю** с последнего показа, у треков из Любимых — **две**; показ
/// продлевает срок (`usedAt`), старое удаляется при запуске (`prune`). «Не найдено» тоже кэшируется и
/// перепроверяется через 30 мин (`recheck`). iOS может сама почистить Caches — тогда текст просто найдётся заново.
struct LyricsCache: Sendable {
    /// «Текста нет» перепроверяется не чаще раза в 30 мин (как в Windows и selfbot).
    static let recheck: TimeInterval = 30 * 60
    static let keep: TimeInterval = 7 * 86_400
    static let keepLiked: TimeInterval = 14 * 86_400

    struct Entry: Codable, Equatable, Sendable {
        var ref: String
        /// nil — «не найдено».
        var lyrics: Lyrics?
        var fetchedAt: Date
        var usedAt: Date
    }

    let directory: URL

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = directory ?? base.appendingPathComponent("Sonar/Lyrics", isDirectory: true)
    }

    /// Имя файла по ref: только буквы и цифры как есть, остальное — %XX (`sc:123` → `sc%3A123.json`).
    func file(for ref: String) -> URL {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let name = ref.addingPercentEncoding(withAllowedCharacters: allowed) ?? ref
        return directory.appendingPathComponent("\(name).json")
    }

    private func read(_ url: URL) -> Entry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(Entry.self, from: data)
    }

    private func write(_ entry: Entry) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(entry) { try? data.write(to: file(for: entry.ref), options: .atomic) }
    }

    /// Запись из кэша; попадание продлевает срок хранения.
    func get(_ ref: String, now: Date = Date()) -> Entry? {
        guard var entry = read(file(for: ref)), entry.ref == ref else { return nil }
        entry.usedAt = now
        write(entry)
        return entry
    }

    /// Что показать из кэша: `.some(lyrics)` — текст, `.some(nil)` — «не найдено» ещё свежее,
    /// `nil` — идти в сеть (нет записи или «не найдено» устарело).
    func lookup(_ ref: String, now: Date = Date()) -> Lyrics?? {
        guard let entry = get(ref, now: now) else { return nil }
        if let lyrics = entry.lyrics { return .some(lyrics) }
        return now.timeIntervalSince(entry.fetchedAt) < Self.recheck ? .some(nil) : nil
    }

    func put(_ ref: String, _ lyrics: Lyrics?, now: Date = Date()) {
        write(Entry(ref: ref, lyrics: lyrics, fetchedAt: now, usedAt: now))
    }

    func remove(_ ref: String) {
        try? FileManager.default.removeItem(at: file(for: ref))
    }

    /// Удалить старое: дольше двух недель без показа — всегда, дольше недели — если трек не в Любимых.
    /// Возвращает, сколько удалено.
    @discardableResult
    func prune(now: Date = Date(), isLiked: (String) -> Bool) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return 0 }
        var removed = 0
        for url in files where url.pathExtension == "json" {
            guard let entry = read(url) else {
                try? FileManager.default.removeItem(at: url) // битый файл
                removed += 1
                continue
            }
            let idle = now.timeIntervalSince(entry.usedAt)
            if idle > Self.keepLiked || (idle > Self.keep && !isLiked(entry.ref)) {
                try? FileManager.default.removeItem(at: url)
                removed += 1
            }
        }
        return removed
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}
