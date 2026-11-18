import XCTest
@testable import Sonar

/// Sonar Deep на iPhone: цены как на ПК (`lib/subscription.ts`), ссылка на оплату, статус Dev по нику и строки экрана.
@MainActor
final class SonarDeepTests: XCTestCase {
    private func plan(_ id: String) -> SonarDeep.Plan { SonarDeep.plans.first { $0.id == id }! }
    private func period(_ id: String) -> SonarDeep.Period { SonarDeep.periods.first { $0.id == id }! }

    func testTiersAndPeriods() {
        XCTAssertEqual(SonarDeep.plans.map(\.id), ["ping", "echo", "pod", "fleet"])
        XCTAssertEqual(SonarDeep.plans.map(\.seats), [1, 2, 3, 4])
        XCTAssertEqual(SonarDeep.periods.map(\.months), [1, 3, 6, 12])
    }

    func testPricesMatchPc() {
        XCTAssertEqual(SonarDeep.price(plan("fleet"), period("1m")), 380)
        XCTAssertEqual(SonarDeep.price(plan("echo"), period("3m")), 510)
        XCTAssertEqual(SonarDeep.price(plan("pod"), period("6m")), 1450)
        XCTAssertEqual(SonarDeep.price(plan("ping"), period("12m")), 900)
        XCTAssertEqual(SonarDeep.price(plan("fleet"), period("12m")), 3420)
    }

    func testPricesRoundDownToFive() {
        for p in SonarDeep.plans {
            for d in SonarDeep.periods {
                XCTAssertEqual(SonarDeep.price(p, d) % 5, 0, "\(p.id) \(d.id)")
                XCTAssertLessThanOrEqual(SonarDeep.price(p, d), p.monthly * d.months)
            }
        }
    }

    func testSavedPercent() {
        XCTAssertEqual(SonarDeep.savedPercent(plan("fleet"), period("1m")), 0)
        XCTAssertEqual(SonarDeep.savedPercent(plan("echo"), period("3m")), 11)
        XCTAssertEqual(SonarDeep.savedPercent(plan("ping"), period("12m")), 25)
    }

    func testPayURL() {
        XCTAssertEqual(SonarDeep.payURL(plan: "echo", period: "3m", username: "folzy")?.absoluteString,
                       "https://sonar.folzy.ru/pay?plan=echo&period=3m&u=folzy")
        XCTAssertEqual(SonarDeep.payURL(plan: "echo", period: "3m", username: " @folzy ")?.absoluteString,
                       "https://sonar.folzy.ru/pay?plan=echo&period=3m&u=folzy")
        XCTAssertEqual(SonarDeep.payURL(plan: "ping", period: "1m", username: "")?.absoluteString,
                       "https://sonar.folzy.ru/pay?plan=ping&period=1m")
        XCTAssertEqual(SonarDeep.payURL(plan: "ping", period: "1m", username: nil)?.absoluteString,
                       "https://sonar.folzy.ru/pay?plan=ping&period=1m")
    }

    func testRub() {
        XCTAssertEqual(SonarDeep.rub(100), "100\u{00A0}₽")
        XCTAssertEqual(SonarDeep.rub(3420), "3\u{202F}420\u{00A0}₽")
        XCTAssertEqual(SonarDeep.rub(1_234_567), "1\u{202F}234\u{202F}567\u{00A0}₽")
    }

    func testOwnerNickIsDev() {
        for nick in ["folzy", "@Folzy", " folzy ", "  @FOLZY  "] {
            let sub = SonarDeep.subscriptionOf(username: nick)
            XCTAssertEqual(sub, SonarDeep.devSubscription, nick)
            XCTAssertEqual(sub.tier, .dev, nick)
            XCTAssertTrue(sub.deep, nick)
            XCTAssertTrue(sub.unlimited, nick)
            XCTAssertNil(sub.until, nick)
        }
    }

    func testOtherOrEmptyNickIsFree() {
        for nick in ["other", "folzy2", "fol zy", "", "   ", "@", nil] as [String?] {
            let sub = SonarDeep.subscriptionOf(username: nick)
            XCTAssertEqual(sub, SonarDeep.freeSubscription, String(describing: nick))
            XCTAssertFalse(sub.deep)
            XCTAssertFalse(sub.unlimited)
        }
    }

    func testNormalizeUsername() {
        XCTAssertEqual(SonarDeep.normalizeUsername("  @@FolZy "), "folzy")
        XCTAssertEqual(SonarDeep.normalizeUsername(nil), "")
    }

    func testDevStringsTranslated() {
        let keys = ["Разработчик Sonar: открыто всё Sonar Deep", "без срока",
                    "Ты разработчик Sonar: всё Sonar Deep открыто, лимитов нет. Тарифы ниже — для остальных."]
        for lang in [Lang.en, .uk] {
            let dict = I18n.dictionaries[lang] ?? [:]
            for key in keys { XCTAssertNotNil(dict[key], "\(lang): \(key)") }
        }
    }

    func testScreenStringsTranslated() {
        let keys = SonarDeep.perks + [
            "Подписка", "Тариф", "Срок", "Итого", "1 год", "Только ты", "Подписка на {period}", "Перейти к оплате",
            "{n} месяц|{n} месяца|{n} месяцев", "Ты и ещё {n} человек|Ты и ещё {n} человека|Ты и ещё {n} человек",
            "Музыка, лайки, плейлисты, синхронизация и скачивание треков — бесплатно.",
            "Оплата откроется на сайте Sonar. Подписка придёт на аккаунт, с которого ты её оформил.",
        ]
        for lang in [Lang.en, .uk] {
            let dict = I18n.dictionaries[lang] ?? [:]
            for key in keys { XCTAssertNotNil(dict[key], "\(lang): \(key)") }
        }
    }
}
