import XCTest
@testable import Sonar

/// Ряд кнопок полного плеера (`Features/Player/ControlsLayout.swift`): с открытым текстом — компактный,
/// с ♥ слева и T справа, и влезает даже на iPhone SE.
final class PlayerControlsLayoutTests: XCTestCase {
    /// iPhone SE / mini: 375 pt минус поля плеера 2 × 18.
    private let narrowestRow: CGFloat = 375 - 36

    func testLyricsOpenPicksCompactRow() {
        XCTAssertEqual(PlayerControlsLayout.current(lyricsOpen: true), .compact)
        XCTAssertEqual(PlayerControlsLayout.current(lyricsOpen: false), .regular)
    }

    func testOnlyCompactRowHasSideButtons() {
        XCTAssertTrue(PlayerControlsLayout.compact.hasSideButtons)
        XCTAssertFalse(PlayerControlsLayout.regular.hasSideButtons)
    }

    func testCompactRowIsSmaller() {
        let compact = PlayerControlsLayout.compact, regular = PlayerControlsLayout.regular
        XCTAssertLessThan(compact.rowHeight, regular.rowHeight)
        XCTAssertLessThan(compact.playSide, regular.playSide)
        XCTAssertLessThan(compact.skipIcon, regular.skipIcon)
        XCTAssertLessThan(compact.toggleIcon, regular.toggleIcon)
        XCTAssertEqual(regular.playScale, 1)
        XCTAssertLessThan(compact.playScale, 1)
    }

    func testBothRowsFitNarrowestPhone() {
        XCTAssertLessThanOrEqual(PlayerControlsLayout.compact.minimumWidth, narrowestRow)
        XCTAssertLessThanOrEqual(PlayerControlsLayout.regular.minimumWidth, narrowestRow)
    }

    func testSideButtonsStayTappable() {
        // Apple HIG: цель касания не меньше 44 pt
        XCTAssertGreaterThanOrEqual(PlayerControlsLayout.compact.sideButton, 44)
        XCTAssertGreaterThanOrEqual(PlayerControlsLayout.compact.playSide, 44)
    }
}
