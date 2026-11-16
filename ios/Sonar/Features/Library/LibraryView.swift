import SwiftUI

/// Медиатека: пока — Любимые на устройстве (свои плейлисты, альбомы, исполнители и плейлисты сервисов —
/// следующим шагом, как Windows `Library.svelte`).
struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine
    @Environment(ChromeState.self) private var chrome

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Любимые")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Theme.text)
                    Text("\(library.liked.count) " + ruPlural(library.liked.count, "трек", "трека", "треков"))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.numericText())
                    Spacer()
                    if !library.liked.isEmpty {
                        Button {
                            if !engine.shuffle { engine.toggleShuffle() }
                            engine.play(library.liked, at: Int.random(in: 0 ..< library.liked.count), context: "Любимые")
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.accentInk)
                                .frame(width: 44, height: 44)
                                .background(Theme.accent, in: Circle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.9))
                    }
                }
                .padding(.bottom, 8)
                if library.liked.isEmpty {
                    Text("Нажми ♥ у трека в поиске или в плеере — он появится здесь.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 20)
                }
                ForEach(Array(library.liked.enumerated()), id: \.element.ref) { index, track in
                    TrackRow(track: track, playing: engine.current?.ref == track.ref) {
                        engine.play(library.liked, at: index, context: "Любимые")
                    }
                    .cascade(index)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 150)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            chrome.scrolled(to: offset)
        }
        .background(Theme.background.ignoresSafeArea())
        .animation(Motion.spring, value: library.liked.count)
    }
}
