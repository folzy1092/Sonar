import SwiftUI
import UIKit

/// Обложка своего плейлиста: коллаж из четырёх обложек треков (как на ПК), меньше четырёх — первая,
/// пусто — значок ноты на поверхности.
struct PlaylistCollage: View {
    let covers: [String]
    var cornerRadius: CGFloat = 20

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if covers.count >= 4 {
                    GeometryReader { proxy in
                        let side = proxy.size.width / 2
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                cell(covers[0], side)
                                cell(covers[1], side)
                            }
                            HStack(spacing: 0) {
                                cell(covers[2], side)
                                cell(covers[3], side)
                            }
                        }
                    }
                } else if let first = covers.first {
                    CoverImage(url: first, cornerRadius: 0)
                } else {
                    ZStack {
                        Theme.raised.opacity(0.75)
                        SonarIcon(.music, size: 34)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func cell(_ url: String, _ side: CGFloat) -> some View {
        CoverImage(url: url, cornerRadius: 0)
            .frame(width: side, height: side)
            .clipped()
    }
}

/// «Добавить в плейлист» из листа трека (на ПК — подменю `TrackMenu.svelte`): сверху «Новый плейлист…»,
/// ниже свои плейлисты с коллажем и числом треков; где трек уже лежит — галочка, повторный тап убирает.
/// Куда встаёт трек — `general.add_position` (Система → Общее → Добавление).
struct AddToPlaylistSheet: View {
    let tracks: [Track]
    /// Добавили или создали — закрыть всё и показать плашку.
    let done: @MainActor (String) -> Void
    @Environment(SettingsStore.self) private var settings
    @State private var naming = false
    @State private var newName = ""

    private var store: PlaylistStore { PlaylistStore.shared }
    private var atStart: Bool { settings.string("general.add_position") != "end" }
    private var single: Track? { tracks.count == 1 ? tracks.first : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(t("Добавить в плейлист"))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(single.map { "\($0.artist) — \($0.title)" } ?? tracksCount(tracks.count))
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 4)
                VStack(spacing: 4) {
                    SheetMenuRow(icon: .plus, title: t("Новый плейлист…"), subtitle: t("Создать и сразу добавить")) {
                        newName = PlaylistMath.freeName(t("Новый плейлист"), taken: store.playlists.map(\.name))
                        naming = true
                    }
                    ForEach(Array(store.playlists.enumerated()), id: \.element.id) { index, playlist in
                        row(playlist)
                            .cascade(index + 1)
                    }
                }
                .padding(.top, 22)
                if store.playlists.isEmpty {
                    HintCard(icon: .music, text: t("Своих плейлистов пока нет"))
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 30)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .animation(Motion.spring, value: store.playlists.map(\.id))
        .alert(t("Новый плейлист"), isPresented: $naming) {
            TextField(t("Название"), text: $newName)
            Button(t("Отмена"), role: .cancel) {}
            Button(t("Создать")) {
                guard let id = store.create(name: newName, tracks: tracks), let made = store.playlist(id) else { return }
                done(t("Добавлено в «{name}»", ["name": made.name]))
            }
        }
    }

    private func row(_ playlist: SonarPlaylist) -> some View {
        let inside = single.map { store.contains($0.ref, in: playlist.id) } ?? false
        return Button {
            if let single, inside {
                store.remove([single.ref], from: playlist.id)
                Haptics.select()
                done(t("Убрано из «{name}»", ["name": playlist.name]))
                return
            }
            let added = store.add(tracks, to: playlist.id, atStart: atStart)
            Haptics.select()
            done(added > 0 ? t("Добавлено в «{name}»", ["name": playlist.name]) : t("Уже в «{name}»", ["name": playlist.name]))
        } label: {
            HStack(spacing: 14) {
                PlaylistCollage(covers: playlist.covers, cornerRadius: 10)
                    .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(tracksCount(playlist.tracks.count))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                if inside {
                    SonarIcon(.check, size: 24)
                        .foregroundStyle(Theme.accent)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}

/// Новый плейлист из Медиатеки («+» сверху): спросить название и открыть его.
struct NewPlaylistAlert: ViewModifier {
    @Binding var isPresented: Bool
    let created: @MainActor (String) -> Void
    @State private var name = ""

    private var store: PlaylistStore { PlaylistStore.shared }

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, open in
                if open { name = PlaylistMath.freeName(t("Новый плейлист"), taken: store.playlists.map(\.name)) }
            }
            .alert(t("Новый плейлист"), isPresented: $isPresented) {
                TextField(t("Название"), text: $name)
                Button(t("Отмена"), role: .cancel) {}
                Button(t("Создать")) {
                    if let id = store.create(name: name) { created(id) }
                }
            } message: {
                Text(t("Добавляй треки через меню трека: «Добавить в плейлист»."))
            }
    }
}

extension View {
    func newPlaylistAlert(isPresented: Binding<Bool>, created: @escaping @MainActor (String) -> Void) -> some View {
        modifier(NewPlaylistAlert(isPresented: isPresented, created: created))
    }
}

/// Название для копирования — «Исполнитель — Трек», как «Копировать название» на ПК.
enum CopyText {
    static func track(_ track: Track) -> String {
        track.artist.isEmpty ? track.title : "\(track.artist) — \(track.title)"
    }
}
