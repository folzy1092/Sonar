import Foundation

// Языки интерфейса (Система → Общее → Язык): русский, English, Українська — как Windows
// `lib/i18n.svelte.ts`. Ключ перевода — **сама русская строка**: `t("Добрый вечер")`. Нет перевода —
// показывается русская, поэтому новая строка без словаря ничего не ломает. Подстановки —
// `t("Версия {version}", ["version": v])`. Множественное — `tn(n, "трек", "трека", "треков")`: ключ —
// три формы через «|», в английском словаре две («track|tracks»), в украинском три.
// Одно слово с разным смыслом — ключ с контекстом `"навигация::Назад"`: по-русски видно «Назад»,
// в словаре свой перевод («Back», а не «Previous» у плеера).
// Словари: `Strings+Windows.swift` (сгенерирован из windows/src/i18n) и `Strings+iOS.swift` (только iOS,
// главнее), а также свои словари разделов (`Strings+Library.swift`, `Strings+YouTube.swift`).
// Язык — `general.language`; не выбран — язык системы, если он ru / en / uk, иначе русский.
// Смена — сразу: `t()` читает настройку из `SettingsStore` (@Observable), экраны перерисовываются.

enum Lang: String, CaseIterable, Identifiable, Sendable {
    case ru, en, uk

    static let settingKey = "general.language"

    var id: String { rawValue }

    /// Название языка на нём самом — в списке выбора.
    var nativeName: String {
        switch self {
        case .ru: "Русский"
        case .en: "English"
        case .uk: "Українська"
        }
    }

    /// Язык по умолчанию: первый из предпочитаемых системой, если он наш, иначе русский.
    static func system(preferred: [String] = Locale.preferredLanguages) -> Lang {
        for id in preferred {
            let code = id.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { String($0).lowercased() } ?? ""
            if let lang = Lang(rawValue: code) { return lang }
        }
        return .ru
    }

    /// Из значения настройки: `ru` / `en` / `uk`; пусто или другое — язык системы.
    static func resolve(_ setting: String?, preferred: [String] = Locale.preferredLanguages) -> Lang {
        if let setting, let lang = Lang(rawValue: setting) { return lang }
        return system(preferred: preferred)
    }

    /// Для форматтеров дат и чисел.
    var locale: Locale { Locale(identifier: rawValue) }
}

enum I18n {
    /// Словарь языка: Windows + iOS (iOS главнее), затем медиатека и экспорт (`Strings+Library`, `Strings+Export`).
    static let dictionaries: [Lang: [String: String]] = [
        .en: windowsEN.merging(iosEN) { _, ios in ios }.merging(accountEN) { _, a in a }.merging(libraryEN) { _, l in l }
            .merging(exportEN) { _, e in e }.merging(youtubeEN) { _, y in y }.merging(spotifyEN) { _, s in s },
        .uk: windowsUK.merging(iosUK) { _, ios in ios }.merging(accountUK) { _, a in a }.merging(libraryUK) { _, l in l }
            .merging(exportUK) { _, e in e }.merging(youtubeUK) { _, y in y }.merging(spotifyUK) { _, s in s },
    ]

    /// Перевод строки (ключ — русский текст, можно с контекстом `контекст::Текст`).
    static func translate(_ ru: String, lang: Lang, params: [String: String] = [:]) -> String {
        let plain = ru.range(of: "::").map { String(ru[$0.upperBound...]) } ?? ru
        let text = lang == .ru ? plain : (dictionaries[lang]?[ru] ?? plain)
        return fill(text, params)
    }

    /// Русское правило множественного числа: 0 — одна, 1 — две, 2 — три формы.
    static func ruPlural(_ n: Int) -> Int {
        let a = abs(n) % 100
        let b = a % 10
        if a > 10, a < 20 { return 2 }
        if b > 1, b < 5 { return 1 }
        return b == 1 ? 0 : 2
    }

    /// Слово при числе: 5, «трек / трека / треков» → «треков» / «tracks» / «треків».
    static func plural(_ n: Int, _ forms: [String], lang: Lang) -> String {
        guard forms.count == 3 else { return forms.first ?? "" }
        let ru = forms[ruPlural(n)]
        guard lang != .ru, let raw = dictionaries[lang]?[forms.joined(separator: "|")] else { return ru }
        let tr = raw.components(separatedBy: "|")
        if lang == .en { return abs(n) == 1 ? tr[0] : (tr.count > 1 ? tr[1] : tr[0]) }
        let i = ruPlural(n)
        return i < tr.count ? tr[i] : (tr.last ?? ru)
    }

    /// `{name}` → значение; неизвестные остаются как есть.
    static func fill(_ text: String, _ params: [String: String]) -> String {
        guard !params.isEmpty, text.contains("{") else { return text }
        var out = text
        for (key, value) in params {
            out = out.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return out
    }
}

/// Текущий язык интерфейса (реактивно: вызов из `body` подписывает экран на смену).
@MainActor
func currentLang() -> Lang {
    let raw: String?
    if case let .string(value)? = SettingsStore.shared.value(Lang.settingKey) { raw = value } else { raw = nil }
    return Lang.resolve(raw)
}

/// Перевод строки интерфейса: `t("Общее")`, `t("Версия {version}", ["version": "0.1.0"])`.
@MainActor
func t(_ ru: String, _ params: [String: String] = [:]) -> String {
    I18n.translate(ru, lang: currentLang(), params: params)
}

/// Слово при числе: `tn(5, "трек", "трека", "треков")`.
@MainActor
func tn(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    I18n.plural(n, [one, few, many], lang: currentLang())
}
