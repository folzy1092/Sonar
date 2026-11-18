// Строки статуса подписки на iPhone: карточка «Sonar Deep · Dev · без срока» на экране «Подписка» и значок
// «Dev» у ника (`SonarDeep.subscriptionOf`). Те же ключи, что в windows/src/i18n/*/subscription-dev.ts;
// ключ — русская строка, как в Strings+iOS.swift. Тройки — чтобы en и uk не разошлись по ключам.

extension I18n {
    /// (ru, en, uk)
    static let sonarDeepStrings: [(String, String, String)] = [
        ("Разработчик Sonar: открыто всё Sonar Deep", "Sonar developer: all of Sonar Deep is unlocked",
         "Розробник Sonar: відкрито все Sonar Deep"),
        ("без срока", "no end date", "безстроково"),
        ("Ты разработчик Sonar: всё Sonar Deep открыто, лимитов нет. Тарифы ниже — для остальных.",
         "You’re a Sonar developer: all of Sonar Deep is unlocked, no limits. The plans below are for everyone else.",
         "Ти розробник Sonar: усе Sonar Deep відкрито, лімітів немає. Тарифи нижче — для інших."),
    ]

    static let sonarDeepEN: [String: String] = Dictionary(sonarDeepStrings.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
    static let sonarDeepUK: [String: String] = Dictionary(sonarDeepStrings.map { ($0.0, $0.2) }, uniquingKeysWith: { a, _ in a })
}
