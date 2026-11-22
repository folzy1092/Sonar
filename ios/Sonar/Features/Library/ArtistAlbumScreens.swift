import SwiftUI
import UIKit

/// Шапка страниц артиста и альбома: ‹ слева, крупная обложка (у артиста — круг), заголовок, подпись,
/// «▶ Слушать / ⏸ Пауза», ⤮, в очередь, сохранить (альбом — в медиатеку, артист — подписка; как на ПК)
/// и поделиться.
private struct PageHeader: View {
    let cover: String?
    var round = false
    let title: String
    let subtitle: String
    let tracks: [Track]
    let context: String
    /// Кнопка «сохранить»: nil — нет (страница ещё грузится).
    var saved: Bool?
    var saveIcon: IconName = .heart
    var savedIcon: IconName = .heart
    var saveLabel = ""
    var onSave: (@MainActor () -> Void)?
    var shareURL: URL?
    @Environment(PlaybackEngine.self) private var engine
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    /// «Слушать» ⇄ «Пауза»: играет эта подборка — пауза, на паузе — продолжить с места.
    private var listen: ListenAction {
        .resolve(page: context, context: engine.contextTitle, isWave: engine.isWave, hasCurrent: engine.current != nil, isPlaying: engine.isPlaying, ended: engine.queueEnded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CircleButton(icon: .back, label: "Назад") { dismiss() }
                Spacer()
                if let saved, let onSave {
                    CircleButton(icon: saved ? savedIcon : saveIcon, filled: saved, label: saveLabel) {
                        withAnimation(Motion.spring) { onSave() }
                        Haptics.select()
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                if let shareURL {
                    ShareLink(item: shareURL) {
                        SonarIcon(.share, size: 22)
                            .foregroundStyle(Theme.text)
                            .frame(width: 52, height: 52)
                            .background(Theme.raised.opacity(0.92), in: Circle())
                    }
                    .accessibilityLabel(t("Поделиться"))
                }
            }
            .padding(.top, 8)
            .animation(Motion.spring, value: saved)
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
                ListenCapsuleButton(playing: listen.showsPause) {
                    switch listen {
                    case .pause: engine.pause()
                    case .resume: engine.resume()
                    case .start:
                        guard !tracks.isEmpty else { return }
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
                CircleButton(icon: .queue, label: t("В очередь")) {
                    for track in tracks { engine.enqueue(track, next: false) }
                    router.say(t("Треки добавлены в очередь"))
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
    /// Что исполнитель репостнул (только SoundCloud) — раздел под альбомами.
    @State private var reposts: [Track] = []
    private static let repostsLimit = 50
    private var collections: PlaylistStore { PlaylistStore.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    cover: page?.artist.avatarURL,
                    round: true,
                    title: page?.artist.name ?? name,
                    subtitle: followers,
                    tracks: page?.tracks ?? [],
                    context: page?.artist.name ?? name,
                    saved: page.map { collections.isFollowed(artist: $0.artist.ref) },
                    saveIcon: .userAdd,
                    savedIcon: .check,
                    saveLabel: page.map { collections.isFollowed(artist: $0.artist.ref) } == true ? t("Вы подписаны") : t("Подписаться"),
                    onSave: {
                        guard let artist = page?.artist else { return }
                        let now = collections.toggleFollow(artist)
                        router.say(now ? t("Вы подписаны") : t("Подписка отменена"))
                    },
                    shareURL: page?.artist.url.flatMap(URL.init(string:))
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
                                    engine.play(page.tracks, at: index, context: page.artist.name, tapped: true)
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
                    if !reposts.isEmpty {
                        repostsSection(artist: page.artist)
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
        .pageBackground()
        .animation(Motion.spring, value: page?.tracks.count)
        .animation(Motion.spring, value: reposts.count)
        .task(id: ref) {
            do {
                page = try await MusicCore.shared.artist(ref)
                failed = nil
            } catch {
                failed = error.localizedDescription
            }
        }
        .task(id: ref) {
            // репосты — дополнение: не открылись — раздела просто нет
            reposts = (try? await MusicCore.shared.artistReposts(ref, limit: Self.repostsLimit)) ?? []
        }
    }

    /// «Репосты» и рядом значок репоста с ником исполнителя, ниже — обычные строки треков.
    private func repostsSection(artist: Artist) -> some View {
        let title = t("Репосты {name}", ["name": artist.name])
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(t("Репосты"))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Label {
                    Text(artist.name).lineLimit(1)
                } icon: {
                    SonarIcon(.repeatAll, size: 13)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel(title)
            }
            .padding(.top, 30)
            .padding(.bottom, 8)
            LazyVStack(spacing: 4) {
                ForEach(Array(reposts.enumerated()), id: \.element.ref) { index, track in
                    TrackRow(track: track, playing: engine.current?.ref == track.ref) {
                        engine.play(reposts, at: index, context: title, tapped: true)
                    }
                    .cascade(index)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var followers: String {
        guard let count = page?.artist.followers, count > 0 else { return Service(ref: ref)?.title ?? "Яндекс Музыка" }
        return "\(count.formatted()) " + ruPlural(count, "слушатель", "слушателя", "слушателей")
    }
}

/// Страница альбома или релиза.
struct AlbumScreen: View {
    let ref: String
    let title: String
    @Environment(PlaybackEngine.self) private var engine
    @Environment(ChromeState.self) private var chrome
    @Environment(Router.self) private var router
    @State private var page: (album: Album, tracks: [Track])?
    @State private var failed: String?
    private var collections: PlaylistStore { PlaylistStore.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    cover: page?.album.coverURL,
                    title: page?.album.title ?? title,
                    subtitle: subtitle,
                    tracks: page?.tracks ?? [],
                    context: page?.album.title ?? title,
                    saved: page.map { collections.isSaved(album: $0.album.ref) },
                    saveLabel: page.map { collections.isSaved(album: $0.album.ref) } == true ? t("Убрать из медиатеки") : t("Сохранить в медиатеку"),
                    onSave: {
                        guard let album = page?.album else { return }
                        let now = collections.toggleSave(album)
                        router.say(now ? t("Альбом в медиатеке") : t("Альбом убран из медиатеки"))
                    },
                    shareURL: page?.album.url.flatMap(URL.init(string:))
                )
                if let page {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(page.tracks.enumerated()), id: \.element.ref) { index, track in
                            TrackRow(track: track, playing: engine.current?.ref == track.ref) {
                                engine.play(page.tracks, at: index, context: page.album.title, tapped: true)
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
        .pageBackground()
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
