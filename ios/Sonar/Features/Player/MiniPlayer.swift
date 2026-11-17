import SwiftUI

/// Мини-плеер (`IMG_6768`): капсула в цвет обложки — обложка кружком в кольце прогресса (`IMG` 09:53), название и исполнитель, лайк,
/// пауза. Свёрнутая панель (`IMG_6769`): уже, без лайка, название бежит строкой. Тап — полный плеер,
/// свайп вбок — действие из Профиль → Жесты → Мини-плеер (по умолчанию следующий / предыдущий). За 10 с до
/// конца вместо исполнителя — «Дальше · …» (`queue.preview`). Форма и размер задаёт `BottomChrome`.
struct MiniPlayer: View {
    var compact = false
    let open: @MainActor () -> Void
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings
    @State private var drag: CGFloat = 0

    /// Вид (Профиль → Мини-плеер): фон, прогресс, обложка, скругление.
    private var style: MiniStyle { MiniStyle.current(settings) }
    private var indicators: Set<ProgressIndicator> { style.progress }

    /// «Дальше»: последние 10 секунд трека, если в очереди есть следующий.
    private var previewNext: Track? {
        guard settings.bool("queue.preview"), engine.duration > 0, engine.position > 0,
              engine.duration - engine.position <= 10 else { return nil }
        return engine.upNext.first
    }

    private var progress: Double {
        engine.duration > 0 ? min(1, max(0, engine.position / engine.duration)) : 0
    }

    var body: some View {
        if let track = engine.current {
            HStack(spacing: compact ? 10 : 12) {
                if style.cover != .hidden {
                    CoverRing(url: track.coverURL, progress: progress, side: compact ? 42 : 48, ring: indicators.contains(.ring),
                              round: style.cover == .circle, loading: engine.isLoading)
                        .id(track.ref)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    Color.clear.frame(width: 6, height: 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(text: track.title, font: .system(size: compact ? 16 : 17, weight: .medium), color: Theme.text)
                    Group {
                        if let next = previewNext {
                            MarqueeText(text: "Дальше · \(next.title)", font: .system(size: compact ? 14 : 15, weight: .medium), color: Theme.accent)
                                .id("next-\(next.ref)")
                        } else {
                            MarqueeText(text: track.artist, font: .system(size: compact ? 14 : 15), color: Theme.text.opacity(0.7))
                                .id("artist")
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
                .animation(Motion.spring, value: previewNext?.ref)
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
            .padding(.leading, style.cover == .hidden ? 12 : (compact ? 7 : 9))
            .padding(.trailing, compact ? 6 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(alignment: .leading) {
                // «Заливка фона»: пройденная часть капсулы светлее
                if indicators.contains(.fill) {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Theme.text.opacity(0.12))
                            .frame(width: proxy.size.width * progress)
                            .animation(.linear(duration: 0.25), value: progress)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: style.corners.radius(height: compact ? 56 : 64), style: .continuous))
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                // «Линия внизу»: тонкая полоска по низу капсулы
                if indicators.contains(.line) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: proxy.size.width * progress, height: 2.5)
                            .animation(.linear(duration: 0.25), value: progress)
                    }
                    .frame(height: 2.5)
                    .padding(.horizontal, compact ? 20 : 28)
                    .padding(.bottom, 3)
                    .transition(.opacity)
                }
            }
            .animation(Motion.spring, value: style)
            .offset(x: drag)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        // жест в эту сторону выключен — капсула лишь чуть поддаётся
                        let direction: SwipeDirection = value.translation.width < 0 ? .left : .right
                        let live = Gestures.action(settings, .mini, direction) != .off
                        drag = value.translation.width * (live ? 0.4 : 0.08)
                    }
                    .onEnded { value in
                        if let action = Gestures.resolve(settings, .mini, dx: value.translation.width, dy: value.translation.height) {
                            GestureRunner.perform(action, track: track)
                        }
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
    /// Контур кольца: круг или закруглённый квадрат (начало — сверху по центру у круга).
    private var outline: AnyShape {
        round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    let url: String?
    let progress: Double
    let side: CGFloat
    /// Кольцо выключено — просто обложка.
    var ring = true
    /// Круг; иначе закруглённый квадрат, и «кольцо» идёт по его краю.
    var round = true
    var loading = false

    var body: some View {
        ZStack {
            if ring {
                outline
                    .stroke(Theme.text.opacity(0.18), lineWidth: 2.5)
                    .transition(.opacity)
                outline
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: progress)
                    .transition(.opacity)
            }
            CoverImage(url: url, cornerRadius: round ? side : (ring ? 7 : 10))
                .padding(ring ? 4.5 : 0)
                .overlay {
                    if loading {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                }
        }
        .frame(width: side, height: side)
        .animation(Motion.spring, value: ring)
        .animation(Motion.spring, value: round)
        .accessibilityLabel("Прогресс \(Int(progress * 100)) %")
    }
}
