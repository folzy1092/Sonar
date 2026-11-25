import Foundation

// Резервный сервис (docs/NEXT_PROMPT.md, этап 4; Windows — `services/fallback.rs`, `lib/fallback.ts`):
// свой поток трека не играет — тот же трек ищется в других сервисах по порядку `audio.fallback_order`
// и играет оттуда. Сверка строгая (`TrackMatch`): не нашлось точно того же — лучше не играть ничего,
// чем чужой ремикс. «SoundCloud через Яндекс» (`audio.sc_via_yandex`) — тот же механизм, Яндекс первым.

/// Почему трек играет не со своего сервиса (`Reason` в `providers/unplayable.rs`).
enum FallbackReason: String, Sendable, Codable {
    /// Трека на сервисе нет (`available: false`, нет потока, сервис не подключён).
    case unavailable
    /// Только отрывок: превью / `policy: SNIP` SoundCloud, превью вместо полного трека Яндекса.
    case preview
    /// Сервис играет только с подпиской (Spotify без Premium — на iPhone всегда).
    case premium
    /// Поток не открылся и после повтора.
    case failed
    /// Не беда, а настройка: «SoundCloud через Яндекс».
    case preferred
}

/// «Свой поток не играет» с причиной. Текст — прежний: его видят журнал и тост. `preview` — отрывок,
/// который можно сыграть, если замены нет.
struct Unplayable: LocalizedError, Sendable {
    let reason: FallbackReason
    let message: String
    var preview: StreamSource?

    var errorDescription: String? { message }

    /// Причина ошибки потока: своя у `Unplayable`, остальное — «не открылся».
    static func reason(of error: Error) -> FallbackReason {
        (error as? Unplayable)?.reason ?? .failed
    }

    /// Отрывок из ошибки, если он есть.
    static func preview(of error: Error) -> StreamSource? {
        (error as? Unplayable)?.preview
    }
}

/// Трек играет не со своего сервиса: что играет (`ref`), откуда, вместо какого сервиса и почему.
struct FallbackVia: Equatable, Sendable {
    let ref: String
    let service: ServiceID
    let from: ServiceID
    let reason: FallbackReason
}

/// Настройки резерва для ядра: включено ли и порядок сервисов.
struct FallbackSettings: Equatable, Sendable {
    var enabled = true
    var order = FallbackPlan.defaultOrder
}

extension FallbackSettings {
    /// Из значений настроек `audio.fallback` и `audio.fallback_order`.
    init(enabled: Bool, saved: String?) {
        self.init(enabled: enabled, order: FallbackPlan.order(saved))
    }
}

/// Чистая логика резерва: порядок по реестру, кандидаты, текст тоста. Без сети — под XCTest.
enum FallbackPlan {
    static let enabledKey = "audio.fallback"
    /// Порядок — id через запятую (`yt,ym,sc`): `SettingValue` без массивов; на ПК — массив JSON.
    static let orderKey = "audio.fallback_order"

    /// Может быть резервом: работает в Sonar, ищет и отдаёт поток (Spotify без потока и локальные файлы — нет).
    static func canBackUp(_ info: ServiceInfo) -> Bool {
        info.implemented && info.caps.search && info.caps.stream
    }

    /// Порядок по умолчанию — порядок реестра.
    static var defaultOrder: [ServiceID] {
        ServiceRegistry.all.filter(canBackUp).map(\.id)
    }

    /// Сохранённый порядок (id или ключи через запятую) → список: неизвестные и повторы — прочь, забытые
    /// сервисы — в конец в порядке реестра (новый сервис сам встаёт в очередь). Как `parse_order` в Rust.
    static func order(_ saved: String?) -> [ServiceID] {
        var out: [ServiceID] = []
        for part in (saved ?? "").split(separator: ",") {
            let key = part.trimmingCharacters(in: .whitespaces)
            if let info = ServiceRegistry.byKey(key), canBackUp(info), !out.contains(info.id) { out.append(info.id) }
        }
        return out + defaultOrder.filter { !out.contains($0) }
    }

    /// Список → строка настройки.
    static func encode(_ order: [ServiceID]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    /// Где искать замену: по порядку, без исходного сервиса и уже не сработавших.
    static func candidates(order: [ServiceID], from: ServiceID, skip: [ServiceID]) -> [ServiceID] {
        order.filter { $0 != from && !skip.contains($0) }
    }

    /// Новый список, где элемент `from` сдвинут на `offset` (кнопки ↑ ↓ в настройках).
    static func moved<T>(_ list: [T], from: Int, by offset: Int) -> [T] {
        let to = from + offset
        guard list.indices.contains(from), list.indices.contains(to), from != to else { return list }
        var next = list
        next.insert(next.remove(at: from), at: to)
        return next
    }

    /// Плашка качества: «MP3 320 · Яндекс Музыка».
    static func labeled(_ source: StreamSource, _ service: ServiceID) -> StreamSource {
        let name = ServiceRegistry.info(service).name
        switch source {
        case let .file(url, quality): return .file(url: url, quality: "\(quality) · \(name)")
        case let .hls(url, quality): return .hls(url: url, quality: "\(quality) · \(name)")
        }
    }

    /// Тост «Играет из YouTube Music — в SoundCloud недоступен». «SoundCloud через Яндекс» — настройка,
    /// а не беда: без тоста (nil). Ключи — те же русские строки, что на ПК (`lib/fallback.ts`).
    static func toast(_ via: FallbackVia?, lang: Lang) -> String? {
        guard let via, via.reason != .preferred else { return nil }
        let params = [
            "to": I18n.translate(ServiceRegistry.info(via.service).name, lang: lang),
            "from": I18n.translate(ServiceRegistry.info(via.from).nameIn, lang: lang),
        ]
        let key = switch via.reason {
        case .preview: "Играет из {to} — в {from} только отрывок"
        case .premium: "Играет из {to} — в {from} нужна подписка"
        default: "Играет из {to} — в {from} недоступен"
        }
        return I18n.translate(key, lang: lang, params: params)
    }

    @MainActor
    static func toast(_ via: FallbackVia?) -> String? {
        toast(via, lang: currentLang())
    }
}

/// Всплывашка резерва — разовое уведомление, а не постоянная деталь (TASTE_ROOMS_PROMPT §5): одна на трек,
/// держится 4 с. Повторная загрузка того же трека (свежая ссылка, попытка попроще) молчит; трек без резерва
/// сбрасывает память — вернулись к треку с резервом, скажем снова. Зеркало `fallbackNotice` в `lib/fallback.ts`.
enum FallbackNotice {
    /// Сколько держится всплывашка резерва.
    static let seconds: Double = 4
    /// Остальные сообщения плеера — как обычный тост (`Router.say`).
    static let otherSeconds: Double = 2.6

    /// Что сказать на поток трека `ref`: текст (nil — молчать) и новая память `shown` — трек, для которого уже сказали.
    static func next(_ via: FallbackVia?, ref: String, shown: String?, lang: Lang) -> (text: String?, shown: String?) {
        if ref == shown { return (nil, shown) }
        let text = FallbackPlan.toast(via, lang: lang)
        return (text, text == nil ? nil : ref)
    }

    /// Сколько держать сообщение плеера: всплывашка резерва (`note` — её последний текст) — 4 с, остальное — 2.6 с.
    static func seconds(for message: String, note: String?) -> Double {
        message == note ? seconds : otherSeconds
    }
}

extension ServiceInfo {
    /// Название после «в»: «в Яндекс Музыке», «в SoundCloud» (как `nameIn` в `lib/services.ts`).
    var nameIn: String {
        switch id {
        case .ym: "Яндекс Музыке"
        case .vk: "VK Музыке"
        case .local: "локальных файлах"
        case .sc, .yt, .sp: name
        }
    }
}
