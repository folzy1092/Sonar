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
        XCTAssertEqual(Lang.system(preferred: ["de-DE", "uk-UA"]), .de)
        XCTAssertEqual(Lang.system(preferred: ["fr-FR", "pl-PL"]), .pl)
        XCTAssertEqual(Lang.system(preferred: ["es-MX"]), .es)
        XCTAssertEqual(Lang.system(preferred: ["lv-LV"]), .ru)
        XCTAssertEqual(Lang.system(preferred: []), .ru)
        XCTAssertEqual(Lang.resolve("uk", preferred: ["en"]), .uk)
        XCTAssertEqual(Lang.resolve(nil, preferred: ["en"]), .en)
        XCTAssertEqual(Lang.resolve("de", preferred: ["ru"]), .de)
        XCTAssertEqual(Lang.resolve("fr", preferred: ["ru"]), .ru)
    }

    /// Порядок списка и флаги — как в ТЗ (флаг только рядом с названием).
    func testLanguageListOrderAndFlags() {
        XCTAssertEqual(Lang.allCases, [.ru, .en, .uk, .es, .de, .pl])
        XCTAssertEqual(Lang.allCases.map(\.nativeName), ["Русский", "English", "Українська", "Español", "Deutsch", "Polski"])
        XCTAssertEqual(Lang.allCases.map(\.flag), ["🇷🇺", "🇬🇧", "🇺🇦", "🇪🇸", "🇩🇪", "🇵🇱"])
    }

    func testPolishPluralRule() {
        XCTAssertEqual([1, 2, 4, 5, 12, 14, 22, 25, 101, 102].map(I18n.plPlural), [0, 1, 1, 2, 2, 2, 1, 2, 2, 1])
    }

    /// Нет строки в es / de / pl — английская; нет и её — русская.
    func testNewLanguagesFallBackToEnglish() {
        XCTAssertEqual(I18n.translate("Общее", lang: .de), I18n.dictionaries[.de]?["Общее"])
        XCTAssertNotEqual(I18n.translate("Общее", lang: .de), "General")
        XCTAssertEqual(I18n.translate("Строки нет ни в одном словаре", lang: .pl), "Строки нет ни в одном словаре")
        let forms = ["минута", "минуты", "минут"]
        let pl = (I18n.dictionaries[.pl]?[forms.joined(separator: "|")] ?? "").components(separatedBy: "|")
        XCTAssertEqual(pl.count, 3)
        XCTAssertEqual(I18n.plural(1, forms, lang: .pl), pl[0])
        XCTAssertEqual(I18n.plural(3, forms, lang: .pl), pl[1])
        XCTAssertEqual(I18n.plural(22, forms, lang: .pl), pl[1])
        XCTAssertEqual(I18n.plural(21, forms, lang: .pl), pl[2])
        let de = (I18n.dictionaries[.de]?[forms.joined(separator: "|")] ?? "").components(separatedBy: "|")
        XCTAssertEqual(I18n.plural(1, forms, lang: .de), de.first)
        XCTAssertEqual(I18n.plural(5, forms, lang: .de), de.last)
    }

    /// Словари es / de / pl — все ключи английского, те же подстановки, нужное число форм.
    func testNewLanguageDictionariesAreComplete() {
        let en = I18n.dictionaries[.en] ?? [:]
        for (lang, formCount) in [(Lang.es, 2), (.de, 2), (.pl, 3)] {
            let dict = I18n.dictionaries[lang] ?? [:]
            XCTAssertEqual(Set(en.keys).subtracting(dict.keys), [], "\(lang): нет перевода")
            for (key, value) in en where key.split(separator: "|").count == 3 {
                XCTAssertEqual(dict[key]?.split(separator: "|", omittingEmptySubsequences: false).count, formCount, "\(lang): \(key) (\(value))")
            }
        }
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
