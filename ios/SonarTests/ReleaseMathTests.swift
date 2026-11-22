import XCTest
@testable import Sonar

/// «Новинки исполнителей» на iPhone (`Core/Home/Releases.swift`, `App/ReleaseNotifier.swift`) — зеркало
/// ПК `windows/src/lib/new-releases.test.ts`: что свежее, что ещё не видели, склейка ленты, даты SoundCloud.
final class ReleaseMathTests: XCTestCase {
    private let zone = TimeZone(identifier: "Europe/Riga")!

    private var now: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 12))!
    }

    private func item(_ ref: String, _ released: String, kind: ReleaseItem.Kind = .album) -> ReleaseItem {
        ReleaseItem(ref: ref, kind: kind, title: ref, artist: "ШИПЫ", coverURL: nil, released: released, track: nil)
    }

    func testFreshIsLastWeekNotFuture() {
        XCTAssertTrue(ReleaseMath.isFresh("2026-11-22", now: now, timeZone: zone))
        XCTAssertTrue(ReleaseMath.isFresh("2026-11-16", now: now, timeZone: zone))
        XCTAssertFalse(ReleaseMath.isFresh("2026-11-14", now: now, timeZone: zone))
        XCTAssertFalse(ReleaseMath.isFresh("2026-11-30", now: now, timeZone: zone))
        XCTAssertFalse(ReleaseMath.isFresh("мусор", now: now, timeZone: zone))
        XCTAssertFalse(ReleaseMath.isFresh("", now: now, timeZone: zone))
    }

    func testUnseenFreshKeepsFeedOrder() {
        let feed = [item("a", "2026-11-21"), item("b", "2026-11-20"), item("c", "2026-11-01")]
        XCTAssertEqual(ReleaseMath.unseenFresh(feed, seen: ["a"], now: now, timeZone: zone).map(\.ref), ["b"])
        XCTAssertEqual(ReleaseMath.unseenFresh(feed, seen: [], now: now, timeZone: zone).map(\.ref), ["a", "b"])
    }

    func testMergeDedupesSortsAndLimits() {
        let first = [item("a", "2026-11-01"), item("b", "2026-11-20")]
        let second = [item("b", "2026-11-20"), item("c", "2026-11-10", kind: .track)]
        XCTAssertEqual(ReleaseMath.merge([first, second]).map(\.ref), ["b", "c", "a"])
        XCTAssertEqual(ReleaseMath.merge([first, second], limit: 2).map(\.ref), ["b", "c"])
        XCTAssertTrue(ReleaseMath.merge([]).isEmpty)
    }

    func testSoundCloudDateFallsBack() throws {
        func date(_ json: String) throws -> String? {
            ReleaseMath.soundCloudDate(try JSONValue(data: Data(json.utf8)))
        }
        XCTAssertEqual(try date(#"{"release_date": "2026-11-20T00:00:00Z", "created_at": "2026-11-01T10:00:00Z"}"#), "2026-11-20")
        XCTAssertEqual(try date(#"{"display_date": "2026-11-18T09:00:00Z", "created_at": "2026-11-01T10:00:00Z"}"#), "2026-11-18")
        XCTAssertEqual(try date(#"{"created_at": "2026/11/01 10:00:00 +0000"}"#), "2026/11/01")
        XCTAssertNil(try date(#"{"release_date": "2026"}"#))
        XCTAssertNil(try date(#"{"id": 1}"#))
    }

    func testRememberAppendsAndCaps() {
        XCTAssertEqual(ReleaseMath.remember(["b", "c", "b"], in: ["a", "b"]), ["a", "b", "c"])
        let many = (0 ..< 700).map { "r\($0)" }
        let kept = ReleaseMath.remember(["new"], in: many)
        XCTAssertEqual(kept.count, ReleaseMath.seenLimit)
        XCTAssertEqual(kept.last, "new")
        XCTAssertFalse(kept.contains("r0"))
    }

    func testNotificationLinksOpenAlbumOrPlayTrack() {
        let album = item("ym-album:123", "2026-11-21")
        let track = item("sc:42", "2026-11-21", kind: .track)
        XCTAssertEqual(DeepLink(ReleaseNotifier.link(album)!), .album("ym-album:123"))
        XCTAssertEqual(DeepLink(ReleaseNotifier.link(track)!), .track("sc:42"))
    }
}
