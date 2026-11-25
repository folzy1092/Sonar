import Foundation

/// «Поделиться» (docs/SPACE_SHARE_PROMPT.md §3): тот же трек в YouTube, SoundCloud и Яндексе для ссылки на сайт.
/// Как `services/share.rs` на ПК: пара из памяти резерва или поиск теми же клиентами, всё параллельно,
/// не дольше `shareTimeout` — не успели, делимся тем, что есть.
extension MusicCore {
    struct ShareTwins: Sendable, Equatable {
        /// Ключ сервиса → ref найденного трека и ссылка на него.
        var refs: [String: String] = [:]
        var urls: [String: String] = [:]
        /// SoundCloud (свой или двойник) играется целиком, а не Go+-отрывком.
        var scFull = false
    }

    static let shareTimeout: Duration = .seconds(4)
    private static let shareLookIn: [ServiceID] = [.yt, .sc, .ym]

    func shareTwins(for track: Track) async -> ShareTwins {
        guard !OfflineFlag.isOn, let from = ServiceRegistry.service(of: track.ref), from != .local else { return ShareTwins() }
        return await withTaskGroup(of: ShareTwins?.self) { group in
            group.addTask { await self.findShareTwins(track, from: from) }
            group.addTask {
                try? await Task.sleep(for: Self.shareTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? ShareTwins()
        }
    }

    private func findShareTwins(_ track: Track, from: ServiceID) async -> ShareTwins {
        var out = ShareTwins()
        let wanted = await fallbackMatch(ref: track.ref, meta: track)
        await withTaskGroup(of: (ServiceID, Track?, String?).self) { group in
            for svc in Self.shareLookIn where svc != from {
                group.addTask { await self.shareTwin(track.ref, wanted: wanted, in: svc) }
            }
            for await (svc, found, known) in group {
                if let found {
                    out.refs[svc.rawValue] = found.ref
                    if let url = found.url { out.urls[svc.rawValue] = url }
                } else if let known {
                    out.refs[svc.rawValue] = known
                }
            }
        }
        let sc = from == .sc ? track.ref : out.refs["sc"]
        if let sc { out.scFull = await soundCloudIsFull(sc) }
        return out
    }

    /// Двойник в `service`: известная пара (только ref) или поиск (трек со ссылкой — нужен путь SoundCloud).
    private func shareTwin(_ ref: String, wanted: TrackMatch?, in service: ServiceID) async -> (ServiceID, Track?, String?) {
        if let known = aliases[ref]?[service] { return (service, nil, known) }
        guard canSearch(service), let wanted, let target = Service(id: service) else { return (service, nil, nil) }
        for query in wanted.queries {
            guard let candidates = try? await search(query, in: target, limit: Self.aliasSearchLimit) else { continue }
            if let match = wanted.best(candidates, reuploads: service == .sc) {
                aliases[ref, default: [:]][service] = .some(match.ref)
                return (service, match, nil)
            }
        }
        return (service, nil, nil)
    }

    /// Трек SoundCloud целиком: не `BLOCK`, не `SNIP` и не обрезанный поток. Не узнали — «нет».
    private func soundCloudIsFull(_ ref: String) async -> Bool {
        let id = String(ref.dropFirst("sc:".count))
        let json: JSONValue?
        if let cached = soundCloudRaw[ref] { json = cached } else { json = try? await withSoundCloud { try await $0.trackJSON(id) } }
        guard let json else { return false }
        soundCloudRaw[ref] = json
        return json["policy"].string != "BLOCK" && !SoundCloud.isSnippet(json)
    }
}

extension MusicCore {
    /// Трек по ref — для `sonar://track/<ref>` со страницы сайта. SoundCloud и Яндекс; остальные — nil.
    func track(ref: String) async -> Track? {
        guard !OfflineFlag.isOn, let i = ref.firstIndex(of: ":") else { return nil }
        let id = String(ref[ref.index(after: i)...])
        switch ServiceRegistry.service(of: ref) {
        case .ym?:
            return try? await yandexClient().tracks([id]).first
        case .sc?:
            guard let json = try? await withSoundCloud({ try await $0.trackJSON(id) }) else { return nil }
            soundCloudRaw[ref] = json
            return keep([json]).first
        default:
            return nil
        }
    }
}
