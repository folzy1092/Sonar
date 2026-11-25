import Foundation

// Резервный сервис в ядре (порт `Core::resolve_playable` из `windows/src-tauri/src/services/fallback.rs`):
// свой поток не играет (нет на сервисе, только отрывок, нужна подписка, не открылся и после повтора) —
// тот же трек ищется по `audio.fallback_order` и играет оттуда. «SoundCloud через Яндекс» — тот же путь,
// Яндекс первым и без тоста. Пары ref → ref помнятся на сеанс (до сервера — без таблицы `track_alias`).

extension MusicCore {
    /// Что играть: поток и, если не свой, откуда он (`via`) — для тоста и плашки качества.
    struct Playable: Sendable {
        let source: StreamSource
        let via: FallbackVia?
    }

    /// Сколько пар держать в памяти, дальше — начать заново.
    static let maxAliases = 5000
    /// Сколько найденных треков сверять на каждый запрос.
    static let aliasSearchLimit = 8

    /// Поток трека с резервом. fresh/safe — как у `stream`; broken — свой поток уже не открылся в плеере
    /// (и после свежей ссылки): сразу искать замену. pin — «Играть из» этого трека (`TrackSourcePlan`, nil — «Авто»).
    func playable(_ track: Track, fresh: Bool = false, safe: Bool = false, broken: Bool = false,
                  pin: ServiceID? = nil) async throws -> Playable {
        let ref = track.ref
        guard let from = ServiceRegistry.service(of: ref), from != .local else {
            return Playable(source: try await stream(ref, fresh: fresh, safe: safe), via: nil)
        }
        var skip: [ServiceID] = []
        var ownBroken = broken
        if let via = routed[ref], !TrackSourcePlan.keeps(via, pin: pin, scViaYandex: soundCloudViaYandex, fallbackOn: fallback.enabled) {
            // выбор поменяли (или вернули «Авто») — прежняя замена не играет, пара остаётся в памяти
            routed[ref] = nil
        }
        if let via = routed[ref] {
            if broken {
                // сломалась замена, а не свой поток
                ownBroken = false
                streams[via.ref] = nil
            } else if let source = try? await stream(via.ref, fresh: fresh, safe: safe) {
                return Playable(source: FallbackPlan.labeled(source, via.service), via: via)
            }
            routed[ref] = nil
            forget(ref, via.service)
            skip.append(via.service)
        }
        if ownBroken { streams[ref] = nil }
        // «Играть из» другого сервиса: двойник оттуда первым; не нашёлся или не играет — как в «Авто»
        if let pin, pin != from, !skip.contains(pin), canSearch(pin) {
            if let played = await tryAlias(track, from: from, in: pin, reason: .pinned, fresh: fresh) { return played }
            skip.append(pin)
        }
        // «SoundCloud через Яндекс» — только в «Авто»
        if pin == nil, from == .sc, soundCloudViaYandex, !safe, !ownBroken, yandex != nil, !skip.contains(.ym) {
            if let played = await tryAlias(track, from: from, in: .ym, reason: .preferred, fresh: fresh) { return played }
            skip.append(.ym)
        }
        let failure: Error
        if ownBroken {
            failure = Unplayable(reason: .failed, message: "поток не открылся")
        } else {
            do {
                let own = try await ownStream(ref, fresh: fresh, safe: safe)
                return Playable(source: TrackSourcePlan.labeled(own, ref: ref, via: nil, pinned: pin), via: nil)
            } catch {
                failure = error
            }
        }
        if fallback.enabled {
            let reason = Unplayable.reason(of: failure)
            for service in FallbackPlan.candidates(order: fallback.order, from: from, skip: skip) where canSearch(service) {
                if let played = await tryAlias(track, from: from, in: service, reason: reason, fresh: fresh) { return played }
            }
        }
        if let preview = Unplayable.preview(of: failure) { return Playable(source: preview, via: nil) }
        throw failure
    }

    /// «Играть из»: на каких сервисах трек есть — свой (если сервис отдаёт поток) и найденные двойники, в порядке
    /// реестра. Двойники — из памяти пар или поиском, не дольше `sourcesTimeout` на всё (как `play_sources` на ПК).
    func playSources(for track: Track) async -> [ServiceID] {
        let ref = track.ref
        guard let from = ServiceRegistry.service(of: ref), from != .local else { return [] }
        // где искать — заранее, в ядре: тело группы задач состояние ядра не трогает
        let look = FallbackPlan.defaultOrder.filter { $0 != from && (aliases[ref]?[$0] != nil || canSearch($0)) }
        let found: [ServiceID] = await withTaskGroup(of: ServiceID?.self) { group in
            for service in look {
                group.addTask {
                    await Self.within(Self.sourcesTimeout) { await self.twin(track, in: service) } ?? nil
                }
            }
            var out: [ServiceID] = []
            for await id in group { if let id { out.append(id) } }
            return out
        }
        return FallbackPlan.defaultOrder.filter { $0 == from || found.contains($0) }
    }

    /// Дольше одного сервиса лист «Играть из» не ждёт.
    static let sourcesTimeout: Duration = .seconds(5)

    /// Двойник трека в сервисе (или nil): известная пара или поиск.
    private func twin(_ track: Track, in service: ServiceID) async -> ServiceID? {
        if let known = aliases[track.ref]?[service] { return known == nil ? nil : service }
        guard let wanted = await fallbackMatch(ref: track.ref, meta: track) else { return nil }
        return await aliasRef(track.ref, wanted: wanted, in: service) == nil ? nil : service
    }

    /// Результат работы или nil, если не успела за `limit`.
    private static func within<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask { try? await Task.sleep(for: limit); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Свой поток; сетевой сбой (не «не играет») — ещё раз со свежей ссылкой.
    private func ownStream(_ ref: String, fresh: Bool, safe: Bool) async throws -> StreamSource {
        do {
            return try await stream(ref, fresh: fresh, safe: safe)
        } catch where !(error is Unplayable) && !fresh {
            return try await stream(ref, fresh: true, safe: safe)
        }
    }

    /// Можно ли сейчас искать в сервисе: SoundCloud и YouTube — без входа, Яндекс — если подключён.
    func canSearch(_ service: ServiceID) -> Bool {
        switch service {
        case .sc, .yt: true
        case .ym: yandex != nil
        case .vk, .sp, .local: false
        }
    }

    /// Тот же трек в `service` и его поток; нет или не играет — nil.
    private func tryAlias(_ track: Track, from: ServiceID, in service: ServiceID, reason: FallbackReason, fresh: Bool) async -> Playable? {
        guard let wanted = await fallbackMatch(ref: track.ref, meta: track),
              let alias = await aliasRef(track.ref, wanted: wanted, in: service) else { return nil }
        guard let source = try? await stream(alias, fresh: fresh) else {
            // найденное перестало играть — в следующий раз искать заново
            forget(track.ref, service)
            return nil
        }
        let via = FallbackVia(ref: alias, service: service, from: from, reason: reason)
        routed[track.ref] = via
        return Playable(source: FallbackPlan.labeled(source, service), via: via)
    }

    /// Что искать. SoundCloud — по сырому JSON (исполнитель из метаданных, полная длительность), иначе — по треку.
    func fallbackMatch(ref: String, meta: Track?) async -> TrackMatch? {
        if ServiceRegistry.service(of: ref) == .sc {
            let id = String(ref.dropFirst("sc:".count))
            let cached = soundCloudRaw[ref]
            let json: JSONValue? = if let cached { cached } else { try? await withSoundCloud { try await $0.trackJSON(id) } }
            if let json {
                soundCloudRaw[ref] = json
                return TrackMatch.soundCloud(
                    uploader: json["user"]["username"].string ?? "",
                    metaArtist: json["publisher_metadata"]["artist"].string,
                    title: json["title"].string ?? "",
                    durationMs: json["full_duration"].int ?? json["duration"].int ?? 0
                )
            }
        }
        guard let meta, !meta.title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return TrackMatch.from(meta)
    }

    /// ref того же трека в `service` (память на сеанс; «нет» тоже помнится, сбой сети — нет).
    func aliasRef(_ ref: String, wanted: TrackMatch, in service: ServiceID) async -> String? {
        if let known = aliases[ref]?[service] { return known }
        guard let target = Service(id: service) else { return nil }
        var failed = false
        var found: String?
        for query in wanted.queries {
            do {
                let candidates = try await search(query, in: target, limit: Self.aliasSearchLimit)
                if let match = wanted.best(candidates, reuploads: service == .sc) {
                    found = match.ref
                    break
                }
            } catch {
                failed = true
            }
        }
        if found != nil || !failed { remember(ref, service, found) }
        return found
    }

    /// Пара перестала играть — забыть (и найденное, и «нет»).
    private func forget(_ ref: String, _ service: ServiceID) {
        aliases[ref]?[service] = nil
    }

    private func remember(_ ref: String, _ service: ServiceID, _ alias: String?) {
        if aliases.count > Self.maxAliases { aliases.removeAll() }
        aliases[ref, default: [:]][service] = .some(alias)
    }
}
