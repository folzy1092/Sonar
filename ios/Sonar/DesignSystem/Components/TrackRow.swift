import SwiftUI

/// Обложка: картинка по ссылке или нота на тёмном, с плавным появлением.
struct CoverImage: View {
    let url: String?
    var cornerRadius: CGFloat = 10

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:)), transaction: Transaction(animation: Motion.quick)) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill().transition(.opacity)
            default:
                ZStack {
                    Theme.card
                    Image(systemName: "music.note").foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Строка трека: обложка, название, исполнитель, длительность; играющий — цветом темы. Долгое нажатие —
/// меню трека (Следующим, В очередь, Любимые).
struct TrackRow: View {
    let track: Track
    var playing = false
    let action: @MainActor () -> Void
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CoverImage(url: track.coverURL, cornerRadius: 8)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(playing ? Theme.accent : Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if track.explicit {
                            Text("E")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.accentInk)
                                .frame(width: 13, height: 13)
                                .background(Theme.textSecondary, in: RoundedRectangle(cornerRadius: 3))
                        }
                        Text(track.artist)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if library.isLiked(track) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(Self.time(track.durationMs))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .opacity(track.available ? 1 : 0.4)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .contextMenu {
            Button { engine.enqueue(track, next: true) } label: { Label("Следующим", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { engine.enqueue(track, next: false) } label: { Label("В очередь", systemImage: "text.append") }
            Button { withAnimation(Motion.spring) { library.toggleLike(track) } } label: {
                library.isLiked(track)
                    ? Label("Убрать из Любимых", systemImage: "heart.slash")
                    : Label("В Любимые", systemImage: "heart")
            }
            if let url = track.url.flatMap(URL.init(string:)) {
                ShareLink(item: url) { Label("Поделиться", systemImage: "square.and.arrow.up") }
            }
        }
        .animation(Motion.spring, value: library.isLiked(track))
    }

    static func time(_ ms: Int) -> String {
        let seconds = max(0, ms / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
