import XCTest
@testable import Sonar

/// Добивка обложки и длины (`TrackBackfill`) — те же случаи, что `windows/src/lib/track-backfill.test.ts`.
@MainActor
final class TrackBackfillTests: XCTestCase {
    private func track(_ ref: String, cover: String? = nil, ms: Int = 0, title: String = "T") -> Track {
        Track(ref: ref, title: title, artist: "A", artists: [], album: nil, durationMs: ms,
              coverURL: cover, url: nil, explicit: false, available: true, plays: nil, tags: nil)
    }

    func testNeedsOnlySupportedTracksWithoutCoverOrLength() {
        XCTAssertTrue(TrackBackfill.needs(track("sc:1")))
        XCTAssertTrue(TrackBackfill.needs(track("ym:1", cover: "https://c", ms: 0)))
        XCTAssertTrue(TrackBackfill.needs(track("sc:1", cover: "", ms: 1000)))
        XCTAssertFalse(TrackBackfill.needs(track("sc:1", cover: "https://c", ms: 1000)))
        XCTAssertFalse(TrackBackfill.needs(track("local:1")), "локальные и прочие сервисы не добиваем")
        XCTAssertFalse(TrackBackfill.needs(track("yt:1")))
    }

    func testMergeTakesOnlyMissingFields() {
        let old = track("sc:1", cover: nil, ms: 0, title: "Старое")
        let fresh = track("sc:1", cover: "https://new", ms: 93_000, title: "Новое")
        let merged = TrackBackfill.merge(old, fresh)
        XCTAssertEqual(merged.title, "Старое")
        XCTAssertEqual(merged.coverURL, "https://new")
        XCTAssertEqual(merged.durationMs, 93_000)
        let full = track("sc:1", cover: "https://old", ms: 5000)
        XCTAssertEqual(TrackBackfill.merge(full, fresh), full, "что есть — не перетираем")
        XCTAssertEqual(TrackBackfill.merge(old, track("sc:1")), old, "пустой ответ ничего не портит")
    }

    func testPlanPutsCurrentFirstSkipsTriedAndLimits() {
        let list = (0 ..< 30).map { track("sc:\($0)") } + [track("sc:full", cover: "c", ms: 1)]
        let batch = TrackBackfill.plan(list, first: "sc:7", tried: ["sc:0"], limit: 20)
        XCTAssertEqual(batch.first, "sc:7")
        XCTAssertEqual(batch.count, 20)
        XCTAssertFalse(batch.contains("sc:0"))
        XCTAssertEqual(Set(batch).count, batch.count, "без повторов")
        XCTAssertFalse(TrackBackfill.plan(list, first: "sc:full", tried: [], limit: 20).contains("sc:full"))
        XCTAssertEqual(TrackBackfill.plan(list, first: nil, tried: [], limit: 3), ["sc:0", "sc:1", "sc:2"])
    }

    func testLikedAreFilledOnceAndMissesNotAskedAgain() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = LibraryStore(file: dir.appendingPathComponent("library.json"))
        library.applySynced(liked: [track("sc:1"), track("sc:2"), track("ym:3", cover: "c", ms: 1)])
        var asked: [String] = []
        let filler = TrackBackfiller()
        filler.library = library
        filler.pauseMs = 0
        filler.fetch = { ref in
            asked.append(ref)
            return ref == "sc:1" ? self.track(ref, cover: "https://c1", ms: 90_000) : nil
        }

        await filler.runLiked(first: "sc:2")
        await filler.runLiked(first: nil)

        XCTAssertEqual(asked, ["sc:2", "sc:1"], "текущий первым, каждый ref — один раз")
        XCTAssertEqual(library.liked[0].coverURL, "https://c1")
        XCTAssertEqual(library.liked[0].durationMs, 90_000)
        XCTAssertNil(library.liked[1].coverURL)
    }
}
