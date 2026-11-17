import XCTest
@testable import Sonar

/// Жесты (`Playback/Gestures.swift`, SETTINGS.md «Жесты»): ключи, умолчания, что где разрешено, разбор
/// свайпа и чтение настроек.
@MainActor
final class GestureTests: XCTestCase {
    private func store() -> SettingsStore {
        SettingsStore(storage: UserDefaults(suiteName: "gestures-\(UUID().uuidString)")!)
    }

    func testKeysAndDefaultsAsInSettingsDoc() {
        let expected: [String: String] = [
            "gestures.library.left": "play_next", "gestures.library.right": "play_next",
            "gestures.queue.left": "delete", "gestures.queue.right": "delete",
            "gestures.mini.left": "next", "gestures.mini.right": "previous",
            "gestures.player.left": "next", "gestures.player.right": "previous",
            "gestures.cover.double_tap": "like", "gestures.cover.triple_tap": "next",
        ]
        XCTAssertEqual(Gestures.defaults, expected)
        for (key, value) in expected {
            XCTAssertEqual(SettingsDefaults.player[key], .string(value), key)
        }
    }

    func testEveryDefaultIsAllowedInItsPlace() {
        for context in GestureContext.allCases {
            for direction in SwipeDirection.allCases {
                XCTAssertTrue(context.allowed.contains(Gestures.fallback(context, direction)), "\(context) \(direction)")
            }
            XCTAssertEqual(context.allowed.first, .off, "выключить можно везде")
        }
        for tap in CoverTap.allCases { XCTAssertTrue(CoverTap.allowed.contains(Gestures.fallback(tap))) }
    }

    func testAllowedActionsPerPlace() {
        XCTAssertFalse(GestureContext.mini.allowed.contains(.delete), "в мини-плеере удалять нечего")
        XCTAssertFalse(GestureContext.player.allowed.contains(.enqueue))
        XCTAssertFalse(GestureContext.library.allowed.contains(.next), "строка трека плеер не листает")
        XCTAssertTrue(GestureContext.queue.allowed.contains(.delete))
        XCTAssertFalse(CoverTap.allowed.contains(.delete))
    }

    func testUnknownOrDisallowedValueFallsBack() {
        XCTAssertEqual(Gestures.action("like", context: .mini, direction: .left), .like)
        XCTAssertEqual(Gestures.action("delete", context: .mini, direction: .left), .next, "не разрешено — умолчание")
        XCTAssertEqual(Gestures.action("fly", context: .queue, direction: .right), .delete)
        XCTAssertEqual(Gestures.action("off", context: .library, direction: .left), .off)
        XCTAssertEqual(Gestures.action("enqueue", tap: .double_tap), .like)
        XCTAssertEqual(Gestures.action("previous", tap: .triple_tap), .previous)
    }

    func testSwipeDetection() {
        XCTAssertEqual(SwipeDirection.detect(dx: -80, dy: 5), .left, "палец влево")
        XCTAssertEqual(SwipeDirection.detect(dx: 90, dy: -20), .right)
        XCTAssertNil(SwipeDirection.detect(dx: 40, dy: 0), "не дотянул до порога")
        XCTAssertNil(SwipeDirection.detect(dx: 80, dy: 90), "больше вниз, чем вбок — это прокрутка / закрытие")
        XCTAssertNil(SwipeDirection.detect(dx: 0, dy: 0))
    }

    func testResolveReadsSettings() {
        let settings = store()
        XCTAssertEqual(Gestures.resolve(settings, .mini, dx: -100, dy: 0), .next)
        XCTAssertEqual(Gestures.resolve(settings, .mini, dx: 100, dy: 0), .previous)
        settings.set(Gestures.key(.mini, .left), .string("like"))
        XCTAssertEqual(Gestures.resolve(settings, .mini, dx: -100, dy: 0), .like)
        settings.set(Gestures.key(.mini, .right), .string("off"))
        XCTAssertNil(Gestures.resolve(settings, .mini, dx: 100, dy: 0), "выключенный жест — ничего")
        XCTAssertNil(Gestures.resolve(settings, .library, dx: 20, dy: 0))
        settings.set(Gestures.key(.triple_tap), .string("off"))
        XCTAssertEqual(Gestures.action(settings, .triple_tap), .off)
        XCTAssertEqual(Gestures.action(settings, .double_tap), .like)
    }
}
