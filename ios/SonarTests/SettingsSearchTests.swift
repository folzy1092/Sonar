import XCTest
@testable import Sonar

/// Поиск по настройкам в Профиле — `Core/Settings/SettingsSearch.swift`, как ПК `lib/settings-catalog.ts`.
final class SettingsSearchTests: XCTestCase {
    /// Названия-бренды без перевода — одинаковые на всех языках.
    private let brands: Set<String> = ["SoundCloud", "YouTube Music", "Sonar Mix"]

    private func search(_ query: String, _ lang: Lang = .ru) -> [SettingsItem] {
        SettingsSearch.search(query) { I18n.translate($0, lang: lang) }
    }

    private func titles(_ query: String, _ lang: Lang = .ru) -> [String] {
        search(query, lang).map(\.title)
    }

    func testEmptyQueryFindsNothing() {
        XCTAssertEqual(search(""), [])
        XCTAssertEqual(search("   \n "), [])
    }

    func testNormalizeFoldsCaseYoAndSpaces() {
        XCTAssertEqual(SettingsSearch.normalize("  Тёмная   ТЕМА "), "темная тема")
        XCTAssertEqual(SettingsSearch.normalize("Только по Wi\u{2011}Fi"), "только по wi-fi")
        XCTAssertEqual(SettingsSearch.tokens(" эквалайзер  басы "), ["эквалайзер", "басы"])
    }

    func testIgnoresCaseAndYo() {
        XCTAssertEqual(titles("ЭКВАЛАЙЗЕР").first, "Эквалайзер")
        XCTAssertTrue(titles("ТЁМНАЯ").contains("Тема"))
        XCTAssertTrue(titles("Только по wi-fi").contains("Только по Wi‑Fi"))
    }

    func testFindsTranslatedTitle() {
        XCTAssertEqual(titles("equalizer", .en).first, "Эквалайзер")
        XCTAssertEqual(titles("еквалайзер", .uk).first, "Эквалайзер")
        XCTAssertEqual(titles("gestures", .en).first, "Жесты")
    }

    func testFindsRussianKeyInAnyLanguage() {
        XCTAssertEqual(titles("эквалайзер", .en).first, "Эквалайзер")
        XCTAssertEqual(titles("кроссфейд", .de).first, "Кроссфейд")
    }

    func testFindsSynonyms() {
        XCTAssertTrue(titles("кэш").contains("Очистка кеша"))
        XCTAssertTrue(titles("eq").contains("Эквалайзер"))
        XCTAssertTrue(titles("вибрация").contains("Тактильный отклик"))
    }

    func testEveryWordMustMatch() {
        XCTAssertTrue(titles("история поиска").contains("История поиска"))
        XCTAssertFalse(titles("история поиска").contains("История прослушиваний"))
        XCTAssertEqual(search("эквалайзер абракадабра"), [])
    }

    func testTitleStartRanksFirst() {
        // «Скругление» с начала слова — выше «Скругление границ», а оба выше синонимов
        let found = titles("скругл")
        XCTAssertEqual(Array(found.prefix(2)), ["Скругление", "Скругление границ"])
        // название важнее синонимов: «Очередь» выше пунктов, где «очередь» лишь в словах
        XCTAssertEqual(titles("очередь").first, "Очередь")
    }

    func testRespectsLimit() {
        XCTAssertLessThanOrEqual(search("а").count, SettingsSearch.maxHits)
        XCTAssertEqual(SettingsSearch.search("а", translate: { $0 }, limit: 3).count, 3)
    }

    func testPathOfPaneAndNestedItem() {
        let eq = search("эквалайзер").first
        XCTAssertEqual(eq?.path, ["Плеер", "Аудио"])
        let audio = search("аудио").first
        XCTAssertEqual(audio?.isPane, true)
        XCTAssertEqual(audio?.path, ["Плеер"])
        let icon = search("значок приложения").first
        XCTAssertEqual(icon?.pane, .appIcon)
        XCTAssertEqual(icon?.path, ["Интерфейс", "Вид"])
    }

    func testMarksMatchedPieces() {
        XCTAssertEqual(SettingsSearch.marks(in: "Тёмная тема", query: "ем"), [
            .init(text: "Т", isMatch: false),
            .init(text: "ём", isMatch: true),
            .init(text: "ная т", isMatch: false),
            .init(text: "ем", isMatch: true),
            .init(text: "а", isMatch: false),
        ])
        XCTAssertEqual(SettingsSearch.marks(in: "Equalizer", query: ""), [.init(text: "Equalizer", isMatch: false)])
        XCTAssertEqual(SettingsSearch.marks(in: "Кроссфейд", query: "КРОСС фейд"), [.init(text: "Кроссфейд", isMatch: true)])
    }

    func testCatalogItemsAreUnique() {
        let keys = SettingsSearch.catalog.map { "\($0.pane.rawValue)|\($0.title)" }
        XCTAssertEqual(keys.count, Set(keys).count)
    }

    func testEveryPaneIsInCatalog() {
        for pane in SettingsPane.allCases {
            XCTAssertTrue(SettingsSearch.catalog.contains { $0.pane == pane && $0.isPane }, pane.rawValue)
        }
    }

    func testEveryTitleIsTranslated() {
        let keys = Set(SettingsSearch.catalog.flatMap { [$0.title] + $0.pane.path }).subtracting(brands)
        for key in keys.sorted() {
            XCTAssertNotNil(I18n.dictionaries[.en]?[key], "нет перевода en: \(key)")
            XCTAssertNotNil(I18n.dictionaries[.uk]?[key], "нет перевода uk: \(key)")
        }
    }

    func testHintWordsFindSomething() {
        // слова из подсказки «ничего не нашлось» должны находить пункты
        for word in ["тема", "эквалайзер", "кэш"] { XCTAssertFalse(search(word).isEmpty, word) }
        for word in ["theme", "equalizer", "cache"] { XCTAssertFalse(search(word, .en).isEmpty, word) }
    }
}
