import SwiftUI

/// Главная в офлайне (`docs/OFFLINE.md` §8.2, как ПК `OfflineHome.svelte`): без Sonar Mix, подборок и релизов —
/// только то, что играет без сети: «Недавно играло», «Любимые офлайн», «Скачанное» и «Перемешать всё».
struct OfflineHome: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(OfflineMode.self) private var offline
    @Environment(LibraryStore.self) private var library
    @Environment(ChromeState.self) private var chrome
    @Environment(Router.self) private var router

    /// Сколько строк в полке — остальное по «›».
    private static let shelfRows = 5

    private struct Shelf: Identifiable {
        let id: String
        let title: String
        let tracks: [Track]
        let route: Route
    }

    private var shelves: [Shelf] {
        let filter = offline.filter
        return [
            Shelf(id: "recent", title: t("Недавно играло"), tracks: filter.tracks(PlayHistory.shared.recent), route: .recent),
            Shelf(id: "liked", title: t("Любимые офлайн"), tracks: filter.tracks(library.liked), route: .liked),
            Shelf(id: "saved", title: t("Скачанное"), tracks: DownloadStore.shared.downloaded, route: .downloaded),
        ].filter { !$0.tracks.isEmpty }
    }

    var body: some View {
        let all = offline.availableTracks
        VStack(alignment: .leading, spacing: 0) {
            head(count: all.count)
            actions(all)
                .padding(.top, 16)
            if shelves.isEmpty {
                HintCard(icon: .cloudOff, text: t("Пока ничего нет: послушай треки, пока есть сеть, — они останутся в кэше."))
                    .padding(.top, 30)
            }
            ForEach(Array(shelves.enumerated()), id: \.element.id) { index, shelf in
                section(shelf)
                    .padding(.top, 30)
                    .cascade(index)
            }
        }
    }

    private func head(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("Офлайн-режим"))
                .font(.system(size: 42, weight: .black).width(.expanded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(t("Играет только то, что есть на этом телефоне")) · \(tracksCount(count))")
                .font(.system(size: 17))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
        }
    }

    private func actions(_ all: [Track]) -> some View {
        HStack(spacing: 10) {
            Button {
                engine.play(all.shuffled(), at: 0, context: t("Всё доступное"), tapped: true)
            } label: {
                Label {
                    Text(t("Перемешать всё"))
                } icon: {
                    SonarIcon(.shuffle, size: 18)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(all.isEmpty)
            .opacity(all.isEmpty ? 0.5 : 1)
            Button { offline.set(false) } label: {
                Text(t("Выключить офлайн-режим"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Theme.raised, in: Capsule())
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func section(_ shelf: Shelf) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                router.push(shelf.route, on: .home, chrome: chrome)
            } label: {
                HStack(spacing: 8) {
                    Text(shelf.title)
                        .font(.system(size: 26, weight: .semibold))
                    SonarIcon(.chevronRight, size: 20)
                        .foregroundStyle(Theme.textSecondary)
                }
                .foregroundStyle(Theme.text)
            }
            .buttonStyle(PressableStyle())
            VStack(spacing: 4) {
                ForEach(Array(shelf.tracks.prefix(Self.shelfRows).enumerated()), id: \.element.ref) { index, track in
                    TrackRow(track: track, playing: engine.current?.ref == track.ref) {
                        engine.play(shelf.tracks, at: index, context: shelf.title, tapped: true)
                    }
                }
            }
        }
    }
}
