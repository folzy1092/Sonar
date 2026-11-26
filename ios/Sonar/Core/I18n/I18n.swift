import Foundation

// Языки интерфейса (Система → Общее → Язык): русский, English, Українська, Español, Deutsch, Polski — как
// Windows `lib/i18n.svelte.ts`. Ключ перевода — **сама русская строка**: `t("Добрый вечер")`. Нет перевода в
// украинском — показывается русская; в испанском, немецком и польском — английская, а нет и её — русская,
// поэтому новая строка без словаря ничего не ломает. Подстановки — `t("Версия {version}", ["version": v])`.
// Множественное — `tn(n, "трек", "трека", "треков")`: ключ — три формы через «|», в английском, испанском и
// немецком словарях две («track|tracks»), в украинском и польском три (у польского своё правило — `plPlural`).
// Одно слово с разным смыслом — ключ с контекстом `"навигация::Назад"`: по-русски видно «Назад»,
// в словаре свой перевод («Back», а не «Previous» у плеера).
// Словари: `Strings+Windows.swift` (сгенерирован из windows/src/i18n) и `Strings+iOS.swift` (только iOS,
// главнее), а также свои словари разделов (`Strings+Library.swift`, `Strings+YouTube.swift`). У es / de / pl —
// `Strings+Windows{ES,DE,PL}.swift` (генератор) и `Strings+App{ES,DE,PL}.swift` (все строки iPhone).
// Язык — `general.language`; не выбран — язык системы, если он из списка, иначе русский.
// Смена — сразу: `t()` читает настройку из `SettingsStore` (@Observable), экраны перерисовываются.

enum Lang: String, CaseIterable, Identifiable, Sendable {
    case ru, en, uk, es, de, pl

    static let settingKey = "general.language"

    var id: String { rawValue }

    /// Название языка на нём самом — в списке выбора.
    var nativeName: String {
        switch self {
        case .ru: "Русский"
        case .en: "English"
        case .uk: "Українська"
        case .es: "Español"
        case .de: "Deutsch"
        case .pl: "Polski"
        }
    }

    /// Флаг перед названием в списке — только рядом с ним, никогда вместо.
    var flag: String {
        switch self {
        case .ru: "🇷🇺"
        case .en: "🇬🇧"
        case .uk: "🇺🇦"
        case .es: "🇪🇸"
        case .de: "🇩🇪"
        case .pl: "🇵🇱"
        }
    }

    /// Недостающая строка берётся из английского (а не из русского) — es / de / pl.
    var fallsBackToEnglish: Bool { self == .es || self == .de || self == .pl }

    /// Две формы множественного числа (1 — первая, иначе вторая) — en / es / de.
    var hasTwoPluralForms: Bool { self == .en || self == .es || self == .de }

    /// Язык по умолчанию: первый из предпочитаемых системой, если он наш, иначе русский.
    static func system(preferred: [String] = Locale.preferredLanguages) -> Lang {
        for id in preferred {
            let code = id.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { String($0).lowercased() } ?? ""
            if let lang = Lang(rawValue: code) { return lang }
        }
        return .ru
    }

    /// Из значения настройки: `ru` / `en` / `uk` / `es` / `de` / `pl`; пусто или другое — язык системы.
    static func resolve(_ setting: String?, preferred: [String] = Locale.preferredLanguages) -> Lang {
        if let setting, let lang = Lang(rawValue: setting) { return lang }
        return system(preferred: preferred)
    }

    /// Для форматтеров дат и чисел.
    var locale: Locale { Locale(identifier: rawValue) }
}

enum I18n {
    /// Словарь языка: Windows + iOS (iOS главнее), затем свои словари экранов (`Strings+Library`, `Strings+Export`,
    /// `Strings+YouTube`, `Strings+Spotify`, `Strings+Fallback`, `Strings+Smart`, `Strings+Remote`, `Strings+SonarDeep`, `Strings+Search`, `Strings+Offline`, `Strings+Blend`, `Strings+Share`, `Strings+TrackSource`, `Strings+Ban`).
    static let dictionaries: [Lang: [String: String]] = [
        .en: windowsEN.merging(iosEN) { _, ios in ios }.merging(accountEN) { _, a in a }.merging(libraryEN) { _, l in l }
            .merging(exportEN) { _, e in e }.merging(youtubeEN) { _, y in y }.merging(spotifyEN) { _, s in s }.merging(fallbackEN) { _, f in f }
            .merging(smartEN) { _, s in s }
            .merging(remoteEN) { _, r in r }
            .merging(sonarDeepEN) { _, d in d }
            .merging(searchEN) { _, s in s }
            .merging(offlineEN) { _, o in o }
            .merging(blendEN) { _, b in b }
            .merging(shareEN) { _, s in s }
            .merging(trackSourceEN) { _, s in s }
            .merging(banEN) { _, b in b },
        .uk: windowsUK.merging(iosUK) { _, ios in ios }.merging(accountUK) { _, a in a }.merging(libraryUK) { _, l in l }
            .merging(exportUK) { _, e in e }.merging(youtubeUK) { _, y in y }.merging(spotifyUK) { _, s in s }.merging(fallbackUK) { _, f in f }
            .merging(smartUK) { _, s in s }
            .merging(remoteUK) { _, r in r }
            .merging(sonarDeepUK) { _, d in d }
            .merging(searchUK) { _, s in s }
            .merging(offlineUK) { _, o in o }
            .merging(blendUK) { _, b in b }
            .merging(shareUK) { _, s in s }
            .merging(trackSourceUK) { _, s in s }
            .merging(banUK) { _, b in b },
        .es: windowsES.merging(appES) { _, a in a }.merging(shareES) { _, s in s }.merging(trackSourceES) { _, s in s }.merging(banES) { _, b in b },
        .de: windowsDE.merging(appDE) { _, a in a }.merging(shareDE) { _, s in s }.merging(trackSourceDE) { _, s in s }.merging(banDE) { _, b in b },
        .pl: windowsPL.merging(appPL) { _, a in a }.merging(sharePL) { _, s in s }.merging(trackSourcePL) { _, s in s }.merging(banPL) { _, b in b },
    ]

    /// Своя строка языка или, у es / de / pl, английская.
    static func lookup(_ key: String, lang: Lang) -> (text: String, lang: Lang)? {
        if let own = dictionaries[lang]?[key] { return (own, lang) }
        if lang.fallsBackToEnglish, let en = dictionaries[.en]?[key] { return (en, .en) }
        return nil
    }

    /// Перевод строки (ключ — русский текст, можно с контекстом `контекст::Текст`).
    static func translate(_ ru: String, lang: Lang, params: [String: String] = [:]) -> String {
        let plain = ru.range(of: "::").map { String(ru[$0.upperBound...]) } ?? ru
        let text = lang == .ru ? plain : (lookup(ru, lang: lang)?.text ?? plain)
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

    /// Польское правило: 0 — 1, 1 — 2–4 (кроме 12–14), 2 — остальное (0, 5–21, 25…).
    static func plPlural(_ n: Int) -> Int {
        let a = abs(n)
        if a == 1 { return 0 }
        let b = a % 10
        let c = a % 100
        return b > 1 && b < 5 && (c < 12 || c > 14) ? 1 : 2
    }

    /// Слово при числе: 5, «трек / трека / треков» → «треков» / «tracks» / «треків» / «utworów».
    static func plural(_ n: Int, _ forms: [String], lang: Lang) -> String {
        guard forms.count == 3 else { return forms.first ?? "" }
        let ru = forms[ruPlural(n)]
        guard lang != .ru, let (raw, from) = lookup(forms.joined(separator: "|"), lang: lang) else { return ru }
        let tr = raw.components(separatedBy: "|")
        if from.hasTwoPluralForms { return abs(n) == 1 ? tr[0] : (tr.count > 1 ? tr[1] : tr[0]) }
        let i = from == .pl ? plPlural(n) : ruPlural(n)
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
