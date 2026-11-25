import XCTest
@testable import Sonar

@MainActor
final class RemovedTracksTests: XCTestCase {
    func testDetectsSoundCloud404Only() {
        XCTAssertTrue(RemovedTracks.isRemoved(ref: "sc:1", error: ServiceError.http("SoundCloud", 404)))
        XCTAssertFalse(RemovedTracks.isRemoved(ref: "sc:1", error: ServiceError.http("SoundCloud", 429)))
        XCTAssertFalse(RemovedTracks.isRemoved(ref: "ym:1", error: ServiceError.http("Яндекс Музыка", 404)))
    }

    func testMarkAndUnmark() {
        let defaults = UserDefaults(suiteName: "RemovedTracksTests")!
        defaults.removePersistentDomain(forName: "RemovedTracksTests")
        let store = RemovedTracks(defaults: defaults)
        store.mark("sc:1", true)
        XCTAssertTrue(store.refs.contains("sc:1"))
        XCTAssertTrue(RemovedTracks(defaults: defaults).refs.contains("sc:1"))
        store.mark("sc:1", false)
        XCTAssertTrue(store.refs.isEmpty)
    }
}
