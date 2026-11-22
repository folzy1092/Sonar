import Foundation

/// «Новинки» любимых исполнителей — порт Windows `commands.rs` `release_feed`.
extension MusicCore {
    /// Сколько исполнителей опрашивать за раз.
    static let releaseArtistLimit = 24

    /// Альбомы и синглы исполнителей (по 4 последних, только с датой) + свежие заливы SoundCloud (по 6).
    /// Без Яндекса — только исполнители SoundCloud, как на ПК. Новые первыми, без повторов; что свежее
    /// и что уже видели — решает `ReleaseMath`.
    func releaseFeed(artists: [String]) async -> [ReleaseItem] {
        let withYandex = hasYandex
        let refs = Array(artists.filter { withYandex || $0.hasPrefix("sca:") }.prefix(Self.releaseArtistLimit))
        let lists = await concurrentMap(refs) { ref in await self.releases(of: ref) }
        return ReleaseMath.merge(lists.compactMap { $0 })
    }

    private func releases(of ref: String) async -> [ReleaseItem] {
        let albums = (try? await artistAlbums(ref)) ?? []
        var out: [ReleaseItem] = albums.prefix(4).compactMap { album in
            guard let released = album.released else { return nil }
            return ReleaseItem(ref: album.ref, kind: .album, title: album.title, artist: album.artist,
                               coverURL: album.coverURL, released: released, track: nil)
        }
        guard ref.hasPrefix("sca:") else { return out }
        let id = String(ref.dropFirst(4))
        let raw = (try? await withSoundCloud { try await $0.userTracks(id, limit: 6) }) ?? []
        let dates = Dictionary(raw.compactMap { json -> (String, String)? in
            guard let id = json["id"].int, let date = ReleaseMath.soundCloudDate(json) else { return nil }
            return ("sc:\(id)", date)
        }, uniquingKeysWith: { first, _ in first })
        for track in keep(raw) {
            guard let released = dates[track.ref] else { continue }
            out.append(ReleaseItem(ref: track.ref, kind: .track, title: track.title, artist: track.artist,
                                   coverURL: track.coverURL, released: released, track: track))
        }
        return out
    }
}
