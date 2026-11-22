import XCTest
@testable import Sonar

/// Главная: «Для вас», «Открытия», «Релизы», подписи рядов, кэш.
@MainActor
final class HomeFeedTests: XCTestCase {
    func testSubtitleFirstThreeUniqueArtists() {
        let tracks = [makeTrack("sc:1", "deadwilliam"), makeTrack("sc:2", "DeadWilliam"), makeTrack("sc:3", "gothviolence"),
                      makeTrack("sc:4", "lil peep"), makeTrack("sc:5", "bexey")]
        XCTAssertEqual(HomeMath.subtitle(tracks), "deadwilliam, gothviolence, lil peep…")
        XCTAssertEqual(HomeMath.subtitle(Array(tracks.prefix(3))), "deadwilliam, gothviolence")
        XCTAssertEqual(HomeMath.subtitle([]), "")
    }

    func testSplitKnownAndUnknown() {
        var taste = Taste()
        taste.likedArtists = ["fav"]
        let similar = [[makeTrack("sc:1", "Fav"), makeTrack("sc:2", "New1", plays: 5000), makeTrack("sc:3", "Fav")],
                       [makeTrack("sc:4", "New1", plays: 9000), makeTrack("sc:5", "Fav"), makeTrack("sc:6", "Tiny", plays: 10),
                        makeTrack("sc:liked", "Fav"), makeTrack("sc:7", "New2", plays: nil, available: false)]]
        let tops = [[makeTrack("sc:t1", "Fav"), makeTrack("sc:t2", "Fav")]]
        let split = HomeMath.split(similar: similar, tops: tops, taste: taste, exclude: ["sc:liked"])
        XCTAssertTrue(split.forYou.allSatisfy { taste.isKnown($0) })
        XCTAssertLessThanOrEqual(split.forYou.count, 2, "≤ 2 трека артиста")
        XCTAssertFalse(split.forYou.contains { $0.ref == "sc:liked" })
        XCTAssertEqual(split.discoveries.map(\.ref), ["sc:4"], "по треку на артиста, без случайных заливов и недоступных")
    }

    func testDiscoveriesOnlyWhenTwoSeedsAgreeWithReasons() {
        let taste = Taste()
        let similar = [[makeTrack("sc:1", "Once", plays: 5000), makeTrack("sc:2", "Shared", plays: 5000)],
                       [makeTrack("sc:3", "Shared", plays: 7000), makeTrack("sc:4", "Twice", plays: 5000)]]
        let split = HomeMath.split(similar: similar, tops: [], taste: taste, exclude: [], seedLabels: ["Seed A", "Seed B"])
        XCTAssertEqual(split.discoveries.map(\.artist), ["Shared"], "одиночный совет — не «Открытия», добора нет")
        XCTAssertEqual(split.reasons[split.discoveries[0].ref], ["Seed A", "Seed B"])
    }

    func testCleanPoolDropsTailAndReuploads() {
        let pool = [makeTrack("sc:1", "A", title: "X", plays: 30000), makeTrack("sc:2", "B", title: "x", plays: 20000),
                    makeTrack("sc:3", "C", plays: 40000), makeTrack("sc:4", "D", plays: 7), makeTrack("ym:5", "E")]
        XCTAssertEqual(HomeMath.cleanPool(pool).map(\.ref), ["sc:1", "sc:3", "ym:5"], "перезалив и хвост — вон, без счётчика — остаётся")
        let niche = [makeTrack("sc:1", "A", plays: 40), makeTrack("sc:2", "B", plays: 30), makeTrack("sc:3", "C", plays: 50)]
        XCTAssertEqual(HomeMath.cleanPool(niche).count, 2, "порог не выше медианы")
    }

    func testFreshReleases() {
        let now = ISO8601DateFormatter().date(from: "2026-11-17T12:00:00Z")!
        let albums = [
            makeAlbum("ymalb:old", "A", released: "2026-01-01"),
            makeAlbum("ymalb:new", "A", released: "2026-11-10"),
            makeAlbum("ymalb:future", "A", released: "2026-12-01"),
            makeAlbum("scalb:year", "B", year: 2026),
            makeAlbum("scalb:lastyear", "B", year: 2025),
            makeAlbum("scalb:dup", "a", released: "2026-11-01", title: "Album ymalb:new"),
            makeAlbum("ymalb:mid", "C", released: "2026-10-01"),
        ]
        let fresh = HomeMath.freshReleases(albums, now: now)
        XCTAssertEqual(fresh.map(\.ref), ["ymalb:new", "ymalb:mid", "scalb:year"])
    }

    private func feed(_ source: FakeSource, now: @escaping () -> Date = Date.init) -> (HomeFeed, LibraryStore, PlayHistory, URL) {
        let dir = tempDirectory()
        let library = LibraryStore(file: dir.appendingPathComponent("library.json"))
        let history = PlayHistory(file: dir.appendingPathComponent("history.json"))
        let file = dir.appendingPathComponent("home.json")
        return (HomeFeed(source: source, library: library, history: history, file: file, now: now, random: { 0 }), library, history, file)
    }

    func testEmptyLibraryGivesEmptyRows() async {
        let source = FakeSource()
        let (home, _, _, _) = feed(source)
        await home.refresh()
        XCTAssertTrue(home.forYou.isEmpty)
        XCTAssertTrue(home.discoveries.isEmpty)
        XCTAssertTrue(home.releases.isEmpty)
        XCTAssertEqual(source.calls("similar"), 0, "без Любимых и истории в сеть не ходим")
    }

    func testRefreshBuildsRowsAndCaches() async {
        let source = FakeSource()
        var now = Date()
        let (home, library, history, file) = feed(source, now: { now })
        library.toggleLike(makeTrack("sc:liked", "Fav", artistRef: "sca:fav"))
        history.record(makeTrack("ym:recent", "Old", artistRef: "yma:old"))
        // в «Открытия» — только тех, кого советуют обе затравки
        source.similarByRef["sc:liked"] = [makeTrack("sc:k1", "Fav"), makeTrack("sc:u1", "Stranger", plays: 5000), makeTrack("ym:u2b", "Other")]
        source.similarByRef["ym:recent"] = [makeTrack("ym:k2", "Old"), makeTrack("ym:u2", "Other"), makeTrack("sc:u1b", "Stranger", plays: 6000)]
        source.topByArtist["sca:fav"] = [makeTrack("sc:t1", "Fav", artistRef: "sca:fav")]
        let today = HomeMath.dayString(now)
        source.albumsByArtist["sca:fav"] = [makeAlbum("scalb:1", "Fav", released: today)]
        source.releases = [makeAlbum("ymalb:n1", "X", released: today), makeAlbum("ymalb:n2", "Y", released: today)]
        await home.refresh()
        XCTAssertFalse(home.forYou.isEmpty)
        XCTAssertTrue(home.forYou.allSatisfy { ["fav", "old"].contains($0.artistKey) })
        XCTAssertEqual(Set(home.discoveries.map(\.ref)), ["sc:u1", "ym:u2"])
        XCTAssertFalse(home.reason(for: "sc:u1").isEmpty, "у «Открытий» есть причина")
        XCTAssertEqual(home.releases.first?.ref, "scalb:1")
        XCTAssertEqual(home.releases.count, 3, "мало своих релизов — дополнили новинками")
        XCTAssertFalse(home.loading)

        // 👎 убирает трек из рядов сразу
        library.toggleDislike(makeTrack("sc:u1", "Stranger"))
        XCTAssertEqual(home.discoveries.map(\.ref), ["ym:u2"])

        // кэш: 6 часов без force в сеть не ходим
        let calls = source.calls("similar")
        now += 3600
        await home.refresh()
        XCTAssertEqual(source.calls("similar"), calls)
        await home.refresh(force: true)
        XCTAssertGreaterThan(source.calls("similar"), calls)
        now += 7 * 3600
        let before = source.calls("similar")
        await home.refresh()
        XCTAssertGreaterThan(source.calls("similar"), before)

        // с диска — то же
        let reloaded = HomeFeed(source: source, library: library, history: history, file: file)
        XCTAssertEqual(reloaded.releases.map(\.ref), home.releases.map(\.ref))
    }

    func testOfflineKeepsOldRows() async {
        let source = FakeSource()
        let (home, library, history, _) = feed(source)
        library.toggleLike(makeTrack("sc:liked", "Fav"))
        history.record(makeTrack("ym:recent", "Old"))
        source.similarByRef["sc:liked"] = [makeTrack("sc:u1", "Stranger", plays: 5000)]
        source.similarByRef["ym:recent"] = [makeTrack("sc:u1b", "Stranger", plays: 4000)]
        await home.refresh()
        XCTAssertEqual(home.discoveries.map(\.ref), ["sc:u1"])
        source.failAll = true
        await home.refresh(force: true)
        XCTAssertEqual(home.discoveries.map(\.ref), ["sc:u1"], "сеть не ответила — старое остаётся")
    }
}
