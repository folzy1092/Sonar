import XCTest
@testable import Sonar

/// Любимые (правка, 👎) и история прослушиваний.
@MainActor
final class LibraryHistoryTests: XCTestCase {
    private func library(_ dir: URL) -> LibraryStore {
        LibraryStore(file: dir.appendingPathComponent("library.json"))
    }

    // MARK: - Любимые

    func testRemoveLikedSeveral() async {
        let dir = tempDirectory()
        let store = library(dir)
        for ref in ["sc:1", "sc:2", "sc:3"] { store.toggleLike(makeTrack(ref, "A")) }
        store.removeLiked(["sc:1", "sc:3"])
        XCTAssertEqual(store.liked.map(\.ref), ["sc:2"])
        XCTAssertFalse(store.isLiked(makeTrack("sc:1", "A")))
        XCTAssertEqual(library(dir).liked.map(\.ref), ["sc:2"], "сохранилось на диск")
    }

    func testMoveLikedLikeSwiftUI() async {
        let dir = tempDirectory()
        let store = library(dir)
        // toggleLike кладёт сверху — добавляем с конца, чтобы вышло a b c d
        for ref in ["sc:d", "sc:c", "sc:b", "sc:a"] { store.toggleLike(makeTrack(ref, "A")) }
        XCTAssertEqual(store.liked.map(\.ref), ["sc:a", "sc:b", "sc:c", "sc:d"])
        store.moveLiked(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(store.liked.map(\.ref), ["sc:b", "sc:c", "sc:a", "sc:d"])
        store.moveLiked(fromOffsets: [3], toOffset: 0)
        XCTAssertEqual(store.liked.map(\.ref), ["sc:d", "sc:b", "sc:c", "sc:a"])
        XCTAssertEqual(library(dir).liked.map(\.ref), ["sc:d", "sc:b", "sc:c", "sc:a"])
    }

    func testListMathMatchesSwiftUIMove() {
        let items = Array("abcdef")
        XCTAssertEqual(String(ListMath.move(items, fromOffsets: [1, 3], toOffset: 5)), "acebdf")
        XCTAssertEqual(String(ListMath.move(items, fromOffsets: [4, 5], toOffset: 0)), "efabcd")
        XCTAssertEqual(String(ListMath.move(items, fromOffsets: [0], toOffset: 6)), "bcdefa")
        XCTAssertEqual(String(ListMath.move(items, fromOffsets: [2], toOffset: 2)), "abcdef")
        XCTAssertEqual(String(ListMath.move(items, fromOffsets: [2], toOffset: 3)), "abcdef")
        XCTAssertEqual(String(ListMath.move(items, fromOffsets: [9], toOffset: 0)), "abcdef", "чужой индекс — ничего")
    }

    func testDislikeTogglesAndPersists() async {
        let dir = tempDirectory()
        let store = library(dir)
        let track = makeTrack("ym:1", "B")
        store.toggleDislike(track)
        XCTAssertTrue(store.isDisliked("ym:1"))
        XCTAssertTrue(library(dir).isDisliked("ym:1"))
        store.toggleDislike(track)
        XCTAssertFalse(store.isDisliked("ym:1"))
        XCTAssertFalse(library(dir).isDisliked("ym:1"))
    }

    func testOldLibraryFileWithoutDislikesLoads() async throws {
        let dir = tempDirectory()
        let old = #"{"liked": [], "speeds": {"sc:1": 1.25}}"#
        try Data(old.utf8).write(to: dir.appendingPathComponent("library.json"))
        let store = library(dir)
        XCTAssertEqual(store.sound(for: "sc:1"), TrackSound(rate: 1.25), "старая «Запомнить скорость» — звук трека")
        XCTAssertTrue(store.disliked.isEmpty)
    }

    // MARK: - История

    func testRecentUniqueNewestFirstAndCapped() async {
        let dir = tempDirectory()
        let history = PlayHistory(file: dir.appendingPathComponent("history.json"))
        history.record(makeTrack("sc:1", "A"))
        history.record(makeTrack("sc:2", "B"))
        history.record(makeTrack("sc:1", "A"))
        XCTAssertEqual(history.recent.map(\.ref), ["sc:1", "sc:2"])
        for i in 0 ..< 150 { history.record(makeTrack("sc:x\(i)", "A")) }
        XCTAssertEqual(history.recent.count, PlayHistory.recentLimit)
        XCTAssertEqual(history.recent.first?.ref, "sc:x149")
        let reloaded = PlayHistory(file: dir.appendingPathComponent("history.json"))
        XCTAssertEqual(reloaded.recent.map(\.ref), history.recent.map(\.ref))
    }

    func testEndedWritesFinishedOrSkip() async {
        let history = PlayHistory(file: tempDirectory().appendingPathComponent("h.json"))
        let track = makeTrack("sc:1", "A", durationMs: 200_000)
        XCTAssertEqual(history.ended(track, listenedMs: 190_000, manualSkip: false), 1)
        XCTAssertEqual(history.finishedRefs(limit: 5), ["sc:1"])
        XCTAssertEqual(history.ended(track, listenedMs: 10_000, manualSkip: true), -1)
        XCTAssertEqual(history.signals.last?.kind, .skip)
        XCTAssertEqual(history.signals.last?.weight, 1)
        // не вручную и не дослушан — ничего
        let count = history.signals.count
        XCTAssertEqual(history.ended(track, listenedMs: 60_000, manualSkip: false), 0)
        XCTAssertEqual(history.signals.count, count)
        // лайк меняет оценку для волны, но в историю пишется сам исход
        XCTAssertEqual(history.ended(track, listenedMs: 10_000, manualSkip: true, liked: true), 1.5)
        XCTAssertEqual(history.signals.last?.kind, .skip)
    }

    func testPlayedRefsWindow() async {
        var now = Date(timeIntervalSince1970: 1_000_000_000)
        let history = PlayHistory(file: tempDirectory().appendingPathComponent("h.json"), now: { now })
        history.record(makeTrack("sc:old", "A"))
        now += 10 * 86_400
        history.record(makeTrack("sc:new", "A"))
        XCTAssertEqual(history.playedRefs(withinDays: 7), ["sc:new"])
        XCTAssertEqual(history.playedRefs(withinDays: 30), ["sc:old", "sc:new"])
    }

    func testTasteDecaysAndCountsSkips() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let day: TimeInterval = 86_400
        let signals = [
            PlaySignal(ref: "sc:1", artists: ["a"], kind: .play, weight: 1, at: now),
            PlaySignal(ref: "sc:1", artists: ["a"], kind: .finish, weight: 1, at: now),
            PlaySignal(ref: "sc:2", artists: ["b"], kind: .play, weight: 1, at: now - 30 * day),
            PlaySignal(ref: "sc:2", artists: ["b"], kind: .finish, weight: 1, at: now - 30 * day),
            PlaySignal(ref: "sc:3", artists: ["c"], kind: .skip, weight: 1, at: now),
            PlaySignal(ref: "sc:4", artists: ["d"], kind: .play, weight: 1, at: now - 200 * day),
        ]
        let taste = Taste.build(signals: signals, liked: [makeTrack("ym:9", "Liked")], now: now)
        XCTAssertEqual(taste.plays["a"] ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(taste.plays["b"] ?? 0, 0.5, accuracy: 1e-9, "полураспад 30 дней")
        XCTAssertNil(taste.plays["d"], "старше 180 дней не считается")
        XCTAssertEqual(taste.skips["c"] ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(taste.trackSkips["sc:3"] ?? 0, 1, accuracy: 1e-9)
        XCTAssertTrue(taste.isKnown(makeTrack("sc:5", "A")))
        XCTAssertTrue(taste.isKnown(makeTrack("sc:6", "liked")))
        XCTAssertFalse(taste.isKnown(makeTrack("sc:7", "C")), "одни пропуски — не знакомый")
        XCTAssertGreaterThan(taste.affinity(makeTrack("sc:5", "A")), taste.affinity(makeTrack("sc:8", "B")))
        XCTAssertLessThan(taste.affinity(makeTrack("sc:7", "C")), 0)
    }

    // MARK: - Оценка исхода и артисты

    func testRewardTable() {
        XCTAssertEqual(Outcome.reward(listenedMs: 100_000, durationMs: 200_000, manualSkip: true, disliked: true), -2)
        XCTAssertEqual(Outcome.reward(listenedMs: 1_000, durationMs: 200_000, manualSkip: true, liked: true), 1.5)
        XCTAssertEqual(Outcome.reward(listenedMs: 20_000, durationMs: 200_000, manualSkip: true), -1)
        XCTAssertEqual(Outcome.reward(listenedMs: 40_000, durationMs: 200_000, manualSkip: true), -1, "f < 0.25")
        XCTAssertEqual(Outcome.reward(listenedMs: 25_000, durationMs: 60_000, manualSkip: true), -1, "< 30 с")
        XCTAssertEqual(Outcome.reward(listenedMs: 60_000, durationMs: 200_000, manualSkip: true), -0.4)
        XCTAssertEqual(Outcome.reward(listenedMs: 120_000, durationMs: 200_000, manualSkip: true), 0)
        XCTAssertEqual(Outcome.reward(listenedMs: 160_000, durationMs: 200_000, manualSkip: true), 1)
        XCTAssertEqual(Outcome.reward(listenedMs: 20_000, durationMs: 200_000, manualSkip: false), 0)
        XCTAssertEqual(Outcome.reward(listenedMs: 20_000, durationMs: 0, manualSkip: true), -1)
        XCTAssertEqual(Outcome.reward(listenedMs: 150_000, durationMs: 0, manualSkip: true), 1)
        XCTAssertEqual(Outcome.reward(listenedMs: 60_000, durationMs: 0, manualSkip: true), 0)
    }

    func testArtistKeys() {
        var track = makeTrack("ym:1", "x")
        track.artists = [ArtistRef(ref: "yma:1", name: " Tyler, The Creator ", avatarURL: nil),
                         ArtistRef(ref: "yma:2", name: "Frank Ocean", avatarURL: nil)]
        XCTAssertEqual(track.artistKeys, ["tyler, the creator", "frank ocean"])
        XCTAssertEqual(track.artistKey, "tyler, the creator")
        XCTAssertEqual(track.mainArtistRef, "yma:1")
        track.artists = []
        track.artist = "Simon & Garfunkel"
        XCTAssertEqual(track.artistKeys, ["simon & garfunkel"])
        XCTAssertNil(track.mainArtistRef)
        XCTAssertNil(makeTrack("sc:1", "A", artistRef: "sca:0").mainArtistRef, "SoundCloud без id")
    }
}
