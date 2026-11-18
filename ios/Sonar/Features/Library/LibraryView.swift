import SwiftUI

/// «221 трек» / «8 треков».
func tracksCount(_ n: Int) -> String {
    "\(n) " + ruPlural(n, "трек", "трека", "треков")
}

/// Медиатека (`photo_28, 29`, `IMG_6766`): сверху капсула «фильтр · сортировка», поиск и «+»; крупные
/// вкладки Все / Плейлисты / Альбомы / Исполнители; сетка в две колонки — Любимые, Скачанные, свои плейлисты
/// Sonar (`PlaylistStore`, скрытые — только во вкладке «Плейлисты»), плейлисты сервисов («фантомные», пока не
/// перенесены в Sonar), сохранённые альбомы и исполнители с подпиской, затем — из Любимых.
struct LibraryView: View {
    enum Shelf: String, CaseIterable, Identifiable {
        case all = "Все"
        case playlists = "Плейлисты"
        case albums = "Альбомы"
        case artists = "Исполнители"
        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable {
        case added = "По добавлению"
        case title = "По названию"
    }

    enum SourceFilter: String, CaseIterable {
        case all = "Все сервисы"
        case soundcloud = "SoundCloud"
        case yandex = "Яндекс Музыка"
        case youtube = "YouTube Music"
        case vk = "VK Музыка"

        func keeps(_ ref: String) -> Bool {
            switch self {
            case .all: true
            case .soundcloud: ServiceRegistry.service(of: ref) == .sc
            case .yandex: ServiceRegistry.service(of: ref) == .ym
            case .youtube: ServiceRegistry.service(of: ref) == .yt
            case .vk: ServiceRegistry.service(of: ref) == .vk
            }
        }
    }

    @Environment(LibraryStore.self) private var library
    @Environment(ChromeState.self) private var chrome
    @Environment(Router.self) private var router
    @State private var section: Shelf = .all
    @State private var sort: Sort = .added
    @State private var source: SourceFilter = .all
    @State private var searching = false
    @State private var query = ""
    @State private var playlists: [ServicePlaylist] = []
    @State private var creating = false
    @FocusState private var searchFocused: Bool
    private var downloads: DownloadStore { DownloadStore.shared }
    private var store: PlaylistStore { PlaylistStore.shared }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 8)
                if searching {
                    searchField
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                tabs
                    .padding(.top, 16)
                grid
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 14)
                    .id(section)
                    .transition(.opacity.combined(with: .offset(y: 10)))
            }
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            if chrome.tab == .library { chrome.scrolled(to: offset) }
        }
        .pageBackground()
        .animation(Motion.spring, value: section)
        .animation(Motion.spring, value: searching)
        .newPlaylistAlert(isPresented: $creating) { id in
            router.push(.sonarPlaylist(id: id), on: .library, chrome: chrome)
        }
        .task { playlists = await MusicCore.shared.myPlaylists() }
        .refreshable { playlists = await MusicCore.shared.myPlaylists() }
    }

    // MARK: - Шапка

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Menu {
                    Picker("Сервис", selection: $source) {
                        ForEach(SourceFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    SonarIcon(.sortLines, size: 24)
                        .foregroundStyle(source == .all ? Theme.text : Theme.accent)
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Фильтр по сервису")
                Menu {
                    Picker("Сортировка", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    SonarIcon(.sortArrows, size: 24)
                        .foregroundStyle(Theme.text)
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Сортировка")
            }
            .background(Theme.raised.opacity(0.92), in: Capsule())
            Spacer()
            CircleButton(icon: searching ? .close : .search, label: "Поиск в медиатеке") {
                searching.toggle()
                if searching { searchFocused = true } else { query = "" }
            }
            CircleButton(icon: .plus, label: t("Новый плейлист")) {
                creating = true
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            SonarIcon(.search, size: 20).foregroundStyle(Theme.textSecondary)
            TextField("Найти в медиатеке", text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Theme.raised.opacity(0.92), in: Capsule())
    }

    /// Крупные вкладки, невыбранные приглушены; выбранная подъезжает в поле зрения.
    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 22) {
                    ForEach(Shelf.allCases) { item in
                        Button {
                            section = item
                            withAnimation(Motion.spring) { proxy.scrollTo(item, anchor: .center) }
                        } label: {
                            Text(item.rawValue)
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(section == item ? Theme.text : Theme.textTertiary.opacity(0.55))
                                .scaleEffect(section == item ? 1 : 0.97, anchor: .bottomLeading)
                        }
                        .buttonStyle(.plain)
                        .id(item)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Сетка

    private func matches(_ text: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || text.localizedCaseInsensitiveContains(q)
    }

    private var shownPlaylists: [ServicePlaylist] {
        // перенесённые в Sonar — уже среди своих, второй раз не показываем
        let moved = Set(store.playlists.compactMap(\.sourceRef))
        let list = playlists.filter { !moved.contains($0.ref) && source.keeps($0.ref) && (matches($0.title) || matches($0.owner)) }
        return sort == .title ? list.sorted { $0.title.localizedCompare($1.title) == .orderedAscending } : list
    }

    /// Свои плейлисты: во «Все» — без скрытых. Фильтр сервиса — по происхождению (перенесённые) или по
    /// трекам (смешанный показывается, если в нём есть треки сервиса).
    private var ownPlaylists: [SonarPlaylist] {
        let list = store.playlists.filter(keepsOwn)
        return sort == .title ? list.sorted { $0.name.localizedCompare($1.name) == .orderedAscending } : list
    }

    private func keepsOwn(_ playlist: SonarPlaylist) -> Bool {
        if section != .playlists, playlist.hidden { return false }
        guard matches(playlist.name) else { return false }
        if source == .all { return true }
        if let origin = playlist.sourceRef, source.keeps(origin) { return true }
        return playlist.tracks.contains { source.keeps($0.ref) }
    }

    /// Альбомы: сохранённые («Сохранить в медиатеку»), затем из Любимых — по ref альбома, обложка от первого трека.
    private var albums: [LibraryAlbum] {
        var seen = Set<String>()
        var out: [LibraryAlbum] = []
        for saved in store.albums where source.keeps(saved.album.ref) {
            let album = saved.album
            guard !seen.contains(album.ref), matches(album.title) || matches(album.artist) else { continue }
            seen.insert(album.ref)
            out.append(LibraryAlbum(ref: album.ref, title: album.title, artist: album.artist, cover: album.coverURL))
        }
        for track in library.liked where source.keeps(track.ref) {
            guard let album = track.album, !seen.contains(album.ref), matches(album.title) || matches(track.artist) else { continue }
            seen.insert(album.ref)
            out.append(LibraryAlbum(ref: album.ref, title: album.title, artist: track.artist, cover: track.coverURL))
        }
        return sort == .title ? out.sorted { $0.title.localizedCompare($1.title) == .orderedAscending } : out
    }

    /// Артисты: с подпиской — первыми, затем из Любимых (чаще встречаются — выше).
    private var artists: [LibraryArtist] {
        let followed = store.artists
            .filter { source.keeps($0.artist.ref) && matches($0.artist.name) }
            .map { LibraryArtist(ref: $0.artist.ref, name: $0.artist.name, avatar: $0.artist.avatarURL, cover: nil, count: 0, followed: true) }
        let followedRefs = Set(followed.map(\.ref))
        let sortedFollowed = sort == .title
            ? followed.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            : followed
        return sortedFollowed + likedArtists.filter { !followedRefs.contains($0.ref) }
    }

    private var likedArtists: [LibraryArtist] {
        var order: [String] = []
        var info: [String: LibraryArtist] = [:]
        for track in library.liked where source.keeps(track.ref) {
            for artist in track.artists where matches(artist.name) {
                if var known = info[artist.ref] {
                    known.count += 1
                    if known.avatar == nil { known.avatar = artist.avatarURL }
                    info[artist.ref] = known
                } else {
                    order.append(artist.ref)
                    info[artist.ref] = LibraryArtist(ref: artist.ref, name: artist.name, avatar: artist.avatarURL, cover: track.coverURL, count: 1)
                }
            }
        }
        let list = order.compactMap { info[$0] }
        return sort == .title
            ? list.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            : list.sorted { $0.count > $1.count }
    }

    @ViewBuilder
    private var grid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            if section == .all || section == .playlists {
                if matches("Любимые") {
                    LibraryTile(title: "Любимые", subtitle: tracksCount(library.liked.count), icon: .heart) {
                        router.push(.liked, on: .library, chrome: chrome)
                    }
                    .cascade(0)
                }
                if matches("Скачанные") {
                    LibraryTile(title: "Скачанные", subtitle: tracksCount(downloads.downloaded.count), icon: .download) {
                        router.push(.downloaded, on: .library, chrome: chrome)
                    }
                    .cascade(1)
                }
                let own = ownPlaylists
                ForEach(Array(own.enumerated()), id: \.element.id) { index, playlist in
                    LibraryTile(title: playlist.name,
                                subtitle: playlist.hidden ? tracksCount(playlist.tracks.count) + " · " + t("скрыт") : tracksCount(playlist.tracks.count),
                                covers: playlist.covers) {
                        router.push(.sonarPlaylist(id: playlist.id), on: .library, chrome: chrome)
                    }
                    .cascade(index + 2)
                }
                ForEach(Array(shownPlaylists.enumerated()), id: \.element.ref) { index, playlist in
                    LibraryTile(title: playlist.title, subtitle: playlist.owner, cover: playlist.coverURL) {
                        router.push(.playlist(playlist), on: .library, chrome: chrome)
                    }
                    .cascade(index + 2 + own.count)
                }
            }
            if section == .all || section == .albums {
                ForEach(Array(albums.prefix(section == .all ? 6 : 200).enumerated()), id: \.element.ref) { index, album in
                    LibraryTile(title: album.title, subtitle: album.artist, cover: album.cover) {
                        router.push(.album(ref: album.ref, title: album.title), on: .library, chrome: chrome)
                    }
                    .cascade(index + 4)
                }
            }
            if section == .all || section == .artists {
                ForEach(Array(artists.prefix(section == .all ? 6 : 200).enumerated()), id: \.element.ref) { index, artist in
                    LibraryTile(title: artist.name,
                                subtitle: artist.followed ? t("Вы подписаны") : tracksCount(artist.count) + " в Любимых",
                                cover: artist.avatar ?? artist.cover, round: true) {
                        router.push(.artist(ref: artist.ref, name: artist.name), on: .library, chrome: chrome)
                    }
                    .cascade(index + 6)
                }
            }
        }
        if isEmpty {
            HintCard(icon: section == .artists ? .user : .album, text: emptyText)
                .padding(.top, 8)
        }
    }

    private var isEmpty: Bool {
        switch section {
        case .albums: albums.isEmpty
        case .artists: artists.isEmpty
        default: false
        }
    }

    private var emptyText: String {
        if !query.isEmpty { return "Ничего не нашлось" }
        return section == .artists
            ? t("Здесь появятся артисты из Любимых и те, на кого ты подписан")
            : t("Здесь появятся сохранённые альбомы и альбомы треков из Любимых")
    }
}

struct LibraryAlbum: Hashable {
    let ref: String
    let title: String
    let artist: String
    let cover: String?
}

struct LibraryArtist: Hashable {
    let ref: String
    let name: String
    var avatar: String?
    let cover: String?
    var count: Int
    /// Подписка («Подписаться» на странице артиста), а не из Любимых.
    var followed = false
}

/// Плитка медиатеки: квадрат (обложка или значок на поверхности), название и подпись.
struct LibraryTile: View {
    let title: String
    let subtitle: String
    var icon: IconName?
    var cover: String?
    /// Коллаж своего плейлиста (`PlaylistCollage`) вместо одной обложки.
    var covers: [String]?
    var round = false
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let icon {
                            ZStack(alignment: .bottomLeading) {
                                Theme.raised.opacity(0.75)
                                SonarIcon(icon, filled: true, size: 30)
                                    .foregroundStyle(Theme.text)
                                    .padding(18)
                            }
                        } else if let covers {
                            PlaylistCollage(covers: covers, cornerRadius: 0)
                        } else {
                            CoverImage(url: cover, cornerRadius: 0)
                        }
                    }
                    .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 20, style: .continuous)))
                    .padding(.bottom, 9)
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }
}
