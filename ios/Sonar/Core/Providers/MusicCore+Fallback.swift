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
    /// (и после свежей ссылки): сразу искать замену.
    func playable(_ track: Track, fresh: Bool = false, safe: Bool = false, broken: Bool = false) async throws -> Playable {
        let ref = track.ref
        guard let from = ServiceRegistry.service(of: ref), from != .local else {
            return Playable(source: try await stream(ref, fresh: fresh, safe: safe), via: nil)
        }
        var skip: [ServiceID] = []
        var ownBroken = broken
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
        if from == .sc, soundCloudViaYandex, !safe, !ownBroken, yandex != nil, !skip.contains(.ym) {
            if let played = await tryAlias(track, from: from, in: .ym, reason: .preferred, fresh: fresh) { return played }
            skip.append(.ym)
        }
        let failure: Error
        if ownBroken {
            failure = Unplayable(reason: .failed, message: "поток не открылся")
        } else {
            do {
                return Playable(source: try await ownStream(ref, fresh: fresh, safe: safe), via: nil)
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

    /// Свой поток; сетевой сбой (не «не играет») — ещё раз со свежей ссылкой.
    private func ownStream(_ ref: String, fresh: Bool, safe: Bool) async throws -> StreamSource {
        do {
            return try await stream(ref, fresh: fresh, safe: safe)
        } catch where !(error is Unplayable) && !fresh {
            return try await stream(ref, fresh: true, safe: safe)
        }
    }

    /// Можно ли сейчас искать в сервисе: SoundCloud и YouTube — без входа, Яндекс и VK — если подключены.
    func canSearch(_ service: ServiceID) -> Bool {
        switch service {
        case .sc, .yt: true
        case .ym: yandex != nil
        case .vk: vk != nil
        case .sp, .local: false
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
