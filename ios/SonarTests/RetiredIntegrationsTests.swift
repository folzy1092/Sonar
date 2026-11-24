import XCTest
@testable import Sonar

/// Одноразовая чистка убранного (Last.fm — docs/LASTFM_EXIT.md, VK — 2026-11-25): вход, очередь и файлы стираются,
/// второй запуск ничего не трогает.
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

    func testForgetsVKLoginAndKeyFile() throws {
        // Arrange
        let vk = RetiredIntegrations.SecretRef(service: "SonarServices", account: "vk")
        let youtube = RetiredIntegrations.SecretRef(service: "SonarServices", account: "yt")
        var stored: [RetiredIntegrations.SecretRef: Data] = [vk: Data("{}".utf8), youtube: Data("{}".utf8)]
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("retired-\(UUID().uuidString)")
        let keys = support.appendingPathComponent("Sonar/vk-keys.json")
        try FileManager.default.createDirectory(at: keys.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: keys)
        defer { try? FileManager.default.removeItem(at: support) }

        // Act
        let removed = RetiredIntegrations.forget(read: { stored[$0] }, remove: { stored[$0] = nil },
                                                 defaults: freshDefaults(), support: support)

        // Assert
        XCTAssertEqual(removed, 2)
        XCTAssertNil(stored[vk])
        XCTAssertNotNil(stored[youtube], "вход YouTube Music не тронут")
        XCTAssertFalse(FileManager.default.fileExists(atPath: keys.path))
    }

    func testRetiredTracksAreFoundOnlyForVK() {
        XCTAssertTrue(RetiredIntegrations.hasRetiredTracks(["sc:1", "vk:-2001_42"]))
        XCTAssertFalse(RetiredIntegrations.hasRetiredTracks(["sc:1", "ym:2", "local:abc", "yt:x"]))
        XCTAssertFalse(RetiredIntegrations.hasRetiredTracks([String]()))
    }

    func testRetiredRefFailsAsUnavailableForFallback() {
        let gone = MusicCore.retiredError("vk:1_2")
        XCTAssertEqual(gone?.reason, .unavailable)
        XCTAssertEqual(gone?.message, "VK Музыка убрана из Sonar")
        XCTAssertNil(MusicCore.retiredError("local:abc"), "свои файлы с ПК — не «убранный сервис»")
        XCTAssertNil(MusicCore.retiredError("sc:1"))
    }
}
