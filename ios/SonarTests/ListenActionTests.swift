import XCTest
@testable import Sonar

/// Кнопка «Слушать» ⇄ «Пауза» на экранах подборок (`Playback/ListenAction.swift`), как на ПК.
@MainActor
final class ListenActionTests: XCTestCase {
    private func resolve(page: String = "Микс", context: String = "Микс", isWave: Bool = false, hasCurrent: Bool = true, isPlaying: Bool, ended: Bool = false) -> ListenAction {
        ListenAction.resolve(page: page, context: context, isWave: isWave, hasCurrent: hasCurrent, isPlaying: isPlaying, ended: ended)
    }

    func testPausesWhenThisCollectionPlays() {
        XCTAssertEqual(resolve(isPlaying: true), .pause)
        XCTAssertTrue(resolve(isPlaying: true).showsPause)
    }

    func testResumesFromPositionWhenThisCollectionIsPaused() {
        XCTAssertEqual(resolve(isPlaying: false), .resume)
        XCTAssertFalse(resolve(isPlaying: false).showsPause)
    }

    func testStartsWhenAnotherCollectionPlays() {
        XCTAssertEqual(resolve(context: "Другой", isPlaying: true), .start)
    }

    func testStartsWhenWaveOrEmptyQueue() {
        XCTAssertEqual(resolve(isWave: true, isPlaying: true), .start)
        XCTAssertEqual(resolve(hasCurrent: false, isPlaying: false), .start)
    }

    func testStartsOverWhenCollectionFinished() {
        XCTAssertEqual(resolve(isPlaying: false, ended: true), .start)
    }

    func testStartsWithoutPageContext() {
        XCTAssertEqual(resolve(page: "", context: "", isPlaying: true), .start)
    }
}
