import Foundation

// Подписка Sonar Deep (решение владельца 2026-11-18), порт ПК `lib/subscription.ts`: в приложении выбирают
// тариф и срок, оплата — на сайте `try-sonar.ru/pay` (будущая платёжка). Платно — только функции Sonar,
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

    /// Строка под тарифами: кому достаётся Deep — «только для тебя» / «для тебя и ещё одного друга…» (как ПК
    /// `seatsNote` в `Subscription.svelte`); друзья — с аккаунтом Sonar.
    static func seatsNote(seats: Int, lang: Lang) -> String {
        let friends = seats - 1
        switch friends {
        case ...0: return I18n.translate("Deep только для тебя", lang: lang)
        case 1: return I18n.translate("Deep для тебя и ещё одного друга, у которого есть аккаунт Sonar", lang: lang)
        case 2: return I18n.translate("Deep для тебя и ещё двух друзей, у которых есть аккаунт Sonar", lang: lang)
        case 3: return I18n.translate("Deep для тебя и ещё трёх друзей, у которых есть аккаунт Sonar", lang: lang)
        default:
            let forms = ["Deep для тебя и ещё {n} друга, у которого есть аккаунт Sonar",
                         "Deep для тебя и ещё {n} друзей, у которых есть аккаунт Sonar",
                         "Deep для тебя и ещё {n} друзей, у которых есть аккаунт Sonar"]
            return I18n.fill(I18n.plural(friends, forms, lang: lang), ["n": String(friends)])
        }
    }

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
        "Эквалайзер",
        "Sonar Mix под себя: тонкая подстройка, свои волны, больше настроений",
        "Подробная статистика: история без срока, итоги за любой период, экспорт",
        "Больше устройств и пульт-плюс: очередь и эквалайзер ПК с iPhone, передача трека с той же секунды",
        "Перевод текстов песен",
        "Кэш треков без лимита",
        "Плейлисты без лимита",
        "Больше умных плейлистов",
        "Перенос плейлистов из сервисов без лимита",
        "Свои темы оверлея и OBS-плашки",
        "Приоритет у баг-репортов и идей в боте",
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

    // MARK: Статус подписки аккаунта

    /// Уровень: бесплатный или разработчик Sonar (всё открыто). С сервером добавятся оплаченные тарифы.
    enum Tier: String, Equatable, Sendable {
        case free
        case dev
    }

    /// Подписка аккаунта (как ПК `Subscription`): открыто ли Sonar Deep, сняты ли бесплатные лимиты, до какого числа.
    struct Subscription: Equatable, Sendable {
        let tier: Tier
        /// Открыты функции Sonar Deep.
        let deep: Bool
        /// Бесплатные лимиты (плейлисты, перенос, кэш) не действуют.
        let unlimited: Bool
        /// Конец срока; nil — без срока.
        let until: Date?
    }

    /// Ники разработчиков Sonar (без «@», в нижнем регистре) — как ПК `DEV_USERNAMES`.
    static let devUsernames: Set<String> = ["folzy"]

    static let freeSubscription = Subscription(tier: .free, deep: false, unlimited: false, until: nil)
    static let devSubscription = Subscription(tier: .dev, deep: true, unlimited: true, until: nil)

    /// Ник для сравнения: без пробелов по краям, без «@» в начале, в нижнем регистре (ПК `normalizeUsername`).
    static func normalizeUsername(_ raw: String?) -> String {
        LocalProfile.cleanUsername(raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Подписка аккаунта — ЕДИНСТВЕННОЕ место, где она решается (порт ПК `subscriptionOf`). До сервера это
    /// ЛОКАЛЬНАЯ проверка по нику из `profile.username`: разработчику (`folzy`) открыто всё, без лимитов и срока.
    /// С сервером её заменит ответ `GET /me` — экраны менять не придётся, они спрашивают только эту функцию.
    static func subscriptionOf(username: String?) -> Subscription {
        let nick = normalizeUsername(username)
        return !nick.isEmpty && devUsernames.contains(nick) ? devSubscription : freeSubscription
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
