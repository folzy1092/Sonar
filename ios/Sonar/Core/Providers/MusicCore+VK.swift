import Foundation

/// Токен VK Kate Mobile `vk1.a.…`.
struct VKCreds: Codable, Sendable, Equatable {
    var token: String
}

/// VK Музыка в ядре — порт `windows/src-tauri/src/services/vk.rs`: `vk` / `vka` / `vkalb` / `vkpl`.
/// Ссылку на поток ядро держит в памяти (`vkSeen`) до `streamTTL`, access_key трека — на диске (`vkKeys`):
/// ссылка протухла (`fresh`) или трек после перезапуска — `audio.getById` с ключом.
extension MusicCore {
    static let vkNotConnected = "VK Музыка не подключена — открой Профиль → Сервисы"
    static let vkLikesTitle = "Моя музыка"
    /// Сколько ссылок на поток держать в памяти; сверх — выкидываем протухшие.
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

    /// Треки VK → модели; ссылку запоминаем в памяти, access_key — на диске.
    func vkKeep(_ list: [VKAudio]) -> [Track] {
        let now = Date()
        if vkSeen.count > Self.vkSeenMax {
            vkSeen = vkSeen.filter { now.timeIntervalSince($0.value.at) < Self.streamTTL }
        }
        for audio in list {
            if let link = audio.streamURL { vkSeen[audio.track.ref] = (link, now) }
        }
        vkKeys.remember(list.compactMap { audio in audio.accessKey.map { (ref: audio.track.ref, key: $0) } })
        return list.map(\.track)
    }

    /// Ссылка, которую VK отдал вместе с треком, пока она не протухла.
    func vkSeenURL(_ ref: String) -> String? {
        guard let seen = vkSeen[ref], Date().timeIntervalSince(seen.at) < Self.streamTTL else { return nil }
        return seen.url
    }

    /// id для `audio.getById`: `owner_id_id` и запомненный access_key, если он есть.
    func vkFullID(_ id: String) -> String {
        vkKeys.key(for: "vk:\(id)").map { "\(id)_\($0)" } ?? id
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

    /// Ссылка из поиска, пока она свежая; иначе (fresh, протухла или трек не видели) — `audio.getById`
    /// с access_key с диска.
    func vkStream(_ id: String, fresh: Bool) async throws -> StreamSource {
        guard VK.isAudioID(id) else { throw ServiceError(message: "Неверный трек vk:\(id)") }
        if !fresh, let link = vkSeenURL("vk:\(id)") { return try VK.source(link) }
        let full = vkFullID(id)
        guard let audio = try await vkClient().byId([full]).first else { throw ServiceError(message: "VK Музыка: трек не найден") }
        _ = vkKeep([audio])
        return try VK.source(audio.streamURL ?? "")
    }
}
