import Foundation

/// Spotify на iPhone (порт `services/sp.rs` без потока): ключ `sp_dc` в Keychain, общий токен веб-плеера и
/// метаданные — поиск, «Любимые треки», плейлисты, исполнитель, альбом. Играть `sp:` iPhone не умеет
/// (librespot — только ПК с Premium): MusicCore отдаёт «нужен резервный сервис» (резерв — этап 4).
actor SpotifyCore {
    static let shared = SpotifyCore()

    /// Ключ в Keychain — тот же, что в keyring ПК (`ServiceId::Sp.key()`).
    static let vaultKey = "spotify"
    /// «Любимые треки» как плейлист сервиса.
    static let likesRef = "sppl:likes"
    static let likesTitle = "Любимые треки"

    private var stored: StoredService<SpotifyCreds>?
    private let tokens = SpotifyTokens()

    init() {
        stored = ServiceVault.load(Self.vaultKey)
    }

    var account: ServiceAccount? { stored?.account }

    /// Подключить по `sp_dc` из окна входа или вставленному (с `sp_dc=` или без): токен, `/me`, Keychain.
    func connect(spDc raw: String) async throws -> ServiceAccount {
        guard let spDc = Spotify.normalizeSpDc(raw) else {
            throw ServiceError(message: "Вставь значение cookie sp_dc с open.spotify.com")
        }
        let creds = SpotifyCreds(spDc: spDc)
        // новый ключ — старый токен не годится; ключ не подошёл — тоже забыть
        await tokens.clear()
        do {
            let account = try await Spotify(creds: creds, tokens: tokens).account()
            let value = StoredService(creds: creds, account: account)
            ServiceVault.save(Self.vaultKey, value)
            stored = value
            return account
        } catch {
            await tokens.clear()
            throw error
        }
    }

    func disconnect() async {
        stored = nil
        await tokens.clear()
        ServiceVault.delete(Self.vaultKey)
    }

    private func client() throws -> Spotify {
        guard let stored else { throw ServiceError(message: Spotify.notConnected) }
        return Spotify(creds: stored.creds, tokens: tokens)
    }

    // MARK: - Метаданные

    func search(_ query: String, limit: Int = 30) async throws -> [Track] {
        try await client().search(query, limit: limit)
    }

    func searchMore(_ query: String, limit: Int = 12) async throws -> SearchResults {
        let found = try await client().searchMore(query, limit: limit)
        return SearchResults(tracks: [], artists: found.artists, albums: found.albums, playlists: found.playlists)
    }

    func artist(_ id: String) async throws -> (artist: Artist, tracks: [Track], albums: [Album]) {
        let page = try await client().artist(id)
        return (page.artist, page.top, page.albums)
    }

    func artistAlbums(_ id: String) async throws -> [Album] {
        try await client().artistAlbums(id)
    }

    func album(_ id: String) async throws -> (album: Album, tracks: [Track]) {
        try await client().album(id)
    }

    /// Для Медиатеки: «Любимые треки» первыми, потом плейлисты аккаунта. Не подключён или ошибка — пусто.
    func playlists() async -> [ServicePlaylist] {
        guard let stored, let client = try? client() else { return [] }
        let likes = ServicePlaylist(ref: Self.likesRef, title: Self.likesTitle, owner: stored.account.name ?? "", coverURL: nil, trackCount: 0)
        return [likes] + ((try? await client.playlists()) ?? [])
    }

    /// Плейлист `sppl:<id>` или `sppl:likes` с треками.
    func playlist(_ id: String, max: Int) async throws -> (head: ServicePlaylist, tracks: [Track]) {
        let client = try client()
        guard id == "likes" else { return try await client.playlist(id, max: max) }
        let tracks = try await client.likes(max: max)
        let head = ServicePlaylist(ref: Self.likesRef, title: Self.likesTitle, owner: stored?.account.name ?? "",
                                   coverURL: tracks.first?.coverURL, trackCount: tracks.count)
        return (head, tracks)
    }
}
