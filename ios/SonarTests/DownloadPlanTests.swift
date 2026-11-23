import XCTest
@testable import Sonar

/// «Скачать» на iPhone (`docs/OFFLINE.md` §8): оценка пачки, подбор под лимит, HLS, очередь по 2,
/// ожидание Wi‑Fi, автоскачивание Любимых.
@MainActor
final class DownloadPlanTests: XCTestCase {
    private func track(_ ref: String, ms: Int = 1000) -> Track {
        Track(ref: ref, title: ref, artist: "a", artists: [], album: nil, durationMs: ms,
              coverURL: nil, url: nil, explicit: false, available: true, plays: nil, tags: nil)
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("download-plan-\(UUID().uuidString)")
    }

    private func poll(_ condition: () async -> Bool) async throws {
        for _ in 0..<300 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("не дождались")
    }

    // MARK: оценка и подтверждение

    func testTrackBytesByServiceAndQuality() {
        // Яндекс high — 320 кбит/с, остальные — 160; секунда = кбит/с × 1000 / 8
        XCTAssertEqual(DownloadPlan.trackBytes(track("ym:1"), quality: "high"), 40_000)
        XCTAssertEqual(DownloadPlan.trackBytes(track("sc:1"), quality: "high"), 20_000)
        XCTAssertEqual(DownloadPlan.trackBytes(track("ym:1"), quality: "что-то"), 125_000, "неизвестное — как FLAC")
        XCTAssertEqual(DownloadPlan.trackBytes(track("sc:1", ms: 0), quality: "high"), 210_000 * 160 / 8, "без длительности — средняя песня")
        XCTAssertEqual(DownloadPlan.batchBytes([track("ym:1"), track("sc:1")], quality: "high"), 60_000)
    }

    func testNeedsConfirmThresholds() {
        XCTAssertFalse(DownloadPlan.needsConfirm(count: 50, bytes: 1 << 30))
        XCTAssertTrue(DownloadPlan.needsConfirm(count: 51, bytes: 0))
        XCTAssertTrue(DownloadPlan.needsConfirm(count: 1, bytes: (1 << 30) + 1))
    }

    func testBatchFitsFreeSpace() {
        let tracks = [track("sc:1"), track("sc:2")]
        XCTAssertTrue(DownloadPlan.Batch(tracks, quality: "high", free: nil).fits, "место не узнали — пробуем")
        XCTAssertTrue(DownloadPlan.Batch(tracks, quality: "high", free: 1 << 20).fits)
        XCTAssertFalse(DownloadPlan.Batch(tracks, quality: "high", free: 30_000).fits)
        XCTAssertFalse(DownloadPlan.Batch(tracks, quality: "high", free: nil).needsConfirm)
    }

    func testFitToLimitStopsAtFirstMisfit() {
        let small = (1...3).map { track("sc:\($0)") } // по 20 000
        XCTAssertEqual(DownloadPlan.fitToLimit(small, used: 0, limit: 50_000, quality: "high").map(\.ref), ["sc:1", "sc:2"])
        XCTAssertEqual(DownloadPlan.fitToLimit(small, used: 40_000, limit: 50_000, quality: "high"), [])
        // большой свежий лайк не влез — мелкие старые за ним не обгоняют
        let order = [track("sc:big", ms: 10_000), track("sc:old")]
        XCTAssertEqual(DownloadPlan.fitToLimit(order, used: 0, limit: 100_000, quality: "high"), [])
    }

    // MARK: HLS

    func testHLSMp3Segments() throws {
        let base = try XCTUnwrap(URL(string: "https://cf.sndcdn.com/a/playlist.m3u8"))
        let text = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\n0.mp3\n#EXTINF:10,\nhttps://x.com/1.mp3\n#EXT-X-ENDLIST\n"
        XCTAssertEqual(HLSPlaylist.parse(text, base: base), .mp3([
            try XCTUnwrap(URL(string: "https://cf.sndcdn.com/a/0.mp3")),
            try XCTUnwrap(URL(string: "https://x.com/1.mp3")),
        ]))
    }

    func testHLSFragmentedMP4() throws {
        let base = try XCTUnwrap(URL(string: "https://cf.sndcdn.com/a/p.m3u8"))
        let text = "#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:6,\nseg1.m4s\n"
        XCTAssertEqual(HLSPlaylist.parse(text, base: base), .fmp4(
            initial: try XCTUnwrap(URL(string: "https://cf.sndcdn.com/a/init.mp4")),
            segments: [try XCTUnwrap(URL(string: "https://cf.sndcdn.com/a/seg1.m4s"))]
        ))
    }

    func testHLSVariantAndRejects() throws {
        let base = try XCTUnwrap(URL(string: "https://cf.sndcdn.com/a/master.m3u8"))
        XCTAssertEqual(
            HLSPlaylist.parse("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=128000\nlow/index.m3u8\n", base: base),
            .variant(try XCTUnwrap(URL(string: "https://cf.sndcdn.com/a/low/index.m3u8")))
        )
        XCTAssertNil(HLSPlaylist.parse("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"k\"\n#EXTINF:10,\n0.mp3\n", base: base), "шифрованное")
        XCTAssertNil(HLSPlaylist.parse("#EXTM3U\n#EXTINF:10,\n0.ts\n", base: base), "MPEG-TS")
        XCTAssertNil(HLSPlaylist.parse("<html>", base: base), "не плейлист")
        XCTAssertNil(HLSPlaylist.parse("#EXTM3U\n#EXT-X-ENDLIST\n", base: base), "без кусков")
    }

    // MARK: обложка

    func testCoverNameIgnoresSize() {
        let big = DownloadStore.coverName("https://i1.sndcdn.com/artworks-a-t500x500.jpg")
        XCTAssertEqual(big, DownloadStore.coverName("https://i1.sndcdn.com/artworks-a-large.jpg?x=1"))
        XCTAssertNotEqual(big, DownloadStore.coverName("https://i1.sndcdn.com/artworks-b-t500x500.jpg"))
        XCTAssertTrue(big.hasSuffix(".jpg"))
    }

    // MARK: очередь

    func testQueueRunsTwoAtATime() async throws {
        let gate = FetchGate()
        let store = DownloadStore(fetcher: GatedFetcher(gate: gate), directory: tempDirectory())
        let refs = ["sc:1", "sc:2", "sc:3"]
        for ref in refs { store.download(track(ref)) }
        XCTAssertEqual(store.progress.count, 3, "третий ждёт в очереди с нулём")
        try await poll { await gate.running == 2 }
        try await Task.sleep(nanoseconds: 50_000_000)
        let peakBefore = await gate.peak
        XCTAssertEqual(peakBefore, DownloadPlan.parallel)

        await gate.release()
        try await poll { refs.allSatisfy { store.isDownloaded($0) } }
        let peakAfter = await gate.peak
        XCTAssertEqual(peakAfter, DownloadPlan.parallel)
        XCTAssertTrue(store.progress.isEmpty)
    }

    func testRedownloadWhileCancelledReusesRunningFetch() async throws {
        let gate = FetchGate()
        let store = DownloadStore(fetcher: GatedFetcher(gate: gate), directory: tempDirectory())
        store.download(track("sc:1"))
        try await poll { await gate.running == 1 }
        store.remove("sc:1")
        XCTAssertNil(store.progress["sc:1"])
        store.download(track("sc:1"))
        XCTAssertEqual(store.progress["sc:1"], 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        let peak = await gate.peak
        XCTAssertEqual(peak, 1, "второй загрузки того же трека нет")

        await gate.release()
        try await poll { store.isDownloaded("sc:1") }
    }

    func testQueueWaitsForGateWithoutError() async throws {
        let wifi = GateFlag()
        let store = DownloadStore(fetcher: FakeFetcher(body: Data("ID3".utf8)), directory: tempDirectory()) { wifi.open }
        store.download(track("sc:1"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.progress["sc:1"], 0, "ждёт Wi‑Fi в очереди")
        XCTAssertFalse(store.isDownloaded("sc:1"))
        XCTAssertNil(store.message, "ожидание — не ошибка")

        wifi.open = true
        store.resume()
        try await poll { store.isDownloaded("sc:1") }
        XCTAssertNil(store.message)
    }

    // MARK: автоскачивание Любимых

    func testLikedPlanSkipsHaveAndCountsQueued() {
        // час FLAC ≈ 450 МБ; скачан a, в очереди b — новые c, d влезают в 2 ГБ, e уже нет
        let liked = ["ym:a", "ym:b", "ym:c", "ym:d", "ym:e"].map { track($0, ms: 3_600_000) }
        let one = DownloadPlan.trackBytes(liked[0], quality: "lossless")
        let plan = LikedAutoDownload.plan(
            liked: liked,
            isDownloaded: { $0 == "ym:a" },
            isQueued: { $0 == "ym:b" },
            downloadedBytes: one,
            limitGB: 2,
            quality: "lossless"
        )
        XCTAssertEqual(plan.map(\.ref), ["ym:c", "ym:d"])

        let full = LikedAutoDownload.plan(liked: liked, isDownloaded: { _ in false }, isQueued: { _ in false },
                                          downloadedBytes: 2 << 30, limitGB: 2, quality: "lossless")
        XCTAssertEqual(full, [], "лимит уже занят")
    }

    // MARK: строки

    func testDownloadStringsTranslated() {
        let keys = [
            "Не закрывай Sonar, пока качается", "Не хватит места: {n}", "Только по Wi‑Fi",
            "По сотовой сети загрузки ждут Wi‑Fi",
            "Лайкнутые треки сами скачиваются на этот телефон по Wi‑Fi, пока не упрутся в лимит",
            "Скачивать Любимые", "Лимит для Любимых",
        ]
        for key in keys {
            for lang in [Lang.en, .uk, .es, .de, .pl] {
                XCTAssertNotEqual(I18n.translate(key, lang: lang), key, "\(lang): \(key)")
            }
        }
    }
}

/// Пропуск для `mayStart` — как «Только по Wi‑Fi».
@MainActor
private final class GateFlag {
    var open = false
}

/// Держит загрузки, пока тест не отпустит, и считает, сколько шло одновременно.
private actor FetchGate {
    private(set) var running = 0
    private(set) var peak = 0
    private var isOpen = false

    func enter() {
        running += 1
        peak = max(peak, running)
    }

    func leave() { running -= 1 }
    func release() { isOpen = true }
    func opened() -> Bool { isOpen }
}

private struct GatedFetcher: DownloadFetcher {
    let gate: FetchGate

    func source(for track: Track) async throws -> DownloadSource {
        DownloadSource(url: URL(string: "https://example.com/\(track.ref)")!, fileExtension: "mp3", quality: "MP3 320")
    }

    func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        await gate.enter()
        while !(await gate.opened()) {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try Data("ID3".utf8).write(to: destination)
        await gate.leave()
    }
}
