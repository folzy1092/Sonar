import Foundation
import XCTest
@testable import Sonar

// Склеенные файлы HLS SoundCloud для сведения (docs/BLEND.md §13): кэш на диске (имя из ref, повторная укладка
// заменяет, вытеснение давно не игравших), когда дек берёт файл вместо потока, когда склеивать заранее.

final class BlendStitchCacheTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("blend-stitch-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func temp(_ bytes: Int, ext: String = "mp3") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stitch-src-\(UUID().uuidString).\(ext)")
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    private func age(_ url: URL, _ seconds: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -seconds)], ofItemAtPath: url.path)
    }

    // MARK: - диск

    func testPutMovesFileAndFindsItByRef() throws {
        let cache = BlendStitchCache(directory: dir)
        let src = try temp(10, ext: "m4a")
        let placed = try cache.put("sc:1", file: src)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertEqual(placed.pathExtension, "m4a")
        XCTAssertEqual(cache.localURL("sc:1")?.lastPathComponent, placed.lastPathComponent)
        XCTAssertNil(cache.localURL("sc_1"), "sc:1 и sc_1 — разные файлы")
        XCTAssertEqual(cache.totalBytes, 10)
    }

    func testStemsAreDistinctAndSafe() {
        XCTAssertNotEqual(BlendStitchCache.stem("sc:1"), BlendStitchCache.stem("sc_1"))
        XCTAssertFalse(BlendStitchCache.stem("sc:1").contains(":"))
        XCTAssertFalse(BlendStitchCache.stem("sc:1").hasSuffix(".json"))
    }

    func testPutAgainReplacesOldFileEvenWithOtherExtension() throws {
        let cache = BlendStitchCache(directory: dir)
        try cache.put("sc:1", file: try temp(10, ext: "mp3"))
        let second = try cache.put("sc:1", file: try temp(20, ext: "m4a"))
        XCTAssertEqual(cache.entries().count, 1)
        XCTAssertEqual(cache.localURL("sc:1")?.lastPathComponent, second.lastPathComponent)
        XCTAssertEqual(cache.totalBytes, 20)
    }

    func testPutEvictsLeastRecentlyUsedButKeepsNewFile() throws {
        let cache = BlendStitchCache(directory: dir, limit: 25)
        let old = try cache.put("sc:1", file: try temp(10))
        let used = try cache.put("sc:2", file: try temp(10))
        try age(old, 300)
        try age(used, 200)
        _ = cache.localURL("sc:2", touch: true)
        try cache.put("sc:3", file: try temp(10))
        XCTAssertNil(cache.localURL("sc:1"), "давно не брали — ушёл первым")
        XCTAssertNotNil(cache.localURL("sc:2"))
        XCTAssertNotNil(cache.localURL("sc:3"))
    }

    func testOversizedNewFileStaysWhileOthersGo() throws {
        let cache = BlendStitchCache(directory: dir, limit: 15)
        try cache.put("sc:1", file: try temp(10))
        try cache.put("sc:2", file: try temp(30))
        XCTAssertNil(cache.localURL("sc:1"))
        XCTAssertNotNil(cache.localURL("sc:2"), "только что склеенный не стираем, даже если он больше предела")
    }

    func testRemoveAndClear() throws {
        let cache = BlendStitchCache(directory: dir)
        try cache.put("sc:1", file: try temp(5))
        try cache.put("sc:2", file: try temp(5))
        cache.remove("sc:1")
        XCTAssertNil(cache.localURL("sc:1"))
        XCTAssertNotNil(cache.localURL("sc:2"))
        cache.clear()
        XCTAssertTrue(cache.entries().isEmpty)
        XCTAssertEqual(cache.totalBytes, 0)
    }

    func testMissingDirectoryIsEmpty() {
        XCTAssertTrue(BlendStitchCache(directory: dir).entries().isEmpty)
        XCTAssertNil(BlendStitchCache(directory: dir).localURL("sc:1"))
    }

    // MARK: - вытеснение

    private func entry(_ stem: String, _ bytes: Int64, _ ago: TimeInterval) -> BlendStitchEntry {
        BlendStitchEntry(stem: stem, url: URL(fileURLWithPath: "/tmp/\(stem).mp3"), bytes: bytes,
                         used: Date(timeIntervalSince1970: 1_000_000 - ago))
    }

    func testEvictNothingUnderLimit() {
        XCTAssertEqual(BlendStitchPlan.evict([entry("a", 5, 10), entry("b", 5, 5)], limit: 10), [])
    }

    func testEvictOldestFirstUntilUnderLimit() {
        let entries = [entry("new", 10, 1), entry("oldest", 10, 100), entry("mid", 10, 50)]
        XCTAssertEqual(BlendStitchPlan.evict(entries, limit: 15).map(\.stem), ["oldest", "mid"])
        XCTAssertEqual(BlendStitchPlan.evict(entries, limit: 20).map(\.stem), ["oldest"])
    }

    func testEvictSkipsProtected() {
        let entries = [entry("a", 10, 100), entry("b", 10, 50)]
        XCTAssertEqual(BlendStitchPlan.evict(entries, limit: 10, protect: ["a"]).map(\.stem), ["b"])
    }

    // MARK: - чем грузить дек

    func testSourceIsStitchedFileForSoundCloudWithBlend() {
        let file = URL(fileURLWithPath: "/tmp/sc_3a1.m4a")
        XCTAssertEqual(BlendStitchPlan.source(ref: "sc:1", blendOn: true, fresh: false, stitched: file),
                       .file(url: file, quality: "AAC"))
    }

    func testSourceIsNilOtherwise() {
        let file = URL(fileURLWithPath: "/tmp/x.mp3")
        XCTAssertNil(BlendStitchPlan.source(ref: "sc:1", blendOn: false, fresh: false, stitched: file), "без сведения — поток")
        XCTAssertNil(BlendStitchPlan.source(ref: "sc:1", blendOn: true, fresh: true, stitched: file), "файл не открылся — поток")
        XCTAssertNil(BlendStitchPlan.source(ref: "ym:1", blendOn: true, fresh: false, stitched: file), "не SoundCloud")
        XCTAssertNil(BlendStitchPlan.source(ref: "sc:1", blendOn: true, fresh: false, stitched: nil), "файла нет — поток")
    }

    func testLabelByExtension() {
        XCTAssertEqual(BlendStitchPlan.label(URL(fileURLWithPath: "/a.m4a")), "AAC")
        XCTAssertEqual(BlendStitchPlan.label(URL(fileURLWithPath: "/a.FLAC")), "FLAC")
        XCTAssertEqual(BlendStitchPlan.label(URL(fileURLWithPath: "/a.mp3")), "MP3")
        XCTAssertEqual(BlendStitchPlan.label(URL(fileURLWithPath: "/a")), "MP3")
    }

    // MARK: - склеивать ли заранее

    private func prefetch(ref: String = "sc:1", durationMs: Int = 200_000, offline: Bool = false,
                          mayDownload: Bool = true, hasFile: Bool = false, attempted: Bool = false) -> Bool {
        BlendStitchPlan.shouldPrefetch(ref: ref, durationMs: durationMs, offline: offline,
                                       mayDownload: mayDownload, hasFile: hasFile, attempted: attempted)
    }

    func testPrefetchOnlyWhenNeededAndAllowed() {
        XCTAssertTrue(prefetch())
        XCTAssertFalse(prefetch(ref: "ym:1"), "у Яндекса прямой файл — склеивать нечего")
        XCTAssertFalse(prefetch(offline: true))
        XCTAssertFalse(prefetch(mayDownload: false), "«Только по Wi‑Fi» на сотовой")
        XCTAssertFalse(prefetch(hasFile: true))
        XCTAssertFalse(prefetch(attempted: true))
        XCTAssertFalse(prefetch(durationMs: BlendAnalysisFiles.maxDurationMs + 1), "микс на час не тянем")
    }
}
