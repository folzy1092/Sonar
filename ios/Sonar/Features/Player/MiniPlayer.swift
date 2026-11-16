import SwiftUI

/// Мини-плеер над таб-баром (все скрины `reference/mobile`): капсула — обложка кружком, название и
/// исполнитель, лайк, пауза. Тап — полный плеер, свайп вбок — следующий / предыдущий трек.
struct MiniPlayer: View {
    /// Свёрнутая панель (`photo_29`): без лайка, уже.
    var compact = false
    let open: @MainActor () -> Void
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @State private var drag: CGFloat = 0

    var body: some View {
        if let track = engine.current {
            HStack(spacing: 12) {
                CoverImage(url: track.coverURL, cornerRadius: 24)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if engine.isLoading {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .id(track.ref)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                Spacer(minLength: 4)
                if !compact {
                    Button {
                        withAnimation(Motion.spring) { library.toggleLike(track) }
                    } label: {
                        Image(systemName: library.isLiked(track) ? "heart.fill" : "heart")
                            .font(.system(size: 20))
                            .foregroundStyle(library.isLiked(track) ? Theme.accent : Theme.text)
                            .symbolEffect(.bounce, value: library.isLiked(track))
                            .frame(width: 40, height: 44)
                    }
                    .buttonStyle(PressableStyle(scale: 0.85))
                    .transition(.scale.combined(with: .opacity))
                }
                Button {
                    engine.toggle()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressableStyle(scale: 0.85))
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: compact ? 54 : 60)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(alignment: .bottom) {
                // тонкая полоска прогресса по низу капсулы
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: proxy.size.width * (engine.duration > 0 ? engine.position / engine.duration : 0), height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 26)
                .padding(.bottom, 3)
            }
            .overlay(Capsule().strokeBorder(Theme.line))
            .offset(x: drag)
            .contentShape(Capsule())
            .onTapGesture(perform: open)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { drag = $0.translation.width * 0.4 }
                    .onEnded { value in
                        if value.translation.width < -70 { engine.next() } else if value.translation.width > 70 { engine.previous() }
                        withAnimation(Motion.spring) { drag = 0 }
                    }
            )
            .animation(Motion.spring, value: track.ref)
        }
    }
}
