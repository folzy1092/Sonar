import SwiftUI
import UIKit

/// Поиск (`IMG_6767`): поле-капсула, справа круг сервиса (SoundCloud → Яндекс → YouTube Music) и круг «ссылка из буфера»;
/// чипы Всё · Треки · Альбомы · Артисты · Плейлисты. Пустой запрос — «Недавнее» (история поиска, по
/// одному убирается ✕, «Очистить» — всё). Ссылка SoundCloud / Яндекса — сразу карточка «что за ней».
struct SearchView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case all = "Всё"
        case tracks = "Треки"
        case albums = "Альбомы"
        case artists = "Артисты"
        case playlists = "Плейлисты"
        var id: String { rawValue }
    }

    @Environment(PlaybackEngine.self) private var engine
    @Environment(ChromeState.self) private var chrome
    @Environment(Router.self) private var router
    @AppStorage("search.source") private var sourceRaw = Service.soundcloud.rawValue
    @AppStorage("search.history") private var historyRaw = ""
    @State private var query = ""
    @State private var kind: Kind = .all
    @State private var tracks: [Track] = []
    @State private var more = SearchResults()
    @State private var link: LinkItem?
    @State private var error: String?
    @State private var loading = false
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var source: Service { Service(rawValue: sourceRaw) ?? .soundcloud }

    /// Значок круга сервиса: у Яндекса и VK своего нет — поверх рисуется буква.
    private var sourceIcon: IconName {
        switch source {
        case .soundcloud: .soundcloud
        case .yandex: .music
        case .youtube: .youtubeMusic
        case .vk: .music
        }
    }

    private var history: [String] {
        historyRaw.split(separator: "\n").map(String.init)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                field
                CircleButton(icon: sourceIcon, label: "Искать в: \(source.title)") {
                    sourceRaw = source.next.rawValue
                    router.say("Ищу в \(source.title)")
                }
                .overlay {
                    if let mark = source.mark {
                        Text(mark)
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(Theme.text)
                            .frame(width: 52, height: 52)
                            .background(Theme.raised, in: Circle())
                            .allowsHitTesting(false)
                    }
                }
                CircleButton(icon: .link, label: "Вставить ссылку") { pasteLink() }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)

            chips
                .padding(.top, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        historyList
                    } else if loading, tracks.isEmpty, link == nil {
                        ProgressView().tint(Theme.textSecondary).frame(maxWidth: .infinity).padding(.top, 30)
                    } else if let error {
                        HintCard(icon: .info, text: error).padding(.top, 10)
                    } else if let link {
                        LinkCard(item: link) { open(link) }
                            .padding(.top, 6)
                        trackList(tracks)
                    } else {
                        results
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 10)
                .padding(.bottom, 170)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                if chrome.tab == .search { chrome.scrolled(to: offset) }
            }
        }
        .pageBackground()
        .onChange(of: query) { search(immediately: false) }
        .onChange(of: sourceRaw) { search(immediately: true) }
        .onChange(of: kind) { search(immediately: true) }
        .animation(Motion.spring, value: loading)
        .animation(Motion.spring, value: kind)
        .animation(Motion.spring, value: historyRaw)
    }

    // MARK: - Поле и чипы

    private var field: some View {
        HStack(spacing: 12) {
            SonarIcon(.search, size: 22).foregroundStyle(Theme.text)
            TextField("Поиск", text: $query)
                .font(.system(size: 18))
                .foregroundStyle(Theme.text)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    remember(query)
                    search(immediately: true)
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    focused = true
                } label: {
                    SonarIcon(.close, size: 18)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(PressableStyle(scale: 0.85))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(Theme.raised.opacity(0.92), in: Capsule())
        .animation(Motion.quick, value: query.isEmpty)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Kind.allCases) { item in
                    Button {
                        kind = item
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(kind == item ? Theme.background : Theme.text)
                            .padding(.horizontal, 20)
                            .frame(height: 40)
                            .background {
                                if kind == item {
                                    Capsule().fill(Theme.text)
                                } else {
                                    Capsule().strokeBorder(Theme.text.opacity(0.18), lineWidth: 1.2)
                                }
                            }
                    }
                    .buttonStyle(PressableStyle(scale: 0.94))
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - История

    @ViewBuilder
    private var historyList: some View {
        if history.isEmpty {
            HintCard(icon: .search, text: "Ищи треки, альбомы и артистов SoundCloud и Яндекс Музыки — или вставь ссылку")
                .padding(.top, 6)
        } else {
            HStack {
                Text("Недавнее")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Очистить") { historyRaw = "" }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.bottom, 4)
            ForEach(Array(history.enumerated()), id: \.element) { index, item in
                HStack(spacing: 18) {
                    SonarIcon(.history, size: 24).foregroundStyle(Theme.textSecondary)
                    Text(item)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button {
                        forget(item)
                    } label: {
                        SonarIcon(.close, size: 22)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.85))
                    .accessibilityLabel("Убрать из истории")
                }
                .frame(height: 52)
                .contentShape(Rectangle())
                .onTapGesture {
                    query = item
                    focused = false
                    remember(item)
                }
                .cascade(index)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    private func remember(_ text: String) {
        let item = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty, !ServiceLink.looksLikeLink(item) else { return }
        var list = history.filter { $0 != item }
        list.insert(item, at: 0)
        historyRaw = list.prefix(20).joined(separator: "\n")
    }

    private func forget(_ item: String) {
        historyRaw = history.filter { $0 != item }.joined(separator: "\n")
    }

    // MARK: - Выдача

    @ViewBuilder
    private var results: some View {
        switch kind {
        case .all:
            trackList(Array(tracks.prefix(5)))
            if !more.artists.isEmpty { artistsRow }
            if !more.albums.isEmpty { albumsRow(more.albums, title: "Альбомы") }
            if !more.playlists.isEmpty { playlistsRow }
            if tracks.count > 5 {
                sectionTitle("Ещё треки")
                trackList(Array(tracks.dropFirst(5)), offset: 5)
            }
            if tracks.isEmpty, more.artists.isEmpty, more.albums.isEmpty, more.playlists.isEmpty, !loading {
                nothing
            }
        case .tracks:
            trackList(tracks)
            if tracks.isEmpty, !loading { nothing }
        case .albums:
            gridOf(more.albums.map { ($0.ref, $0.title, $0.artist, $0.coverURL, false) }) { ref, title in
                router.push(.album(ref: ref, title: title), on: .search, chrome: chrome)
            }
        case .artists:
            gridOf(more.artists.map { ($0.ref, $0.name, "Исполнитель", $0.avatarURL, true) }) { ref, name in
                router.push(.artist(ref: ref, name: name), on: .search, chrome: chrome)
            }
        case .playlists:
            gridOf(more.playlists.map { ($0.ref, $0.title, $0.owner, $0.coverURL, false) }) { ref, _ in
                if let playlist = more.playlists.first(where: { $0.ref == ref }) {
                    router.push(.playlist(playlist), on: .search, chrome: chrome)
                }
            }
        }
    }

    private var nothing: some View {
        Text("Ничего не нашлось")
            .font(.system(size: 15))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.top, 22)
            .padding(.bottom, 8)
    }

    private func trackList(_ list: [Track], offset: Int = 0) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.ref) { index, track in
            TrackRow(track: track, playing: engine.current?.ref == track.ref) {
                focused = false
                remember(query)
                engine.play(tracks, at: index + offset, context: "Поиск", tapped: true)
            }
            .cascade(index)
        }
    }

    private var artistsRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Артисты")
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(more.artists, id: \.ref) { artist in
                        Button {
                            remember(query)
                            router.push(.artist(ref: artist.ref, name: artist.name), on: .search, chrome: chrome)
                        } label: {
                            VStack(spacing: 8) {
                                CoverImage(url: artist.avatarURL, cornerRadius: 60)
                                    .frame(width: 104, height: 104)
                                Text(artist.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                            }
                            .frame(width: 104)
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func albumsRow(_ albums: [Album], title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(title)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(albums, id: \.ref) { album in
                        ReleaseCard(album: album) {
                            remember(query)
                            router.push(.album(ref: album.ref, title: album.title), on: .search, chrome: chrome)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private var playlistsRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Плейлисты")
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(more.playlists, id: \.ref) { playlist in
                        LibraryTile(title: playlist.title, subtitle: playlist.owner, cover: playlist.coverURL) {
                            remember(query)
                            router.push(.playlist(playlist), on: .search, chrome: chrome)
                        }
                        .frame(width: MosaicCard.side)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func gridOf(_ items: [(String, String, String, String?, Bool)], open: @escaping @MainActor (String, String) -> Void) -> some View {
        if items.isEmpty, !loading {
            nothing
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 22) {
                ForEach(Array(items.enumerated()), id: \.element.0) { index, item in
                    LibraryTile(title: item.1, subtitle: item.2, cover: item.3, round: item.4) {
                        remember(query)
                        open(item.0, item.1)
                    }
                    .cascade(index)
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Ссылки и запросы

    private func pasteLink() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            router.say("В буфере обмена нет ссылки")
            return
        }
        guard ServiceLink.looksLikeLink(text) else {
            router.say("Это не ссылка SoundCloud или Яндекс Музыки")
            return
        }
        query = text
        focused = false
    }

    private func open(_ item: LinkItem) {
        switch item {
        case let .track(track): engine.play([track], at: 0, context: "Поиск")
        case let .album(album): router.push(.album(ref: album.ref, title: album.title), on: .search, chrome: chrome)
        case let .artist(artist): router.push(.artist(ref: artist.ref, name: artist.name), on: .search, chrome: chrome)
        case let .playlist(playlist): router.push(.playlist(playlist), on: .search, chrome: chrome)
        }
    }

    /// С задержкой, пока печатают; ссылка — сразу разбирается.
    private func search(immediately: Bool) {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            tracks = []
            more = SearchResults()
            link = nil
            error = nil
            loading = false
            return
        }
        let service = source
        let wantsMore = kind != .tracks
        task = Task {
            if !immediately { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            loading = true
            defer { if !Task.isCancelled { loading = false } }
            do {
                if ServiceLink.looksLikeLink(text) {
                    let item = try await MusicCore.shared.resolveLink(text)
                    guard !Task.isCancelled else { return }
                    link = item
                    more = SearchResults()
                    if case let .track(track) = item { tracks = [track] } else { tracks = [] }
                } else {
                    async let found = MusicCore.shared.search(text, in: service)
                    async let extra: SearchResults? = wantsMore ? (try? await MusicCore.shared.searchMore(text, in: service)) : nil
                    let list = try await found
                    let rest = await extra
                    guard !Task.isCancelled else { return }
                    link = nil
                    tracks = list
                    more = rest ?? SearchResults()
                }
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                tracks = []
                more = SearchResults()
                link = nil
                self.error = error.localizedDescription
            }
        }
    }
}

/// Что нашлось по ссылке: альбом, артист или плейлист — тап открывает страницу.
private struct LinkCard: View {
    let item: LinkItem
    let open: @MainActor () -> Void

    var body: some View {
        switch item {
        case .track:
            EmptyView()
        case let .album(album):
            card(cover: album.coverURL, title: album.title, subtitle: "Альбом · \(album.artist)")
        case let .artist(artist):
            card(cover: artist.avatarURL, title: artist.name, subtitle: "Исполнитель")
        case let .playlist(playlist):
            card(cover: playlist.coverURL, title: playlist.title, subtitle: "Плейлист · \(playlist.owner)")
        }
    }

    private func card(cover: String?, title: String, subtitle: String) -> some View {
        Button(action: open) {
            HStack(spacing: 14) {
                CoverImage(url: cover, cornerRadius: 14).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer()
                SonarIcon(.chevronRight, size: 20).foregroundStyle(Theme.textSecondary)
            }
            .padding(12)
            .background(Theme.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}
