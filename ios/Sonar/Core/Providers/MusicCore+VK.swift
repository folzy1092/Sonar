import Foundation

/// Токен VK Kate Mobile `vk1.a.…`.
struct VKCreds: Codable, Sendable, Equatable {
    var token: String
}

/// Что VK отдал вместе с треком: access_key и ссылка на поток — чтобы не спрашивать второй раз.
struct VKSeen: Sendable, Equatable {
    var accessKey: String?
    var streamURL: String?
}

/// VK Музыка в ядре — порт `windows/src-tauri/src/services/vk.rs`: `vk` / `vka` / `vkalb` / `vkpl`.
/// access_key и ссылку трека ядро держит в памяти (`vkSeen`); ссылка протухла (`fresh`) — `audio.getById`.
extension MusicCore {
    static let vkNotConnected = "VK Музыка не подключена — открой Профиль → Сервисы"
    static let vkLikesTitle = "Моя музыка"
    /// Сколько треков помнить с их access_key и ссылкой.
    static let vkSeenMax = 5000
    /// Треки альбома или плейлиста.
    static let vkListMax = 1000
    /// Популярное на странице исполнителя.
    static let vkTop = 10
    /// Альбомы на странице исполнителя.
    static let vkAlbums = 50

    func connectVK(token: String) async throws -> ServiceAccount {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ServiceError(message: "Вставь токен VK") }
        let account = try await VK(token: token).account()
        let stored = StoredService(creds: VKCreds(token: token), account: account)
        ServiceVault.save(Service.vk.info.key, stored)
        vk = stored
        vkSeen.removeAll()
        streams.removeAll()
        return account
    }

    func vkClient() throws -> VK {
        guard let vk else { throw ServiceError(message: Self.vkNotConnected) }
        return VK(token: vk.creds.token)
    }

    /// Треки VK → модели; access_key и ссылку запоминаем для потока.
    func vkKeep(_ list: [VKAudio]) -> [Track] {
        if vkSeen.count > Self.vkSeenMax { vkSeen.removeAll() }
        for audio in list {
            vkSeen[audio.track.ref] = VKSeen(accessKey: audio.accessKey, streamURL: audio.streamURL)
        }
        return list.map(\.track)
    }

    /// id своего аккаунта VK: из сохранённого, иначе спросить у VK.
    private func vkOwner() async throws -> (client: VK, uid: String, name: String) {
        let client = try vkClient()
        let account = vk?.account
        if let uid = account?.uid { return (client, uid, account?.name ?? "") }
        guard let uid = try await client.account().uid else { throw ServiceError(message: "VK Музыка: не узнал id аккаунта") }
        return (client, uid, account?.name ?? "")
    }

    func vkSearch(_ query: String, limit: Int) async throws -> [Track] {
        vkKeep(try await vkClient().search(query, limit: limit))
    }

    func vkSimilar(_ id: String, limit: Int) async throws -> [Track] {
        vkKeep(try await vkClient().similar(id, limit: limit))
    }

    func vkArtist(_ id: String) async throws -> (artist: Artist, tracks: [Track], albums: [Album]) {
        let client = try vkClient()
        let artist = try await client.artist(id)
        let top = try await client.artistTracks(id, max: Self.vkTop)
        let albums = try await client.artistAlbums(id, limit: Self.vkAlbums)
        return (artist, vkKeep(top), albums)
    }

    func vkArtistTop(_ id: String, limit: Int) async throws -> [Track] {
        vkKeep(try await vkClient().artistTracks(id, max: limit))
    }

    func vkAlbum(_ id: String) async throws -> (album: Album, tracks: [Track]) {
        let (head, list) = try await vkClient().playlist(id, max: Self.vkListMax)
        guard let album = VK.parseAlbum(head) else { throw ServiceError(message: "VK Музыка: альбом не найден") }
        return (album, vkKeep(list))
    }

    /// «Моя музыка» первой, потом свои и добавленные плейлисты. Не подключён — пусто.
    func vkPlaylists() async -> [ServicePlaylist] {
        guard vk != nil, let owner = try? await vkOwner() else { return [] }
        let likes = ServicePlaylist(ref: "vkpl:likes", title: Self.vkLikesTitle, owner: owner.name, coverURL: nil, trackCount: 0)
        return [likes] + ((try? await owner.client.playlists(uid: owner.uid)) ?? [])
    }

    /// Плейлист VK с треками: `vkpl:likes` — «Моя музыка», иначе `vkpl:<owner>_<id>[_<key>]`.
    func vkPlaylist(_ id: String) async throws -> (head: ServicePlaylist, tracks: [Track]) {
        if id == "likes" {
            let (client, uid, name) = try await vkOwner()
            let tracks = vkKeep(try await client.likes(uid: uid, max: Self.maxServiceLikes))
            return (ServicePlaylist(ref: "vkpl:likes", title: Self.vkLikesTitle, owner: name,
                                    coverURL: tracks.first?.coverURL, trackCount: tracks.count), tracks)
        }
        let (head, list) = try await vkClient().playlist(id, max: Self.vkListMax)
        guard let playlist = VK.parsePlaylist(head) else { throw ServiceError(message: "VK Музыка: плейлист не найден") }
        return (playlist, vkKeep(list))
    }

    /// Ссылка из поиска, пока она свежая; иначе (fresh или трек не видели) — `audio.getById` с access_key.
    func vkStream(_ id: String, fresh: Bool) async throws -> StreamSource {
        guard VK.isAudioID(id) else { throw ServiceError(message: "Неверный трек vk:\(id)") }
        let seen = vkSeen["vk:\(id)"]
        if !fresh, let link = seen?.streamURL { return try VK.source(link) }
        let full = seen?.accessKey.map { "\(id)_\($0)" } ?? id
        guard let audio = try await vkClient().byId([full]).first else { throw ServiceError(message: "VK Музыка: трек не найден") }
        _ = vkKeep([audio])
        return try VK.source(audio.streamURL ?? "")
    }
}
