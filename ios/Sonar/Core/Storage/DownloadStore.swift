import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking // тесты логики на Linux
#endif

/// Откуда качать трек целиком: прямой файл (mp3 / FLAC) или плейлист HLS SoundCloud, который склеивается в файл.
struct DownloadSource: Sendable, Equatable {
    var url: URL
    /// `mp3` / `flac` / `m4a` (AAC YouTube Music).
    var fileExtension: String
    /// Что скачано — для плашки качества: «MP3 320», «FLAC · Яндекс».
    var quality: String
    /// `url` — плейлист HLS: куски склеиваются в один файл (`HLSPlaylist`).
    var isHLS = false

    /// Ссылка на поток → источник для скачивания; HLS скачать файлом нельзя — nil.
    static func from(_ stream: StreamSource) -> DownloadSource? {
        guard case let .file(url, quality) = stream else { return nil }
        return DownloadSource(url: url, fileExtension: fileExtension(quality), quality: quality)
    }

    /// По плашке качества: «FLAC …» — flac, «AAC …» — m4a, остальное — mp3.
    static func fileExtension(_ quality: String) -> String {
        let quality = quality.uppercased()
        if quality.hasPrefix("FLAC") { return "flac" }
        if quality.hasPrefix("AAC") { return "m4a" }
        return "mp3"
    }
}

/// Где взять ссылку и как скачать файл. В приложении — `MusicCore` + `FileDownloader`
/// (`MusicCore+Shared.swift`), в тестах — заглушка.
protocol DownloadFetcher: Sendable {
    func source(for track: Track) async throws -> DownloadSource
    /// Скачать url в destination; progress — 0…1 (может звать с любого потока).
    func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws
    /// Скачать источник целиком (HLS — склейкой). По умолчанию — как обычный файл.
    func fetch(_ source: DownloadSource, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

extension DownloadFetcher {
    func fetch(_ source: DownloadSource, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await fetch(source.url, to: destination, progress: progress)
    }
}

/// «Скачанные»: трек целиком в файл на телефоне — играет без сети (`PlaybackEngine` берёт файл, если он
/// есть). Файлы — Application Support/Sonar/Downloads (не в бэкап iCloud), список — `downloads.json`
/// там же, новые сверху; обложка — рядом в `covers/` (одна на альбом). SoundCloud: Яндекс-двойник, прямой
/// mp3 или склейка HLS; шифрованный поток — честно «Этот трек нельзя скачать».
///
/// Очередь (`docs/OFFLINE.md` §8.3): по `DownloadPlan.parallel` за раз; `mayStart` — пускает ли сеть (только
/// Wi‑Fi), офлайн-режим держит очередь. Оборвалось из-за сети или офлайна — трек ждёт в начале очереди
/// (`resume()`), а не падает с ошибкой.
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
        /// Обложка в `covers/` (nil — не скачалась или у трека её нет).
        var cover: String?
    }

    @ObservationIgnored private var entries: [String: Entry] = [:]
    @ObservationIgnored let directory: URL
    @ObservationIgnored private let fetcher: DownloadFetcher
    /// Удалили, пока качался, — файл не сохранять.
    @ObservationIgnored private var cancelled: Set<String> = []
    /// Ждут своей очереди (уже в `progress` с 0).
    @ObservationIgnored private var pending: [Track] = []
    /// Качаются сейчас.
    @ObservationIgnored private var active: Set<String> = []
    /// Можно ли сейчас начинать (сеть подходит).
    @ObservationIgnored private let mayStart: @MainActor () -> Bool
    /// Имена файлов обложек, что лежат в `covers/`.
    @ObservationIgnored private var coverFiles: Set<String> = []
    /// Трек сохранён / удалён — текст песни рядом (`LyricsStore.pin`). У кэша волны — нет.
    @ObservationIgnored var onSaved: (@MainActor (Track) -> Void)?
    @ObservationIgnored var onRemoved: (@MainActor (String) -> Void)?

    private var index: URL { directory.appendingPathComponent("downloads.json") }
    private var coversDirectory: URL { directory.appendingPathComponent("covers", isDirectory: true) }

    init(fetcher: DownloadFetcher, directory: URL? = nil, mayStart: @escaping @MainActor () -> Bool = { true }) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fetcher = fetcher
        self.mayStart = mayStart
        self.directory = directory ?? base.appendingPathComponent("Sonar/Downloads", isDirectory: true)
        if let data = try? Data(contentsOf: index), let list = try? JSONDecoder().decode([Entry].self, from: data) {
            // файл пропал (чистка, восстановление из бэкапа без загрузок) — трек больше не скачан
            let present = list.filter { FileManager.default.fileExists(atPath: self.directory.appendingPathComponent($0.file).path) }
            downloaded = present.map(\.track)
            entries = Dictionary(present.map { ($0.track.ref, $0) }, uniquingKeysWith: { first, _ in first })
            coverFiles = Set(present.compactMap(\.cover).filter {
                FileManager.default.fileExists(atPath: self.coversDirectory.appendingPathComponent($0).path)
            })
        }
    }

    /// Обложка скачанного трека на диске — для офлайна (`CoverImage`). Ключ — адрес без размера (`Covers.key`).
    func localCover(_ url: String) -> URL? {
        let name = Self.coverName(url)
        return coverFiles.contains(name) ? coversDirectory.appendingPathComponent(name) : nil
    }

    /// Ждёт очереди или качается.
    func isQueued(_ ref: String) -> Bool {
        progress[ref] != nil
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

    /// Скачать трек (в очередь). Уже скачан или в очереди — ничего.
    func download(_ track: Track) {
        let ref = track.ref
        guard entries[ref] == nil, progress[ref] == nil else { return }
        guard !OfflineFlag.isOn else {
            message = t("Нет доступа к сети: включён офлайн-режим")
            return
        }
        progress[ref] = 0
        // отменили и тут же передумали, а прежняя загрузка ещё идёт — пусть она и докачает
        if cancelled.remove(ref) != nil, active.contains(ref) { return }
        pending.append(track)
        pump()
    }

    /// Сеть вернулась / офлайн выключили / сняли «только Wi‑Fi» — продолжить очередь.
    func resume() {
        pump()
    }

    private func pump() {
        while active.count < DownloadPlan.parallel, !pending.isEmpty, !OfflineFlag.isOn, mayStart() {
            let track = pending.removeFirst()
            active.insert(track.ref)
            Task {
                await run(track)
                active.remove(track.ref)
                pump()
            }
        }
    }

    private func run(_ track: Track) async {
        let ref = track.ref
        do {
            // ссылку — прямо перед загрузкой: подписанные ссылки Яндекса протухают
            let source = try await fetcher.source(for: track)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let part = directory.appendingPathComponent(Self.fileName(ref: ref, ext: "part"))
            try? FileManager.default.removeItem(at: part)
            try await fetcher.fetch(source, to: part) { [weak self] value in
                Task { @MainActor in
                    guard let self, self.active.contains(ref), self.progress[ref] != nil else { return }
                    self.progress[ref] = min(1, max(0, value))
                }
            }
            if cancelled.contains(ref) {
                try? FileManager.default.removeItem(at: part)
                cancelled.remove(ref)
                progress[ref] = nil
                return
            }
            try save(track, part: part, source: source)
            progress[ref] = nil
            if let cover = await fetchCover(track) {
                if entries[ref] != nil {
                    entries[ref]?.cover = cover
                    coverFiles.insert(cover)
                    save()
                } else if !entries.values.contains(where: { $0.cover == cover }) {
                    // удалили, пока качалась обложка
                    try? FileManager.default.removeItem(at: coversDirectory.appendingPathComponent(cover))
                }
            }
            onSaved?(track)
        } catch {
            if cancelled.remove(ref) != nil {
                progress[ref] = nil
            } else if OfflineFlag.isOn || !mayStart() {
                // оборвал офлайн или ушли с Wi‑Fi — ждать в начале очереди, без ошибки
                progress[ref] = 0
                pending.insert(track, at: 0)
            } else {
                progress[ref] = nil
                message = "Не скачался «\(track.title)»: \(error.localizedDescription)"
            }
        }
    }

    /// `.part` → файл с расширением по содержимому, запись в список.
    private func save(_ track: Track, part: URL, source: DownloadSource) throws {
        let ref = track.ref
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
    }

    /// Обложка рядом с треком (одна на альбом): уже есть — та же; не скачалась — трек всё равно скачан.
    private func fetchCover(_ track: Track) async -> String? {
        guard let raw = track.coverURL, let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else { return nil }
        let name = Self.coverName(raw)
        if coverFiles.contains(name) { return name }
        let target = coversDirectory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
            try await fetcher.fetch(url, to: target) { _ in }
            Self.excludeFromBackup(target)
            return name
        } catch {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
    }

    /// Имя файла обложки: FNV-1a от адреса без размера — у треков одного альбома совпадает.
    static func coverName(_ url: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Covers.key(url).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16) + ".jpg"
    }

    /// Удалить скачанный (или прервать загрузку).
    func remove(_ ref: String) {
        if progress[ref] != nil {
            if active.contains(ref) { cancelled.insert(ref) }
            pending.removeAll { $0.ref == ref }
            progress[ref] = nil
        }
        guard let entry = entries.removeValue(forKey: ref) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.file))
        // обложку — только если она больше ни у кого из скачанных
        if let cover = entry.cover, !entries.values.contains(where: { $0.cover == cover }) {
            try? FileManager.default.removeItem(at: coversDirectory.appendingPathComponent(cover))
            coverFiles.remove(cover)
        }
        downloaded.removeAll { $0.ref == ref }
        save()
        onRemoved?(ref)
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
/// `shared` — фоновая сессия: загрузка не рвётся, когда Sonar свёрнут (но после выгрузки приложения — заново).
/// `segments` — обычная, для кусков HLS и диапазонов GVideo (мелкие, фон им не нужен).
/// Фоновая сессия не видит `OfflineGuard` (`protocolClasses` ей не передаются) — офлайн проверяем сами.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = FileDownloader(background: "com.folzy.sonar.downloads")
    static let segments = FileDownloader(background: nil)

    private struct Job {
        let destination: URL
        let progress: @Sendable (Double) -> Void
        let continuation: CheckedContinuation<Void, Error>
        var failure: Error?
    }

    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]
    /// Задаётся один раз в `init` (делегат — сам объект, до `super.init` его не передать).
    private var session: URLSession!

    private init(background identifier: String?) {
        super.init()
        var base = URLSessionConfiguration.default
        if let identifier {
            base = .background(withIdentifier: identifier)
            base.sessionSendsLaunchEvents = false
            base.isDiscretionary = false
        }
        session = URLSession(configuration: Net.configuration(base), delegate: self, delegateQueue: nil)
        // Фоновая сессия после перезапуска отдаёт и задачи прошлого запуска — ждать их некому, отменяем.
        // Свои отличаем по `jobs`: задача и запись о ней появляются под одним замком.
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            self.lock.lock()
            let orphans = tasks.filter { self.jobs[$0.taskIdentifier] == nil }
            self.lock.unlock()
            orphans.forEach { $0.cancel() }
        }
    }

    func download(_ request: URLRequest, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        if OfflineFlag.isOn {
            OfflineFlag.noteBlocked()
            throw URLError(.notConnectedToInternet)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            let task = session.downloadTask(with: request)
            jobs[task.taskIdentifier] = Job(destination: destination, progress: progress, continuation: continuation)
            lock.unlock()
            task.resume()
        }
    }

    /// Оборвать всё, что качается.
    func cancelAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    /// Офлайн включили — обе сессии (`OfflineMode`).
    static func stopAll() {
        shared.cancelAll()
        segments.cancelAll()
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
