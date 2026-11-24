import SwiftUI

/// Умный плейлист (NEXT_PROMPT, этап 6; на ПК — `SmartPlaylistPage.svelte`): треки считаются заново при
/// открытии и после любой правки медиатеки — лайк, прослушивание, правка исходного плейлиста или правил.
/// Порядок задают правила, поэтому режима выбора нет; «Сохранить как обычный плейлист» делает снимок.
struct SmartPlaylistScreen: View {
    let id: String
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(ChromeState.self) private var chrome
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var outcome: SmartOutcome?
    @State private var searching = false
    @State private var query = ""
    @State private var editor: SmartDraft?
    @State private var confirmDelete = false
    @FocusState private var searchFocused: Bool

    private var store: SmartPlaylistStore { SmartPlaylistStore.shared }
    private var playlists: PlaylistStore { PlaylistStore.shared }
    private var def: SmartPlaylistDef? { store.list(id) }
    private var title: String { def?.name ?? t("Умный плейлист") }
    private var tracks: [Track] { outcome?.tracks ?? [] }

    private var shown: [Track] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tracks }
        return tracks.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q) }
    }

    /// Что меняет итог: правила, журнал прослушиваний, Любимые (и даты лайков), свои плейлисты.
    private var recomputeKey: [String] {
        [
            String(def?.updatedAt ?? 0),
            String(PlayLog.shared.revision),
            library.liked.map(\.ref).joined(separator: ","),
            String(library.likedAt.count),
            playlists.playlists.map { "\($0.id)@\($0.updatedAt)" }.joined(separator: ","),
        ]
    }

    private var listen: ListenAction {
        .resolve(page: title, context: engine.contextTitle, isWave: engine.isWave, hasCurrent: engine.current != nil,
                 isPlaying: engine.isPlaying, ended: engine.queueEnded)
    }

    // MARK: - Вид

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, 8)
                if searching {
                    searchField
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                artwork
                    .frame(maxWidth: .infinity)
                    .padding(.top, 34)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    SonarIcon(.sliders, filled: true, size: 30)
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                .padding(.top, 44)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 2)
                Text(countLine)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
                    .padding(.top, 2)
                actions
                    .padding(.top, 20)
                list
                    .padding(.top, 22)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            chrome.scrolled(to: offset)
        }
        .pageBackground()
        .animation(Motion.spring, value: searching)
        .animation(Motion.spring, value: outcome)
        .task(id: recomputeKey) { recompute() }
        .onChange(of: def == nil) { _, gone in
            // умный плейлист удалили — назад
            if gone { dismiss() }
        }
        .alert(t("Удалить плейлист?"), isPresented: $confirmDelete) {
            Button(t("Отмена"), role: .cancel) {}
            Button(t("Удалить"), role: .destructive, action: delete)
        } message: {
            Text(t("Треки останутся в Любимых и сервисах — удалится только список"))
        }
        .sheet(item: $editor) { draft in
            SmartEditorSheet(draft: draft) { _ in }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            CircleButton(icon: .back, label: t("Назад")) { dismiss() }
            Spacer()
            CircleButton(icon: searching ? .close : .search, label: t("Найти")) {
                searching.toggle()
                if searching { searchFocused = true } else { query = "" }
            }
            Menu {
                Button(t("Изменить правила"), action: openEditor)
                Button(t("Сохранить как обычный плейлист"), action: snapshot)
                    .disabled(tracks.isEmpty)
                Button(t("Удалить плейлист"), role: .destructive) { confirmDelete = true }
            } label: {
                SonarIcon(.more, size: 22)
                    .foregroundStyle(Theme.text)
                    .frame(width: 52, height: 52)
                    .background(Theme.raised.opacity(0.92), in: Circle())
            }
            .accessibilityLabel(t("Изменить правила"))
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            SonarIcon(.search, size: 20).foregroundStyle(Theme.textSecondary)
            TextField(t("Найти"), text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Theme.raised.opacity(0.92), in: Capsule())
    }

    @ViewBuilder
    private var artwork: some View {
        let covers = SonarPlaylist.covers(of: tracks)
        if covers.isEmpty {
            SonarIcon(.sliders, filled: true, size: 92)
                .foregroundStyle(Theme.text.opacity(0.92))
                .frame(height: 100)
        } else {
            PlaylistCollage(covers: covers, cornerRadius: 24)
                .frame(width: 220, height: 220)
                .shadow(color: Theme.glow.opacity(0.35), radius: 24, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            ListenCapsuleButton(playing: listen.showsPause) {
                switch listen {
                case .pause: engine.pause()
                case .resume: engine.resume()
                case .start: play(shuffle: false)
                }
            }
            .disabled(tracks.isEmpty)
            CircleButton(icon: .shuffle, label: t("Перемешать")) { play(shuffle: true) }
                .disabled(tracks.isEmpty)
            CircleButton(icon: .sliders, label: t("Изменить правила"), action: openEditor)
            CircleButton(icon: .copy, label: t("Сохранить как обычный плейлист"), action: snapshot)
                .disabled(tracks.isEmpty)
        }
    }

    // MARK: - Подписи

    /// «Умный плейлист · из Любимых · 2 условия».
    private var subtitle: String {
        var parts = [t("Умный плейлист")]
        guard let rules = def?.parsed else { return parts[0] }
        switch rules.source {
        case .liked: parts.append(t("из Любимых"))
        case .played: parts.append(t("из всего прослушанного"))
        case let .playlist(source):
            parts.append(t("из «{name}»", ["name": playlists.playlist(source)?.name ?? t("плейлиста")]))
        }
        let n = rules.conditions.count
        if n > 0 { parts.append("\(n) " + tn(n, "условие", "условия", "условий")) }
        return parts.joined(separator: " · ")
    }

    private var countLine: String {
        let ms = tracks.reduce(0) { $0 + $1.durationMs }
        guard ms > 0 else { return tracksCount(tracks.count) }
        return tracksCount(tracks.count) + ", " + PlaylistDuration.text(ms: ms)
    }

    // MARK: - Список

    @ViewBuilder
    private var list: some View {
        switch outcome {
        case nil:
            ProgressView().tint(Theme.textSecondary).frame(maxWidth: .infinity).padding(.top, 30)
        case .invalid:
            hint(t("Правила этого плейлиста не читаются"),
                 t("Похоже, их сохранила более новая версия Sonar. Открой «Изменить правила» и собери их заново."))
        case .sourceMissing:
            hint(t("Исходного плейлиста больше нет"), t("Выбери другой источник в «Изменить правила»."))
        case let .tracks(all) where all.isEmpty:
            hint(t("Пока ни один трек не подходит"), t("Слушай и лайкай дальше — плейлист обновится сам. Или ослабь правила."))
        case .tracks:
            let list = shown
            LazyVStack(spacing: 4) {
                ForEach(Array(list.enumerated()), id: \.element.ref) { index, track in
                    TrackRow(track: track, playing: engine.current?.ref == track.ref, remove: nil) {
                        engine.play(list, at: index, context: title, tapped: true)
                    }
                    .cascade(index)
                }
            }
            if list.isEmpty {
                Text(t("Ничего не нашлось"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
    }

    private func hint(_ title: String, _ text: String) -> some View {
        HintCard(icon: .sliders, text: title + "\n" + text)
            .transition(.opacity)
    }

    // MARK: - Действия

    private func recompute() {
        guard let def else { return }
        outcome = SmartRunner.run(def, library: library, playlists: playlists)
    }

    private func play(shuffle: Bool) {
        let list = shown
        guard !list.isEmpty else { return }
        if shuffle != engine.shuffle { engine.toggleShuffle() }
        engine.play(list, at: shuffle ? Int.random(in: 0 ..< list.count) : 0, context: title)
    }

    private func openEditor() {
        guard let def else { return }
        editor = SmartDraft(editing: def.id, name: def.name, rules: def.parsed ?? .blank)
    }

    /// Снимок: обычный плейлист Sonar с текущими треками в текущем порядке.
    private func snapshot() {
        guard !tracks.isEmpty else {
            router.say(t("В плейлисте нет треков — сохранять нечего"))
            return
        }
        guard let copy = playlists.create(name: title, tracks: tracks) else { return }
        router.say(t("«{name}» сохранён как обычный плейлист — {tracks}", ["name": title, "tracks": tracksCount(tracks.count)]))
        router.push(.sonarPlaylist(id: copy), on: .library, chrome: chrome)
    }

    private func delete() {
        let name = title
        store.delete(id)
        router.say(t("Плейлист «{name}» удалён", ["name": name]))
    }
}
