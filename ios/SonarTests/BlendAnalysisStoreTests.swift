import Foundation
import XCTest
@testable import Sonar

// Файлы анализа сведения (docs/BLEND.md §4.1): разные ref — разные имена, запись читается обратно, чужой ref в
// файле не подхватывается, разбор LRLR на каналы.

final class BlendAnalysisStoreTests: XCTestCase {
    private func sample(_ ref: String) -> BlendAnalysis {
        BlendAnalysis(
            version: blendAnalysisVersion, ref: ref, durationMs: 180_000, startMs: 120, endMs: 179_500,
            bpm: 124, bpmConf: 0.8, beatMs: 60000.0 / 124, firstBeatMs: 120, downbeat: 0, gridStable: true,
            key: 9, keyConf: 0.6, loudness: -9.5,
            bars: BlendBars(energy: [0.2, 0.9], low: [0.1, 0.8], mid: [0.3, 0.5], onsets: [0.4, 0.7]),
            phrases: [BlendPhrase(bar: 0, kind: .intro), BlendPhrase(bar: 16, kind: .drop)]
        )
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("blend-analysis-\(UUID().uuidString)", isDirectory: true)
    }

    func testNamesAreSafeAndDistinct() {
        let a = BlendAnalysisFiles.name("sc:1")
        let b = BlendAnalysisFiles.name("sc_1")
        let c = BlendAnalysisFiles.name("local:/a/b.mp3")
        XCTAssertNotEqual(a, b)
        XCTAssertFalse(c.dropLast(5).contains("/"))
        XCTAssertFalse(a.contains(":"))
        XCTAssertTrue(a.hasSuffix(".json"))
    }

    func testWriteThenRead() {
        let dir = tempDir()
        defer { BlendAnalysisFiles.clear(in: dir) }
        XCTAssertTrue(BlendAnalysisFiles.write(sample("sc:1"), in: dir))
        XCTAssertTrue(BlendAnalysisFiles.write(sample("ym:2"), in: dir))
        let found = BlendAnalysisFiles.read(["sc:1", "ym:2", "vk:3"], in: dir)
        XCTAssertEqual(found["sc:1"], sample("sc:1"))
        XCTAssertEqual(found["ym:2"], sample("ym:2"))
        XCTAssertNil(found["vk:3"])
    }

    func testForeignRefInFileIgnored() throws {
        let dir = tempDir()
        defer { BlendAnalysisFiles.clear(in: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(sample("ym:9"))
        try data.write(to: dir.appendingPathComponent(BlendAnalysisFiles.name("sc:1")))
        XCTAssertTrue(BlendAnalysisFiles.read(["sc:1"], in: dir).isEmpty)
    }

    func testDeinterleaveDropsUnpairedTail() {
        var left: [Float] = [9]
        var right: [Float] = [8]
        BlendAnalysisStore.deinterleave([1, 2, 3, 4, 5], left: &left, right: &right)
        XCTAssertEqual(left, [9, 1, 3])
        XCTAssertEqual(right, [8, 2, 4])
    }
}
