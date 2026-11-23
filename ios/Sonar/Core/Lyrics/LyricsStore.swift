import Foundation
import Observation

/// Текст текущего трека (порт `windows/src/lyrics/lyrics.svelte.ts`): память на ~100 треков → кэш на
/// телефоне (`LyricsCache`) → поиск (`LyricsFinder`: lrclib → NetEase → Genius), предзагрузка следующего,
/// сдвиг синхронизации на трек, аннотации Genius, перевод и настройки вида `lyrics.*`.
@MainActor
@Observable
final class LyricsStore {
    static let shared = LyricsStore()

    /// Текст для `trackRef`. nil — грузится или не найден (`loading` / `failed`).
    private(set) var lyrics: Lyrics?
    private(set) var trackRef: String?
    private(set) var loading = false
    /// «Текст не найден» — показать пустое состояние (без тостов, LYRICS.md §7).
    private(set) var failed: String?

    /// id строки → перевод. Пусто — перевода нет (паузы и строки без перевода — без ключа).
    private(set) var translation: [Int: String] = [:]
    /// Перевод идёт.
    private(set) var translating = false
    /// На какой язык переводим (`ru`, `en`, `uk`). Не nil — следующие треки переводятся сами, пока не
    /// `clearTranslation()` (как «Перевести» в Windows держится между треками).
    private(set) var translationLanguage: String?
    /// Сообщение о переводе для тоста: «Текст уже на этом языке», «Перевод не удался — попробуй позже».
    var translationMessage: String?

    /// Аннотации Genius: id строки → пояснение. Грузятся в фоне после текста; нет на Genius — пусто.
    private(set) var notes: [Int: LyricsAnnotation] = [:]

    /// Сдвиги синхронизации, ref → мс (как `track_prefs.lyrics_offset_ms`; 0 — записи нет).
    private(set) var offsets: [String: Int] = [:]

    static let notFound = "Текст не найден"
    static let memoryMax = 100

    @ObservationIgnored private let provider: LyricsProviding
    @ObservationIgnored private let cache: LyricsCache
    /// Тексты скачанных треков (`DownloadStore.onSaved`): не чистятся и в офлайне показываются без срока.
    @ObservationIgnored private let pinned: LyricsCache
    @ObservationIgnored private let offsetsFile: URL
    @ObservationIgnored private let settings: SettingsStore
    /// ref → текст (nil — «не найдено»), новые в конце.
    @ObservationIgnored private var memory: [String: Lyrics?] = [:]
    @ObservationIgnored private var memoryOrder: [String] = []
    @ObservationIgnored private var inflight: [String: Task<Lyrics?, Error>] = [:]
    @ObservationIgnored private var notesCache: [String: [LyricsAnnotation]] = [:]
    @ObservationIgnored private var translationCache: [String: [Int: String]] = [:]
    /// Растёт при каждой смене трека — устаревшие ответы не применяются.
    @ObservationIgnored private var generation = 0

    /// `isLiked` — трек в Любимых (кэш у них живёт две недели). Без аргументов — общие хранилища приложения.
    init(provider: LyricsProviding = LyricsFinder(), cache: LyricsCache = LyricsCache(), pinned: LyricsCache? = nil,
         offsetsFile: URL? = nil, settings: SettingsStore? = nil, isLiked: ((String) -> Bool)? = nil) {
        self.provider = provider
        self.cache = cache
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.pinned = pinned ?? LyricsCache(directory: base.appendingPathComponent("Sonar/Downloads/lyrics", isDirectory: true))
        self.offsetsFile = offsetsFile ?? base.appendingPathComponent("Sonar/lyrics-offsets.json")
        self.settings = settings ?? .shared
        if let data = try? Data(contentsOf: self.offsetsFile), let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
            offsets = saved
        }
        let liked = isLiked ?? { LibraryStore.shared.likedRefs.contains($0) }
        // в офлайне кэш не чистим: новый текст без сети не найти
        if !OfflineFlag.isOn { cache.prune(isLiked: liked) }
    }

    // MARK: текст

    /// Текст трека: память → кэш → скачанное → сеть. Повторный вызов для того же трека — из памяти, без запроса.
    func load(for track: Track) async {
        if track.ref == trackRef, lyrics != nil || loading || failed != nil { return }
        await show(track, refresh: false)
    }

    /// «Найти заново»: мимо памяти и кэша.
    func reload(for track: Track) async {
        cache.remove(track.ref)
        forget(track.ref)
        inflight[track.ref]?.cancel()
        inflight[track.ref] = nil
        await provider.recheck(track.ref)
        await show(track, refresh: true)
    }

    /// Подгрузить текст заранее (следующий трек очереди) — в память и кэш, на экран не выводится.
    func preload(_ track: Track) async {
        guard memory[track.ref] == nil else { return }
        _ = try? await fetch(track)
    }

    /// Экран текста закрыт и трека нет — забыть текущий.
    func reset() {
        generation += 1
        trackRef = nil
        lyrics = nil
        loading = false
        failed = nil
        notes = [:]
        translation = [:]
    }

    private func show(_ track: Track, refresh: Bool) async {
        generation += 1
        let token = generation
        let ref = track.ref
        trackRef = ref
        lyrics = nil
        failed = nil
        notes = [:]
        translation = [:]
        loading = true
        let found: Lyrics?
        do {
            found = try await fetch(track)
        } catch {
            // сеть не ответила — тихо «Текст не найден» (не кэшируется, в следующий раз — снова в сеть)
            guard token == generation else { return }
            loading = false
            failed = Self.notFound
            return
        }
        guard token == generation else { return }
        loading = false
        guard let found, !found.lines.isEmpty else {
            failed = Self.notFound
            return
        }
        lyrics = found
        // пояснения Genius и перевод — только с сетью
        guard !OfflineFlag.isOn else { return }
        Task { await loadNotes(track, found, token: token) }
        if let language = translationLanguage { await translate(to: language, quiet: true) }
    }

    /// Память → кэш → скачанное → сеть (одновременные запросы одного трека — один поиск).
    private func fetch(_ track: Track) async throws -> Lyrics? {
        let ref = track.ref
        if let hit = memory[ref] {
            touch(ref)
            return hit
        }
        if let hit = cache.lookup(ref) {
            remember(ref, hit)
            return hit
        }
        // скачанный трек: текст рядом; без сети годится и «не найдено» любой давности
        let offline = OfflineFlag.isOn
        if let entry = pinned.get(ref), entry.lyrics != nil || offline {
            remember(ref, entry.lyrics)
            return entry.lyrics
        }
        if offline, let entry = cache.get(ref) {
            remember(ref, entry.lyrics)
            return entry.lyrics
        }
        if let running = inflight[ref] { return try await running.value }
        let provider = provider
        let query = LyricsQuery(track)
        let task = Task { try await provider.find(query) }
        inflight[ref] = task
        defer { if inflight[ref] == task { inflight[ref] = nil } }
        let found = try await task.value
        let saved = found?.lines.isEmpty == false ? found : nil
        cache.put(ref, saved)
        if FileManager.default.fileExists(atPath: pinned.file(for: ref).path) { pinned.put(ref, saved) }
        remember(ref, saved)
        return saved
    }

    /// Трек скачан — текст рядом с ним. Текста нет — пустая запись: найдётся позже — `fetch` её обновит.
    /// Сеть упала — ничего не пишем.
    func pin(_ track: Track) async {
        let found: Lyrics?
        do { found = try await fetch(track) } catch { return }
        pinned.put(track.ref, found)
    }

    /// Скачанный трек удалён.
    func unpin(_ ref: String) {
        pinned.remove(ref)
    }

    private func remember(_ ref: String, _ lyrics: Lyrics?) {
        memory[ref] = .some(lyrics)
        touch(ref)
        while memoryOrder.count > Self.memoryMax {
            memory[memoryOrder.removeFirst()] = nil
        }
    }

    private func touch(_ ref: String) {
        memoryOrder.removeAll { $0 == ref }
        memoryOrder.append(ref)
    }

    private func forget(_ ref: String) {
        memory[ref] = nil
        memoryOrder.removeAll { $0 == ref }
        notesCache[ref] = nil
        translationCache = translationCache.filter { !$0.key.hasPrefix("\(ref)|") }
    }

    // MARK: аннотации Genius

    private func loadNotes(_ track: Track, _ lyrics: Lyrics, token: Int) async {
        var annotations = notesCache[track.ref]
        if annotations == nil {
            guard let fetched = try? await provider.annotations(LyricsQuery(track)) else { return }
            notesCache[track.ref] = fetched
            if notesCache.count > 30, let any = notesCache.keys.first(where: { $0 != track.ref }) { notesCache[any] = nil }
            annotations = fetched
        }
        guard token == generation, let annotations else { return }
        let byIndex = LyricsAnnotations.map(lyrics.lines.map(\.text), annotations)
        notes = Dictionary(uniqueKeysWithValues: byIndex.compactMap { index, note in
            lyrics.lines.indices.contains(index) ? (lyrics.lines[index].id, note) : nil
        })
    }

    // MARK: сдвиг синхронизации (LYRICS.md §5)

    /// Сдвиг текста трека, секунды (−15…+15). Прибавляется к позиции до поиска строки и слова.
    func offset(for ref: String) -> Double {
        LyricsClock.offsetFromMs(offsets[ref])
    }

    /// 0 — запись удаляется.
    func setOffset(_ seconds: Double, for ref: String) {
        let ms = LyricsClock.offsetToMs(seconds)
        if ms == 0 { offsets[ref] = nil } else { offsets[ref] = ms }
        try? FileManager.default.createDirectory(at: offsetsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(offsets) { try? data.write(to: offsetsFile, options: .atomic) }
    }

    // MARK: перевод (translate.rs)

    /// Перевести текущий текст на `language` (`ru` / `en` / `uk` — язык интерфейса). Следующие треки
    /// переводятся сами, пока не `clearTranslation()`. Не вышло — `translationMessage`.
    func translate(to language: String) async {
        translationLanguage = language
        await translate(to: language, quiet: false)
    }

    /// `quiet` — для следующего трека: без сообщения «уже на этом языке».
    private func translate(to language: String, quiet: Bool) async {
        guard let ref = trackRef, let lyrics, !lyrics.lines.isEmpty else { return }
        let key = "\(ref)|\(language)"
        if let hit = translationCache[key] {
            translation = hit
            return
        }
        let token = generation
        translating = true
        defer { if token == generation { translating = false } }
        do {
            let result = try await provider.translate(lyrics.lines.map(\.text), to: language)
            guard token == generation, translationLanguage == language else { return }
            // текст уже на этом языке — переводить нечего
            if result.source == language {
                translation = [:]
                if !quiet { translationMessage = "Текст уже на этом языке" }
                return
            }
            var map: [Int: String] = [:]
            for (index, line) in lyrics.lines.enumerated() where index < result.lines.count {
                let text = result.lines[index]
                if !line.text.isEmpty, !text.isEmpty { map[line.id] = text }
            }
            translationCache[key] = map
            if translationCache.count > 30, let any = translationCache.keys.first(where: { $0 != key }) { translationCache[any] = nil }
            translation = map
        } catch {
            if token == generation, !quiet { translationMessage = "Перевод не удался — попробуй позже" }
        }
    }

    /// Выключить перевод (и для следующих треков).
    func clearTranslation() {
        translationLanguage = nil
        translation = [:]
        translationMessage = nil
    }

    // MARK: настройки вида (SETTINGS.md «Текст песни»)

    static let modeKey = "lyrics.mode"
    static let sizeKey = "lyrics.size"
    static let styleKey = "lyrics.style"
    static let animationKey = "lyrics.animation"

    /// «По словам» / «По строкам».
    var mode: LyricsMode {
        get { LyricsMode(rawValue: settings.string(Self.modeKey)) ?? .words }
        set { settings.set(Self.modeKey, .string(newValue.rawValue)) }
    }

    var size: LyricsSize {
        get { LyricsSize(rawValue: settings.string(Self.sizeKey)) ?? .l }
        set { settings.set(Self.sizeKey, .string(newValue.rawValue)) }
    }

    var style: LyricsTextStyle {
        get { LyricsTextStyle(rawValue: settings.string(Self.styleKey)) ?? .blur }
        set { settings.set(Self.styleKey, .string(newValue.rawValue)) }
    }

    var animation: LyricsAnimation {
        get { LyricsAnimation(rawValue: settings.string(Self.animationKey)) ?? .normal }
        set { settings.set(Self.animationKey, .string(newValue.rawValue)) }
    }

    /// Караоке по словам для текущего текста: режим «По словам» и время строк есть (слов нет — делятся по длине, как в Windows).
    var wordsOn: Bool { mode == .words && lyrics?.synced == true }
}
