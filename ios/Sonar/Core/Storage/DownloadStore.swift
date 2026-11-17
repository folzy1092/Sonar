import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking // тесты логики на Linux
#endif

/// Откуда качать трек целиком: прямой файл (mp3 / FLAC), не HLS.
struct DownloadSource: Sendable, Equatable {
    var url: URL
    /// `mp3` / `flac`.
    var fileExtension: String
    /// Что скачано — для плашки качества: «MP3 320», «FLAC · Яндекс».
    var quality: String

    /// Ссылка на поток → источник для скачивания; HLS скачать файлом нельзя — nil.
    static func from(_ stream: StreamSource) -> DownloadSource? {
        guard case let .file(url, quality) = stream else { return nil }
        return DownloadSource(url: url, fileExtension: quality.uppercased().hasPrefix("FLAC") ? "flac" : "mp3", quality: quality)
    }
}

/// Где взять ссылку и как скачать файл. В приложении — `MusicCore` + `FileDownloader`
/// (`MusicCore+Shared.swift`), в тестах — заглушка.
protocol DownloadFetcher: Sendable {
    func source(for track: Track) async throws -> DownloadSource
    /// Скачать url в destination; progress — 0…1 (может звать с любого потока).
    func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

/// «Скачанные»: трек целиком в файл на телефоне — играет без сети (`PlaybackEngine` берёт файл, если он
/// есть). Файлы — Application Support/Sonar/Downloads (не в бэкап iCloud), список — `downloads.json`
/// там же, новые сверху. SoundCloud отдаёт в основном HLS — тогда качаем Яндекс-двойника или прямой
/// mp3 SoundCloud, а если нет ни того, ни другого — честно «Этот трек нельзя скачать».
@MainActor
@Observable
final class DownloadStore {
    private(set) var downloaded: [Track] = []
    /// ref → 0…1, пока качается.
    private(set) var progress: [String: Double] = [:]
    /// Последняя ошибка — для тоста.
    var message: String?

    struct Entry: Codable, Equatable, Sendable {
        var track: Track
        /// Имя файла в папке загрузок.
        var file: String
        var quality: String
        var bytes: Int64
    }

    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored let directory: URL
    @ObservationIgnored private let fetcher: DownloadFetcher
    /// Удалили, пока качался, — файл не сохранять.
    @ObservationIgnored private var cancelled: Set<String> = []

    private var index: URL { directory.appendingPathComponent("downloads.json") }

    init(fetcher: DownloadFetcher, directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fetcher = fetcher
        self.directory = directory ?? base.appendingPathComponent("Sonar/Downloads", isDirectory: true)
        if let data = try? Data(contentsOf: index), let list = try? JSONDecoder().decode([Entry].self, from: data) {
            // файл пропал (чистка, восстановление из бэкапа без загрузок) — трек больше не скачан
            let present = list.filter { FileManager.default.fileExists(atPath: self.directory.appendingPathComponent($0.file).path) }
            downloaded = present.map(\.track)
            entries = Dictionary(present.map { ($0.track.ref, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    func isDownloaded(_ ref: String) -> Bool {
        entries[ref] != nil
    }

    /// Файл скачанного трека, если он на месте.
    func localURL(_ ref: String) -> URL? {
        guard let entry = entries[ref] else { return nil }
        let url = directory.appendingPathComponent(entry.file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Качество скачанного — для плашки в плеере.
    func quality(_ ref: String) -> String? {
        entries[ref]?.quality
    }

    /// Сколько места занимают загрузки (для Хранилища).
    var totalBytes: Int64 {
        entries.values.reduce(0) { $0 + $1.bytes }
    }

    /// Скачать трек (фоном). Уже скачан или качается — ничего.
    func download(_ track: Track) {
        let ref = track.ref
        guard entries[ref] == nil, progress[ref] == nil else { return }
        progress[ref] = 0
        cancelled.remove(ref)
        Task {
            do {
                let source = try await fetcher.source(for: track)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let part = directory.appendingPathComponent(Self.fileName(ref: ref, ext: "part"))
                try? FileManager.default.removeItem(at: part)
                try await fetcher.fetch(source.url, to: part) { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.progress[ref] != nil else { return }
                        self.progress[ref] = min(1, max(0, value))
                    }
                }
                if cancelled.contains(ref) {
                    try? FileManager.default.removeItem(at: part)
                    cancelled.remove(ref)
                    progress[ref] = nil
                    return
                }
                // расширение — по содержимому: FLAC Яндекса бывает и в MP4-контейнере, а AVPlayer
                // узнаёт формат локального файла по расширению
                let head = (try? FileHandle(forReadingFrom: part)).map { handle in
                    defer { try? handle.close() }
                    return handle.readData(ofLength: 12)
                } ?? Data()
                let name = Self.fileName(ref: ref, ext: Self.sniffExtension(head) ?? source.fileExtension)
                let target = directory.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: part, to: target)
                Self.excludeFromBackup(target)
                let bytes = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
                entries[ref] = Entry(track: track, file: name, quality: source.quality, bytes: bytes)
                downloaded.removeAll { $0.ref == ref }
                downloaded.insert(track, at: 0)
                save()
            } catch {
                if !cancelled.contains(ref) {
                    message = "Не скачался «\(track.title)»: \(error.localizedDescription)"
                }
                cancelled.remove(ref)
            }
            progress[ref] = nil
        }
    }

    /// Удалить скачанный (или прервать загрузку).
    func remove(_ ref: String) {
        if progress[ref] != nil {
            cancelled.insert(ref)
            progress[ref] = nil
        }
        guard let entry = entries.removeValue(forKey: ref) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.file))
        downloaded.removeAll { $0.ref == ref }
        save()
    }

    /// Удалить все загрузки (Хранилище).
    func removeAll() {
        for ref in Array(entries.keys) + Array(progress.keys) { remove(ref) }
    }

    /// `sc:123` → `sc_123.mp3`: только буквы, цифры, «-» и «_».
    static func fileName(ref: String, ext: String) -> String {
        let safe = String(ref.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_") ? Character(scalar) : "_"
        })
        return "\(safe).\(ext)"
    }

    /// Формат по первым байтам: `fLaC` — flac, `ftyp` на 4-м байте — m4a (MP4), `ID3` / кадр MPEG — mp3.
    /// Не узнали (или пришла страница ошибки) — nil.
    static func sniffExtension(_ head: Data) -> String? {
        let bytes = [UInt8](head.prefix(12))
        if bytes.starts(with: Array("fLaC".utf8)) { return "flac" }
        if bytes.count >= 8, Array(bytes[4 ..< 8]) == Array("ftyp".utf8) { return "m4a" }
        if bytes.starts(with: Array("ID3".utf8)) { return "mp3" }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] & 0xE0 == 0xE0 { return "mp3" }
        return nil
    }

    private static func excludeFromBackup(_ url: URL) {
        #if os(iOS)
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        #endif
    }

    private func save() {
        let list = downloaded.compactMap { entries[$0.ref] }
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: index, options: .atomic)
    }
}

/// Скачивание файла с прогрессом: свой `URLSession` с делегатом (у async `download(for:)` прогресса нет).
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = FileDownloader()

    private struct Job {
        let destination: URL
        let progress: @Sendable (Double) -> Void
        let continuation: CheckedContinuation<Void, Error>
        var failure: Error?
    }

    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    func download(_ request: URLRequest, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = session.downloadTask(with: request)
            lock.lock()
            jobs[task.taskIdentifier] = Job(destination: destination, progress: progress, continuation: continuation)
            lock.unlock()
            task.resume()
        }
    }

    private func job(_ id: Int) -> Job? {
        lock.lock()
        defer { lock.unlock() }
        return jobs[id]
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let job = job(downloadTask.taskIdentifier) else { return }
        job.progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let job = job(downloadTask.taskIdentifier) else { return }
        // файл во временной папке живёт только до выхода из этого метода — переносим сразу
        var failure: Error?
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        if !(200 ..< 300).contains(status) {
            failure = ServiceError(message: "сервер ответил ошибкой (HTTP \(status))")
        } else {
            do {
                try? FileManager.default.removeItem(at: job.destination)
                try FileManager.default.moveItem(at: location, to: job.destination)
            } catch {
                failure = error
            }
        }
        lock.lock()
        jobs[downloadTask.taskIdentifier]?.failure = failure
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let job = jobs.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let job else { return }
        if let failure = error ?? job.failure {
            job.continuation.resume(throwing: failure)
        } else {
            job.continuation.resume()
        }
    }
}
