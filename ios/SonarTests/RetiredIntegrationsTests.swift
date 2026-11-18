import XCTest
@testable import Sonar

/// Одноразовая чистка Last.fm (docs/LASTFM_EXIT.md): вход и очередь стираются, второй запуск ничего не трогает.
final class RetiredIntegrationsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "retired-\(UUID().uuidString)")!
    }

    func testForgetsStoredSessionAndPendingQueue() {
        // Arrange
        var stored: [RetiredIntegrations.SecretRef: Data] = [
            RetiredIntegrations.SecretRef(service: "com.folzy.sonar.lastfm", account: "session"): Data("{}".utf8),
        ]
        let defaults = freshDefaults()
        defaults.set(Data("[]".utf8), forKey: "sonar.lastfm.pending")
        defaults.set("keep", forKey: "audio.quality")

        // Act
        let removed = RetiredIntegrations.forget(read: { stored[$0] }, remove: { stored[$0] = nil }, defaults: defaults)

        // Assert
        XCTAssertEqual(removed, 2)
        XCTAssertTrue(stored.isEmpty)
        XCTAssertNil(defaults.object(forKey: "sonar.lastfm.pending"))
        XCTAssertEqual(defaults.string(forKey: "audio.quality"), "keep")
    }

    func testSecondRunHasNothingToRemove() {
        // Arrange
        var removeCalls = 0
        let defaults = freshDefaults()

        // Act
        let removed = RetiredIntegrations.forget(read: { _ in nil }, remove: { _ in removeCalls += 1 }, defaults: defaults)

        // Assert
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(removeCalls, 0)
    }
}
