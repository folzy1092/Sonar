import SwiftUI

/// Шапка страниц артиста и альбома: ‹ слева, крупная обложка (у артиста — круг), заголовок, подпись,
/// «▶ Слушать / ⏸ Пауза» и ⤮.
private struct PageHeader: View {
    let cover: String?
    var round = false
    let title: String
    let subtitle: String
    let tracks: [Track]
    let context: String
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    private var isThisPlaying: Bool { engine.isPlaying && engine.contextTitle == context && !engine.isWave }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CircleButton(icon: .back, label: "Назад") { dismiss() }
                Spacer()
            }
            .padding(.top, 8)
            CoverImage(url: cover, cornerRadius: round ? 120 : 24)
                .frame(width: 220, height: 220)
                .shadow(color: Theme.glow.opacity(0.35), radius: 24, y: 10)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            Text(title)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
                .padding(.top, 28)
            Text(subtitle)
                .font(.system(size: 17))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .padding(.top, 2)
            HStack(spacing: 12) {
                AccentCapsuleButton(icon: isThisPlaying ? .pause : .play, title: isThisPlaying ? "Пауза" : "Слушать") {
                    if engine.contextTitle == context, !engine.isWave, engine.current != nil {
                        engine.toggle()
                    } else if !tracks.isEmpty {
                        if engine.shuffle { engine.toggleShuffle() }
                        engine.play(tracks, at: 0, context: context)
                    }
                }
                .disabled(tracks.isEmpty)
                CircleButton(icon: .shuffle, label: "Перемешать") {
                    guard !tracks.isEmpty else { return }
                    if !engine.shuffle { engine.toggleShuffle() }
                    engine.play(tracks, at: Int.random(in: 0 ..< tracks.count), context: context)
                }
                .disabled(tracks.isEmpty)
            }
            .padding(.top, 20)
        }
    }
}

/// Страница артиста: шапка, популярные треки, альбомы и синглы.
struct ArtistScreen: View {
    let ref: String
    let name: String
    @Environment(PlaybackEngine.self) private var engine
    @Environment(ChromeState.self) private var chrome
    @Environment(Router.self) private var router
    @State private var page: (artist: Artist, tracks: [Track], albums: [Album])?
    @State private var failed: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    cover: page?.artist.avatarURL,
                    round: true,
                    title: page?.artist.name ?? name,
                    subtitle: followers,
                    tracks: page?.tracks ?? [],
                    context: page?.artist.name ?? name
                )
                if let page {
                    if !page.tracks.isEmpty {
                        Text("Популярное")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.top, 30)
                            .padding(.bottom, 8)
                        LazyVStack(spacing: 4) {
                            ForEach(Array(page.tracks.enumerated()), id: \.element.ref) { index, track in
                                TrackRow(track: track, playing: engine.current?.ref == track.ref) {
                                    engine.play(page.tracks, at: index, context: page.artist.name)
                                }
                                .cascade(index)
                            }
                        }
                    }
                    if !page.albums.isEmpty {
                        Text("Альбомы и синглы")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.top, 30)
                            .padding(.bottom, 14)
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(Array(page.albums.enumerated()), id: \.element.ref) { index, album in
                                    ReleaseCard(album: album) {
                                        router.push(.album(ref: album.ref, title: album.title), on: chrome.tab, chrome: chrome)
                                    }
                                    .cascade(index)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                        .scrollTargetBehavior(.viewAligned)
                    }
                } else if let failed {
                    HintCard(icon: .info, text: failed).padding(.top, 30)
                } else {
                    ProgressView().tint(Theme.textSecondary).frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            chrome.scrolled(to: offset)
        }
        .background(Theme.background.ignoresSafeArea())
        .animation(Motion.spring, value: page?.tracks.count)
        .task(id: ref) {
            do {
                page = try await MusicCore.shared.artist(ref)
                failed = nil
            } catch {
                failed = error.localizedDescription
            }
        }
    }

    private var followers: String {
        guard let count = page?.artist.followers, count > 0 else { return ref.hasPrefix("sc") ? "SoundCloud" : "Яндекс Музыка" }
        return "\(count.formatted()) " + ruPlural(count, "слушатель", "слушателя", "слушателей")
    }
}

/// Страница альбома или релиза.
struct AlbumScreen: View {
    let ref: String
    let title: String
    @Environment(PlaybackEngine.self) private var engine
    @Environment(ChromeState.self) private var chrome
    @State private var page: (album: Album, tracks: [Track])?
    @State private var failed: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    cover: page?.album.coverURL,
                    title: page?.album.title ?? title,
                    subtitle: subtitle,
                    tracks: page?.tracks ?? [],
                    context: page?.album.title ?? title
                )
                if let page {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(page.tracks.enumerated()), id: \.element.ref) { index, track in
                            TrackRow(track: track, playing: engine.current?.ref == track.ref) {
                                engine.play(page.tracks, at: index, context: page.album.title)
                            }
                            .cascade(index)
                        }
                    }
                    .padding(.top, 22)
                } else if let failed {
                    HintCard(icon: .info, text: failed).padding(.top, 30)
                } else {
                    ProgressView().tint(Theme.textSecondary).frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            chrome.scrolled(to: offset)
        }
        .background(Theme.background.ignoresSafeArea())
        .task(id: ref) {
            do {
                page = try await MusicCore.shared.album(ref)
                failed = nil
            } catch {
                failed = error.localizedDescription
            }
        }
    }

    private var subtitle: String {
        guard let album = page?.album else { return "" }
        var parts = [album.artist]
        if let year = album.year { parts.append(String(year)) }
        if let count = page?.tracks.count, count > 0 { parts.append(tracksCount(count)) }
        return parts.joined(separator: " · ")
    }
}
