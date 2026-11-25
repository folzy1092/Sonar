import XCTest
@testable import Sonar

/// Личные сообщения (`DMCore`) — те же случаи, что ПК `dm-core.test.ts`.
final class DMCoreTests: XCTestCase {
    private func msg(_ id: String, _ from: String, _ at: Int, _ text: String = "привет") -> DMMessage {
        DMMessage(id: id, threadID: "t1", from: from, text: text, sentAt: at)
    }

    private let thread = DMThread(id: "t1", peer: "ann", roomID: nil, peerReadAt: 200, myReadAt: 150)

    func testLinkRoundTrip() {
        let link = DMCore.link(.track, "sc:123")
        XCTAssertEqual(link, "sonar://track/sc:123")
        XCTAssertEqual(DMCore.parseLinks("лови \(link), огонь"), [SonarLink(kind: .track, value: "sc:123")])
    }

    func testSeveralKindsNoRepeatsTrailingPunctuation() {
        let text = "sonar://room/r42! и sonar://TRACK/ym:9. ещё раз sonar://track/ym:9 и sonar://album/ymalb:1)"
        XCTAssertEqual(DMCore.parseLinks(text), [
            SonarLink(kind: .room, value: "r42"),
            SonarLink(kind: .track, value: "ym:9"),
            SonarLink(kind: .album, value: "ymalb:1"),
        ])
    }

    func testCyrillicAndForeignSchemes() {
        XCTAssertEqual(DMCore.parseLinks(DMCore.link(.user, "фолзи")), [SonarLink(kind: .user, value: "фолзи")])
        XCTAssertEqual(DMCore.parseLinks("https://x.ru/track/1 sonar://play/liked sonar://track/"), [])
        XCTAssertEqual(DMCore.parseLinks("sonar://track/%E0%A4%A"), [])
    }

    func testAttachmentLinksOpenInDeepLink() throws {
        let track = DMAttachment.track(ref: "sc:1", title: "a", artist: "b", coverURL: nil)
        XCTAssertEqual(track.link, "sonar://track/sc:1")
        let url = try XCTUnwrap(URL(string: track.link))
        XCTAssertEqual(DeepLink(url), .track("sc:1"))
        XCTAssertEqual(DMAttachment.room(roomID: "r1", host: "h", title: "x").link, "sonar://room/r1")
        XCTAssertEqual(DeepLink(try XCTUnwrap(URL(string: "sonar://room/r1"))), .room("r1"))
    }

    func testDraft() {
        XCTAssertEqual(DMCore.checkDraft("   ", attachments: []), .failure(.empty))
        XCTAssertEqual(DMCore.checkDraft(" ", attachments: [.room(roomID: "r", host: "h", title: "t")]), .success(""))
        XCTAssertEqual(DMCore.checkDraft(String(repeating: "🎵", count: DMCore.maxText), attachments: []),
                       .success(String(repeating: "🎵", count: DMCore.maxText)))
        XCTAssertEqual(DMCore.checkDraft(String(repeating: "a", count: DMCore.maxText + 1), attachments: []), .failure(.tooLong))
    }

    func testEdit() {
        let mine = msg("1", "me", 0)
        var expected = mine
        expected.text = "ку"
        expected.editedAt = 10
        XCTAssertEqual(DMCore.edit(mine, me: "me", text: " ку ", now: 10), expected)
        XCTAssertNil(DMCore.edit(mine, me: "ann", text: "ку", now: 10))
        XCTAssertNil(DMCore.edit(mine, me: "me", text: "привет", now: 10))
        XCTAssertFalse(DMCore.canEdit(mine, me: "me", now: DMCore.editWindowMs + 1))
        var gone = mine
        gone.deleted = true
        XCTAssertNil(DMCore.edit(gone, me: "me", text: "ку", now: 10))
    }

    func testRetention30Days() {
        let now = DMCore.retentionMs + 1000
        XCTAssertEqual(DMCore.dropExpired([msg("old", "a", 999), msg("new", "a", 1000)], now: now).map(\.id), ["new"])
    }

    func testDelete() {
        var withRoom = msg("1", "me", 0, "x")
        withRoom.attachments = [.room(roomID: "r", host: "h", title: "t")]
        let d = DMCore.delete(withRoom, me: "me")
        XCTAssertEqual(d?.text, "")
        XCTAssertEqual(d?.attachments, [])
        XCTAssertEqual(d?.deleted, true)
        XCTAssertNil(DMCore.delete(msg("1", "ann", 0), me: "me"))
    }

    func testUnreadAndSeen() {
        var deleted = msg("4", "ann", 180, "")
        deleted.deleted = true
        let list = [msg("1", "ann", 100), msg("2", "ann", 160), msg("3", "me", 170), deleted]
        XCTAssertEqual(DMCore.unreadCount(thread, list, me: "me"), 1)
        XCTAssertTrue(DMCore.seenByPeer(thread, list[2], me: "me"))
        var early = thread
        early.peerReadAt = 100
        XCTAssertFalse(DMCore.seenByPeer(early, list[2], me: "me"))
    }

    func testReplyPreview() {
        XCTAssertEqual(DMCore.replyPreview(msg("1", "a", 0, "раз\nдва")), "раз")
        XCTAssertEqual(DMCore.replyPreview(msg("1", "a", 0, "абвгд"), max: 4), "абв…")
        var att = msg("1", "a", 0, "")
        att.attachments = [.track(ref: "sc:1", title: "Т", artist: "А", coverURL: nil)]
        XCTAssertEqual(DMCore.replyPreview(att), "А — Т")
        var gone = msg("1", "a", 0, "x")
        gone.deleted = true
        XCTAssertNil(DMCore.replyPreview(gone))
        XCTAssertNil(DMCore.replyPreview(nil))
    }

    func testTimelineAndRuns() {
        var other = msg("z", "x", 1)
        other.threadID = "t2"
        let list = [msg("b", "me", 20), msg("a", "ann", 10), msg("b", "me", 20, "правка"), other]
        let line = DMCore.timeline(list, thread: "t1")
        XCTAssertEqual(line.map(\.id), ["a", "b"])
        XCTAssertEqual(line[1].text, "правка")
        let runs = DMCore.groupRuns([msg("1", "a", 0), msg("2", "a", 1000), msg("3", "b", 2000), msg("4", "b", 2000 + 6 * 60_000)])
        XCTAssertEqual(runs.map { $0.map(\.id) }, [["1", "2"], ["3"], ["4"]])
    }
}
