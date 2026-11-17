import SwiftUI

/// Мини-плеер (`IMG_6768`): капсула в цвет обложки — обложка кружком в кольце прогресса (`IMG` 09:53), название и исполнитель, лайк,
/// пауза. Свёрнутая панель (`IMG_6769`): уже, без лайка, название бежит строкой. Тап — полный плеер,
/// свайп вбок — следующий / предыдущий трек. Форма и размер задаёт `BottomChrome`, тут — содержимое.
struct MiniPlayer: View {
    var compact = false
    let open: @MainActor () -> Void
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @State private var drag: CGFloat = 0

    private var progress: Double {
        engine.duration > 0 ? min(1, max(0, engine.position / engine.duration)) : 0
    }

    var body: some View {
        if let track = engine.current {
            HStack(spacing: compact ? 10 : 12) {
                CoverRing(url: track.coverURL, progress: progress, side: compact ? 42 : 48, loading: engine.isLoading)
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

/// Обложка кружком, вокруг — кольцо прогресса цветом темы по тусклой дорожке; грузится — крутилка.
struct CoverRing: View {
    let url: String?
    let progress: Double
    let side: CGFloat
    var loading = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.text.opacity(0.18), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
            CoverImage(url: url, cornerRadius: side)
                .padding(4.5)
                .overlay {
                    if loading {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                }
        }
        .frame(width: side, height: side)
        .accessibilityLabel("Прогресс \(Int(progress * 100)) %")
    }
}
