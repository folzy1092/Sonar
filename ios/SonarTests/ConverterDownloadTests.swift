import XCTest
@testable import Sonar

/// «Конвертировать на другой сервис» и «Скачанные».
@MainActor
final class ConverterDownloadTests: XCTestCase {
    // MARK: - Конвертер

    func testSoundCloudToYandex() async {
        let source = FakeSource()
        let sc = makeTrack("sc:1", "Kizaru", title: "Narcos (prod. someone)", durationMs: 180_000)
        let match = makeTrack("ym:9", "Kizaru", title: "Narcos", durationMs: 181_000)
        source.searchResults["yandex|Kizaru Narcos"] = [makeTrack("ym:8", "Kizaru", title: "Narcos (Remix)", durationMs: 180_000), match]
        let result = await Converter.convert([sc], to: .yandex, using: source)
        XCTAssertEqual(result.found.map(\.ref), ["ym:9"], "remix — другая версия")
        XCTAssertTrue(result.missing.isEmpty)
    }

    func testYandexToSoundCloudReupload() async {
        let source = FakeSource()
        let ym = makeTrack("ym:1", "Lil Peep", title: "Benz Truck", durationMs: 160_000)
        // перезалив: залил кто-то другой, артист — в названии
        let reupload = makeTrack("sc:5", "random uploader", title: "Lil Peep - Benz Truck", durationMs: 161_000)
        source.searchResults["soundcloud|Lil Peep Benz Truck"] = [reupload]
        let result = await Converter.convert([ym], to: .soundcloud, using: source)
        XCTAssertEqual(result.found.map(\.ref), ["sc:5"])
    }

    func testConvertKeepsOrderAndReportsMissing() async {
        let source = FakeSource()
        let tracks = (0 ..< 6).map { makeTrack("ym:\($0)", "Art\($0)", title: "T\($0)") }
        for i in [0, 2, 5] {
            source.searchResults["soundcloud|Art\(i) T\(i)"] = [makeTrack("sc:\(i)", "Art\(i)", title: "T\(i)")]
        }
        let already = makeTrack("sc:own", "X")
        let result = await Converter.convert(tracks + [already], to: .soundcloud, using: source)
        XCTAssertEqual(result.found.map(\.ref), ["sc:0", "sc:2", "sc:5", "sc:own"])
        XCTAssertEqual(result.missing.map(\.ref), ["ym:1", "ym:3", "ym:4"])
    }

    func testConvertOfflineAllMissing() async {
        let source = FakeSource()
        source.failAll = true
        let result = await Converter.convert([makeTrack("ym:1", "A")], to: .soundcloud, using: source)
        XCTAssertEqual(result.missing.map(\.ref), ["ym:1"])
    }

    // MARK: - Загрузки

    func testFileNameAndSniff() {
        XCTAssertEqual(DownloadStore.fileName(ref: "sc:123", ext: "mp3"), "sc_123.mp3")
        XCTAssertEqual(DownloadStore.fileName(ref: "ympl:1/../x", ext: "flac"), "ympl_1____x.flac")
        XCTAssertEqual(DownloadStore.sniffExtension(Data("fLaC\u{0}\u{0}".utf8)), "flac")
        XCTAssertEqual(DownloadStore.sniffExtension(Data([0, 0, 0, 0x20] + Array("ftypM4A ".utf8))), "m4a")
        XCTAssertEqual(DownloadStore.sniffExtension(Data("ID3\u{3}".utf8)), "mp3")
        XCTAssertEqual(DownloadStore.sniffExtension(Data([0xFF, 0xFB, 0x90, 0x64])), "mp3")
        XCTAssertNil(DownloadStore.sniffExtension(Data("<html>".utf8)))
    }

    func testPickProgressiveForDownload() throws {
        let json = try JSONValue(data: Data(#"""
        {"media": {"transcodings": [
          {"url": "hls", "preset": "aac_160k", "format": {"protocol": "hls", "mime_type": "audio/mp4; codecs=\"mp4a.40.2\""}},
          {"url": "snip", "preset": "mp3_1_0", "snipped": true, "format": {"protocol": "progressive", "mime_type": "audio/mpeg"}},
          {"url": "file", "preset": "mp3_1_0", "format": {"protocol": "progressive", "mime_type": "audio/mpeg"}}
        ]}}
        """#.utf8))
        XCTAssertEqual(SoundCloud.pickProgressive(json)?["url"].string, "file")
        let onlyHLS = try JSONValue(data: Data(#"{"media": {"transcodings": [{"url": "hls", "format": {"protocol": "hls", "mime_type": "audio/mpeg"}}]}}"#.utf8))
        XCTAssertNil(SoundCloud.pickProgressive(onlyHLS), "только HLS — скачать нельзя")
    }

    func testDownloadSourceOnlyFiles() {
        let url = URL(string: "https://example.com/a")!
        XCTAssertEqual(DownloadSource.from(.file(url: url, quality: "FLAC · Яндекс"))?.fileExtension, "flac")
        XCTAssertEqual(DownloadSource.from(.file(url: url, quality: "MP3 320"))?.fileExtension, "mp3")
        XCTAssertNil(DownloadSource.from(.hls(url: url, quality: "AAC 160")), "HLS файлом не скачать")
    }

    func testDownloadPlaysFromFileAndRemoves() async throws {
        let dir = tempDirectory()
        let fetcher = FakeFetcher(body: Data("ID3 fake mp3".utf8))
        let store = DownloadStore(fetcher: fetcher, directory: dir)
        let track = makeTrack("sc:1", "A")
        store.download(track)
        XCTAssertNotNil(store.progress["sc:1"])
        try await waitUntil { store.isDownloaded("sc:1") }
        XCTAssertNil(store.progress["sc:1"])
        let url = try XCTUnwrap(store.localURL("sc:1"))
        XCTAssertEqual(url.pathExtension, "mp3")
        XCTAssertEqual(try Data(contentsOf: url), Data("ID3 fake mp3".utf8))
        XCTAssertEqual(store.quality("sc:1"), "MP3 320")
        XCTAssertEqual(store.downloaded.map(\.ref), ["sc:1"])
        XCTAssertGreaterThan(store.totalBytes, 0)

        // список переживает перезапуск
        let reloaded = DownloadStore(fetcher: fetcher, directory: dir)
        XCTAssertTrue(reloaded.isDownloaded("sc:1"))

        store.remove("sc:1")
        XCTAssertFalse(store.isDownloaded("sc:1"))
        XCTAssertNil(store.localURL("sc:1"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(DownloadStore(fetcher: fetcher, directory: dir).isDownloaded("sc:1"))
    }

    func testDownloadErrorIsMessage() async throws {
        let store = DownloadStore(fetcher: FakeFetcher(body: Data(), fails: true), directory: tempDirectory())
        store.download(makeTrack("sc:hls", "A", title: "Only HLS"))
        try await waitUntil { store.message != nil }
        XCTAssertTrue(store.message?.contains("Этот трек нельзя скачать") == true)
        XCTAssertFalse(store.isDownloaded("sc:hls"))
        XCTAssertNil(store.progress["sc:hls"])
    }

    func testMissingFileIsNotDownloaded() async throws {
        let dir = tempDirectory()
        let store = DownloadStore(fetcher: FakeFetcher(body: Data("fLaC".utf8)), directory: dir)
        store.download(makeTrack("ym:1", "A"))
        try await waitUntil { store.isDownloaded("ym:1") }
        let url = try XCTUnwrap(store.localURL("ym:1"))
        XCTAssertEqual(url.pathExtension, "flac", "расширение по содержимому")
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(store.localURL("ym:1"))
        XCTAssertFalse(DownloadStore(fetcher: FakeFetcher(body: Data()), directory: dir).isDownloaded("ym:1"))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("не дождались")
    }
}

/// Загрузка без сети: «скачивает» заданные байты.
struct FakeFetcher: DownloadFetcher {
    var body: Data
    var fails = false

    func source(for track: Track) async throws -> DownloadSource {
        if fails { throw ServiceError(message: "Этот трек нельзя скачать") }
        return DownloadSource(url: URL(string: "https://example.com/\(track.ref)")!, fileExtension: "mp3", quality: "MP3 320")
    }

    func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0.5)
        try body.write(to: destination)
        progress(1)
    }
}
