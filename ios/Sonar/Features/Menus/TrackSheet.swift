import SwiftUI
import UIKit

/// Лист трека (`IMG_6774`): сверху обложка во всю ширину, растворяется в фон, на ней название,
/// исполнитель и знак сервиса; капсула ♥ · + · в очередь · поделиться; ниже — Следующим, Волна по
/// треку, Перейти к артисту, Открыть альбом, Скачать (в Sonar, играет без сети — «Скачанные»), у играющего
/// трека — Устройства и Таймер сна (по настройке `player.sleep_button`, запущенный — всегда), Копировать
/// название, Не интересно, Удалить из плейлиста (если трек в списке). «+» — свои плейлисты Sonar (`AddToPlaylistSheet`). «Закрепить в профиле» — с сервером.
struct TrackSheet: View {
    let item: TrackMenuItem
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(ChromeState.self) private var chrome
    @Environment(Router.self) private var router
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var addToPlaylist = false
    @State private var showDevices = false
    @State private var showSleep = false

    /// Трек в меню — тот, что играет: тогда есть «Устройства» и «Таймер сна».
    private var isCurrent: Bool { engine.current?.ref == track.ref }

    private var track: Track { item.track }
    private var downloads: DownloadStore { DownloadStore.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banner
                VStack(alignment: .leading, spacing: 0) {
                    capsule
                        .padding(.top, 22)
                    if let reason = engine.waveWhy(for: track) {
                        whyNote(reason)
                            .padding(.top, 12)
                    }
                    VStack(spacing: 4) {
                        SheetMenuRow(icon: .next, title: "Следующим", subtitle: "Сыграет после текущего") {
                            engine.enqueue(track, next: true)
                            done("Сыграет следующим")
                        }
                        SheetMenuRow(icon: .wave, title: "Sonar Mix по треку", subtitle: "Подборка похожего") {
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
                        if isCurrent {
                            SheetMenuRow(icon: .computer, title: t("Устройства"), subtitle: t("Выбрать, где играет музыка")) {
                                showDevices = true
                            }
                            if settings.bool("player.sleep_button") || engine.sleep != nil {
                                SheetMenuRow(icon: .moon, title: t("Таймер сна"),
                                             subtitle: engine.sleep == nil ? t("Остановить музыку через заданное время")
                                                 : t("Включён — нажми, чтобы изменить")) {
                                    showSleep = true
                                }
                            }
                        }
                        SheetMenuRow(icon: .copy, title: t("Копировать название"), subtitle: CopyText.track(track)) {
                            UIPasteboard.general.string = CopyText.track(track)
                            done(t("Название скопировано"))
                        }
                        SheetMenuRow(icon: .dislike, title: library.isDisliked(track.ref) ? "Снова интересно" : "Не интересно",
                                     subtitle: library.isDisliked(track.ref) ? "Вернётся в подборки" : "Не попадётся в подборках") {
                            let was = library.isDisliked(track.ref)
                            // 👎 через плеер: если трек играет — сразу следующий
                            if was { library.toggleDislike(track) } else { engine.dislike(track) }
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
        .sheet(isPresented: $showDevices) {
            DevicePickerSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showSleep) {
            SleepTimerSection()
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 28)
                .frame(maxHeight: .infinity, alignment: .top)
                .presentationDetents([.height(190)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $addToPlaylist) {
            AddToPlaylistSheet(tracks: [track]) { message in
                // закрыть оба листа разом (вложенный и лист трека) и показать плашку; dismiss, а не
                // router.trackMenu — лист открывается и из полного плеера, своим `sheet`
                addToPlaylist = false
                dismiss()
                router.say(message)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
            .presentationBackground(Theme.background)
        }
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
                if let id = ServiceRegistry.service(of: track.ref), id != .local {
                    SonarIcon(LibraryServices.icon(id), size: 30)
                        .foregroundStyle(Theme.text)
                        .accessibilityLabel(t(ServiceRegistry.info(id).name))
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 4)
        }
    }

    /// «Почему этот трек» — у треков Sonar Mix: откуда он пришёл.
    private func whyNote(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SonarIcon(.sparkles, size: 16)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("Почему этот трек"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(reason)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var capsule: some View {
        let liked = library.isLiked(track)
        return HStack(spacing: 0) {
            capsuleButton(.heart, filled: liked, tint: liked ? Theme.accent : nil, label: liked ? "Убрать из Любимых" : "В Любимые") {
                withAnimation(Motion.spring) { library.toggleLike(track) }
            }
            capsuleButton(.plus, label: t("Добавить в плейлист")) {
                addToPlaylist = true
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
