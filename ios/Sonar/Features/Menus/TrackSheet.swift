import SwiftUI

/// Лист трека (`IMG_6774`): сверху обложка во всю ширину, растворяется в фон, на ней название,
/// исполнитель и знак сервиса; капсула ♥ · + · в очередь · поделиться; ниже — Следующим, Волна по
/// треку, Перейти к артисту, Скачать, Не интересно, Удалить из плейлиста (если трек в списке).
/// «Из кеша» и «Закрепить в профиле» — с сервером.
struct TrackSheet: View {
    let item: TrackMenuItem
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(ChromeState.self) private var chrome
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    private var track: Track { item.track }
    private var downloads: DownloadStore { DownloadStore.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banner
                VStack(alignment: .leading, spacing: 0) {
                    capsule
                        .padding(.top, 22)
                    VStack(spacing: 4) {
                        SheetMenuRow(icon: .next, title: "Следующим", subtitle: "Сыграет после текущего") {
                            engine.enqueue(track, next: true)
                            done("Сыграет следующим")
                        }
                        SheetMenuRow(icon: .wave, title: "Волна по треку", subtitle: "Подборка похожего") {
                            engine.playWave(from: track)
                            done(nil)
                        }
                        if let artist = track.artists.first {
                            SheetMenuRow(icon: .user, title: "Перейти к артисту", subtitle: artist.name) {
                                let route = Route.artist(ref: artist.ref, name: artist.name)
                                dismiss()
                                router.push(route, on: chrome.tab, chrome: chrome)
                            }
                        }
                        if let album = track.album {
                            SheetMenuRow(icon: .album, title: "Открыть альбом", subtitle: album.title) {
                                let route = Route.album(ref: album.ref, title: album.title)
                                dismiss()
                                router.push(route, on: chrome.tab, chrome: chrome)
                            }
                        }
                        downloadRow
                        SheetMenuRow(icon: .dislike, title: library.isDisliked(track.ref) ? "Снова интересно" : "Не интересно",
                                     subtitle: library.isDisliked(track.ref) ? "Вернётся в подборки" : "Не попадётся в подборках") {
                            let was = library.isDisliked(track.ref)
                            library.toggleDislike(track)
                            done(was ? "Трек вернётся в подборки" : "Больше не попадётся в подборках")
                        }
                        if let remove = item.remove {
                            SheetMenuRow(icon: .minusCircle, title: "Удалить из плейлиста", tint: Theme.danger) {
                                dismiss()
                                remove()
                            }
                        }
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 6)
                }
                .padding(.horizontal, Theme.gutter)
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
    }

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            CoverImage(url: track.coverURL, cornerRadius: 0)
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(colors: [.clear, Theme.background.opacity(0.55), Theme.background],
                                   startPoint: .init(x: 0.5, y: 0.25), endPoint: .bottom)
                )
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(track.artist)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                if track.service == .soundcloud {
                    SonarIcon(.soundcloud, size: 30).foregroundStyle(Theme.text)
                } else if track.service == .yandex {
                    Text("Я")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.background)
                        .frame(width: 26, height: 26)
                        .background(Theme.text, in: Circle())
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 4)
        }
    }

    private var capsule: some View {
        let liked = library.isLiked(track)
        return HStack(spacing: 0) {
            capsuleButton(.heart, filled: liked, tint: liked ? Theme.accent : nil, label: liked ? "Убрать из Любимых" : "В Любимые") {
                withAnimation(Motion.spring) { library.toggleLike(track) }
            }
            capsuleButton(.plus, label: "В плейлист") {
                router.say("Свои плейлисты Sonar появятся вместе с сервером")
            }
            capsuleButton(.queue, label: "В очередь") {
                engine.enqueue(track, next: false)
                done("Добавлено в очередь")
            }
            if let url = track.url.flatMap(URL.init(string:)) {
                ShareLink(item: url) {
                    SonarIcon(.share, size: 24)
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Поделиться")
            }
        }
        .background(Theme.raised.opacity(0.7), in: Capsule())
    }

    private func capsuleButton(_ icon: IconName, filled: Bool = false, tint: Color? = nil, label: String,
                               action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            SonarIcon(icon, filled: filled, size: 24)
                .foregroundStyle(tint ?? Theme.text)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var downloadRow: some View {
        if let progress = downloads.progress[track.ref] {
            SheetMenuRow(icon: .download, title: "Скачивается…", subtitle: "\(Int(progress * 100)) %", enabled: false) {}
        } else if downloads.isDownloaded(track.ref) {
            SheetMenuRow(icon: .trash, title: "Удалить загрузку", subtitle: "Освободит место на телефоне") {
                downloads.remove(track.ref)
                done("Загрузка удалена")
            }
        } else {
            SheetMenuRow(icon: .download, title: "Скачать", subtitle: "В файл на телефоне — играет без интернета") {
                downloads.download(track)
                done("Скачиваю «\(track.title)»")
            }
        }
    }

    private func done(_ message: String?) {
        dismiss()
        if let message { router.say(message) }
    }
}
