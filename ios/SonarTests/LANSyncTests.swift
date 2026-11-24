import XCTest
@testable import Sonar

/// ПК по Wi‑Fi: синк как у сервера, но прослушивания не берёт.
private actor NoPlays: SyncTransport {
    let inner = MemorySyncServer()
    private(set) var playCalls = 0
    nonisolated var sendsPlays: Bool { false }
    func push(_ ops: [SyncOp]) async throws -> SyncPushReply { try await inner.push(ops) }
    func pull(since: Int) async throws -> SyncPullReply { try await inner.pull(since: since) }
    func plays(_ plays: [PlayUpload]) async throws -> Int {
        playCalls += 1
        return plays.count
    }
}

/// Синк с ПК по Wi‑Fi (пока нет сервера): сообщения, страницы `sync_pull`, выбор стороны, какой ПК помним,
/// смена стороны в журнале и что прослушивания на ПК не уходят.
@MainActor
final class LANSyncTests: XCTestCase {
    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // MARK: - Сообщения

    func testPushEnvelopeCarriesOpsWithoutLocalRev() throws {
        let op = SyncOp(opId: "d:like:sc:1:3", type: "like", key: "sc:1", value: .null, clientTs: 42, rev: 3)
        let json = try object(RemoteSync.push([op], id: "s1"))
        XCTAssertEqual(json["v"] as? Int, RemoteProtocol.version)
        XCTAssertEqual(json["type"] as? String, "sync_push")
        XCTAssertEqual(json["id"] as? String, "s1")
        let ops = try XCTUnwrap((json["body"] as? [String: Any])?["ops"] as? [[String: Any]])
        XCTAssertEqual(ops.first?["op_id"] as? String, "d:like:sc:1:3")
        XCTAssertEqual(ops.first?["client_ts"] as? Int, 42)
        XCTAssertTrue(ops.first?["value"] is NSNull, "удаление — явный null")
        XCTAssertNil(ops.first?["rev"], "локальный rev на ПК не едет")
    }

    func testPullEnvelope() throws {
        let json = try object(RemoteSync.pull(since: 17, id: "s2"))
        XCTAssertEqual(json["type"] as? String, "sync_pull")
        XCTAssertEqual((json["body"] as? [String: Any])?["since"] as? Int, 17)
    }

    func testDecodeReplies() throws {
        let pushed = try RemoteSync.decode(#"{"v":1,"type":"sync_push","re":"a","body":{"rev":5,"applied":["x","y"]}}"#)
        XCTAssertEqual(pushed.re, "a")
        XCTAssertEqual(pushed.reply, .pushed(SyncPushReply(applied: ["x", "y"])))

        let pulled = try RemoteSync.decode(
            #"{"v":1,"type":"sync_pull","re":"b","body":{"rev":9,"more":true,"changes":[{"type":"like","key":"sc:1","value":null,"rev":9}]}}"#)
        XCTAssertEqual(pulled.reply, .pulled(SyncPullReply(rev: 9, changes: [SyncChange(type: "like", key: "sc:1", value: .null, rev: 9)]), more: true))

        let noMore = try RemoteSync.decode(#"{"v":1,"type":"sync_pull","re":"c","body":{"rev":0,"changes":[]}}"#)
        XCTAssertEqual(noMore.reply, .pulled(SyncPullReply(rev: 0, changes: []), more: false), "без more — всё отдано")

        let error = try RemoteSync.decode(#"{"v":1,"type":"error","re":"d","body":{"code":"not_paired"}}"#)
        XCTAssertEqual(error.reply, .error(code: "not_paired"))

        let state = try RemoteSync.decode(#"{"v":1,"type":"state","body":{}}"#)
        XCTAssertNil(state.re)
        XCTAssertEqual(state.reply, .other(type: "state"))
    }

    func testDecodeRejectsBadInput() {
        XCTAssertThrowsError(try RemoteSync.decode("не json")) { XCTAssertEqual($0 as? RemoteDecodeError, .badJSON) }
        XCTAssertThrowsError(try RemoteSync.decode(#"{"v":2,"type":"sync_pull","body":{}}"#)) {
            XCTAssertEqual($0 as? RemoteDecodeError, .badVersion(2))
        }
        XCTAssertThrowsError(try RemoteSync.decode(#"{"v":1,"type":"sync_pull","body":{"rev":"x"}}"#)) {
            XCTAssertEqual($0 as? RemoteDecodeError, .badBody("sync_pull"))
        }
    }

    // MARK: - Страницы sync_pull

    func testPullAllFollowsMoreAndAccumulates() async throws {
        var asked: [Int] = []
        let pages: [Int: (SyncPullReply, Bool)] = [
            0: (SyncPullReply(rev: 2, changes: [change(1), change(2)]), true),
            2: (SyncPullReply(rev: 3, changes: [change(3)]), false),
        ]
        let all = try await RemoteSync.pullAll(since: 0) { since in
            asked.append(since)
            let page = try XCTUnwrap(pages[since])
            return (page.0, more: page.1)
        }
        XCTAssertEqual(asked, [0, 2])
        XCTAssertEqual(all.rev, 3)
        XCTAssertEqual(all.changes.map(\.rev), [1, 2, 3])
    }

    func testPullAllStopsWhenRevDoesNotMove() async throws {
        var calls = 0
        let all = try await RemoteSync.pullAll(since: 5) { _ in
            calls += 1
            return (SyncPullReply(rev: 5, changes: []), more: true)
        }
        XCTAssertEqual(calls, 1, "ПК, который не двигает rev, не держит в цикле")
        XCTAssertEqual(all.rev, 5)
    }

    private func change(_ rev: Int) -> SyncChange {
        SyncChange(type: "like", key: "sc:\(rev)", value: .object([:]), rev: rev)
    }

    // MARK: - С кем синкаться и какой ПК помним

    func testTargetPrefersServerThenPairedPC() {
        let pc = RemoteSyncPC(id: "pc1", name: "Комп")
        XCTAssertEqual(SyncTarget.choose(serverReady: true, offline: false, pc: pc, hasKey: { _ in true }), .server)
        XCTAssertEqual(SyncTarget.choose(serverReady: false, offline: false, pc: pc, hasKey: { _ in true }), .lan(pcID: "pc1"))
        XCTAssertEqual(SyncTarget.choose(serverReady: false, offline: false, pc: pc, hasKey: { _ in false }), .none, "без ключа пульта — никуда")
        XCTAssertEqual(SyncTarget.choose(serverReady: false, offline: false, pc: nil, hasKey: { _ in true }), .none)
        XCTAssertEqual(SyncTarget.choose(serverReady: true, offline: true, pc: pc, hasKey: { _ in true }), .none, "офлайн — ни байта")
        XCTAssertEqual(SyncTarget.lan(pcID: "pc1").tag, "lan:pc1")
        XCTAssertEqual(SyncTarget.server.tag, "server")
        XCTAssertNil(SyncTarget.none.tag)
    }

    func testRemoteSyncPCSaveLoadForget() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lan-sync-\(UUID().uuidString)"))
        XCTAssertNil(RemoteSyncPC.load(from: defaults))
        RemoteSyncPC.save(RemoteSyncPC(id: "pc1", name: "Комп"), to: defaults)
        XCTAssertEqual(RemoteSyncPC.load(from: defaults), RemoteSyncPC(id: "pc1", name: "Комп"))
        RemoteSyncPC.forget("pc2", in: defaults)
        XCTAssertNotNil(RemoteSyncPC.load(from: defaults), "отвязали другой ПК — этот помним")
        RemoteSyncPC.forget("pc1", in: defaults)
        XCTAssertNil(RemoteSyncPC.load(from: defaults))
    }

    func testErrorTextsAreRussianAndCoverCodes() {
        XCTAssertEqual(RemoteSyncError.refused("offline").russian, "На ПК включён офлайн-режим")
        XCTAssertEqual(RemoteSyncError.refused("что-то новое").russian, "ПК не принял синхронизацию")
        XCTAssertEqual(RemoteSyncError.notFound.russian, "ПК не найден в этой сети")
    }

    // MARK: - Журнал и движок

    @MainActor
    private final class Phone {
        let library: LibraryStore
        var plays: [PlayRow] = []
        var clock: Int64 = 1_800_000_000_000
        private(set) var engine: SyncEngine!

        init(dir: URL = tempDirectory()) {
            library = LibraryStore(file: dir.appendingPathComponent("library.json"))
            let now = { [unowned self] in self.clock }
            engine = SyncEngine(
                deviceId: "phone",
                adapters: [LikesSyncAdapter(library: library, now: now)],
                file: dir.appendingPathComponent("sync.json"),
                plays: { [unowned self] since in
                    PlayUpload.from(self.plays, since: since, now: Date(timeIntervalSince1970: Double(self.clock) / 1000))
                },
                now: now)
        }
    }

    func testSwitchingTargetResendsEverythingAndPullsFromScratch() async throws {
        let phone = Phone()
        phone.library.toggleLike(makeTrack("sc:1", "A"))
        phone.engine.use(target: "server")
        _ = try await phone.engine.syncOnce(MemorySyncServer())
        XCTAssertEqual(phone.engine.journal.pendingCount, 0)
        XCTAssertEqual(phone.engine.journal.target, "server")

        phone.engine.use(target: "server")
        XCTAssertEqual(phone.engine.journal.pendingCount, 0, "та же сторона — курсоры на месте")

        phone.engine.use(target: "lan:pc1")
        XCTAssertEqual(phone.engine.journal.pendingCount, 1, "новая сторона нашего не видела — уйдёт заново")
        XCTAssertEqual(phone.engine.journal.pulledRev, 0)

        let pc = MemorySyncServer()
        let report = try await phone.engine.syncOnce(pc)
        XCTAssertEqual(report.pushed, 1)
        let liked = await pc.value("like", "sc:1")
        XCTAssertNotNil(liked)
    }

    func testLegacyJournalWithoutTargetCountsAsServer() throws {
        var journal = try JSONDecoder().decode(SyncJournal.self, from: Data(#"{"rows":[],"rev":4,"pushedRev":4,"pulledRev":9,"playsUploadedAt":0}"#.utf8))
        XCTAssertNil(journal.target)
        XCTAssertFalse(journal.use(target: "server"), "журнал до синка по Wi‑Fi был с сервером")
        XCTAssertEqual(journal.pulledRev, 9)
        XCTAssertTrue(journal.use(target: "lan:pc1"))
        XCTAssertEqual(journal.pulledRev, 0)
    }

    func testPlaysStayOnPhoneWhenTransportDoesNotTakeThem() async throws {
        let phone = Phone()
        let base = Date(timeIntervalSince1970: Double(phone.clock) / 1000)
        phone.plays = [PlayRow(ref: "sc:1", artist: "A", at: base.addingTimeInterval(-7200), ms: 200_000)]
        let pc = NoPlays()
        let report = try await phone.engine.syncOnce(pc)
        XCTAssertEqual(report.plays, 0)
        let calls = await pc.playCalls
        XCTAssertEqual(calls, 0, "ПК прослушивания не берёт")
        XCTAssertEqual(phone.engine.journal.playsUploadedAt, 0, "метка сервера не сдвинулась — потом уйдут на сервер")

        let server = MemorySyncServer()
        let later = try await phone.engine.syncOnce(server)
        XCTAssertEqual(later.plays, 1)
    }
}
