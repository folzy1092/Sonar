import SwiftUI

/// «Конвертировать на другой сервис»: для каждого трека ищется пара на выбранном сервисе (`Converter`
/// поверх `Matching`: артист, название, длительность ±3 с). Итог — сколько нашлось, кого нет; найденное
/// можно сразу слушать или добавить в Любимые.
struct ConvertSheet: View {
    let title: String
    let tracks: [Track]
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var target: Service = .yandex
    @State private var running = false
    @State private var result: (found: [Track], missing: [Track])?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Конвертировать")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    CircleButton(icon: .close, size: 44, iconSize: 20, label: "Закрыть") { dismiss() }
                }
                Text("«\(title)» · " + tracksCount(tracks.count))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    ForEach(Service.allCases, id: \.self) { service in
                        Button {
                            target = service
                            result = nil
                        } label: {
                            Text(service.title)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 8)
                                .foregroundStyle(target == service ? Theme.accentInk : Theme.text)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(target == service ? Theme.accent : Theme.raised, in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(running)
                    }
                }
                .padding(.top, 24)
                .animation(Motion.spring, value: target)

                if let result {
                    summary(result)
                        .padding(.top, 26)
                        .transition(.opacity.combined(with: .offset(y: 10)))
                } else {
                    AccentCapsuleButton(icon: .transfer, title: running ? "Ищу пары…" : "Найти на \(target.title)") {
                        run()
                    }
                    .disabled(running || tracks.isEmpty)
                    .opacity(running ? 0.7 : 1)
                    .padding(.top, 26)
                    if running {
                        ProgressView().tint(Theme.textSecondary).frame(maxWidth: .infinity).padding(.top, 20)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 26)
            .padding(.bottom, 40)
        }
        .animation(Motion.spring, value: running)
    }

    private func summary(_ result: (found: [Track], missing: [Track])) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Нашлось \(result.found.count) из \(tracks.count)")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.text)
            HStack(spacing: 12) {
                AccentCapsuleButton(icon: .play, title: "Слушать") {
                    engine.play(result.found, at: 0, context: title + " · " + target.title)
                    dismiss()
                }
                .disabled(result.found.isEmpty)
                CircleButton(icon: .heart, label: "Добавить найденное в Любимые") {
                    let new = result.found.filter { !library.isLiked($0) }
                    for track in new.reversed() { library.toggleLike(track) }
                    router.say("В Любимые: " + tracksCount(new.count))
                }
                .disabled(result.found.isEmpty)
            }
            if !result.missing.isEmpty {
                Text("Не нашлось")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 10)
                ForEach(result.missing, id: \.ref) { track in
                    HStack(spacing: 12) {
                        CoverImage(url: track.coverURL, cornerRadius: 8).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.system(size: 15)).foregroundStyle(Theme.text).lineLimit(1)
                            Text(track.artist).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func run() {
        running = true
        let list = tracks
        let service = target
        Task {
            let converted = await Converter.convert(list, to: service, using: MusicCore.shared)
            withAnimation(Motion.spring) {
                result = converted
                running = false
            }
        }
    }
}
