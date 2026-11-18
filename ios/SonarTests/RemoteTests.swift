import Foundation
import XCTest
@testable import Sonar

/// Пульт (docs/API.md «Пульт»): сборка и разбор сообщений, проверки кода и ключа, ПК из Bonjour и ссылка из QR.
/// Тот же протокол, что `windows/src-tauri/src/remote/protocol.rs`.
final class RemoteTests: XCTestCase {
    private let phone = RemoteDevice(id: "a1b2c3d4-0000-4000-8000-000000000001", name: "iPhone 16")
    private let key = String(repeating: "k", count: 43)

    /// JSON-строку — в словарь, чтобы сравнивать без зависимости от форматирования.
    private func object(_ text: String) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try XCTUnwrap(value as? [String: Any])
    }

    private func body(_ text: String) throws -> [String: Any] {
        try object(text)["body"] as? [String: Any] ?? [:]
    }

    // MARK: - Телефон → ПК

    func testHelloEnvelope() throws {
        let text = RemoteOutgoing.hello(phone, key: key).encoded(id: "i1")
        let envelope = try object(text)
        XCTAssertEqual(envelope["v"] as? Int, RemoteProtocol.version)
        XCTAssertEqual(envelope["type"] as? String, "hello")
        XCTAssertEqual(envelope["id"] as? String, "i1")
        XCTAssertNil(envelope["re"])
        let body = try body(text)
        XCTAssertEqual(body["key"] as? String, key)
        let device = try XCTUnwrap(body["device"] as? [String: Any])
        XCTAssertEqual(device["id"] as? String, phone.id)
        XCTAssertEqual(device["name"] as? String, "iPhone 16")
    }

    func testPairCleansDeviceName() throws {
        let text = RemoteOutgoing.pair(RemoteDevice(id: "x", name: "  Мой\u{0007} iPhone \n"), code: "123456").encoded(id: "i2")
        XCTAssertEqual(try object(text)["type"] as? String, "pair")
        let body = try body(text)
        XCTAssertEqual(body["code"] as? String, "123456")
        XCTAssertEqual((body["device"] as? [String: Any])?["name"] as? String, "Мой iPhone")
    }

    func testPingHasNoBody() throws {
        let envelope = try object(RemoteOutgoing.ping.encoded(id: "i3"))
        XCTAssertEqual(envelope["type"] as? String, "ping")
        XCTAssertNil(envelope["body"])
    }

    func testEncodingIsStable() {
        XCTAssertEqual(RemoteOutgoing.command(.next).encoded(id: "i4"), #"{"id":"i4","type":"next","v":1}"#)
        XCTAssertEqual(RemoteOutgoing.command(.seek(ms: 61000)).encoded(id: "i5"),
                       #"{"body":{"ms":61000},"id":"i5","type":"seek","v":1}"#)
    }

    func testCommandTypes() {
        XCTAssertEqual(RemoteCommand.toggle.type, "toggle")
        XCTAssertEqual(RemoteCommand.prev.type, "prev")
        XCTAssertEqual(RemoteCommand.volume(0.5).type, "volume")
        XCTAssertEqual(RemoteCommand.like(ref: nil, value: nil).type, "like")
        XCTAssertEqual(RemoteCommand.playWave.type, "play")
        XCTAssertEqual(RemoteCommand.play(ref: "sc:1", track: nil).type, "play")
        XCTAssertEqual(RemoteCommand.queueAdd(ref: "sc:1", track: nil, next: true).type, "queue_add")
        XCTAssertEqual(RemoteCommand.queuePlayIndex(2).type, "queue_play_index")
    }

    func testCommandBodiesClampValues() {
        XCTAssertEqual(RemoteCommand.seek(ms: -5).body["ms"] as? Int, 0)
        XCTAssertEqual(RemoteCommand.volume(1.7).body["value"] as? Double, 1)
        XCTAssertEqual(RemoteCommand.volume(-0.2).body["value"] as? Double, 0)
        XCTAssertEqual(RemoteCommand.volume(.nan).body["value"] as? Double, 0)
        XCTAssertTrue(RemoteCommand.toggle.body.isEmpty)
        XCTAssertEqual(RemoteCommand.queuePlayIndex(3).body["index"] as? Int, 3)
    }

    func testLikeBodyOnlyHasGivenFields() {
        XCTAssertTrue(RemoteCommand.like(ref: nil, value: nil).body.isEmpty)
        let body = RemoteCommand.like(ref: "ym:5", value: false).body
        XCTAssertEqual(body["ref"] as? String, "ym:5")
        XCTAssertEqual(body["value"] as? Bool, false)
    }

    func testPlayCarriesTrackOnlyForSameRef() throws {
        let track = makeTrack("sc:42", "Artist")
        let play = RemoteCommand.play(ref: "sc:42", track: track).body
        XCTAssertEqual(play["wave"] as? Bool, false)
        XCTAssertEqual(play["ref"] as? String, "sc:42")
        let sent = try XCTUnwrap(play["track"] as? [String: Any])
        XCTAssertEqual(sent["ref"] as? String, "sc:42")
        XCTAssertEqual(sent["duration_ms"] as? Int, 200_000)
        // чужой трек не прикладываем
        XCTAssertNil(RemoteCommand.play(ref: "sc:1", track: track).body["track"])
        let add = RemoteCommand.queueAdd(ref: "sc:42", track: track, next: true).body
        XCTAssertEqual(add["next"] as? Bool, true)
        XCTAssertNotNil(add["track"])
        XCTAssertEqual(RemoteCommand.playWave.body["wave"] as? Bool, true)
    }

    // MARK: - ПК → телефон

    func testDecodeWelcome() throws {
        let decoded = try RemoteProtocol.decode(#"{"v":1,"type":"welcome","re":"i1","body":{"pc":{"id":"pc-1","name":"Folzy-PC"}}}"#)
        XCTAssertEqual(decoded.re, "i1")
        XCTAssertEqual(decoded.message, .welcome(RemotePCInfo(id: "pc-1", name: "Folzy-PC")))
    }

    func testDecodePaired() throws {
        let text = #"{"v":1,"type":"paired","body":{"pc":{"id":"pc-1","name":"PC"},"key":"\#(key)"}}"#
        XCTAssertEqual(try RemoteProtocol.decode(text).message, .paired(RemotePCInfo(id: "pc-1", name: "PC"), key: key))
    }

    func testDecodePairedRejectsBadKey() {
        let text = #"{"v":1,"type":"paired","body":{"pc":{"id":"pc-1"},"key":"short"}}"#
        XCTAssertThrowsError(try RemoteProtocol.decode(text)) { error in
            XCTAssertEqual(error as? RemoteDecodeError, .badBody("key"))
        }
    }

    func testDecodeWelcomeNeedsPC() {
        XCTAssertThrowsError(try RemoteProtocol.decode(#"{"v":1,"type":"welcome","body":{}}"#)) { error in
            XCTAssertEqual(error as? RemoteDecodeError, .badBody("pc"))
        }
    }

    func testDecodeState() throws {
        let text = """
        {"v":1,"type":"state","body":{
          "track":{"ref":"sc:1","title":"Song","artist":"A","artists":[],"duration_ms":180000,"explicit":false,"available":true},
          "position_ms":30000,"duration_ms":180000,"playing":true,"volume":0.4,"repeat":"one","shuffle":true,
          "liked":true,"queue":[],"context_title":"Любимые","device":{"id":"pc-1","name":"PC","kind":"desktop"}}}
        """
        guard case let .state(state) = try RemoteProtocol.decode(text).message else { return XCTFail("не state") }
        XCTAssertEqual(state.track?.ref, "sc:1")
        XCTAssertEqual(state.positionMs, 30000)
        XCTAssertEqual(state.durationMs, 180_000)
        XCTAssertTrue(state.playing)
        XCTAssertEqual(state.volume, 0.4)
        XCTAssertEqual(state.repeatMode, .one)
        XCTAssertTrue(state.shuffle)
        XCTAssertTrue(state.liked)
        XCTAssertEqual(state.contextTitle, "Любимые")
        XCTAssertEqual(state.device, RemoteState.Device(id: "pc-1", name: "PC", kind: "desktop"))
        XCTAssertEqual(state.duration, 180)
    }

    func testStateIsTolerant() throws {
        let text = """
        {"v":1,"type":"state","body":{"position_ms":-5,"duration_ms":1e15,"volume":7,"repeat":"forever",
          "queue":[{"ref":"sc:2","title":"Ok","artist":"B","artists":[],"duration_ms":1,"explicit":false,"available":true},
                   {"broken":true}],
          "future_field":42}}
        """
        guard case let .state(state) = try RemoteProtocol.decode(text).message else { return XCTFail("не state") }
        XCTAssertNil(state.track)
        XCTAssertEqual(state.positionMs, 0)
        XCTAssertEqual(state.durationMs, 24 * 60 * 60 * 1000)
        XCTAssertEqual(state.volume, 1)
        XCTAssertEqual(state.repeatMode, .off)
        XCTAssertFalse(state.playing)
        XCTAssertEqual(state.queue.map(\.ref), ["sc:2"])
    }

    func testStateQueueIsLimited() throws {
        let track = #"{"ref":"sc:1","title":"T","artist":"A","artists":[],"duration_ms":1,"explicit":false,"available":true}"#
        let queue = Array(repeating: track, count: 70).joined(separator: ",")
        let text = #"{"v":1,"type":"state","body":{"queue":[\#(queue)]}}"#
        guard case let .state(state) = try RemoteProtocol.decode(text).message else { return XCTFail("не state") }
        XCTAssertEqual(state.queue.count, RemoteProtocol.queueLimit)
    }

    func testDecodeErrorPongBye() throws {
        XCTAssertEqual(try RemoteProtocol.decode(#"{"v":1,"type":"error","re":"i2","body":{"code":"bad_code"}}"#).message,
                       .error(code: "bad_code"))
        XCTAssertEqual(try RemoteProtocol.decode(#"{"v":1,"type":"error"}"#).message, .error(code: "unknown"))
        XCTAssertEqual(try RemoteProtocol.decode(#"{"v":1,"type":"pong","re":"i9"}"#).message, .pong)
        XCTAssertEqual(try RemoteProtocol.decode(#"{"v":1,"type":"bye","body":{"reason":"unpaired"}}"#).message,
                       .bye(reason: "unpaired"))
    }

    func testEmptyReIsNil() throws {
        XCTAssertNil(try RemoteProtocol.decode(#"{"v":1,"type":"pong","re":""}"#).re)
    }

    func testDecodeRejectsBadInput() {
        XCTAssertThrowsError(try RemoteProtocol.decode("not json")) { XCTAssertEqual($0 as? RemoteDecodeError, .badJSON) }
        XCTAssertThrowsError(try RemoteProtocol.decode(#"[1,2]"#)) { XCTAssertEqual($0 as? RemoteDecodeError, .badJSON) }
        XCTAssertThrowsError(try RemoteProtocol.decode(#"{"v":1}"#)) { XCTAssertEqual($0 as? RemoteDecodeError, .badJSON) }
        XCTAssertThrowsError(try RemoteProtocol.decode(#"{"v":2,"type":"pong"}"#)) {
            XCTAssertEqual($0 as? RemoteDecodeError, .badVersion(2))
        }
        XCTAssertThrowsError(try RemoteProtocol.decode(#"{"type":"pong"}"#)) {
            XCTAssertEqual($0 as? RemoteDecodeError, .badVersion(-1))
        }
        XCTAssertThrowsError(try RemoteProtocol.decode(#"{"v":1,"type":"dance"}"#)) {
            XCTAssertEqual($0 as? RemoteDecodeError, .unknown("dance"))
        }
    }

    // MARK: - Позиция

    func testPositionMovesOnlyWhilePlaying() {
        let playing = RemoteState(track: nil, positionMs: 10_000, durationMs: 60_000, playing: true)
        XCTAssertEqual(playing.position(after: 5), 15, accuracy: 0.001)
        XCTAssertEqual(playing.position(after: 500), 60, accuracy: 0.001)
        XCTAssertEqual(playing.position(after: -3), 10, accuracy: 0.001)
        let paused = RemoteState(track: nil, positionMs: 10_000, durationMs: 60_000, playing: false)
        XCTAssertEqual(paused.position(after: 5), 10, accuracy: 0.001)
        // длительность неизвестна — не упираемся
        let stream = RemoteState(track: nil, positionMs: 1000, durationMs: 0, playing: true)
        XCTAssertEqual(stream.position(after: 2), 3, accuracy: 0.001)
    }

    // MARK: - Код, ключ, имя

    func testCodeChecks() {
        XCTAssertTrue(RemoteProtocol.isCode("012345"))
        XCTAssertFalse(RemoteProtocol.isCode("12345"))
        XCTAssertFalse(RemoteProtocol.isCode("1234567"))
        XCTAssertFalse(RemoteProtocol.isCode("12a456"))
        XCTAssertFalse(RemoteProtocol.isCode("١٢٣٤٥٦"))
        XCTAssertEqual(RemoteProtocol.cleanCode(" 123-456 "), "123456")
        XCTAssertEqual(RemoteProtocol.cleanCode("12 34 56 78"), "123456")
        XCTAssertEqual(RemoteProtocol.cleanCode("abc"), "")
    }

    func testKeyAndDeviceIDChecks() {
        XCTAssertTrue(RemoteProtocol.isKey(key))
        XCTAssertTrue(RemoteProtocol.isKey("AbC-_0123456789xyz"))
        XCTAssertFalse(RemoteProtocol.isKey("short"))
        XCTAssertFalse(RemoteProtocol.isKey(String(repeating: "a", count: 129)))
        XCTAssertFalse(RemoteProtocol.isKey("aaaaaaaaaaaaaaaa+/"))
        XCTAssertTrue(RemoteProtocol.isDeviceID(UUID().uuidString.lowercased()))
        XCTAssertFalse(RemoteProtocol.isDeviceID(""))
        XCTAssertFalse(RemoteProtocol.isDeviceID("a b"))
        XCTAssertFalse(RemoteProtocol.isDeviceID(String(repeating: "a", count: 65)))
    }

    func testCleanName() {
        XCTAssertEqual(RemoteProtocol.cleanName("  iPhone\t"), "iPhone")
        XCTAssertEqual(RemoteProtocol.cleanName("\u{0000}\n"), "iPhone")
        XCTAssertEqual(RemoteProtocol.cleanName(String(repeating: "я", count: 100)).count, RemoteProtocol.maxDeviceName)
    }

    func testErrorTextsCoverCodes() {
        let fallback = RemoteErrorText.russian("whatever")
        for code in ["bad_code", "code_expired", "no_code", "code_burned", "not_paired", "bad_version"] {
            XCTAssertNotEqual(RemoteErrorText.russian(code), fallback, code)
        }
    }

    // MARK: - Где искать ПК

    func testPCFromService() {
        let pc = RemotePC.fromService(name: "Sonar (PC)", txt: ["id": "pc-1", "v": "1", "name": "Folzy-PC"])
        XCTAssertEqual(pc?.id, "pc-1")
        XCTAssertEqual(pc?.name, "Folzy-PC")
        XCTAssertEqual(pc?.endpoint, .service(name: "Sonar (PC)", type: "_sonar._tcp", domain: "local."))
        XCTAssertEqual(RemotePC.fromService(name: "Sonar", txt: ["id": "pc-1"])?.name, "Sonar")
        XCTAssertNil(RemotePC.fromService(name: "Sonar", txt: [:]))
        XCTAssertNil(RemotePC.fromService(name: "Sonar", txt: ["id": "pc-1", "v": "2"]))
    }

    func testPairLink() throws {
        let url = try XCTUnwrap(URL(string: "sonar://remote/pair?pc=pc-1&name=Folzy%20PC&host=192.168.1.5&port=53120&code=123456"))
        let link = try XCTUnwrap(RemotePairLink(url))
        XCTAssertEqual(link.code, "123456")
        XCTAssertEqual(link.pc.id, "pc-1")
        XCTAssertEqual(link.pc.name, "Folzy PC")
        XCTAssertEqual(link.pc.endpoint, .host("192.168.1.5", port: 53120))
        XCTAssertEqual(DeepLink(url), .remotePair(link))
    }

    func testPairLinkRejectsBadLinks() {
        let bad = [
            "sonar://remote/pair?pc=pc-1&host=h&port=53120&code=12345",
            "sonar://remote/pair?pc=pc-1&host=h&port=0&code=123456",
            "sonar://remote/pair?pc=pc-1&host=h&port=70000&code=123456",
            "sonar://remote/pair?host=h&port=53120&code=123456",
            "sonar://remote/pair?pc=pc-1&port=53120&code=123456",
            "sonar://remote/other?pc=pc-1&host=h&port=53120&code=123456",
            "https://remote/pair?pc=pc-1&host=h&port=53120&code=123456",
        ]
        for string in bad {
            let url = URL(string: string)!
            XCTAssertNil(RemotePairLink(url), string)
        }
        XCTAssertNil(DeepLink(URL(string: "sonar://remote/pair?pc=pc-1")!))
    }

    func testPairLinkWithoutNameUsesHost() throws {
        let url = try XCTUnwrap(URL(string: "sonar://remote/pair?pc=pc-1&host=10.0.0.2&port=53120&code=000111"))
        XCTAssertEqual(RemotePairLink(url)?.pc.name, "10.0.0.2")
    }
}
