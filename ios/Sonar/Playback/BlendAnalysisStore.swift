import AVFoundation
import Foundation

// Хранилище и расчёт анализа сведения на iPhone (docs/BLEND.md §4.1, §13) — то, что `BlendAnalyzeQueue` получает
// снаружи. Готовый анализ лежит JSON по треку в `Application Support/Sonar/blend/analysis/` (на ПК — таблица
// `blend_analysis`). Расчёт: скачанный или кэшированный файл, иначе прямой поток трека (в офлайне — нет), декод в
// моно 11025 Гц через `AVAssetReader`, дальше `BlendAnalyzer` — тот же, что в тестах с векторами ПК.
// HLS SoundCloud склеивается в файл тем же путём, что «Скачать» (`CoreDownloadFetcher`), анализируется и остаётся
// в `BlendStitchCache` — со сведением дек играет его; HLS других сервисов (VK) — нет, там обычный кроссфейд.

enum BlendAnalysisError: Error {
    case noTrack, hls, offline, tooBig, tooLong, decode
}

/// Откуда брать звук для анализа, если своего файла нет.
enum BlendAnalysisFetch: Equatable {
    /// Файл уже на телефоне.
    case local(URL)
    /// Прямая ссылка — скачать как есть.
    case direct(URL)
    /// HLS SoundCloud — склеить куски в файл (`MusicCore.downloadSource` + `CoreDownloadFetcher`).
    case stitch
    /// HLS, который склеить нечем.
    case unsupported

    static func of(_ source: StreamSource, ref: String) -> BlendAnalysisFetch {
        switch source {
        case let .file(url, _): return url.isFileURL ? .local(url) : .direct(url)
        case .hls: return ServiceRegistry.service(of: ref) == .sc ? .stitch : .unsupported
        }
    }
}

enum BlendAnalysisFiles {
    /// Больше не качаем: длинный микс или битая ссылка.
    static let maxDownloadBytes = 60 * 1024 * 1024
    /// Длиннее не анализируем: микс на час — это сотни МБ отсчётов в памяти телефона.
    static let maxDurationMs = 20 * 60 * 1000

    static func isTooLong(_ durationMs: Int) -> Bool {
        durationMs > maxDurationMs
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Sonar/blend/analysis", isDirectory: true)
    }

    /// Имя файла из ref: латиница, цифры и `-` как есть, остальное — `_<код>`, чтобы `sc:1` и `sc_1` не совпали.
    static func name(_ ref: String) -> String {
        var out = ""
        for scalar in ref.unicodeScalars {
            let c = Character(scalar)
            if scalar.isASCII, c.isLetter || c.isNumber || c == "-" {
                out.append(c)
            } else {
                out += "_\(String(scalar.value, radix: 16))"
            }
        }
        return out + ".json"
    }

    static func read(_ refs: [String], in dir: URL) -> [String: BlendAnalysis] {
        var found: [String: BlendAnalysis] = [:]
        let decoder = JSONDecoder()
        for ref in refs {
            let url = dir.appendingPathComponent(name(ref))
            guard let data = try? Data(contentsOf: url),
                  let analysis = try? decoder.decode(BlendAnalysis.self, from: data),
                  analysis.ref == ref
            else { continue }
            found[ref] = analysis
        }
        return found
    }

    @discardableResult
    static func write(_ analysis: BlendAnalysis, in dir: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(analysis)
            try data.write(to: dir.appendingPathComponent(name(analysis.ref)), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Стереть все анализы (Хранилище → «Сведение»).
    static func clear(in dir: URL = directory) {
        try? FileManager.default.removeItem(at: dir)
    }
}

enum BlendAnalysisStore {
    /// Зависимости очереди: файлы и расчёт — в фоне, ответ — на главном потоке.
    @MainActor
    static func deps(track: @escaping @MainActor (String) -> Track?) -> BlendAnalyzeDeps {
        let dir = BlendAnalysisFiles.directory
        return BlendAnalyzeDeps(
            load: { refs, done in
                Task.detached(priority: .utility) {
                    let found = BlendAnalysisFiles.read(refs, in: dir)
                    await MainActor.run { done(found) }
                }
            },
            compute: { ref, done in
                guard let item = track(ref) else {
                    done(.failure(BlendAnalysisError.noTrack))
                    return
                }
                let local = DownloadStore.shared.localURL(ref) ?? WaveCache.shared.localURL(ref)
                Task.detached(priority: .utility) {
                    let result: Result<BlendAnalysis, Error>
                    do {
                        let own = local ?? BlendStitchCache.shared.localURL(ref)
                        result = .success(try await compute(item, local: own))
                    } catch {
                        result = .failure(error)
                    }
                    await MainActor.run { done(result) }
                }
            },
            save: { analysis in
                Task.detached(priority: .utility) { BlendAnalysisFiles.write(analysis, in: dir) }
            }
        )
    }

    nonisolated static func compute(_ track: Track, local: URL?) async throws -> BlendAnalysis {
        if let local { return try await analyze(file: local, ref: track.ref) }
        if OfflineFlag.isOn { throw BlendAnalysisError.offline }
        if BlendAnalysisFiles.isTooLong(track.durationMs) { throw BlendAnalysisError.tooLong }
        let playable = try await MusicCore.shared.playable(track)
        switch BlendAnalysisFetch.of(playable.source, ref: track.ref) {
        case .local(let url):
            return try await analyze(file: url, ref: track.ref)
        case .direct(let url):
            let temp = try await download(url)
            defer { try? FileManager.default.removeItem(at: temp) }
            return try await analyze(file: temp, ref: track.ref)
        case .stitch:
            // склеенный файл не стираем: со сведением дек играет его, а не поток (`BlendStitchCache`)
            let file = try await stitched(track.ref)
            return try await analyze(file: file, ref: track.ref)
        case .unsupported:
            throw BlendAnalysisError.hls
        }
    }

    /// Анализ уже есть, а склеенного файла нет — только склеить, для игры. HLS ли трек, говорит сервис:
    /// прямой файл и так играет через `AudioTap`, склеивать нечего.
    nonisolated static func prefetchStitch(_ track: Track) async {
        guard let playable = try? await MusicCore.shared.playable(track),
              BlendAnalysisFetch.of(playable.source, ref: track.ref) == .stitch else { return }
        _ = try? await stitched(track.ref)
    }

    /// Склеить HLS SoundCloud и положить в кэш склеенных; не легло — временный файл стирается.
    nonisolated static func stitched(_ ref: String) async throws -> URL {
        let temp = try await stitch(ref)
        do {
            return try BlendStitchCache.shared.put(ref, file: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// HLS SoundCloud → временный файл: источник и склейка — те же, что у «Скачать» (там прямой mp3 и
    /// Яндекс-двойник идут первыми, HLS — последним).
    private nonisolated static func stitch(_ ref: String) async throws -> URL {
        let fetcher = CoreDownloadFetcher()
        let source = try await MusicCore.shared.downloadSource(ref)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("blend-\(UUID().uuidString).\(source.fileExtension)")
        try await fetcher.fetch(source, to: file) { _ in }
        if OfflineFlag.isOn {
            try? FileManager.default.removeItem(at: file)
            throw BlendAnalysisError.offline
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        guard size <= BlendAnalysisFiles.maxDownloadBytes else {
            try? FileManager.default.removeItem(at: file)
            throw BlendAnalysisError.tooBig
        }
        return file
    }

    private nonisolated static func download(_ url: URL) async throws -> URL {
        if OfflineFlag.isOn { throw BlendAnalysisError.offline }
        var request = URLRequest(url: url)
        if VK.isCDN(url) { request.setValue(VK.userAgent, forHTTPHeaderField: "User-Agent") }
        let session = URLSession(configuration: Net.configuration())
        defer { session.finishTasksAndInvalidate() }
        let (file, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: file)
            throw URLError(.badServerResponse)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        guard size <= BlendAnalysisFiles.maxDownloadBytes else {
            try? FileManager.default.removeItem(at: file)
            throw BlendAnalysisError.tooBig
        }
        // у временного файла загрузки нет расширения — AVAsset без него формат не угадывает
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let named = FileManager.default.temporaryDirectory.appendingPathComponent("blend-\(UUID().uuidString).\(ext)")
        try FileManager.default.moveItem(at: file, to: named)
        return named
    }

    /// Файл → моно 11025 Гц → анализ.
    nonisolated static func analyze(file: URL, ref: String) async throws -> BlendAnalysis {
        let mono = try await decodeMono(file)
        guard !mono.isEmpty else { throw BlendAnalysisError.decode }
        return BlendAnalyzer.analyze(mono, ref: ref)
    }

    private nonisolated static func decodeMono(_ file: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: file)
        guard let audio = try await asset.loadTracks(withMediaType: .audio).first else { throw BlendAnalysisError.decode }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: BlendAnalyzer.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        guard reader.canAdd(output) else { throw BlendAnalysisError.decode }
        reader.add(output)
        guard reader.startReading() else { throw BlendAnalysisError.decode }
        var left: [Float] = []
        var right: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let bytes = CMBlockBufferGetDataLength(block)
            var frame = [Float](repeating: 0, count: bytes / MemoryLayout<Float>.size)
            let status = frame.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return kCMBlockBufferBadCustomBlockSourceErr }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: raw.count, destination: base)
            }
            guard status == kCMBlockBufferNoErr else { throw BlendAnalysisError.decode }
            deinterleave(frame, left: &left, right: &right)
        }
        guard reader.status == .completed else { throw BlendAnalysisError.decode }
        return BlendAnalyzer.toMono([left, right])
    }

    /// LRLR… → два канала (хвост без пары отбрасывается).
    nonisolated static func deinterleave(_ frame: [Float], left: inout [Float], right: inout [Float]) {
        let pairs = frame.count / 2
        left.reserveCapacity(left.count + pairs)
        right.reserveCapacity(right.count + pairs)
        for i in 0..<pairs {
            left.append(frame[2 * i])
            right.append(frame[2 * i + 1])
        }
    }
}
