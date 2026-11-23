import SwiftUI

/// Обложка: картинка по ссылке или нота на тёмном, с плавным появлением.
struct CoverImage: View {
    let url: String?
    var cornerRadius: CGFloat = 10

    /// Скачанный трек или кэш волны — обложка с телефона (в офлайне сеть закрыта, `docs/OFFLINE.md` §7).
    private var source: URL? {
        guard let url else { return nil }
        return DownloadStore.shared.localCover(url) ?? WaveCache.shared.localCover(url) ?? URL(string: url)
    }

    var body: some View {
        AsyncImage(url: source, transaction: Transaction(animation: Motion.quick)) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill().transition(.opacity)
            default:
                ZStack {
                    Theme.raised
                    SonarIcon(.music, size: 20).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Столбики «сейчас играет» (в плашке длительности, `IMG_6770`): играет — прыгают, пауза — замирают.
struct EqualizerBars: View {
    var playing: Bool
    var color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0 ..< 4, id: \.self) { i in
                    let phase = Double(i) * 1.7
                    let level = playing ? 0.35 + 0.65 * abs(sin(t * (3.1 + Double(i) * 0.6) + phase)) : [0.6, 1, 0.75, 0.5][i]
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: 4 + 10 * level)
                }
            }
            .frame(height: 14)
        }
    }
}

/// Строка трека (`IMG_6764`, `IMG_6770`): обложка, название и исполнитель, длительность в плашке, ⋮.
/// Играющий — название цветом темы, в плашке столбики. ⋮ и долгое нажатие — лист трека, свайп вбок —
/// действие из «Жестов» (`gestures.library.*`).
struct TrackRow: View {
    let track: Track
    var playing = false
    /// Убрать из списка, где показан (Любимые, плейлист) — пункт «Удалить из плейлиста» в листе.
    var remove: (@MainActor () -> Void)?
    /// Свайп вбок — жест из «Жестов». false — там, где вбок листаются страницы («Недавнее» на Главной).
    var swipes = true
    /// Строка под исполнителем — почему трек здесь (подборки Главной); пусто — нет строки.
    var note: String = ""
    let action: @MainActor () -> Void
    @Environment(PlaybackEngine.self) private var engine
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 14) {
            Button(action: action) {
                HStack(spacing: 14) {
                    CoverImage(url: track.coverURL, cornerRadius: 10)
                        .frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 2) {
                        TrackTitle(track: track, playing: playing)
                        if !note.isEmpty {
                            Text(note)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.98, haptic: false))
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in open() })

            if LibraryStore.shared.sound(for: track.ref) != nil {
                // свой звук трека («Для этого трека»): скорость, тон, реверб или эквалайзер только у него
                SonarIcon(.sliders, size: 15)
                    .foregroundStyle(Theme.accent.opacity(0.85))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityLabel(t("Свой звук трека"))
            }

            DurationPill(ms: track.durationMs, playing: playing, isPlaying: engine.isPlaying)

            Button(action: open) {
                SonarIcon(.more, size: 22)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.85))
            .accessibilityLabel("Меню трека")
        }
        .padding(.vertical, 5)
        // свайпы из Профиль → Жесты → Медиатека (по умолчанию — «Играть следующим»)
        .modifier(OptionalTrackSwipe(on: swipes, track: track, remove: remove))
        .opacity(track.available ? 1 : 0.4)
        .animation(Motion.spring, value: LibraryStore.shared.sound(for: track.ref) != nil)
    }

    private func open() {
        router.showMenu(track, remove: remove)
    }

    static func time(_ ms: Int) -> String {
        let seconds = max(0, ms / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Название (цветом темы, если играет; значок «скачан») и исполнитель.
struct TrackTitle: View {
    let track: Track
    var playing = false
    private var downloads: DownloadStore { DownloadStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if downloads.isDownloaded(track.ref) {
                    SonarIcon(.download, size: 16)
                        .foregroundStyle(Theme.textTertiary)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(track.title)
                    .font(.system(size: 17))
                    .foregroundStyle(playing ? Theme.accent : Theme.text)
                    .lineLimit(1)
            }
            HStack(spacing: 5) {
                if track.explicit {
                    Text("E")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.background)
                        .frame(width: 13, height: 13)
                        .background(Theme.textSecondary, in: RoundedRectangle(cornerRadius: 3))
                }
                Text(track.artist)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .animation(Motion.spring, value: downloads.isDownloaded(track.ref))
    }
}

/// Длительность в обводке; у играющего — столбики.
struct DurationPill: View {
    let ms: Int
    var playing = false
    var isPlaying = false

    var body: some View {
        ZStack {
            if playing {
                EqualizerBars(playing: isPlaying, color: Theme.accent)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                Text(TrackRow.time(ms))
                    .font(.system(size: 15).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            }
        }
        .frame(width: 52, height: 28)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 1.2))
        .animation(Motion.spring, value: playing)
    }
}

/// Свайпы строки — только если они не мешают листать (`TrackRow.swipes`).
private struct OptionalTrackSwipe: ViewModifier {
    let on: Bool
    let track: Track
    let remove: (@MainActor () -> Void)?

    func body(content: Content) -> some View {
        if on {
            content.trackSwipe(.library, track: track, remove: remove)
        } else {
            content
        }
    }
}
