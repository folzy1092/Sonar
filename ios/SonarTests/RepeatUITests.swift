import XCTest
@testable import Sonar

/// Повтор и перемешивание в плеере (`Features/Player/PlayerToggle.swift`, docs/POLISH_PROMPT.md п. 5).
final class RepeatUITests: XCTestCase {
    func testRepeatOneKeepsDigitIcon() {
        XCTAssertEqual(RepeatUI.icon(.one), .repeatOne)
        XCTAssertEqual(RepeatUI.icon(.all), .repeatAll)
        XCTAssertEqual(RepeatUI.icon(.off), .repeatAll)
    }

    func testLabelsMatchDesktopTooltips() {
        XCTAssertEqual([RepeatMode.off, .all, .one].map(RepeatUI.labelKey), ["Повтор: выкл", "Повтор: всё", "Повтор: один трек"])
        XCTAssertEqual(RepeatUI.shuffleKey(true), "Перемешивание: вкл")
        XCTAssertEqual(RepeatUI.shuffleKey(false), "Перемешивание: выкл")
    }

    func testLabelsAreTranslated() {
        let keys = [RepeatMode.off, .all, .one].map(RepeatUI.labelKey) + [true, false].map(RepeatUI.shuffleKey) + ["Повтор", "Перемешивание"]
        for key in keys {
            XCTAssertNotEqual(I18n.translate(key, lang: .en), key, key)
            XCTAssertFalse(I18n.translate(key, lang: .uk).isEmpty, key)
        }
        XCTAssertEqual(I18n.translate("Повтор: один трек", lang: .en), "Repeat: one track")
    }

    func testValueDropsButtonName() {
        XCTAssertEqual(RepeatUI.value(of: "Повтор: один трек"), "один трек")
        XCTAssertEqual(RepeatUI.value(of: "Repeat: all"), "all")
        XCTAssertEqual(RepeatUI.value(of: "Повтор"), "Повтор")
    }
}
