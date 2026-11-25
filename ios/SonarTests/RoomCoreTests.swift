import XCTest
@testable import Sonar

/// Комнаты (`RoomCore`, `RoomSync`) — те же случаи, что ПК `room-core.test.ts` / `room-sync.test.ts`.
final class RoomCoreTests: XCTestCase {
    private func m(_ username: String) -> RoomMember { RoomMember(username: username) }

    private func ok(_ result: Result<Room, RoomError>, file: StaticString = #filePath, line: UInt = #line) -> Room {
        switch result {
        case let .success(room): return room
        case let .failure(error):
            XCTFail("ошибка \(error)", file: file, line: line)
            return RoomCore.newRoom(id: "x", host: m("x"), queue: [], serverNow: 0)
        }
    }

    private func err(_ room: Room, _ by: String, _ op: RoomOp, now: Int = 2000) -> RoomError? {
        if case let .failure(error) = RoomCore.apply(room, by: by, op, serverNow: now) { return error }
        return nil
    }

    private func room() -> Room {
        var r = RoomCore.newRoom(id: "r1", host: m("host"), queue: ["sc:1", "ym:2", "sc:3"], serverNow: 1000)
        for u in ["dj", "ann"] { r = ok(RoomCore.apply(r, by: u, .join(m(u)), serverNow: 1000)) }
        return ok(RoomCore.apply(r, by: "host", .djSet(username: "dj", on: true), serverNow: 1000))
    }

    func testRoles() {
        let r = room()
        XCTAssertEqual(RoomCore.roles(r, "host"), [.host, .leader])
        XCTAssertEqual(RoomCore.mainRole(r, "dj"), .dj)
        XCTAssertEqual(RoomCore.mainRole(r, "ann"), .listener)
        XCTAssertEqual(RoomCore.roles(r, "stranger"), [])
    }

    func testRights() {
        let r = room()
        XCTAssertTrue(RoomCore.can(r, "host", .play(position: nil)))
        XCTAssertFalse(RoomCore.can(r, "dj", .play(position: nil)))
        XCTAssertTrue(RoomCore.can(r, "dj", .queueAdd(ref: "a")))
        XCTAssertFalse(RoomCore.can(r, "ann", .queueAdd(ref: "a")))
        XCTAssertTrue(RoomCore.can(r, "ann", .suggest(ref: "a")))
        XCTAssertFalse(RoomCore.can(r, "dj", .close))
        XCTAssertFalse(RoomCore.can(r, "stranger", .suggest(ref: "a")))
    }

    func testOpensPausedAndRevGrowsOnlyOnAccepted() {
        let r = room()
        XCTAssertFalse(r.playing)
        XCTAssertEqual(err(r, "ann", .play(position: nil)), .forbidden)
        let played = ok(RoomCore.apply(r, by: "host", .play(position: nil), serverNow: 2000))
        XCTAssertEqual(played.rev, r.rev + 1)
        XCTAssertEqual(err(played, "host", .play(position: nil)), .noop)
    }

    func testPassLeaderKeepsPosition() {
        let r = ok(RoomCore.apply(room(), by: "host", .play(position: 10_000), serverNow: 2000))
        let passed = ok(RoomCore.apply(r, by: "host", .leaderSet(username: "ann"), serverNow: 5000))
        XCTAssertEqual(passed.leader, "ann")
        XCTAssertEqual(RoomCore.anchorPosition(passed, serverNow: 5000), 13_000)
        XCTAssertTrue(RoomCore.can(passed, "ann", .pause(position: 0)))
        XCTAssertFalse(RoomCore.can(passed, "host", .pause(position: 0)))
        XCTAssertTrue(RoomCore.can(passed, "host", .leaderSet(username: "dj")))
        XCTAssertEqual(err(passed, "host", .leaderSet(username: "nope")), .noUser)
    }

    func testLeaderLeavesThenHostLeaves() {
        let r = ok(RoomCore.apply(room(), by: "host", .leaderSet(username: "dj"), serverNow: 2000))
        let left = ok(RoomCore.apply(r, by: "dj", .leave, serverNow: 3000))
        XCTAssertEqual(left.leader, "host")
        XCTAssertEqual(left.djs, [])
        let closed = ok(RoomCore.apply(left, by: "host", .leave, serverNow: 3000))
        XCTAssertTrue(closed.closed)
        XCTAssertEqual(err(closed, "ann", .suggest(ref: "x")), .closed)
    }

    func testFreeFourDeepEight() {
        var r = room()
        r = ok(RoomCore.apply(r, by: "n4", .join(m("n4")), serverNow: 1))
        XCTAssertEqual(err(r, "n5", .join(m("n5"))), .full)
        XCTAssertNotNil(try? RoomCore.apply(r, by: "n5", .join(m("n5")), serverNow: 1, maxMembers: RoomCore.limit(hostHasDeep: true)).get())
        XCTAssertEqual([RoomCore.limit(hostHasDeep: false), RoomCore.limit(hostHasDeep: true)], [4, 8])
    }

    func testMemberLimitAndRejoin() {
        var r = room()
        XCTAssertEqual(err(r, "ann", .join(m("ann"))), .noop)
        XCTAssertEqual(err(r, "x", .join(m("y"))), .forbidden)
        r = ok(RoomCore.apply(r, by: "n4", .join(m("n4")), serverNow: 1, maxMembers: 4))
        if case let .failure(error) = RoomCore.apply(r, by: "n5", .join(m("n5")), serverNow: 1, maxMembers: 4) {
            XCTAssertEqual(error, .full)
        } else {
            XCTFail("пятый зашёл в комнату на четверых")
        }
    }

    func testPauseAndResume() {
        var r = ok(RoomCore.apply(room(), by: "host", .play(position: 0), serverNow: 1000))
        XCTAssertEqual(RoomCore.anchorPosition(r, serverNow: 4000), 3000)
        r = ok(RoomCore.apply(r, by: "host", .pause(position: 3000), serverNow: 4000))
        XCTAssertEqual(RoomCore.anchorPosition(r, serverNow: 9000), 3000)
        r = ok(RoomCore.apply(r, by: "host", .play(position: nil), serverNow: 9000))
        XCTAssertEqual(RoomCore.anchorPosition(r, serverNow: 10_000), 4000)
    }

    func testNextStartsAfterWarmup() {
        let playing = ok(RoomCore.apply(room(), by: "host", .play(position: nil), serverNow: 1000))
        let r = ok(RoomCore.apply(playing, by: "host", .next, serverNow: 5000))
        XCTAssertEqual(r.pos, 1)
        XCTAssertEqual(r.anchor, RoomAnchor(serverTs: 5000 + RoomCore.startDelayMs, position: 0))
        XCTAssertEqual(RoomCore.anchorPosition(r, serverNow: 5000), 0)
        XCTAssertEqual(RoomCore.anchorPosition(r, serverNow: 5000 + RoomCore.startDelayMs + 200), 200)
    }

    func testPrevRestartsOrGoesBack() {
        var r = ok(RoomCore.apply(room(), by: "host", .jump(index: 2), serverNow: 0))
        r = ok(RoomCore.apply(r, by: "host", .seek(position: 60_000), serverNow: 1000))
        let restart = ok(RoomCore.apply(r, by: "host", .prev, serverNow: 1000))
        XCTAssertEqual(restart.pos, 2)
        XCTAssertEqual(restart.anchor.position, 0)
        XCTAssertEqual(ok(RoomCore.apply(restart, by: "host", .prev, serverNow: 1000)).pos, 1)
        XCTAssertEqual(err(r, "host", .next), .badIndex)
    }

    func testQueueEditKeepsPlayingTrack() {
        var r = ok(RoomCore.apply(room(), by: "host", .jump(index: 1), serverNow: 0))
        r = ok(RoomCore.apply(r, by: "dj", .queueAdd(ref: "sc:9"), serverNow: 0))
        XCTAssertEqual(r.queue.last, RoomItem(ref: "sc:9", addedBy: "dj"))
        XCTAssertEqual(err(r, "dj", .queueRemove(index: 1)), .badIndex)
        r = ok(RoomCore.apply(r, by: "dj", .queueRemove(index: 0), serverNow: 0))
        XCTAssertEqual(r.queue[r.pos].ref, "ym:2")
        XCTAssertEqual(r.pos, 0)
        r = ok(RoomCore.apply(r, by: "dj", .queueMove(from: 2, to: 0), serverNow: 0))
        XCTAssertEqual(r.queue.map(\.ref), ["sc:9", "ym:2", "sc:3"])
        XCTAssertEqual(r.queue[r.pos].ref, "ym:2")
    }

    func testMovedPos() {
        XCTAssertEqual(RoomCore.movedPos(2, from: 2, to: 0), 0)
        XCTAssertEqual(RoomCore.movedPos(2, from: 0, to: 3), 1)
        XCTAssertEqual(RoomCore.movedPos(2, from: 4, to: 1), 3)
        XCTAssertEqual(RoomCore.movedPos(2, from: 3, to: 4), 2)
    }

    func testSuggestAndClose() {
        let r = room()
        XCTAssertEqual(err(r, "ann", .suggest(ref: "sc:7")), .noop)
        XCTAssertEqual(err(r, "dj", .close), .forbidden)
        XCTAssertTrue(ok(RoomCore.apply(r, by: "host", .close, serverNow: 0)).closed)
    }

    func testSnapshotOnlyNewer() {
        let r = room()
        var newer = r
        newer.rev += 1
        newer.pos = 2
        XCTAssertEqual(RoomCore.accept(local: r, incoming: newer), newer)
        XCTAssertEqual(RoomCore.accept(local: newer, incoming: r), newer)
        XCTAssertEqual(RoomCore.accept(local: nil, incoming: r), r)
        var other = r
        other.id = "other"
        other.rev = 0
        XCTAssertEqual(RoomCore.accept(local: r, incoming: other).id, "other")
    }

    func testSnapshotDecodesPcJson() throws {
        let json = #"{"id":"r","host":"h","leader":"h","djs":[],"members":[{"username":"h","display_name":null,"avatar_url":null}],"queue":[{"ref":"sc:1","added_by":"h"}],"pos":0,"playing":true,"anchor":{"server_ts_ms":5,"position_ms":7},"rev":3,"closed":false}"#
        let room = try JSONDecoder().decode(Room.self, from: Data(json.utf8))
        XCTAssertEqual(room.anchor, RoomAnchor(serverTs: 5, position: 7))
        XCTAssertEqual(room.queue.first?.addedBy, "h")
    }

    func testErrorsHaveTranslatedMessages() {
        let keys = [RoomError.closed, .forbidden, .full, .notMember, .badIndex, .noUser].compactMap(\.message)
            + [RoomRole.host, .leader, .dj, .listener].map(\.title)
        for key in keys {
            XCTAssertNotNil(I18n.windowsEN[key], key)
        }
        XCTAssertNil(RoomError.noop.message)
    }

    func testDemoRoomAndChat() {
        let me = RoomMember(username: "me")
        let members = SocialDemo.members(me: me, friendName: "Друг", friend2Name: "Второй друг")
        let tracks = (1 ... 10).map { makeTrack("sc:\($0)", "A\($0)") }
        let room = SocialDemo.room(members: members, tracks: tracks, now: 1000)
        XCTAssertEqual(room.members.count, 3)
        XCTAssertEqual(room.queue.count, 8)
        XCTAssertEqual(room.queue[1].addedBy, SocialDemo.friend)
        XCTAssertTrue(room.playing)
        XCTAssertEqual(RoomCore.mainRole(room, SocialDemo.friend), .dj)
        XCTAssertEqual(RoomCore.mainRole(room, SocialDemo.friend2), .listener)
        let lines = SocialDemo.Lines(hey: "a", fire: "b", join: "c", room: "d")
        let chat = SocialDemo.chat(me: "me", tracks: tracks, roomTitle: "R", lines: lines, now: 10_000_000)
        XCTAssertEqual(DMCore.unreadCount(chat.threads[0], chat.messages, me: "me"), 1)
        XCTAssertEqual(DMCore.timeline(chat.messages, thread: "dm_friend").map(\.id), ["m1", "m2", "m3", "m4"])
        XCTAssertTrue(SocialDemo.room(members: members, tracks: [], now: 0).queue.isEmpty)
    }

    // MARK: синхронизация

    func testClockOffsetPicksMinRtt() {
        let est = RoomSync.clockOffset([
            ClockSample(sent: 0, server: 5300, received: 400),
            ClockSample(sent: 1000, server: 6020, received: 1040),
            ClockSample(sent: 2000, server: 7150, received: 2200),
        ])
        XCTAssertEqual(est, ClockEstimate(offset: 5000, rtt: 40))
        XCTAssertEqual(RoomSync.serverTime(localNow: 10_000, clock: est), 15_000)
        XCTAssertNil(RoomSync.clockOffset([]))
        XCTAssertNil(RoomSync.clockOffset([ClockSample(sent: 10, server: 0, received: 5)]))
    }

    func testSyncActions() {
        let anchor = RoomAnchor(serverTs: 0, position: 0)
        XCTAssertEqual(RoomSync.action(playing: true, anchor: anchor, localPosition: 10_100, serverNow: 10_000), .none(drift: -100))
        XCTAssertEqual(RoomSync.action(playing: true, anchor: anchor, localPosition: 9000, serverNow: 10_000),
                       .nudge(rate: 1 + RoomSync.rate, drift: 1000))
        XCTAssertEqual(RoomSync.action(playing: true, anchor: anchor, localPosition: 11_000, serverNow: 10_000),
                       .nudge(rate: 1 - RoomSync.rate, drift: -1000))
        XCTAssertEqual(RoomSync.action(playing: true, anchor: RoomAnchor(serverTs: 0, position: 5000), localPosition: 1000, serverNow: 10_000),
                       .seek(position: 15_000, drift: 14_000))
        let paused = RoomAnchor(serverTs: 0, position: 30_000)
        XCTAssertEqual(RoomSync.action(playing: false, anchor: paused, localPosition: 29_000, serverNow: 99_000),
                       .seek(position: 30_000, drift: 1000))
        XCTAssertEqual(RoomSync.action(playing: true, anchor: RoomAnchor(serverTs: 11_500, position: 0), localPosition: 0, serverNow: 10_000),
                       .wait(startIn: 1500))
        XCTAssertEqual(RoomSync.nudgeDuration(1000), 33_333)
    }
}
