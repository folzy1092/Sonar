import XCTest
@testable import Sonar

/// Языки интерфейса — как Windows `lib/i18n.svelte.ts` и `i18n.test.ts`.
final class I18nTests: XCTestCase {
    func testRussianIsKeyAndFallback() {
        XCTAssertEqual(I18n.translate("Общее", lang: .ru), "Общее")
        XCTAssertEqual(I18n.translate("Строки нет ни в одном словаре", lang: .en), "Строки нет ни в одном словаре")
        XCTAssertEqual(I18n.translate("Общее", lang: .en), "General")
        XCTAssertEqual(I18n.translate("Общее", lang: .uk), "Загальне")
    }

    func testContextKeys() {
        XCTAssertEqual(I18n.translate("навигация::Назад", lang: .ru), "Назад")
        XCTAssertEqual(I18n.translate("навигация::Назад", lang: .en), "Back")
        XCTAssertEqual(I18n.translate("Назад", lang: .en), "Previous") // кнопка плеера
    }

    func testParams() {
        XCTAssertEqual(I18n.translate("Версия {version}", lang: .en, params: ["version": "0.1.0"]), "Version 0.1.0")
        XCTAssertEqual(I18n.translate("Версия {version}", lang: .ru, params: ["version": "1"]), "Версия 1")
        XCTAssertEqual(I18n.fill("{a} и {b}", ["a": "1"]), "1 и {b}")
    }

    func testRussianPluralRule() {
        XCTAssertEqual([0, 1, 2, 5, 11, 12, 21, 22, 25, 101, 111].map(I18n.ruPlural), [2, 0, 1, 2, 2, 2, 0, 1, 2, 0, 2])
    }

    func testPluralForms() {
        let forms = ["минута", "минуты", "минут"]
        XCTAssertEqual(I18n.plural(1, forms, lang: .ru), "минута")
        XCTAssertEqual(I18n.plural(3, forms, lang: .ru), "минуты")
        XCTAssertEqual(I18n.plural(5, forms, lang: .ru), "минут")
        XCTAssertEqual(I18n.plural(1, forms, lang: .en), "minute")
        XCTAssertEqual(I18n.plural(5, forms, lang: .en), "minutes")
        XCTAssertEqual(I18n.plural(2, forms, lang: .uk), "хвилини")
        XCTAssertEqual(I18n.plural(5, forms, lang: .uk), "хвилин")
        XCTAssertEqual(I18n.plural(7, ["нет", "такой", "формы"], lang: .en), "формы")
    }

    func testLanguageFromSystem() {
        XCTAssertEqual(Lang.system(preferred: ["en-US", "ru"]), .en)
        XCTAssertEqual(Lang.system(preferred: ["de-DE", "uk-UA"]), .uk)
        XCTAssertEqual(Lang.system(preferred: ["lv-LV"]), .ru)
        XCTAssertEqual(Lang.system(preferred: []), .ru)
        XCTAssertEqual(Lang.resolve("uk", preferred: ["en"]), .uk)
        XCTAssertEqual(Lang.resolve(nil, preferred: ["en"]), .en)
        XCTAssertEqual(Lang.resolve("de", preferred: ["ru"]), .ru)
    }

    /// Словари en и uk — одни ключи; во всех переводах те же подстановки `{…}`, у множественного —
    /// нужное число форм.
    func testDictionariesAreComplete() {
        let en = I18n.dictionaries[.en] ?? [:]
        let uk = I18n.dictionaries[.uk] ?? [:]
        XCTAssertGreaterThan(en.count, 800)
        XCTAssertEqual(Set(en.keys).symmetricDifference(uk.keys), [])
        func params(_ s: String) -> Set<String> {
            var out = Set<String>()
            var rest = Substring(s)
            while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
                out.insert(String(rest[open ... close]))
                rest = rest[rest.index(after: close)...]
            }
            return out
        }
        for (key, value) in en {
            let plain = key.range(of: "::").map { String(key[$0.upperBound...]) } ?? key
            XCTAssertEqual(params(plain), params(value), "en: \(key)")
            XCTAssertEqual(params(plain), params(uk[key] ?? ""), "uk: \(key)")
            if plain.split(separator: "|").count == 3 {
                XCTAssertEqual(value.split(separator: "|").count, 2, "en: \(key)")
                XCTAssertEqual(uk[key]?.split(separator: "|").count, 3, "uk: \(key)")
            }
        }
    }

    @MainActor
    func testSettingSwitchesLanguage() {
        let settings = SettingsStore.shared
        let before = settings.value(Lang.settingKey)
        defer { settings.set(Lang.settingKey, before ?? .string("")) }
        settings.set(Lang.settingKey, .string("en"))
        XCTAssertEqual(t("Общее"), "General")
        XCTAssertEqual(tn(2, "трек", "трека", "треков"), "tracks")
        settings.set(Lang.settingKey, .string("ru"))
        XCTAssertEqual(t("Общее"), "Общее")
    }
}
