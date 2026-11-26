import XCTest
@testable import Sonar

/// «Сейчас играет» на сервер — те же случаи, что в `now_push.rs` ПК.
final class NowPushTests: XCTestCase {
    private func track(_ ref: String) -> Track {
        Track(ref: ref, title: "Song \(ref)", artist: "A", artists: [], album: nil, durationMs: 200_000,
              coverURL: "https://c/\(ref).jpg", url: nil, explicit: false, available: true, plays: nil, tags: nil)
    }

    private func snap(_ count: Int, pos: Int) -> PlaybackSnapshot {
        PlaybackSnapshot(tracks: (0 ..< count).map { track("sc:\($0)") }, order: Array(0 ..< count), pos: pos,
                         position: 12.5, context: "Любимые", shuffle: false, repeatMode: .all, autoRefs: [])
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCurrentTrackGoesWithMeta() throws {
        let state = NowPush.state(snap(3, pos: 1), isPlaying: true, deviceId: "d1", now: now)
        XCTAssertEqual(state.ref, "sc:1")
        XCTAssertEqual(state.positionMs, 12_500)
        XCTAssertEqual(state.queue, ["sc:0", "sc:1", "sc:2"])
        XCTAssertEqual(state.queueIndex, 1)
        XCTAssertEqual(state.track, .init(title: "Song sc:1", artist: "A", coverURL: "https://c/sc:1.jpg", durationMs: 200_000))
        let json = try JSONValue(data: APIClient.encoder.encode(state))
        guard case let .object(o) = json else { return XCTFail("не объект") }
        XCTAssertEqual(o["repeat"], .string("all"))
        XCTAssertEqual(o["client_ts"], .int(1_800_000_000_000))
        XCTAssertNotNil(o["track"])
    }

    func testUnknownLengthComesFromPlayerOrIsOmitted() throws {
        var bare = track("sc:1")
        bare.durationMs = 0
        bare.coverURL = ""
        XCTAssertEqual(NowPush.meta(bare, playerDurationMs: 93_000).durationMs, 93_000, "длину знает плеер")
        let none = NowPush.meta(bare, playerDurationMs: 0)
        XCTAssertNil(none.durationMs)
        XCTAssertNil(none.coverURL)
        guard case let .object(o) = try JSONValue(data: APIClient.encoder.encode(none)) else { return XCTFail("не объект") }
        XCTAssertNil(o["duration_ms"], "не знаем — не шлём ноль")
        XCTAssertNil(o["cover_url"])
        XCTAssertEqual(NowPush.meta(track("sc:2"), playerDurationMs: 1).durationMs, 200_000, "своя длина важнее плеера")
    }

    func testLongQueueIsCutAroundCurrent() {
        let state = NowPush.state(snap(500, pos: 300), isPlaying: false, deviceId: "d1", now: now)
        XCTAssertEqual(state.queue.count, NowPush.queueMax)
        XCTAssertEqual(state.queue.first, "sc:250")
        XCTAssertEqual(state.queueIndex, NowPush.queueBefore)
        XCTAssertEqual(state.queue[state.queueIndex!], "sc:300")
    }

    func testNothingPlayingIsStopped() {
        let state = NowPush.state(nil, isPlaying: true, deviceId: "d1", now: now)
        XCTAssertNil(state.ref)
        XCTAssertFalse(state.isPlaying)
        XCTAssertNil(state.track)
    }

    func testPusherSendsPut() async {
        let api = FakeAPI()
        api.on("PUT /player/state", 204, "")
        let client = APIClient(base: URL(string: "https://try-sonar.ru/api")!, token: "tok", fetch: api.fetch)
        let state = NowPush.state(snap(2, pos: 0), isPlaying: true, deviceId: "d1", now: now)

        await NowPusher().submit(state, client: client)

        XCTAssertEqual(api.count("PUT /player/state"), 1)
        guard case let .object(o)? = api.body("PUT /player/state") else { return XCTFail("нет тела") }
        XCTAssertEqual(o["ref"], .string("sc:0"))
        XCTAssertEqual(o["device_id"], .string("d1"))
    }
}
