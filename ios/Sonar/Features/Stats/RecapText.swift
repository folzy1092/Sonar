import Foundation

/// Что написано на карточке итогов: надзаголовок, заголовок, большое число с подписью и строки под ним.
/// Списки (топы, сервисы) и столбики часов карточка рисует сама. Как ПК `lib/recap-text.ts`.
struct RecapCardText: Equatable {
    var eyebrow: String
    var title: String
    var value: Int?
    var unit = ""
    var lines: [String] = []
}

/// Подписи итогов на языке интерфейса — одни и те же для экрана и картинки.
@MainActor
enum RecapText {
    /// Месяцы в именительном падеже — один ключ словаря на все 12 (как на ПК).
    private static let months = "Январь|Февраль|Март|Апрель|Май|Июнь|Июль|Август|Сентябрь|Октябрь|Ноябрь|Декабрь"

    /// «Ноябрь 2026» или «2026».
    static func periodTitle(_ ref: RecapRef) -> String {
        guard ref.kind == .month, let month = ref.month else { return String(ref.year) }
        let names = t(months).components(separatedBy: "|")
        let name = names.indices.contains(month - 1) ? names[month - 1] : ""
        return "\(name) \(ref.year)"
    }

    /// «Итоги месяца» / «Итоги года».
    static func kindTitle(_ ref: RecapRef) -> String {
        ref.kind == .year ? t("Итоги года") : t("Итоги месяца")
    }

    static func introLine(_ ref: RecapRef) -> String {
        ref.kind == .year ? t("Твой год в музыке — листай карточки") : t("Твой месяц в музыке — листай карточки")
    }

    /// Число с разделителями разрядов языка интерфейса.
    static func number(_ n: Int) -> String {
        n.formatted(.number.locale(currentLang().locale))
    }

    /// «3 ноября 2026».
    static func dateLong(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(currentLang().locale))
    }

    static func duration(_ ms: Int) -> String {
        let hours = ms / 3_600_000
        if hours > 0 { return "\(number(hours)) \(tn(hours, "час", "часа", "часов"))" }
        let minutes = Int((Double(ms) / 60_000).rounded())
        return "\(minutes) \(tn(minutes, "минута", "минуты", "минут"))"
    }

    static func tracks(_ n: Int) -> String {
        "\(number(n)) \(tn(n, "трек", "трека", "треков"))"
    }

    /// Имя сервиса из реестра (переведённое).
    static func serviceTitle(_ id: ServiceID) -> String {
        t(ServiceRegistry.info(id).name)
    }

    static func hourRange(_ hour: Int) -> String {
        String(format: "%02d:00–%02d:00", hour, (hour + 1) % 24)
    }

    /// Подпись части суток по любимому часу.
    static func listener(_ hour: Int) -> String {
        [t("Ночной слушатель"), t("Утренний слушатель"), t("Дневной слушатель"), t("Вечерний слушатель")][RecapEngine.partOfDay(hour)]
    }

    static func delta(_ value: Int?) -> String? {
        guard let value, value != 0 else { return nil }
        return value > 0
            ? t("На {n}% больше, чем в прошлый раз", ["n": number(value)])
            : t("На {n}% меньше, чем в прошлый раз", ["n": number(abs(value))])
    }

    static func card(_ card: RecapCard, ref: RecapRef) -> RecapCardText {
        switch card {
        case .intro:
            return RecapCardText(eyebrow: kindTitle(ref), title: periodTitle(ref), lines: [introLine(ref)])
        case let .minutes(minutes, delta, days, plays):
            let daysText = "\(days) \(tn(days, "день", "дня", "дней"))"
            let playsText = "\(number(plays)) \(tn(plays, "прослушивание", "прослушивания", "прослушиваний"))"
            let lines = [self.delta(delta), t("{days} с музыкой · {plays}", ["days": daysText, "plays": playsText])]
            return RecapCardText(eyebrow: t("Время с музыкой"), title: "", value: minutes,
                                 unit: tn(minutes, "минута", "минуты", "минут"), lines: lines.compactMap { $0 })
        case let .tracks(list):
            return RecapCardText(eyebrow: t("Топ-5 треков"), title: list.first?.track.title ?? "")
        case let .artists(list):
            return RecapCardText(eyebrow: t("Топ-5 артистов"), title: list.first?.name ?? "")
        case let .newArtist(artist, firstPlayed):
            return RecapCardText(eyebrow: t("Новый артист"), title: artist.name,
                                 lines: [t("Первое прослушивание — {date}", ["date": dateLong(firstPlayed)]), duration(artist.ms)])
        case let .hour(hour, _):
            return RecapCardText(eyebrow: t("Любимый час"), title: hourRange(hour), lines: [listener(hour)])
        case let .day(date, minutes, plays):
            return RecapCardText(eyebrow: t("Самый длинный день"), title: dateLong(date), value: minutes,
                                 unit: tn(minutes, "минута", "минуты", "минут"),
                                 lines: [t("{tracks} за день", ["tracks": tracks(plays)])])
        case let .onRepeat(item, count, date):
            return RecapCardText(eyebrow: t("На повторе"), title: item.track.title, value: count,
                                 unit: tn(count, "раз за день", "раза за день", "раз за день"),
                                 lines: [item.track.artist, dateLong(date)])
        case let .services(list):
            return RecapCardText(eyebrow: t("Сервисы"), title: list.first.map { serviceTitle($0.service) } ?? "",
                                 lines: [t("{pct}% времени — здесь", ["pct": String(list.first?.pct ?? 0)])])
        }
    }
}
