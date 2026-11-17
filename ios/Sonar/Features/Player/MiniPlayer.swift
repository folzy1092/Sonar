import SwiftUI

/// Мини-плеер (`IMG_6768`): капсула в цвет обложки — обложка кружком, название и исполнитель, лайк,
/// пауза. Свёрнутая панель (`IMG_6769`): уже, без лайка, название бежит строкой. Тап — полный плеер,
/// свайп вбок — следующий / предыдущий трек. Форма и размер задаёт `BottomChrome`, тут — содержимое.
struct MiniPlayer: View {
    var compact = false
    let open: @MainActor () -> Void
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @State private var drag: CGFloat = 0

    var body: some View {
        if let track = engine.current {
            HStack(spacing: compact ? 10 : 12) {
                CoverImage(url: track.coverURL, cornerRadius: 40)
                    .frame(width: compact ? 40 : 46, height: compact ? 40 : 46)
                    .overlay {
                        if engine.isLoading {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        }
                    }
                    .id(track.ref)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(text: track.title, font: .system(size: compact ? 16 : 17, weight: .medium), color: Theme.text)
                    MarqueeText(text: track.artist, font: .system(size: compact ? 14 : 15), color: Theme.text.opacity(0.7))
                }
                .id(track.ref)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                if !compact {
                    Button {
                        withAnimation(Motion.spring) { library.toggleLike(track) }
                    } label: {
                        SonarIcon(.heart, filled: library.isLiked(track), size: 26)
                            .foregroundStyle(library.isLiked(track) ? Theme.accent : Theme.text)
                            .scaleEffect(library.isLiked(track) ? 1.06 : 1)
                            .frame(width: 44, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.82))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .accessibilityLabel(library.isLiked(track) ? "Убрать из Любимых" : "В Любимые")
                }
                Button {
                    engine.toggle()
                } label: {
                    SonarIcon(engine.isPlaying ? .pause : .play, filled: true, size: 26)
                        .foregroundStyle(Theme.text)
                        .contentTransition(.opacity)
                        .frame(width: 44, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.82))
                .accessibilityLabel(engine.isPlaying ? "Пауза" : "Играть")
            }
            .padding(.leading, compact ? 7 : 9)
            .padding(.trailing, compact ? 6 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                // тонкая полоска прогресса по низу капсулы
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.text.opacity(0.85))
                        .frame(width: proxy.size.width * (engine.duration > 0 ? min(1, engine.position / engine.duration) : 0), height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, compact ? 22 : 30)
                .padding(.bottom, 4)
                .opacity(compact ? 0 : 1)
            }
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
            .animation(Motion.spring, value: library.isLiked(track))
        }
    }
}
