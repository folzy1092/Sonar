import XCTest
@testable import Sonar

/// Телефон с плейлистами: свой `PlaylistStore` в temp и движок синка поверх него.
@MainActor
private final class Phone {
    let dir: URL
    let store: PlaylistStore
    var clock: Int64 = 1_800_000_000_000
    private(set) var engine: SyncEngine!

    init(_ id: String, dir: URL = tempDirectory(), playlists: Bool = true) {
        self.dir = dir
        store = PlaylistStore(file: dir.appendingPathComponent("collections.json"))
        store.now = { [unowned self] in Int(self.clock) }
        let now = { [unowned self] in self.clock }
        let library = LibraryStore(file: dir.appendingPathComponent("library.json"))
        var adapters: [SyncAdapter] = [LikesSyncAdapter(library: library, now: now)]
        if playlists { adapters.append(PlaylistSyncAdapter(store: store, now: now)) }
        engine = SyncEngine(deviceId: id, adapters: adapters, file: dir.appendingPathComponent("sync.json"), now: now)
    }

    func tick(_ ms: Int64 = 10) { clock += ms }

    @discardableResult
    func sync(_ server: SyncTransport) async throws -> SyncReport {
        try await engine.syncOnce(server)
    }

    var refs: [String] { store.playlists.first?.tracks.map(\.ref) ?? [] }
}

/// Плейлист так, как его шлёт ПК (`store/sync.rs` `pending_ops`): элементы с дробной позицией и карточкой трека.
private enum PC {
    static func playlist(_ id: String, name: String, op: String = "1", ts: Int64 = 1_700_000_000_000) -> SyncOp {
        SyncOp(opId: "pc:playlist:\(id):\(op)", type: "playlist", key: id,
               value: .object(["name": .string(name), "hidden": .bool(false), "source_ref": .null,
                               "created_at": .int(Int(ts)), "updated_at": .int(Int(ts))]),
               clientTs: ts, rev: 0)
    }

    static func item(_ n: Int, in playlist: String, position: Double? = nil, op: String = "1") -> SyncOp {
        let track = makeTrack("sc:\(n)", "Artist \(n % 7)")
        return SyncOp(opId: "pc:playlist_item:pi_pc\(n):\(op)", type: "playlist_item", key: "pi_pc\(n)",
                      value: .object(["playlist_id": .string(playlist), "ref": .string(track.ref),
                                      "position": .double(position ?? Double(n)), "added_at": .int(1_700_000_000_000),
                                      "track": .encode(track)]),
                      clientTs: 1_700_000_000_000, rev: 0)
    }

    static func gone(_ type: String, _ key: String, op: String) -> SyncOp {
        SyncOp(opId: "pc:\(type):\(key):\(op)", type: type, key: key, value: .null, clientTs: 1_700_000_000_000, rev: 0)
    }
}

@MainActor
final class PlaylistSyncTests: XCTestCase {
    func testBigPCPlaylistArrivesInOrderEvenWhenItemsComeFirst() async throws {
        let server = MemorySyncServer()
        // элементы раньше плейлиста и не по порядку позиций — pull идёт по rev, а не по смыслу
        let items = (0 ..< 450).reversed().map { PC.item($0, in: "pl_pc") }
        _ = try await server.push(items)
        _ = try await server.push([PC.playlist("pl_pc", name: "Ночь")])

        let phone = Phone("ios")
        let report = try await phone.sync(server)
        XCTAssertEqual(phone.store.playlists.count, 1)
        let playlist = try XCTUnwrap(phone.store.playlist("pl_pc"))
        XCTAssertEqual(playlist.name, "Ночь")
        XCTAssertEqual(playlist.tracks.map(\.ref), (0 ..< 450).map { "sc:\($0)" })
        XCTAssertEqual(report.pulled, 451)

        let again = try await phone.sync(server)
        XCTAssertEqual(again.pushed, 0, "пришедшее не уехало обратно эхом")
        XCTAssertEqual(phone.engine.journal.pendingCount, 0)

        // перезапуск: журнал и плейлисты из файлов, своих изменений нет
        let reopened = Phone("ios", dir: phone.dir)
        XCTAssertEqual(reopened.refs.count, 450)
        XCTAssertEqual(reopened.engine.scan(), 0, "числа в журнале пережили запись в файл")
    }

    func testItemsWaitForTheirPlaylistAcrossPulls() async throws {
        let server = MemorySyncServer()
        _ = try await server.push((0 ..< 3).map { PC.item($0, in: "pl_late") })
        let phone = Phone("ios")
        try await phone.sync(server)
        XCTAssertTrue(phone.store.playlists.isEmpty, "без самого плейлиста показывать нечего")
        let waiting = try await phone.sync(server)
        XCTAssertEqual(waiting.pushed, 0, "ждущие элементы не превратились в удаления")

        _ = try await server.push([PC.playlist("pl_late", name: "Позже")])
        try await phone.sync(server)
        XCTAssertEqual(phone.refs, ["sc:0", "sc:1", "sc:2"])
        let quiet = try await phone.sync(server)
        XCTAssertEqual(quiet.pushed, 0)
    }

    func testPhoneEditsGoBackAsFewRows() async throws {
        let server = MemorySyncServer()
        _ = try await server.push([PC.playlist("pl_pc", name: "Ночь")] + (0 ..< 400).map { PC.item($0, in: "pl_pc") })
        let phone = Phone("ios")
        try await phone.sync(server)

        phone.tick()
        phone.store.remove(["sc:5"], from: "pl_pc")
        var order = phone.refs
        let moved = order.remove(at: 300)
        order.insert(moved, at: 10)
        phone.store.setOrder(order, in: "pl_pc")
        let report = try await phone.sync(server)
        XCTAssertEqual(report.pushed, 3, "плейлист (updated_at), удалённый и перенесённый элемент — не все 400")

        let removed = await server.value("playlist_item", "pi_pc5")
        XCTAssertEqual(removed, .null)
        let position = await server.value("playlist_item", "pi_pc301")?["position"].number
        XCTAssertEqual(try XCTUnwrap(position), 10.5, accuracy: 0.001, "sc:301 встал между sc:10 и sc:11")

        // второй телефон видит тот же порядок
        let other = Phone("ios-b")
        try await other.sync(server)
        XCTAssertEqual(other.refs, order)
    }

    func testPlaylistMadeOnPhoneReachesServerInPCFormat() async throws {
        let server = MemorySyncServer()
        let phone = Phone("ios")
        let id = try XCTUnwrap(phone.store.create(name: "С телефона", tracks: [makeTrack("ym:1", "A"), makeTrack("sc:2", "B")]))
        try await phone.sync(server)

        let playlist = await server.value("playlist", id)
        XCTAssertEqual(playlist?["name"].string, "С телефона")
        let first = PlaylistOrder.itemId(playlist: id, ref: "ym:1")
        let stored = await server.value("playlist_item", first)
        let item = try XCTUnwrap(stored)
        XCTAssertEqual(item["playlist_id"].string, id)
        XCTAssertEqual(item["ref"].string, "ym:1")
        XCTAssertEqual(item["position"].number, 0)
        XCTAssertEqual(item["track"].decode(Track.self)?.ref, "ym:1", "карточка — чтобы ПК показал трек без сети")

        phone.tick()
        phone.store.add([makeTrack("sc:3", "C")], to: id, atStart: true)
        let added1 = try await phone.sync(server)
        XCTAssertEqual(added1.pushed, 2, "новый элемент и updated_at плейлиста")
        let added = await server.value("playlist_item", PlaylistOrder.itemId(playlist: id, ref: "sc:3"))
        XCTAssertEqual(added?["position"].number, -1, "в начало — перед первым, как add_to_playlist на ПК")
    }

    func testDeletesBothWays() async throws {
        let server = MemorySyncServer()
        _ = try await server.push([PC.playlist("pl_a", name: "A"), PC.playlist("pl_b", name: "B")]
            + (0 ..< 3).map { PC.item($0, in: "pl_a") } + (10 ..< 12).map { PC.item($0, in: "pl_b") })
        let phone = Phone("ios")
        try await phone.sync(server)
        XCTAssertEqual(phone.store.playlists.count, 2)

        // ПК удалил плейлист и один элемент другого
        _ = try await server.push([PC.gone("playlist", "pl_b", op: "2"), PC.gone("playlist_item", "pi_pc1", op: "2")])
        try await phone.sync(server)
        XCTAssertNil(phone.store.playlist("pl_b"))
        XCTAssertEqual(phone.store.playlist("pl_a")?.tracks.map(\.ref), ["sc:0", "sc:2"])

        // телефон удалил плейлист — уходят плейлист и его элементы
        phone.tick()
        phone.store.delete("pl_a")
        try await phone.sync(server)
        let gone = await server.value("playlist", "pl_a")
        XCTAssertEqual(gone, .null)
        let item = await server.value("playlist_item", "pi_pc0")
        XCTAssertEqual(item, .null)
    }

    func testDuplicateOnPCIsShownOnceAndNotDeleted() async throws {
        let server = MemorySyncServer()
        var twin = PC.item(1, in: "pl_pc", position: 5)
        twin.key = "pi_twin"
        twin.opId = "pc:playlist_item:pi_twin:1"
        _ = try await server.push([PC.playlist("pl_pc", name: "Дубли"), PC.item(0, in: "pl_pc"), PC.item(1, in: "pl_pc"), twin])
        let phone = Phone("ios")
        try await phone.sync(server)
        XCTAssertEqual(phone.refs, ["sc:0", "sc:1"])
        let quiet = try await phone.sync(server)
        XCTAssertEqual(quiet.pushed, 0)
        let kept = await server.value("playlist_item", "pi_twin")
        XCTAssertEqual(kept?["ref"].string, "sc:1", "дубль на ПК телефон не удаляет")
    }

    func testPlaylistsPulledBeforeTheUpdateAppearOnStart() async throws {
        let server = MemorySyncServer()
        _ = try await server.push([PC.playlist("pl_old", name: "Старый")] + (0 ..< 5).map { PC.item($0, in: "pl_old") })
        let dir = tempDirectory()
        // прежняя сборка: плейлисты легли в журнал «чужими»
        let before = Phone("ios", dir: dir, playlists: false)
        try await before.sync(server)
        XCTAssertTrue(before.store.playlists.isEmpty)

        let after = Phone("ios", dir: dir)
        after.engine.replayForeign()
        XCTAssertEqual(after.refs, (0 ..< 5).map { "sc:\($0)" })
        let quiet = try await after.sync(server)
        XCTAssertEqual(quiet.pushed, 0)
    }

    func testOrderMathKeepsKnownPositions() {
        XCTAssertEqual(PlaylistOrder.positions([]), [])
        XCTAssertEqual(PlaylistOrder.positions([nil, nil, nil]), [0, 1, 2])
        XCTAssertEqual(PlaylistOrder.positions([0, 1, 2, 3]), [0, 1, 2, 3])
        // перенос: 3 встал в начало — двигается только он
        XCTAssertEqual(PlaylistOrder.positions([3, 0, 1, 2]), [-1, 0, 1, 2])
        XCTAssertEqual(PlaylistOrder.positions([0, nil, 1]), [0, 0.5, 1])
        XCTAssertEqual(PlaylistOrder.positions([5, nil, nil]), [5, 6, 7])
        let tight = PlaylistOrder.positions([1, 1, 1])
        XCTAssertTrue(zip(tight, tight.dropFirst()).allSatisfy { $0 < $1 }, "\(tight)")
        XCTAssertEqual(PlaylistOrder.json(2.0), .int(2))
        XCTAssertEqual(PlaylistOrder.json(2.5), .double(2.5))
        XCTAssertEqual(PlaylistOrder.itemId(playlist: "pl_a", ref: "sc:1"), PlaylistOrder.itemId(playlist: "pl_a", ref: "sc:1"))
        XCTAssertNotEqual(PlaylistOrder.itemId(playlist: "pl_a", ref: "sc:1"), PlaylistOrder.itemId(playlist: "pl_b", ref: "sc:1"))
    }
}
