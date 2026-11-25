import XCTest
@testable import Sonar

/// Устройство для тестов синка: свои хранилища в temp и движок поверх них.
@MainActor
private final class Device {
    let library: LibraryStore
    let settings: SettingsStore
    var offsets: [String: Int] = [:]
    var plays: [PlayRow] = []
    var clock: Int64 = 1_800_000_000_000
    private(set) var engine: SyncEngine!

    init(_ id: String, dir: URL = tempDirectory()) {
        library = LibraryStore(file: dir.appendingPathComponent("library.json"))
        settings = SettingsStore(storage: UserDefaults(suiteName: "sync-\(UUID().uuidString)")!)
        let now = { [unowned self] in self.clock }
        engine = SyncEngine(
            deviceId: id,
            adapters: [
                LikesSyncAdapter(library: library, now: now),
                DislikesSyncAdapter(library: library, artist: { [unowned self] ref in self.library.liked.first { $0.ref == ref }?.artist }, now: now),
                TrackPrefsSyncAdapter(library: library, offsets: { [unowned self] in self.offsets },
                                      setOffset: { [unowned self] ref, ms in self.offsets[ref] = ms }),
                SettingsSyncAdapter(settings: settings),
            ],
            file: dir.appendingPathComponent("sync.json"),
            plays: { [unowned self] since in PlayUpload.from(self.plays, since: since, now: Date(timeIntervalSince1970: Double(self.clock) / 1000)) },
            now: now)
    }

    func tick(_ ms: Int64 = 10) { clock += ms }

    func sync(_ server: SyncTransport) async throws -> SyncReport {
        try await engine.syncOnce(server)
    }
}

@MainActor
final class SyncTests: XCTestCase {
    func testTwoDevicesShareLikesSettingsDislikesAndTrackPrefs() async throws {
        let server = MemorySyncServer()
        let a = Device("ios-a"), b = Device("pc-b")
        a.library.toggleLike(makeTrack("sc:1", "A"))
        a.tick()
        a.library.toggleLike(makeTrack("ym:5", "B"))
        a.library.toggleLike(makeTrack("sc:2", "C"))
        a.library.toggleLike(makeTrack("sc:2", "C")) // снят — не должен приехать лайком
        a.library.toggleDislike(makeTrack("sc:9", "Bad"))
        a.library.rememberSound(TrackSound(rate: 0.8, linked: true, reverb: 0.4, eq: Array(repeating: 2, count: 12)), for: "sc:1")
        a.offsets["sc:1"] = 250
        a.settings.set("appearance.animations", false)
        a.settings.set("wave.mode", .string("sad"))
        a.settings.set("audio.quality", .string("high")) // устройство
        a.settings.set("update.channel", .string("beta")) // устройство

        let ra = try await a.sync(server)
        XCTAssertGreaterThanOrEqual(ra.pushed, 6, "\(ra)")
        let again = try await a.sync(server)
        XCTAssertEqual(again.pushed, 0, "своё вернулось с сервера и обратно не поехало")
        let quality = await server.value("setting", "audio.quality")
        XCTAssertNil(quality, "качество — настройка устройства")

        let rb = try await b.sync(server)
        XCTAssertGreaterThanOrEqual(rb.pulled, 6)
        XCTAssertEqual(b.library.liked.map(\.ref), ["ym:5", "sc:1"], "порядок как на A, снятый лайк не приехал")
        XCTAssertEqual(b.library.liked.first?.title, "Song ym:5", "карточка трека приехала с лайком")
        XCTAssertEqual(b.library.disliked, ["sc:9"])
        XCTAssertEqual(b.library.sound(for: "sc:1"), TrackSound(rate: 0.8, linked: true, reverb: 0.4, eq: Array(repeating: 2, count: 12)))
        XCTAssertNil(b.library.sound(for: "ym:5"), "другие треки — по общим настройкам")
        let pushedSound = await server.value("track_pref", "sc:1")
        XCTAssertEqual(pushedSound?["speed"].number, 0.8, "скорость рядом — для старых клиентов")
        XCTAssertEqual(b.offsets["sc:1"], 250)
        XCTAssertFalse(b.settings.bool("appearance.animations"))
        XCTAssertEqual(b.settings.string("wave.mode"), "sad")
        XCTAssertEqual(b.settings.string("audio.quality"), "lossless", "своё качество не перезаписано")
        XCTAssertEqual(b.settings.string("update.channel"), "stable")
        let back = try await b.sync(server)
        XCTAssertEqual(back.pushed, 0, "чужое не отправляется обратно")

        // B снял лайк и 👎 — A получает удаления
        b.library.toggleLike(makeTrack("sc:1", "A"))
        b.library.toggleDislike(makeTrack("sc:9", "Bad"))
        b.library.rememberSound(nil, for: "sc:1")
        b.offsets["sc:1"] = nil
        _ = try await b.sync(server)
        _ = try await a.sync(server)
        XCTAssertEqual(a.library.liked.map(\.ref), ["ym:5"])
        XCTAssertTrue(a.library.disliked.isEmpty)
        XCTAssertNil(a.library.sound(for: "sc:1"))
        XCTAssertNil(a.offsets["sc:1"])
        let quiet = try await a.sync(server)
        XCTAssertEqual(quiet.pushed, 0)
    }

    func testTrackSourceRidesSyncBothWays() async throws {
        let server = MemorySyncServer()
        let a = Device("ios-a"), b = Device("pc-b")
        a.library.rememberSource(.ym, for: "sc:1")
        _ = try await a.sync(server)
        let pushed = await server.value("track_pref", "sc:1")
        XCTAssertEqual(pushed?["source"].string, "ym", "ключ сервиса — как на ПК")
        _ = try await b.sync(server)
        XCTAssertEqual(b.library.source(for: "sc:1"), .ym, "на другом устройстве — то же")
        b.tick()
        b.library.rememberSource(nil, for: "sc:1")
        _ = try await b.sync(server)
        _ = try await a.sync(server)
        XCTAssertNil(a.library.source(for: "sc:1"), "«Авто» приехало обратно")
    }

    func testOwnPendingChangeBeatsIncomingAndLaterSettingWins() async throws {
        let server = MemorySyncServer()
        let a = Device("a"), b = Device("b")
        b.clock = a.clock + 5
        a.settings.set("wave.mode", .string("sad"))
        _ = try await a.sync(server)
        // B поменял то же позже, ещё не отправив
        b.settings.set("wave.mode", .string("fun"))
        _ = try await b.sync(server)
        XCTAssertEqual(b.settings.string("wave.mode"), "fun", "своё неотправленное не затёрто")
        _ = try await a.sync(server)
        XCTAssertEqual(a.settings.string("wave.mode"), "fun", "позднее победило")

        // A меняет с более ранним временем (часы отстают) — сервер оставляет позднее
        a.clock = b.clock - 1000
        a.settings.set("wave.mode", .string("calm"))
        _ = try await a.sync(server)
        XCTAssertEqual(a.settings.string("wave.mode"), "fun", "раннее по client_ts проиграло")
    }

    func testFailedPushKeepsChangesPending() async throws {
        struct Down: SyncTransport {
            struct Offline: Error {}
            func push(_ ops: [SyncOp]) async throws -> SyncPushReply { throw Offline() }
            func pull(since: Int) async throws -> SyncPullReply { throw Offline() }
            func plays(_ plays: [PlayUpload]) async throws -> Int { throw Offline() }
        }
        struct Partial: SyncTransport {
            func push(_ ops: [SyncOp]) async throws -> SyncPushReply { SyncPushReply(applied: []) }
            func pull(since: Int) async throws -> SyncPullReply { SyncPullReply(rev: 0, changes: []) }
            func plays(_ plays: [PlayUpload]) async throws -> Int { 0 }
        }
        let a = Device("a")
        a.library.toggleLike(makeTrack("sc:1", "A"))
        do { _ = try await a.sync(Down()); XCTFail() } catch {}
        XCTAssertEqual(a.engine.pendingOps().ops.count, 1, "не отправилось — осталось")
        do { _ = try await a.sync(Partial()); XCTFail() } catch {
            XCTAssertEqual(error as? SyncError, .partial(applied: 0, sent: 1))
        }
        XCTAssertEqual(a.engine.pendingOps().ops.count, 1)
        let report = try await a.sync(MemorySyncServer())
        XCTAssertEqual(report.pushed, 1)
    }

    func testOpIdsStableForRetriesAndJournalPersists() throws {
        let dir = tempDirectory()
        let a = Device("dev-1", dir: dir)
        a.library.toggleLike(makeTrack("sc:1", "A"))
        a.engine.scan()
        let first = a.engine.pendingOps(), second = a.engine.pendingOps()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.ops.first?.opId, "dev-1:like:sc:1:1")
        let json = try JSONValue(data: JSONEncoder().encode(first.ops[0]))
        XCTAssertEqual(json["type"].string, "like")
        XCTAssertNotNil(json["client_ts"].int)
        XCTAssertEqual(json["value"]["kind"].string, "track")
        XCTAssertEqual(json["value"]["track"]["ref"].string, "sc:1")
        XCTAssertTrue(json["rev"].isNull, "локальный rev на сервер не едет")

        // перезапуск — журнал из файла, лишних операций нет
        let restarted = Device("dev-1", dir: dir)
        XCTAssertEqual(restarted.engine.scan(), 0)
        XCTAssertEqual(restarted.engine.pendingOps().ops.map(\.opId), first.ops.map(\.opId))
    }

    func testDeletionIsExplicitNull() throws {
        let a = Device("a")
        a.library.toggleLike(makeTrack("sc:1", "A"))
        a.engine.scan()
        a.engine.markPushed(a.engine.pendingOps().upto)
        a.library.toggleLike(makeTrack("sc:1", "A"))
        a.engine.scan()
        let op = try XCTUnwrap(a.engine.pendingOps().ops.first)
        XCTAssertTrue(op.value.isNull)
        let text = String(decoding: try JSONEncoder().encode(op), as: UTF8.self)
        XCTAssertTrue(text.contains(#""value":null"#), text)
    }

    func testReorderOnPhoneMovesOneLikeAndOrderMatchesOnOtherDevice() async throws {
        let server = MemorySyncServer()
        let a = Device("a"), b = Device("b")
        for (i, ref) in ["sc:1", "sc:2", "sc:3", "sc:4"].enumerated() {
            a.clock += 1000
            a.library.toggleLike(makeTrack(ref, "A\(i)"))
        }
        _ = try await a.sync(server)
        _ = try await b.sync(server)
        XCTAssertEqual(b.library.liked.map(\.ref), ["sc:4", "sc:3", "sc:2", "sc:1"])
        // самый старый — наверх
        a.library.moveLiked(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        a.engine.scan()
        XCTAssertEqual(a.engine.pendingOps().ops.map(\.key), ["sc:1"], "перенос меняет только перенесённый")
        // и в середину
        _ = try await a.sync(server)
        a.library.moveLiked(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        a.engine.scan()
        XCTAssertEqual(a.engine.pendingOps().ops.map(\.key), ["sc:1"])
        _ = try await a.sync(server)
        _ = try await b.sync(server)
        XCTAssertEqual(b.library.liked.map(\.ref), a.library.liked.map(\.ref))
        XCTAssertEqual(b.library.liked.map(\.ref), ["sc:4", "sc:3", "sc:1", "sc:2"])
    }

    func testLikeOrderMath() {
        XCTAssertEqual(LikeOrder.addedTimes(order: ["a", "b"], known: [:], now: 1_000_000), [1_000_000, 999_000])
        // новый сверху — «сейчас», остальные как были
        XCTAssertEqual(LikeOrder.addedTimes(order: ["n", "a", "b"], known: ["a": 50_000, "b": 40_000], now: 1_000_000),
                       [1_000_000, 50_000, 40_000])
        // перенесённый между соседями — середина
        XCTAssertEqual(LikeOrder.addedTimes(order: ["a", "c", "b"], known: ["a": 50, "b": 40, "c": 10], now: 100), [50, 45, 40])
        // тесно — сдвиг вниз, порядок строго убывает
        let tight = LikeOrder.addedTimes(order: ["a", "c", "b"], known: ["a": 50, "b": 49, "c": 10], now: 100)
        XCTAssertEqual(tight[0], 50)
        XCTAssertTrue(zip(tight, tight.dropFirst()).allSatisfy { $0 > $1 }, "\(tight)")
        XCTAssertEqual(LikeOrder.longestDecreasing([5, nil, 1, 4, 3]), [0, 3, 4])
        XCTAssertEqual(LikeOrder.insertIndex(45, times: [50, 40]), 1)
        XCTAssertEqual(LikeOrder.insertIndex(60, times: [50, 40]), 0)
        XCTAssertEqual(LikeOrder.insertIndex(1, times: [50, 40]), 2)
    }

    func testForeignRowsKeptAndNotDeleted() async throws {
        let server = MemorySyncServer()
        // ПК прислал плейлист, лайк альбома и настройку-объект — телефон их не хранит
        _ = try await server.push([
            SyncOp(opId: "pc:playlist:pl_1:1", type: "playlist", key: "pl_1", value: .object(["name": .string("ночь")]), clientTs: 1, rev: 1),
            SyncOp(opId: "pc:like:ymalb:9:2", type: "like", key: "ymalb:9", value: .object(["kind": .string("album"), "added_at": .int(5)]), clientTs: 1, rev: 2),
            SyncOp(opId: "pc:setting:player.tempo:3", type: "setting", key: "appearance.grid", value: .object(["rate": .int(1)]), clientTs: 1, rev: 3),
        ])
        let a = Device("a")
        let report = try await a.sync(server)
        XCTAssertEqual(report.pulled, 0, "ничего не применено")
        XCTAssertNotNil(a.engine.journal.value("playlist", "pl_1"), "лежит в журнале")
        let again = try await a.sync(server)
        XCTAssertEqual(again.pushed, 0, "чужое не превращается в удаление")
        let album = await server.value("like", "ymalb:9")
        XCTAssertEqual(album?["kind"].string, "album")
    }

    func testPlaysUploadOnceAndHoldBackPlaying() async throws {
        let server = MemorySyncServer()
        let a = Device("a")
        let base = Date(timeIntervalSince1970: Double(a.clock) / 1000)
        a.plays = [
            PlayRow(ref: "sc:1", artist: "A", at: base.addingTimeInterval(-7200), ms: 200_000),
            PlayRow(ref: "sc:2", artist: "B", at: base.addingTimeInterval(-60), ms: 30_000), // ещё играет
        ]
        let first = try await a.sync(server)
        XCTAssertEqual(first.plays, 1)
        let none = try await a.sync(server)
        XCTAssertEqual(none.plays, 0)
        a.clock += 2 * 3600 * 1000
        let later = try await a.sync(server)
        XCTAssertEqual(later.plays, 1, "дослушанное ушло позже")
        let total = await server.playsCount
        XCTAssertEqual(total, 2)
    }

    func testResetForgetsJournalButKeepsLibrary() throws {
        let a = Device("a")
        a.library.toggleLike(makeTrack("sc:1", "A"))
        a.engine.scan()
        a.engine.reset()
        XCTAssertEqual(a.engine.journal.rows.count, 0)
        XCTAssertEqual(a.library.liked.count, 1)
        XCTAssertEqual(a.engine.scan(), 1, "после входа в другой аккаунт всё уйдёт заново")
    }
}

/// Сервер отдаёт `pull` страницами (`more`, ~1 МБ): HTTP-транспорт забирает их подряд за один обмен.
final class HTTPSyncPagingTests: XCTestCase {
    func testPullFollowsMorePages() async throws {
        let pages: [String: String] = [
            "0": #"{"rev":2,"changes":[{"type":"like","key":"sc:1","value":null,"rev":1},{"type":"like","key":"sc:2","value":null,"rev":2}],"more":true}"#,
            "2": #"{"rev":7,"changes":[{"type":"like","key":"sc:3","value":null,"rev":3}],"more":false}"#,
        ]
        let fetch: APIClient.Fetch = { request in
            let since = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "since" }?.value ?? ""
            return (Data((pages[since] ?? #"{"rev":0,"changes":[]}"#).utf8), 200)
        }
        let transport = HTTPSyncTransport(client: APIClient(base: URL(string: "https://try-sonar.ru/api")!, token: "t", fetch: fetch))
        let reply = try await transport.pull(since: 0)
        XCTAssertEqual(reply.changes.map(\.key), ["sc:1", "sc:2", "sc:3"])
        XCTAssertEqual(reply.rev, 7)
    }
}
