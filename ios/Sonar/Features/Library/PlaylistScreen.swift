import SwiftUI
import UIKit

/// Страница списка треков (`IMG_6770`): сверху ‹ · поиск · фильтр · ⋮, крупный значок (♥ у Любимых) или
/// обложка, название и число треков, «▶ Слушать / ⏸ Пауза», ⤮, ✎; ниже — треки. ✎ — режим выбора
/// (`IMG_6771`, `IMG_6772`): ✕ / ✓ сверху, тап выбирает трек, ≡ тянет его выше-ниже, снизу капсула
/// «Выбрано N треков» с действиями. Изменения применяются по ✓, ✕ — отменяет.
struct PlaylistScreen: View {
    enum Source: Hashable {
        case liked
        case downloaded
        case recent
        case service(ServicePlaylist)
        /// Свой плейлист Sonar (`PlaylistStore`).
        case sonar(String)
        /// Подборка Главной (`HomeFeed`).
        case mix(HomeMix)
    }

    let source: Source
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(ChromeState.self) private var chrome
    @Environment(Router.self) private var router
    @Environment(OfflineMode.self) private var offline
    @Environment(\.dismiss) private var dismiss

    @State private var loaded: [Track] = []
    @State private var loading = false
    @State private var failed: String?
    @State private var searching = false
    @State private var query = ""
    @State private var filter: LibraryView.SourceFilter = .all
    @State private var showMenu = false
    @State private var showConvert = false
    @State private var showExport = false
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var confirmDelete = false
    /// «Скачать всё» больше 50 треков или 1 ГБ — сначала спросить (`docs/OFFLINE.md` §8.2).
    @State private var batch: DownloadPlan.Batch?
    @State private var addAllToPlaylist = false
    @FocusState private var searchFocused: Bool

    // режим выбора
    @State private var editing = false
    @State private var draft: [Track] = []
    @State private var selected: Set<String> = []
    @State private var dragRef: String?
    @State private var dragOffset: CGFloat = 0

    static let editRowHeight: CGFloat = 64

    private var downloads: DownloadStore { DownloadStore.shared }
    private var store: PlaylistStore { PlaylistStore.shared }

    private var own: SonarPlaylist? {
        if case let .sonar(id) = source { return store.playlist(id) }
        return nil
    }

    // MARK: - Данные

    private var title: String {
        switch source {
        case .liked: "Любимые"
        case .downloaded: "Скачанные"
        case .recent: "Недавнее"
        case let .service(playlist): playlist.title
        case .sonar: own?.name ?? t("Плейлист Sonar")
        case .mix(.forYou): "Для вас"
        case .mix(.discoveries): "Открытия"
        }
    }

    /// Имя файла экспорта: свои названия (Любимые, Скачанные, Недавнее) — на языке интерфейса.
    private var exportName: String {
        switch source {
        case .service, .sonar: title
        default: t(title)
        }
    }

    /// В офлайне — только то, что есть на телефоне (`docs/OFFLINE.md` §6: недоступное скрыто).
    private var tracks: [Track] {
        offline.isOn ? offline.filter.tracks(allTracks) : allTracks
    }

    private var allTracks: [Track] {
        switch source {
        case .liked: library.liked
        case .downloaded: downloads.downloaded
        case .recent: PlayHistory.shared.recent
        case .service: loaded
        case .sonar: own?.tracks ?? []
        case .mix(.forYou): HomeFeed.shared.forYou
        case .mix(.discoveries): HomeFeed.shared.discoveries
        }
    }

    private var shown: [Track] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return tracks.filter { track in
            filter.keeps(track.ref) && (q.isEmpty || track.title.localizedCaseInsensitiveContains(q) || track.artist.localizedCaseInsensitiveContains(q))
        }
    }

    private var editable: Bool {
        // офлайн: правка списка по урезанному виду перемешала бы скрытое — только чтение (Скачанные можно)
        if offline.isOn, source != .downloaded { return false }
        return switch source {
        case .liked, .downloaded, .sonar: true
        default: false
        }
    }

    /// Порядок можно менять у Любимых и своих плейлистов (Скачанные — по дате загрузки).
    private var reorderable: Bool {
        guard !offline.isOn else { return false }
        return switch source {
        case .liked, .sonar: true
        default: false
        }
    }

    /// «Слушать» ⇄ «Пауза»: играет эта подборка — пауза, на паузе — продолжить с места.
    private var listen: ListenAction {
        .resolve(page: title, context: engine.contextTitle, isWave: engine.isWave, hasCurrent: engine.current != nil, isPlaying: engine.isPlaying, ended: engine.queueEnded)
    }

    // MARK: - Вид

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, 8)
                if searching, !editing {
                    searchField
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                artwork
                    .frame(maxWidth: .infinity)
                    .padding(.top, editing ? 24 : 34)
                Text(title)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, editing ? 18 : 44)
                Text(countLine)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
                    .padding(.top, 2)
                if !editing {
                    actions
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
                list
                    .padding(.top, editing ? 18 : 22)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 170)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .scrollDisabled(dragRef != nil)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            if !editing { chrome.scrolled(to: offset) }
        }
        .pageBackground()
        .overlay(alignment: .bottom) {
            if editing {
                selectionPanel
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.spring, value: editing)
        .animation(Motion.spring, value: searching)
        .animation(Motion.spring, value: tracks.count)
        .task(id: source) { await load() }
        .onChange(of: own == nil) { _, gone in
            // свой плейлист удалили (здесь или синком) — назад
            if gone, case .sonar = source { dismiss() }
        }
        .alert(t("Переименовать"), isPresented: $renaming) {
            TextField(t("Название"), text: $nameDraft)
            Button(t("Отмена"), role: .cancel) {}
            Button(t("Сохранить")) {
                if case let .sonar(id) = source { store.rename(id, to: nameDraft) }
            }
        }
        .alert(t("Скачать всё?"), isPresented: Binding(get: { batch != nil }, set: { if !$0 { batch = nil } }), presenting: batch) { batch in
            Button(t("Отмена"), role: .cancel) {}
            Button(t("Скачать")) { startDownloads(batch.tracks) }
        } message: { batch in
            Text(batch.summary + "\n" + t("Не закрывай Sonar, пока качается"))
        }
        .alert(t("Удалить плейлист?"), isPresented: $confirmDelete) {
            Button(t("Отмена"), role: .cancel) {}
            Button(t("Удалить"), role: .destructive) {
                guard case let .sonar(id) = source else { return }
                let name = title
                store.delete(id)
                router.say(t("Плейлист «{name}» удалён", ["name": name]))
            }
        } message: {
            Text(t("Треки останутся в Любимых и сервисах — удалится только список"))
        }
        .onDisappear { if editing { finishEditing(apply: false) } }
        .sheet(isPresented: $showMenu) {
            PlaylistSheet(
                title: title,
                count: tracks.count,
                canEdit: editable,
                canDownload: source != .downloaded && !offline.isOn,
                play: { play(shuffle: false) },
                shuffle: { play(shuffle: true) },
                download: downloadAll,
                edit: startEditing,
                convert: { showConvert = true },
                rows: menuRows
            )
            .presentationDetents([.height(PlaylistSheet.height(rows: menuRows.count + (editable ? 2 : 1))), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
            .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $addAllToPlaylist) {
            AddToPlaylistSheet(tracks: tracks) { message in
                addAllToPlaylist = false
                router.say(message)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
            .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showConvert) {
            ConvertSheet(title: title, tracks: tracks)
                .presentationDetents([.large])
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(name: exportName, tracks: tracks)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            if editing {
                CircleButton(icon: .close, label: "Отменить") { finishEditing(apply: false) }
                    .transition(.scale.combined(with: .opacity))
                Spacer()
                CircleButton(icon: .check, label: "Готово") { finishEditing(apply: true) }
                    .transition(.scale.combined(with: .opacity))
            } else {
                CircleButton(icon: .back, label: "Назад") { dismiss() }
                    .transition(.scale.combined(with: .opacity))
                Spacer()
                CircleButton(icon: searching ? .close : .search, label: "Поиск в списке") {
                    searching.toggle()
                    if searching { searchFocused = true } else { query = "" }
                }
                Menu {
                    Picker("Сервис", selection: $filter) {
                        ForEach(LibraryView.SourceFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    SonarIcon(.filter, filled: filter != .all, size: 22)
                        .foregroundStyle(filter == .all ? Theme.text : Theme.accent)
                        .frame(width: 52, height: 52)
                        .background(Theme.raised.opacity(0.92), in: Circle())
                }
                .accessibilityLabel("Фильтр")
                CircleButton(icon: .more, label: "Меню списка") { showMenu = true }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            SonarIcon(.search, size: 20).foregroundStyle(Theme.textSecondary)
            TextField("Найти в «\(title)»", text: $query)
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
        switch source {
        case .liked: bigIcon(.heart)
        case .downloaded: bigIcon(.download)
        case .recent: bigIcon(.history)
        case .mix:
            PlaylistCollage(covers: Covers.collage(tracks), cornerRadius: 24)
                .frame(width: 220, height: 220)
                .shadow(color: Theme.glow.opacity(0.35), radius: 24, y: 10)
        case let .service(playlist):
            CoverImage(url: playlist.coverURL, cornerRadius: 24)
                .frame(width: 220, height: 220)
                .shadow(color: Theme.glow.opacity(0.35), radius: 24, y: 10)
        case .sonar:
            PlaylistCollage(covers: own?.covers ?? [], cornerRadius: 24)
                .frame(width: editing ? 0 : 220, height: editing ? 0 : 220)
                .opacity(editing ? 0 : 1)
                .shadow(color: Theme.glow.opacity(0.35), radius: 24, y: 10)
        }
    }

    private func bigIcon(_ icon: IconName) -> some View {
        SonarIcon(icon, filled: true, size: editing ? 0 : 92)
            .foregroundStyle(Theme.text.opacity(0.92))
            .frame(height: editing ? 0 : 100)
            .opacity(editing ? 0 : 1)
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
            CircleButton(icon: .shuffle, label: "Перемешать") { play(shuffle: true) }
                .disabled(tracks.isEmpty)
            if editable {
                CircleButton(icon: .edit, label: "Редактировать", action: startEditing)
                    .disabled(tracks.isEmpty)
            }
        }
    }

    // MARK: - Список

    @ViewBuilder
    private var list: some View {
        if editing {
            editList
        } else if loading, tracks.isEmpty {
            ProgressView().tint(Theme.textSecondary).frame(maxWidth: .infinity).padding(.top, 30)
        } else if let failed, tracks.isEmpty {
            HintCard(icon: .info, text: failed)
        } else if tracks.isEmpty {
            HintCard(icon: emptyIcon, text: emptyText)
        } else {
            let list = shown
            LazyVStack(spacing: 4) {
                ForEach(Array(list.enumerated()), id: \.element.ref) { index, track in
                    TrackRow(track: track, playing: engine.current?.ref == track.ref, remove: removal(for: track),
                             note: source == .mix(.discoveries) ? HomeFeed.shared.reason(for: track.ref) : "") {
                        engine.play(list, at: index, context: title, tapped: true)
                    }
                    .cascade(index)
                }
            }
            if list.isEmpty {
                Text("Ничего не нашлось")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
    }

    private var emptyIcon: IconName {
        switch source {
        case .liked: .heart
        case .downloaded: .download
        default: .music
        }
    }

    private var emptyText: String {
        switch source {
        case .liked: "Нажми ♥ у трека — он появится здесь"
        case .downloaded: "Скачанные треки играют без интернета. Скачать — в меню трека или плейлиста"
        case .recent: "Здесь будут треки, которые ты слушал"
        case .service: offline.isOn ? t("Плейлисты сервисов открываются только с сетью.") : "В плейлисте пусто"
        case .sonar: t("Добавляй треки через меню трека: «Добавить в плейлист».")
        case .mix: t("Слушай и лайкай дальше — здесь соберутся треки под твой вкус.")
        }
    }

    /// «Удалить из плейлиста» в листе трека — для Любимых и Скачанных.
    private func removal(for track: Track) -> (@MainActor () -> Void)? {
        switch source {
        case .liked:
            return { withAnimation(Motion.spring) { library.removeLiked([track.ref]) } }
        case .downloaded:
            return { withAnimation(Motion.spring) { downloads.remove(track.ref) } }
        case let .sonar(id):
            return { withAnimation(Motion.spring) { store.remove([track.ref], from: id) } }
        default:
            return nil
        }
    }

    // MARK: - Режим выбора

    private var editList: some View {
        VStack(spacing: 0) {
            ForEach(draft, id: \.ref) { track in
                let isSelected = selected.contains(track.ref)
                let isDragged = dragRef == track.ref
                HStack(spacing: 14) {
                    CoverImage(url: track.coverURL, cornerRadius: 10)
                        .frame(width: 50, height: 50)
                    TrackTitle(track: track, playing: engine.current?.ref == track.ref)
                    Spacer(minLength: 8)
                    ZStack {
                        if isSelected {
                            SonarIcon(.check, size: 26)
                                .foregroundStyle(Theme.text)
                                .transition(.scale(scale: 0.5).combined(with: .opacity))
                        } else if reorderable {
                            SonarIcon(.drag, size: 26)
                                .foregroundStyle(Theme.textSecondary)
                                .transition(.opacity)
                                .frame(width: 52, height: Self.editRowHeight)
                                .contentShape(Rectangle())
                                .highPriorityGesture(dragGesture(track))
                        }
                    }
                    .frame(width: 52, height: Self.editRowHeight)
                }
                .frame(height: Self.editRowHeight)
                .contentShape(Rectangle())
                .onTapGesture { toggleSelection(track) }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.raised)
                        .padding(.horizontal, -8)
                        .opacity(isDragged ? 1 : 0)
                )
                .scaleEffect(isDragged ? 1.03 : 1)
                .shadow(color: .black.opacity(isDragged ? 0.35 : 0), radius: 14, y: 6)
                .offset(y: isDragged ? dragOffset : 0)
                .zIndex(isDragged ? 1 : 0)
                .animation(isDragged ? nil : Motion.spring, value: dragOffset)
                .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .animation(Motion.spring, value: draft.map(\.ref))
        .animation(Motion.quick, value: selected)
    }

    /// Тянем за ≡: строка едет за пальцем, соседи расступаются, когда она проходит половину строки.
    private func dragGesture(_ track: Track) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragRef == nil {
                    dragRef = track.ref
                    Haptics.tap()
                }
                guard let from = draft.firstIndex(where: { $0.ref == track.ref }) else { return }
                var offset = value.translation.height - consumed(track)
                let rows = Int((offset / Self.editRowHeight).rounded())
                let to = min(max(from + rows, 0), draft.count - 1)
                if to != from {
                    let moved = draft.remove(at: from)
                    withAnimation(Motion.spring) { draft.insert(moved, at: to) }
                    shift[track.ref, default: 0] += CGFloat(to - from) * Self.editRowHeight
                    offset = value.translation.height - consumed(track)
                    Haptics.select()
                }
                dragOffset = offset
            }
            .onEnded { _ in
                withAnimation(Motion.spring) {
                    dragRef = nil
                    dragOffset = 0
                }
                shift = [:]
            }
    }

    /// Сколько строк трек уже проехал (в pt) за это перетаскивание.
    @State private var shift: [String: CGFloat] = [:]
    private func consumed(_ track: Track) -> CGFloat { shift[track.ref] ?? 0 }

    private func toggleSelection(_ track: Track) {
        if selected.contains(track.ref) { selected.remove(track.ref) } else { selected.insert(track.ref) }
        Haptics.select()
    }

    private var selectionPanel: some View {
        let none = selected.isEmpty
        let chosen = draft.filter { selected.contains($0.ref) }
        let allLiked = !chosen.isEmpty && chosen.allSatisfy { library.isLiked($0) }
        return HStack(spacing: 4) {
            Text(none ? "Нажмите на треки, чтобы выбрать" : "Выбрано " + tracksCount(selected.count))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)
            panelButton(.listCheck, label: selected.count == draft.count ? "Снять выбор" : "Выбрать все", enabled: !draft.isEmpty) {
                selected = selected.count == draft.count ? [] : Set(draft.map(\.ref))
            }
            panelButton(.queue, label: "В очередь", enabled: !none) {
                for track in chosen { engine.enqueue(track, next: false) }
                router.say("В очереди: " + tracksCount(chosen.count))
            }
            panelButton(.heart, filled: allLiked, label: allLiked ? "Убрать из Любимых" : "В Любимые", enabled: !none) {
                for track in chosen where library.isLiked(track) == allLiked { library.toggleLike(track) }
                if source == .liked, allLiked {
                    draft.removeAll { selected.contains($0.ref) }
                    selected = []
                }
            }
            panelButton(.trash, label: "Удалить", tint: Theme.danger, enabled: !none) {
                draft.removeAll { selected.contains($0.ref) }
                selected = []
            }
            .padding(.trailing, 8)
        }
        .frame(height: 64)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().fill(Theme.raised.opacity(0.55)).allowsHitTesting(false))
        .overlay(Capsule().strokeBorder(Theme.line))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .animation(Motion.spring, value: none)
    }

    private func panelButton(_ icon: IconName, filled: Bool = false, label: String, tint: Color? = nil,
                             enabled: Bool, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            SonarIcon(icon, filled: filled, size: 25)
                .foregroundStyle(tint ?? Theme.text)
                .frame(width: 46, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private func startEditing() {
        guard editable else { return }
        searching = false
        query = ""
        draft = tracks
        selected = []
        editing = true
        chrome.barHidden = true
    }

    /// ✓ — удалить убранные и сохранить порядок; ✕ — всё как было.
    private func finishEditing(apply: Bool) {
        if apply {
            let kept = Set(draft.map(\.ref))
            let removed = Set(tracks.map(\.ref)).subtracting(kept)
            switch source {
            case .liked:
                if !removed.isEmpty { library.removeLiked(removed) }
                applyOrder(draft.map(\.ref))
            case .downloaded:
                for ref in removed { downloads.remove(ref) }
            case let .sonar(id):
                store.setOrder(draft.map(\.ref), in: id)
            default:
                break
            }
            if !removed.isEmpty { router.say("Удалено: " + tracksCount(removed.count)) }
        }
        editing = false
        selected = []
        draft = []
        chrome.barHidden = false
    }

    /// Привести порядок Любимых к нужному ходами «переставить один».
    private func applyOrder(_ order: [String]) {
        var current = library.liked.map(\.ref)
        for (target, ref) in order.enumerated() {
            guard let from = current.firstIndex(of: ref), from != target else { continue }
            library.moveLiked(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
            current.move(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
        }
    }

    // MARK: - Действия

    private func play(shuffle: Bool) {
        let list = shown
        guard !list.isEmpty else { return }
        if shuffle != engine.shuffle { engine.toggleShuffle() }
        engine.play(list, at: shuffle ? Int.random(in: 0 ..< list.count) : 0, context: title)
    }

    private func downloadAll() {
        let missing = tracks.filter { !downloads.isDownloaded($0.ref) && !downloads.isQueued($0.ref) }
        guard !missing.isEmpty else {
            router.say(t("Уже скачано"))
            return
        }
        let plan = DownloadPlan.Batch(missing, quality: SettingsStore.shared.string("audio.quality"),
                                      free: DownloadPlan.freeBytes(at: downloads.directory))
        guard plan.fits else {
            router.say(t("Не хватит места: {n}", ["n": plan.summary]))
            return
        }
        if plan.needsConfirm {
            batch = plan
        } else {
            startDownloads(missing)
        }
    }

    private func startDownloads(_ list: [Track]) {
        for track in list { downloads.download(track) }
        router.say(t("Скачивание: {n}", ["n": tracksCount(list.count)]))
    }

    /// «217 треков, 6 ч 51 мин» — у своих плейлистов, как на ПК; у остальных — только число.
    private var countLine: String {
        if offline.isOn { return OfflineFilter.countText(available: tracks.count, total: allTracks.count) }
        guard case .sonar = source, let own, own.durationMs > 0 else { return tracksCount(tracks.count) }
        return tracksCount(tracks.count) + ", " + PlaylistDuration.text(ms: own.durationMs)
    }

    /// Пункты меню списка сверх «Редактировать» / «Конвертировать» (на ПК — `PlaylistMenu.svelte`).
    private var menuRows: [PlaylistSheet.Row] {
        var rows: [PlaylistSheet.Row] = []
        let list = tracks
        if !list.isEmpty {
            rows.append(.init(icon: .next, title: t("Следующими"), subtitle: t("Сыграют после текущего")) {
                // каждый встаёт сразу за текущим — идём с конца, чтобы порядок сохранился
                for track in list.reversed() { engine.enqueue(track, next: true) }
                router.say(t("Треки будут играть следующими"))
            })
            rows.append(.init(icon: .queue, title: t("В очередь"), subtitle: t("В конец очереди")) {
                for track in list { engine.enqueue(track, next: false) }
                router.say(t("Треки добавлены в очередь"))
            })
            if source != .liked {
                rows.append(.init(icon: .heart, title: t("Лайкнуть все треки"), subtitle: t("Все — в Любимые")) {
                    let missing = list.filter { !library.isLiked($0) }
                    guard !missing.isEmpty else {
                        router.say(t("Все треки уже в Любимых"))
                        return
                    }
                    // toggleLike кладёт сверху — с конца, чтобы порядок списка сохранился
                    for track in missing.reversed() { library.toggleLike(track) }
                    router.say(t("В Любимых: {count}", ["count": tracksCount(missing.count)]))
                })
            }
            rows.append(.init(icon: .listCheck, title: t("Добавить в плейлист"), subtitle: t("Все треки списка")) {
                addAllToPlaylist = true
            })
        }
        rows.append(.init(icon: .copy, title: t("Копировать название"), subtitle: title) {
            UIPasteboard.general.string = title
            router.say(t("Название скопировано"))
        })
        if !list.isEmpty {
            rows.append(.init(icon: .share, title: t("Экспорт"), subtitle: "M3U8, CSV, JSON") {
                showExport = true
            })
        }
        switch source {
        case let .service(playlist) where !offline.isOn:
            if let existing = store.playlist(source: playlist.ref) {
                rows.append(.init(icon: .transfer, title: t("Открыть в Sonar"), subtitle: existing.name) {
                    router.push(.sonarPlaylist(id: existing.id), on: chrome.tab, chrome: chrome)
                })
            } else if !list.isEmpty {
                rows.append(.init(icon: .transfer, title: t("Перенести в Sonar"), subtitle: t("Свой плейлист из этих треков")) {
                    transfer(playlist, tracks: list)
                })
            }
        case let .sonar(id):
            let hidden = own?.hidden ?? false
            rows.append(.init(icon: .edit, title: t("Переименовать"), subtitle: title) {
                nameDraft = title
                renaming = true
            })
            rows.append(.init(icon: .eyeClosed, title: hidden ? t("Показать в «Все»") : t("Скрыть из «Все»"),
                              subtitle: hidden ? t("Снова в общей сетке Медиатеки") : t("Останется во вкладке «Плейлисты»")) {
                store.setHidden(id, !hidden)
                router.say(hidden ? t("Плейлист снова виден") : t("Плейлист скрыт из «Все»"))
            })
            rows.append(.init(icon: .trash, title: t("Удалить плейлист"), tint: Theme.danger) {
                confirmDelete = true
            })
        default:
            break
        }
        return rows
    }

    /// «Перенести в Sonar»: свой плейлист с треками сервиса (`source_ref` — чтобы не перенести дважды).
    private func transfer(_ playlist: ServicePlaylist, tracks list: [Track]) {
        guard let id = store.create(name: playlist.title, tracks: list, sourceRef: playlist.ref) else { return }
        router.say(t("Плейлист перенесён в Sonar"))
        router.push(.sonarPlaylist(id: id), on: chrome.tab, chrome: chrome)
    }

    private func load() async {
        guard case let .service(playlist) = source, !offline.isOn else { return }
        loading = true
        defer { loading = false }
        do {
            loaded = try await MusicCore.shared.playlist(playlist.ref).tracks
            failed = nil
        } catch {
            failed = error.localizedDescription
        }
    }
}

/// Лист списка (`IMG_6773`): название и число треков, капсула ▶ ⤮ ⤓, «Редактировать», «Конвертировать».
struct PlaylistSheet: View {
    let title: String
    let count: Int
    let canEdit: Bool
    let canDownload: Bool
    let play: @MainActor () -> Void
    let shuffle: @MainActor () -> Void
    let download: @MainActor () -> Void
    let edit: @MainActor () -> Void
    let convert: @MainActor () -> Void
    var rows: [Row] = []
    @Environment(\.dismiss) private var dismiss

    /// Пункт меню сверх встроенных.
    struct Row: Identifiable {
        let id = UUID()
        let icon: IconName
        let title: String
        var subtitle: String?
        var tint: Color?
        let action: @MainActor () -> Void
    }

    /// Высота листа: шапка с капсулой и строки по ~70 pt (больше экрана — лист растягивается).
    static func height(rows: Int) -> CGFloat {
        min(330 + CGFloat(rows) * 70, 760)
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            Text(tracksCount(count))
                .font(.system(size: 17))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            IconCapsuleRow(items: [
                .init(icon: .play, label: "Слушать") { close(play) },
                .init(icon: .shuffle, label: "Перемешать") { close(shuffle) },
                .init(icon: .download, enabled: canDownload, label: "Скачать всё") { close(download) },
            ])
            .padding(.top, 34)
            VStack(spacing: 6) {
                if canEdit {
                    SheetMenuRow(icon: .listCheck, title: "Редактировать", subtitle: "Порядок и удаление треков") { close(edit) }
                }
                SheetMenuRow(icon: .transfer, title: "Конвертировать", subtitle: "На другой сервис") { close(convert) }
                ForEach(rows) { row in
                    SheetMenuRow(icon: row.icon, title: row.title, subtitle: row.subtitle, tint: row.tint) { close(row.action) }
                }
            }
            .padding(.top, 26)
            .padding(.horizontal, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 30)
        .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Сначала закрыть лист, потом действие — иначе второй лист не откроется.
    private func close(_ action: @escaping @MainActor () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            action()
        }
    }
}
