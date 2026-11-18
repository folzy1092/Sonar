import XCTest
@testable import Sonar

/// Поиск дублей в Любимых и своих плейлистах (`DupeFinder`, порт `dupes/mod.rs`) и порядок качества реестра.
final class DupeFinderTests: XCTestCase {
    private func refs(_ groups: [DupeGroup]) -> [[String]] {
        groups.map { $0.tracks.map(\.ref) }
    }

    func testQualityOrderCoversEveryServiceOnce() {
        XCTAssertEqual(Set(ServiceRegistry.qualityOrder), Set(ServiceID.allCases))
        XCTAssertEqual(ServiceRegistry.qualityOrder.count, ServiceID.allCases.count)
        XCTAssertLessThan(ServiceRegistry.qualityRank("ym:1"), ServiceRegistry.qualityRank("sp:1"))
        XCTAssertLessThan(ServiceRegistry.qualityRank("yt:1"), ServiceRegistry.qualityRank("sc:1"))
        XCTAssertEqual(ServiceRegistry.qualityRank("pl_1"), ServiceRegistry.qualityOrder.count, "без сервиса — последним")
    }

    func testSameTrackFromAnotherServiceKeepsBestQuality() {
        // Arrange
        let list = [
            makeTrack("sc:1", "Artist", title: "Song", durationMs: 200_000),
            makeTrack("yt:9", "Other", title: "Song", durationMs: 200_000),
            makeTrack("ym:1", "Artist", title: "Song (Remastered)", durationMs: 201_500),
        ]
        // Act
        let groups = DupeFinder.groups(list, newestFirst: false)
        // Assert
        XCTAssertEqual(refs(groups), [["ym:1", "sc:1"]], "другой исполнитель — не дубль, Яндекс — первым")
        XCTAssertEqual(groups.first?.extra.map(\.ref), ["sc:1"])
    }

    func testRemixPartsAndLengthAreNotDupes() {
        let list = [
            makeTrack("sc:1", "A", title: "Song", durationMs: 200_000),
            makeTrack("sc:2", "A", title: "Song (Remix)", durationMs: 200_000),
            makeTrack("sc:3", "A", title: "Intro", durationMs: 90_000),
            makeTrack("sc:4", "A", title: "Intro 2", durationMs: 90_000),
            makeTrack("sc:5", "A", title: "Part 1", durationMs: 120_000),
            makeTrack("ym:5", "A", title: "Part 2", durationMs: 120_000),
            makeTrack("ym:6", "A", title: "Song", durationMs: 206_000),
        ]
        XCTAssertEqual(DupeFinder.groups(list, newestFirst: false), [], "ремикс, номера и ±6 с — разные треки")
    }

    func testUnknownLengthNeedsTheExactTitle() {
        let list = [
            makeTrack("sc:1", "A", title: "Night Drive", durationMs: 0),
            makeTrack("ym:1", "A", title: "Night Drive", durationMs: 240_000),
            makeTrack("sc:2", "A", title: "Night Drives", durationMs: 0),
        ]
        XCTAssertEqual(refs(DupeFinder.groups(list, newestFirst: false)), [["ym:1", "sc:1"]])
    }

    func testUnavailableLosesAndTieGoesToAddedEarlier() {
        let unavailable = [
            makeTrack("ym:1", "A", title: "Song", available: false),
            makeTrack("sc:1", "A", title: "Song"),
        ]
        XCTAssertEqual(DupeFinder.groups(unavailable, newestFirst: false).first?.keep.ref, "sc:1")

        let tie = [makeTrack("sc:1", "A", title: "Song"), makeTrack("sc:2", "A", title: "Song")]
        XCTAssertEqual(DupeFinder.groups(tie, newestFirst: false).first?.keep.ref, "sc:1", "плейлист: выше — раньше")
        XCTAssertEqual(DupeFinder.groups(tie, newestFirst: true).first?.keep.ref, "sc:2", "Любимые: ниже — раньше")
    }

    func testGroupsFollowListOrderAndJoinTransitively() {
        let list = [
            makeTrack("sc:9", "B", title: "Other"),
            makeTrack("sc:1", "A", title: "Song", durationMs: 200_000),
            makeTrack("ym:9", "B", title: "Other"),
            makeTrack("yt:1", "A", title: "Song", durationMs: 202_500),
            makeTrack("ym:1", "A", title: "Song", durationMs: 204_500),
        ]
        XCTAssertEqual(refs(DupeFinder.groups(list, newestFirst: false)), [["ym:9", "sc:9"], ["ym:1", "sc:1", "yt:1"]],
                       "дубль дубля — та же группа, даже если с первым больше 3 с")
    }

    func testBigListStaysFast() {
        let list = (0..<3000).map { makeTrack("sc:\($0)", "Artist \($0 % 50)", title: "Track \($0)", durationMs: 180_000 + $0) }
        let started = Date()
        XCTAssertEqual(DupeFinder.groups(list, newestFirst: true), [])
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
}
