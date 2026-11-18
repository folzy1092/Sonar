import Foundation

// Подписка Sonar Deep (решение владельца 2026-11-18), порт ПК `lib/subscription.ts`: в приложении выбирают
// тариф и срок, оплата — на сайте `sonar.folzy.ru/pay` (будущая платёжка). Платно — только функции Sonar,
// не доступ к музыке. Помесячные цены утвердил владелец, скидки за срок — черновик; с сервером придут из
// `GET /config`, тогда эта таблица — запасная. Меняешь здесь — поменяй и на ПК (и наоборот).

enum SonarDeep {
    /// Название подписки (бренд, не переводится).
    static let name = "Sonar Deep"

    struct Plan: Identifiable, Equatable, Sendable {
        let id: String
        /// Бренд, не переводится.
        let name: String
        /// Сколько аккаунтов: ты и ещё N − 1.
        let seats: Int
        /// Цена за месяц при оплате помесячно, ₽.
        let monthly: Int
    }

    struct Period: Identifiable, Equatable, Sendable {
        let id: String
        let months: Int
        /// Скидка за срок, доля (0.25 = −25 %).
        let discount: Double
    }

    static let plans: [Plan] = [
        Plan(id: "ping", name: "Ping", seats: 1, monthly: 100),
        Plan(id: "echo", name: "Echo", seats: 2, monthly: 190),
        Plan(id: "pod", name: "Pod", seats: 3, monthly: 285),
        Plan(id: "fleet", name: "Fleet", seats: 4, monthly: 380),
    ]

    static let periods: [Period] = [
        Period(id: "1m", months: 1, discount: 0),
        Period(id: "3m", months: 3, discount: 0.1),
        Period(id: "6m", months: 6, discount: 0.15),
        Period(id: "12m", months: 12, discount: 0.25),
    ]

    /// Что даёт Sonar Deep — ключи перевода (общие с ПК), по важности.
    static let perks: [String] = [
        "Объёмный звук 3D · 8D · 12D · 16D",
        "Реверб и пространство: зал, клуб, собор",
        "Свои шрифты интерфейса",
        "Своя тема: цвета, фон, поверхности",
        "Перевод текстов песен",
        "Кэш треков без лимита",
        "Плейлисты без лимита",
        "Перенос плейлистов из сервисов без лимита",
        "Пульт-плюс: очередь и громкость ПК с iPhone, передача трека с той же секунды",
        "Подробная статистика прослушиваний",
        "Видео-фон и живые обои из обложки",
        "Цвет и эффект ника, значок Sonar Deep в профиле",
        "Чат подписчиков",
        "Доступ к бета-версиям",
    ]

    /// Округление цены за срок — вниз до 5 ₽, но не меньше 5.
    private static let priceStep = 5

    /// Цена за весь срок, ₽: месяц — как есть, дольше — со скидкой, округлено вниз до 5 ₽ (как ПК `price`).
    static func price(_ plan: Plan, _ period: Period) -> Int {
        if period.months == 1 { return plan.monthly }
        let raw = Double(plan.monthly * period.months) * (1 - period.discount)
        return max(priceStep, Int((raw / Double(priceStep)).rounded(.down)) * priceStep)
    }

    /// Скидка в процентах от помесячной оплаты — по итоговой цене.
    static func savedPercent(_ plan: Plan, _ period: Period) -> Int {
        if period.months == 1 { return 0 }
        let full = Double(plan.monthly * period.months)
        return Int(((1 - Double(price(plan, period)) / full) * 100).rounded())
    }

    /// Ссылка на оплату: аккаунт сайт возьмёт из входа (с сервером), до него — по @username.
    static func payURL(plan: String, period: String, username: String?) -> URL? {
        var parts = URLComponents(string: "\(LocalProfile.siteURL)/pay")
        var query = [URLQueryItem(name: "plan", value: plan), URLQueryItem(name: "period", value: period)]
        let name = username.map(LocalProfile.cleanUsername) ?? ""
        if !name.isEmpty { query.append(URLQueryItem(name: "u", value: name)) }
        parts?.queryItems = query
        return parts?.url
    }

    /// «1 799 ₽» — узкий неразрывный пробел между тысячами и неразрывный перед ₽, как на ПК.
    static func rub(_ amount: Int) -> String {
        let digits = String(abs(amount))
        var groups: [String] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(String(digits[start ..< end]), at: 0)
            end = start
        }
        return (amount < 0 ? "-" : "") + groups.joined(separator: "\u{202F}") + "\u{00A0}₽"
    }
}
