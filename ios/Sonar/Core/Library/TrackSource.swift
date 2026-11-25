import Foundation

/// «Играть из» — сервис, закреплённый за одним треком (лист трека; ПК — `store/track_source.rs`,
/// `services/fallback.rs`, `lib/track-source.ts`). «Авто» (нет записи) — как раньше: резерв и «SoundCloud через
/// Яндекс» решают сами. Закреплён другой сервис — двойник оттуда первым (причина `pinned`); закреплён свой —
/// «SoundCloud через Яндекс» трек не трогает. Не играет выбранное — дальше как в «Авто». Хранится в
/// `LibraryStore.sources`, едет синком в `track_pref` полем `source` (ключ сервиса, `null` — «Авто»).
/// **Правила менять в обоих местах.**
enum TrackSourcePlan {
    /// Ключ сервиса (`sc`, `ym`, `yt` или ключ реестра) → сервис, который можно закрепить: как резерв — ищет и
    /// отдаёт поток. Неизвестное — «Авто» (nil). Как `pin_of` в Rust.
    static func pin(_ key: String?) -> ServiceID? {
        guard let key, let info = ServiceRegistry.byKey(key), FallbackPlan.canBackUp(info) else { return nil }
        return info.id
    }

    /// Прежняя замена ещё годится (`Fallback::allows` в Rust): «SoundCloud через Яндекс» — своим ключом, «Играть
    /// из» — выбором, остальное — `audio.fallback`. Закреплён другой сервис — замена не годится, если только
    /// закреплён свой и он не играет (тогда резерв — по беде, а не по выбору).
    static func keeps(_ via: FallbackVia, pin: ServiceID?, scViaYandex: Bool, fallbackOn: Bool) -> Bool {
        if let pin {
            let ownFailed = pin == via.from && via.reason != .preferred && via.reason != .pinned
            if pin != via.service, !ownFailed { return false }
        }
        switch via.reason {
        case .pinned: return pin == via.service
        case .preferred: return scViaYandex
        default: return fallbackOn
        }
    }

    /// Вариант в листе: «Авто» (nil) или сервис.
    struct Choice: Hashable, Identifiable, Sendable {
        let service: ServiceID?
        var id: String { service?.rawValue ?? "auto" }
    }

    /// Варианты «Играть из»: «Авто» и сервисы, где трек есть (свой первым — порядок реестра). Выбирать не из чего
    /// (трек нашёлся только у себя и ничего не закреплено) — пусто. Как `sourceChoices` на ПК.
    static func choices(ref: String, services: [ServiceID], pinned: ServiceID?) -> [Choice] {
        let own = ServiceRegistry.service(of: ref)
        var list: [ServiceID] = []
        for id in services where !list.contains(id) { list.append(id) }
        if let pinned, !list.contains(pinned) { list.append(pinned) }
        guard list.contains(where: { $0 != own }) || pinned != nil else { return [] }
        return [Choice(service: nil)] + list.map { Choice(service: $0) }
    }

    /// Плашка: откуда играет трек с выбранным «Играть из» — сервис пишется и у своего. «Авто» — как раньше.
    static func labeled(_ source: StreamSource, ref: String, via: FallbackVia?, pinned: ServiceID?) -> StreamSource {
        guard pinned != nil, via == nil, let own = ServiceRegistry.service(of: ref) else { return source }
        return FallbackPlan.labeled(source, own)
    }
}
