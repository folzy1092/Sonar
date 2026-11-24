import SwiftUI

/// Сервисы с плейлистами, по порядку реестра: SoundCloud, Яндекс, YouTube Music, Spotify.
@MainActor
enum LibraryServices {
    static var all: [ServiceInfo] {
        ServiceRegistry.all.filter { $0.implemented && $0.caps.playlists }
    }

    /// Значок сервиса для шапки блока.
    static func icon(_ id: ServiceID) -> IconName {
        switch id {
        case .sc: .soundcloud
        case .ym: .yandexMusic
        case .yt: .youtubeMusic
        case .vk: .vk
        case .sp: .spotify
        case .local: .music
        }
    }

    /// Цвет знака сервиса.
    static func tint(_ service: ServiceInfo) -> Color {
        RGB(hex: service.color).map { Color($0) } ?? Theme.accent
    }

    /// Экран входа: отдельный сервис или все (у Spotify — свой раздел на общем экране).
    static func settingsService(_ id: ServiceID) -> Service? {
        Service.allCases.first { $0.id == id }
    }

    /// Плейлисты сервиса, ещё не перенесённые в Sonar.
    static func playlists(_ all: [ServicePlaylist], of id: ServiceID, moved: Set<String>) -> [ServicePlaylist] {
        all.filter { ServiceRegistry.service(of: $0.ref) == id && !moved.contains($0.ref) }
    }

    /// Сервис подключён — значит, вернул хотя бы строку «Лайки».
    static func connected(_ all: [ServicePlaylist], _ id: ServiceID) -> Bool {
        all.contains { ServiceRegistry.service(of: $0.ref) == id }
    }
}

/// Плейлисты сервисов в Медиатеке — как на ПК (`Library.svelte`, решение владельца 2026-11-16): шапка с
/// названием сервиса, тап — следующий сервис (прежний уезжает вверх, новый поднимается снизу), ниже — его
/// плейлисты, ещё не перенесённые в Sonar. Во «Все» — ряд с прокруткой вбок, в «Плейлистах» — сетка.
struct ServicePlaylistsBlock: View {
    let playlists: [ServicePlaylist]
    let moved: Set<String>
    let loading: Bool
    let grid: Bool
    let open: @MainActor (ServicePlaylist) -> Void
    let connect: @MainActor (ServiceID) -> Void
    @AppStorage("library.service") private var selected = ServiceID.sc.rawValue
    @State private var direction: CGFloat = 1

    private var current: ServiceInfo {
        LibraryServices.all.first { $0.id.rawValue == selected } ?? LibraryServices.all[0]
    }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .padding(.horizontal, Theme.gutter)
            ZStack(alignment: .topLeading) {
                content
                    .id(current.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 26)),
                        removal: .opacity.combined(with: .offset(y: -26))
                    ))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .animation(Motion.spring, value: selected)
    }

    private var header: some View {
        Button(action: next) {
            HStack(spacing: 8) {
                SonarIcon(LibraryServices.icon(current.id), size: 22)
                    .foregroundStyle(LibraryServices.tint(current))
                Text(t(current.name))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.opacity)
                SonarIcon(.chevronRight, size: 18)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(t("Плейлисты {service}, следующий сервис", ["service": t(current.name)]))
    }

    @ViewBuilder
    private var content: some View {
        let list = LibraryServices.playlists(playlists, of: current.id, moved: moved)
        if loading && playlists.isEmpty {
            HStack(spacing: 14) {
                ForEach(0 ..< 2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.raised.opacity(0.6))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, Theme.gutter)
        } else if !LibraryServices.connected(playlists, current.id) {
            Button { connect(current.id) } label: {
                HintCard(icon: .link, text: t("{service}: не подключено — нажми, чтобы войти", ["service": t(current.name)]))
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .padding(.horizontal, Theme.gutter)
        } else if list.isEmpty {
            HintCard(icon: .transfer, text: t("Все плейлисты {service} уже перенесены в Sonar.", ["service": t(current.name)]))
                .padding(.horizontal, Theme.gutter)
        } else if grid {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                ForEach(Array(list.enumerated()), id: \.element.ref) { index, playlist in
                    tile(playlist).cascade(index)
                }
            }
            .padding(.horizontal, Theme.gutter)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(list.enumerated()), id: \.element.ref) { index, playlist in
                        tile(playlist)
                            .frame(width: 160)
                            .cascade(index)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func tile(_ playlist: ServicePlaylist) -> some View {
        let likes = playlist.ref.hasSuffix(":likes")
        // «Мне нравится» и «Лайки» — подписью сервис, а не владелец: иначе не понять, чьи лайки
        let subtitle = likes ? t(current.name) : (playlist.trackCount > 0 ? tracksCount(playlist.trackCount) : playlist.owner)
        return LibraryTile(title: playlist.title,
                           subtitle: subtitle,
                           icon: likes && playlist.coverURL == nil ? .heart : nil,
                           cover: playlist.coverURL,
                           badge: current.id) {
            open(playlist)
        }
    }

    private func next() {
        let services = LibraryServices.all
        let index = services.firstIndex { $0.id == current.id } ?? 0
        Haptics.select()
        selected = services[(index + 1) % services.count].id.rawValue
    }
}

/// «+» → «Импорт»: плейлисты всех подключённых сервисов, «Перенести» — свой плейлист Sonar из треков.
struct ImportPlaylistsSheet: View {
    let playlists: [ServicePlaylist]
    let connect: @MainActor (ServiceID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy: Set<String> = []
    @State private var done: Set<String> = []
    @State private var failed: [String: String] = [:]
    private var store: PlaylistStore { PlaylistStore.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(t("Свой плейлист Sonar из плейлиста сервиса: треки разных сервисов потом можно смешивать."))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(LibraryServices.all, id: \.id) { service in
                        section(service)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .navigationTitle(t("Импорт"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Готово")) { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ service: ServiceInfo) -> some View {
        let list = playlists.filter { ServiceRegistry.service(of: $0.ref) == service.id }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SonarIcon(LibraryServices.icon(service.id), size: 20)
                    .foregroundStyle(LibraryServices.tint(service))
                Text(t(service.name))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            if list.isEmpty {
                Button {
                    dismiss()
                    connect(service.id)
                } label: {
                    Text(t("Не подключено — войти"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(list.enumerated()), id: \.element.ref) { index, playlist in
                        row(playlist).cascade(index)
                    }
                }
            }
        }
    }

    private func row(_ playlist: ServicePlaylist) -> some View {
        let existing = store.playlist(source: playlist.ref)
        return HStack(spacing: 12) {
            Group {
                if playlist.coverURL == nil, playlist.ref.hasSuffix(":likes") {
                    ZStack {
                        Theme.raised.opacity(0.75)
                        SonarIcon(.heart, filled: true, size: 20).foregroundStyle(Theme.text)
                    }
                } else {
                    CoverImage(url: playlist.coverURL, cornerRadius: 0)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if let id = ServiceRegistry.service(of: playlist.ref) {
                    ServiceBadge(id: id, size: 20).offset(x: 4, y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(failed[playlist.ref] ?? (playlist.trackCount > 0 ? tracksCount(playlist.trackCount) : playlist.owner))
                    .font(.system(size: 13))
                    .foregroundStyle(failed[playlist.ref] == nil ? Theme.textSecondary : Theme.danger)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if busy.contains(playlist.ref) {
                ProgressView().tint(Theme.accent).frame(width: 44)
            } else if existing != nil || done.contains(playlist.ref) {
                SonarIcon(.check, size: 20)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(t("Уже в Sonar"))
            } else {
                Button(t("Перенести")) { transfer(playlist) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.accent, in: Capsule())
                    .buttonStyle(PressableStyle())
            }
        }
        .padding(.vertical, 6)
        .animation(Motion.spring, value: busy)
        .animation(Motion.spring, value: done)
    }

    private func transfer(_ playlist: ServicePlaylist) {
        busy.insert(playlist.ref)
        failed[playlist.ref] = nil
        Task {
            defer { busy.remove(playlist.ref) }
            do {
                let tracks = try await MusicCore.shared.playlist(playlist.ref).tracks
                guard !tracks.isEmpty else {
                    failed[playlist.ref] = t("Плейлист пуст")
                    return
                }
                if store.create(name: playlist.title, tracks: tracks, sourceRef: playlist.ref) != nil {
                    done.insert(playlist.ref)
                    Haptics.success()
                }
            } catch {
                failed[playlist.ref] = error.localizedDescription
            }
        }
    }
}

/// Знак сервиса в цветном круге — в углу обложки плейлиста сервиса.
struct ServiceBadge: View {
    let id: ServiceID
    var size: CGFloat = 28

    var body: some View {
        SonarIcon(LibraryServices.icon(id), size: size * 0.56)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LibraryServices.tint(ServiceRegistry.info(id)), in: Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .accessibilityLabel(t(ServiceRegistry.info(id).name))
    }
}
