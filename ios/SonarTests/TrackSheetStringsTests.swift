import XCTest
@testable import Sonar

/// Новые строки меню трека (Устройства, Таймер сна), настройки таймера и «T» в тексте — на всех языках.
final class TrackSheetStringsTests: XCTestCase {
    func testMenuStringsAreTranslated() {
        for key in ["Устройства", "Таймер сна", "Выбрать, где играет музыка", "Остановить музыку через заданное время",
                    "Включён — нажми, чтобы изменить", "Таймер сна в плеере",
                    "В меню трека и в листе скорости: выключить музыку через время", "Меню текста"] {
            for lang in Lang.allCases where lang != .ru {
                XCTAssertNotEqual(I18n.translate(key, lang: lang), key, "\(key) — \(lang)")
            }
        }
    }
}
