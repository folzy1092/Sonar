import XCTest
@testable import Sonar

/// «Играть из» — те же случаи, что `windows/src/lib/track-source.test.ts` и тесты `services/fallback.rs`,
/// `store/track_source.rs`.
@MainActor
final class TrackSourceTests: XCTestCase {
    private func via(_ service: ServiceID, _ reason: FallbackReason) -> FallbackVia {
        FallbackVia(ref: "x:2", service: service, from: .sc, reason: reason)
    }

    func testPinAcceptsOnlyStreamingServices() {
        XCTAssertEqual(TrackSourcePlan.pin("sc"), .sc)
        XCTAssertEqual(TrackSourcePlan.pin("ym"), .ym)
        XCTAssertEqual(TrackSourcePlan.pin("yt"), .yt)
        XCTAssertNil(TrackSourcePlan.pin("sp"))
        XCTAssertNil(TrackSourcePlan.pin("vk"))
        XCTAssertNil(TrackSourcePlan.pin("local"))
        XCTAssertNil(TrackSourcePlan.pin("???"))
        XCTAssertNil(TrackSourcePlan.pin(nil))
    }

    func testRoutedFollowsPin() {
        // «Авто» — как раньше
        XCTAssertTrue(TrackSourcePlan.keeps(via(.ym, .preferred), pin: nil, scViaYandex: true, fallbackOn: true))
        XCTAssertFalse(TrackSourcePlan.keeps(via(.ym, .preferred), pin: nil, scViaYandex: false, fallbackOn: true))
        // закрепили SoundCloud — повышение качества с Яндекса больше не играет, резерв по беде — играет
        XCTAssertFalse(TrackSourcePlan.keeps(via(.ym, .preferred), pin: .sc, scViaYandex: true, fallbackOn: true))
        XCTAssertTrue(TrackSourcePlan.keeps(via(.ym, .unavailable), pin: .sc, scViaYandex: true, fallbackOn: true))
        // закреплён YouTube — замена с Яндекса не годится даже по беде
        XCTAssertFalse(TrackSourcePlan.keeps(via(.ym, .unavailable), pin: .yt, scViaYandex: true, fallbackOn: true))
        // выбор держится и при выключенном резерве; «Авто» его снимает
        XCTAssertTrue(TrackSourcePlan.keeps(via(.ym, .pinned), pin: .ym, scViaYandex: false, fallbackOn: false))
        XCTAssertFalse(TrackSourcePlan.keeps(via(.ym, .pinned), pin: nil, scViaYandex: true, fallbackOn: true))
    }

    func testChoices() {
        let ids = { (c: [TrackSourcePlan.Choice]) in c.map(\.id) }
        XCTAssertEqual(ids(TrackSourcePlan.choices(ref: "sc:1", services: [.sc, .ym], pinned: nil)), ["auto", "sc", "ym"])
        XCTAssertEqual(TrackSourcePlan.choices(ref: "sc:1", services: [.sc], pinned: nil), [], "выбирать не из чего")
        XCTAssertEqual(ids(TrackSourcePlan.choices(ref: "sc:1", services: [.sc], pinned: .ym)), ["auto", "sc", "ym"],
                       "закреплённое видно, даже если двойник сейчас не нашёлся")
    }

    func testPinnedOwnServiceIsLabeled() {
        let src = StreamSource.file(url: URL(fileURLWithPath: "/x"), quality: "AAC 160")
        guard case let .file(_, q) = TrackSourcePlan.labeled(src, ref: "sc:1", via: nil, pinned: .sc) else { return XCTFail() }
        XCTAssertEqual(q, "AAC 160 · SoundCloud")
        guard case let .file(_, plain) = TrackSourcePlan.labeled(src, ref: "sc:1", via: nil, pinned: nil) else { return XCTFail() }
        XCTAssertEqual(plain, "AAC 160", "«Авто» — как раньше")
    }

    func testPinnedIsNotAFallbackToast() {
        XCTAssertNil(FallbackPlan.toast(via(.ym, .pinned), lang: .ru))
    }

    func testLibraryKeepsSourceAfterRestart() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = dir.appendingPathComponent("library.json")
        let a = LibraryStore(file: file)
        a.rememberSource(.ym, for: "sc:1")
        a.rememberSource(.sp, for: "sc:2")
        XCTAssertEqual(LibraryStore(file: file).source(for: "sc:1"), .ym, "после перезапуска — то же")
        XCTAssertNil(LibraryStore(file: file).source(for: "sc:2"), "сервис без потока не закрепляется")
        a.rememberSource(nil, for: "sc:1")
        XCTAssertNil(LibraryStore(file: file).source(for: "sc:1"))
    }
}
