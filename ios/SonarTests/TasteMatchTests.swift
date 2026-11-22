import XCTest
@testable import Sonar

/// «Схожесть» вкуса (`Core/Account/TasteMatch.swift`) — зеркало ПК `windows/src/lib/taste-match.test.ts`:
/// цифры обязаны совпадать, иначе ПК, iPhone и сервер покажут другу разный процент.
final class TasteMatchTests: XCTestCase {
    private struct Like: TasteTrack, Equatable {
        let ref: String
        let title: String
        let artist: String
    }

    private func artist(_ name: String, _ plays: Int, ref: String? = nil) -> TasteArtist {
        TasteArtist(name: name, ref: ref, avatarURL: nil, plays: plays)
    }

    private func track(_ ref: String, _ artist: String = "A", _ title: String? = nil) -> Like {
        Like(ref: ref, title: title ?? ref, artist: artist)
    }

    private func likes(_ count: Int) -> [Like] {
        (0 ..< count).map { track("sc:\($0)") }
    }

    private func side(_ artists: [TasteArtist], _ likes: [Like] = []) -> TasteSide<Like> {
        TasteSide(artists: artists, likes: likes)
    }

    func testIdenticalIsHundredVery() {
        let me = side([artist("A", 10), artist("B", 5)], likes(20))
        let m = TasteMath.match(me: me, friend: me)
        XCTAssertEqual(m?.percent, 100)
        XCTAssertEqual(m?.level, .very)
    }

    func testNothingInCommonIsZero() {
        let m = TasteMath.match(me: side([artist("A", 10)], [track("sc:1")]),
                                friend: side([artist("B", 10)], [track("sc:2", "B")]))
        XCTAssertEqual(m?.percent, 0)
        XCTAssertEqual(m?.level, .different)
        XCTAssertEqual(m?.artists, [])
        XCTAssertEqual(m?.tracks, [])
    }

    func testArtistSharesWeighted() {
        // у меня A — 3/4, B — 1/4; у друга наоборот → 0.5 → √0.5 ≈ 71
        let m = TasteMath.match(me: side([artist("A", 30), artist("B", 10)]),
                                friend: side([artist("A", 10), artist("B", 30)]))
        XCTAssertEqual(m?.percent, 71)
        XCTAssertEqual(m?.level, .similar)
    }

    func testLikesUseFloorOfTwenty() {
        let mine = likes(40)
        let full = TasteMath.match(me: side([artist("A", 1)], mine), friend: side([artist("A", 1)], Array(mine.prefix(20))))
        XCTAssertEqual(full?.percent, 100)
        let few = TasteMath.match(me: side([artist("A", 1)], mine), friend: side([artist("A", 1)], Array(mine.prefix(2))))
        XCTAssertEqual(few?.percent, 85)
    }

    func testFallbacksAndNil() {
        XCTAssertEqual(TasteMath.match(me: side([artist("A", 1)]), friend: side([artist("A", 1)], [track("x")]))?.percent, 100)
        // только лайки: 1 / 20 → √0.05 ≈ 22
        XCTAssertEqual(TasteMath.match(me: side([], [track("x")]), friend: side([artist("A", 1)], [track("x")]))?.percent, 22)
        XCTAssertNil(TasteMath.match(me: side([]), friend: side([artist("A", 1)])))
    }

    func testCrossServiceArtistByName() {
        var theirs = artist("шипы", 5, ref: "yma:9")
        theirs.avatarURL = "https://img/a.jpg"
        let m = TasteMath.match(me: side([artist("Шипы ", 5, ref: "sca:1")]), friend: side([theirs]))
        XCTAssertEqual(m?.artists, [TasteArtist(name: "Шипы ", ref: "sca:1", avatarURL: "https://img/a.jpg", plays: 5)])
    }

    func testSharedArtistsOrderedByWeight() {
        let m = TasteMath.match(me: side([artist("A", 1), artist("B", 8), artist("C", 1)]),
                                friend: side([artist("A", 1), artist("B", 8), artist("D", 1)]))
        XCTAssertEqual(m?.artists.map(\.name), ["B", "A"])
    }

    func testSharedTracksByRefOrNameDedupedCapped() {
        let mine = [track("sc:1", "A", "Один"), track("ym:2", "B", "Два"), track("sc:3", "C"), track("sc:1", "A", "Один")]
        let theirs = [track("sc:1", "A", "Один"), track("sc:77", "b", "два")]
        XCTAssertEqual(TasteMath.match(me: side([], mine), friend: side([], theirs))?.tracks.map(\.ref), ["sc:1", "ym:2"])
        XCTAssertEqual(TasteMath.match(me: side([], likes(9)), friend: side([], likes(9)))?.tracks.count, TasteMath.tracksShown)
    }

    func testLevelThresholdsAndKey() {
        XCTAssertEqual([59, 60, 84, 85, 100].map(TasteMath.level), [.different, .similar, .similar, .very, .very])
        XCTAssertEqual(TasteMath.key("  Ёлка   и  Ко "), "елка и ко")
    }

    func testDemoFriendIsDeterministic() {
        let me = side([artist("A", 50), artist("B", 30), artist("C", 20), artist("D", 10)], likes(9))
        let friend = TasteMath.demoFriend(me)
        XCTAssertEqual(friend.likes.map(\.ref), ["sc:0", "sc:3", "sc:6"])
        let m = TasteMath.match(me: me, friend: friend)
        // как на ПК: √(0.7 · 0.377 + 0.3 · 0.15) ≈ 56
        XCTAssertEqual(m?.percent, 56)
        XCTAssertEqual(m?.artists.map(\.name).sorted(), ["A", "B", "D"])
        XCTAssertEqual(TasteMath.match(me: me, friend: TasteMath.demoFriend(me))?.percent, m?.percent)
    }
}
