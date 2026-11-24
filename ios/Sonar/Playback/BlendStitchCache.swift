import Foundation

// Склеенные файлы HLS SoundCloud для сведения (docs/BLEND.md §13). AVFoundation не пускает HLS-поток через
// `AudioTap`, поэтому со сведением дек играет склеенный файл: тогда в переходе слышны фильтры, эхо и свап баса,
// а не одна громкость. Файл появляется при анализе трека (`BlendAnalysisStore` склеивает его всё равно) и
// остаётся здесь, а не стирается; повторный анализ и игра берут его отсюда.
// Лежит в Caches/Sonar/BlendStitch (в бэкап не идёт, iOS может почистить сама), вытесняется по размеру —
// давно не игравшие первыми.

/// Файл в кэше: имя без расширения — из ref, дата — когда последний раз брали.
struct BlendStitchEntry: Equatable, Sendable {
    let stem: String
    let url: URL
    let bytes: Int64
    let used: Date
}

enum BlendStitchPlan {
    /// Сколько держим склеенного: ~50 треков по 8 МБ.
    static let limitBytes: Int64 = 400 * 1024 * 1024

    /// Что удалить, чтобы влезть в предел: давно не брали — первыми; `protect` (только что положенный) не трогаем.
    static func evict(_ entries: [BlendStitchEntry], limit: Int64 = limitBytes, protect: Set<String> = []) -> [BlendStitchEntry] {
        var total = entries.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > limit else { return [] }
        var out: [BlendStitchEntry] = []
        for entry in entries.sorted(by: { $0.used < $1.used }) where !protect.contains(entry.stem) {
            guard total > limit else { break }
            out.append(entry)
            total -= entry.bytes
        }
        return out
    }

    /// Чем грузить дек вместо потока: склеенный файл — только со сведением, только SoundCloud и не на повторе
    /// со свежей ссылкой (fresh — файл не открылся, берём поток). Нет файла — nil, играет поток (только громкость).
    static func source(ref: String, blendOn: Bool, fresh: Bool, stitched: URL?) -> StreamSource? {
        guard blendOn, !fresh, ServiceRegistry.service(of: ref) == .sc, let stitched else { return nil }
        return .file(url: stitched, quality: label(stitched))
    }

    /// Плашка качества по расширению — без слов, переводить нечего.
    static func label(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a": "AAC"
        case "flac": "FLAC"
        default: "MP3"
        }
    }

    /// Склеивать ли трек заранее, если анализ уже есть, а файла нет (анализ считали до этого кэша или файл
    /// вытеснили): это лишняя загрузка, поэтому — по правилу «Только по Wi‑Fi» и не в офлайне.
    static func shouldPrefetch(ref: String, durationMs: Int, offline: Bool, mayDownload: Bool,
                               hasFile: Bool, attempted: Bool) -> Bool {
        ServiceRegistry.service(of: ref) == .sc && !offline && mayDownload && !hasFile && !attempted
            && !BlendAnalysisFiles.isTooLong(durationMs)
    }
}

/// Файлы на диске. Только `FileManager` (потокобезопасен), своего состояния нет — можно звать из любого потока.
final class BlendStitchCache: Sendable {
    static let shared = BlendStitchCache(directory: {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Sonar/BlendStitch", isDirectory: true)
    }())

    let directory: URL
    let limit: Int64

    init(directory: URL, limit: Int64 = BlendStitchPlan.limitBytes) {
        self.directory = directory
        self.limit = limit
    }

    /// Имя без расширения — то же, что у файла анализа (`sc:1` и `sc_1` не совпадут).
    static func stem(_ ref: String) -> String {
        String(BlendAnalysisFiles.name(ref).dropLast(".json".count))
    }

    /// Склеенный файл трека; touch — отметить, что взяли (для вытеснения).
    func localURL(_ ref: String, touch: Bool = false) -> URL? {
        let stem = Self.stem(ref)
        guard let found = entries().first(where: { $0.stem == stem }) else { return nil }
        if touch { mark(found.url) }
        return found.url
    }

    /// Положить склеенный файл (переносом) и вытеснить лишнее. Возвращает новое место файла.
    @discardableResult
    func put(_ ref: String, file: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = Self.stem(ref)
        for old in entries() where old.stem == stem { try? fm.removeItem(at: old.url) }
        let ext = file.pathExtension.isEmpty ? "mp3" : file.pathExtension
        let target = directory.appendingPathComponent("\(stem).\(ext)")
        try fm.moveItem(at: file, to: target)
        mark(target)
        for entry in BlendStitchPlan.evict(entries(), limit: limit, protect: [stem]) {
            try? fm.removeItem(at: entry.url)
        }
        return target
    }

    func remove(_ ref: String) {
        let stem = Self.stem(ref)
        for entry in entries() where entry.stem == stem { try? FileManager.default.removeItem(at: entry.url) }
    }

    var totalBytes: Int64 {
        entries().reduce(0) { $0 + $1.bytes }
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    func entries() -> [BlendStitchEntry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else {
            return []
        }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return BlendStitchEntry(stem: url.deletingPathExtension().lastPathComponent, url: url,
                                    bytes: Int64(values.fileSize ?? 0), used: values.contentModificationDate ?? .distantPast)
        }
    }

    private func mark(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }
}
