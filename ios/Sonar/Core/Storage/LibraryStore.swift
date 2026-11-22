import Foundation
import Observation

/// Медиатека на устройстве, пока нет базы и сервера: Любимые (новые сверху, порядок можно менять),
/// 👎 «Не интересно» (`wave_dislikes`: трек не попадёт в подборки, волну и «Авто похожие») и
/// звук трека «Для этого трека» (`track_prefs.sound_json`, `TrackSound`). JSON в Application Support; когда появится SQLite по DB.md — переедут
/// туда с теми же полями.
@MainActor
@Observable
final class LibraryStore {
    static let shared = LibraryStore()

    private(set) var liked: [Track] = []
    private(set) var likedRefs: Set<String> = []
    /// ref → звук трека («Для этого трека» в листе скорости). Остальные треки — по общим настройкам.
    private(set) var sounds: [String: TrackSound] = [:]
    /// 👎 — ref треков «Не интересно».
    private(set) var disliked: Set<String> = []
    /// ref → когда лайкнут (мс с 1970) — для умных плейлистов («Новое в Любимых»). Перетаскивание его не
    /// меняет; лайкнутые до появления поля даты не имеют (условие «добавлен за N дней» их не берёт).
    private(set) var likedAt: [String: Int] = [:]

    private struct Snapshot: Codable {
        var liked: [Track]
        /// Старый файл: только «Запомнить скорость» — переносится в `sounds` (скорость, тон сохраняется).
        var speeds: [String: Float]?
        var sounds: [String: TrackSound]?
        /// Нет в старом файле — пусто.
        var disliked: [String]?
        var likedAt: [String: Int]?
    }

    @ObservationIgnored private let file: URL
    /// Часы — тесты подставляют свои.
    @ObservationIgnored var now: () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }

    init(file: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.file = file ?? base.appendingPathComponent("Sonar/library.json")
        if let data = try? Data(contentsOf: self.file), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            liked = snapshot.liked
            likedRefs = Set(snapshot.liked.map(\.ref))
            var sounds = (snapshot.speeds ?? [:]).compactMapValues { TrackSound(rate: Double($0)).normalized() }
            for (ref, sound) in snapshot.sounds ?? [:] { sounds[ref] = sound.normalized() }
            self.sounds = sounds
            disliked = Set(snapshot.disliked ?? [])
            likedAt = (snapshot.likedAt ?? [:]).filter { likedRefs.contains($0.key) }
        }
    }

    func isLiked(_ track: Track) -> Bool {
        likedRefs.contains(track.ref)
    }

    func toggleLike(_ track: Track) {
        if likedRefs.contains(track.ref) {
            liked.removeAll { $0.ref == track.ref }
            likedRefs.remove(track.ref)
            likedAt[track.ref] = nil
        } else {
            liked.insert(track, at: 0)
            likedRefs.insert(track.ref)
            likedAt[track.ref] = now()
        }
        save()
    }

    /// Убрать из Любимых сразу несколько (режим редактирования).
    func removeLiked(_ refs: Set<String>) {
        guard !refs.isEmpty else { return }
        liked.removeAll { refs.contains($0.ref) }
        likedRefs.subtract(refs)
        likedAt = likedAt.filter { !refs.contains($0.key) }
        save()
    }

    /// Перетаскивание в Любимых — те же правила, что у SwiftUI `onMove`.
    func moveLiked(fromOffsets: IndexSet, toOffset: Int) {
        let moved = ListMath.move(liked, fromOffsets: fromOffsets, toOffset: toOffset)
        guard moved != liked else { return }
        liked = moved
        save()
    }

    func isDisliked(_ ref: String) -> Bool {
        disliked.contains(ref)
    }

    /// 👎 «Не интересно»; повторно — вернуть. Из Любимых трек не убирается: это разные списки.
    func toggleDislike(_ track: Track) {
        if disliked.contains(track.ref) {
            disliked.remove(track.ref)
        } else {
            disliked.insert(track.ref)
        }
        save()
    }

    func sound(for ref: String) -> TrackSound? {
        sounds[ref]
    }

    /// Запомнить звук для трека; nil — забыть (трек снова по общим настройкам).
    func rememberSound(_ sound: TrackSound?, for ref: String) {
        let sound = sound?.normalized()
        guard sounds[ref] != sound else { return }
        sounds[ref] = sound
        save()
    }

    private func save() {
        let snapshot = Snapshot(liked: liked, speeds: nil, sounds: sounds, disliked: disliked.sorted(), likedAt: likedAt)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        onChange?()
    }

    // MARK: - Синк (`Core/Sync/StoreAdapters.swift`)

    /// Любое изменение медиатеки — журнал синка сверяет снимок (`SyncService.noteLocalChange`).
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    /// Пришло с другого устройства: заменить списки целиком (nil — не трогать). `likedAt` — даты новых лайков;
    /// у оставшихся в Любимых даты сохраняются.
    func applySynced(liked: [Track]? = nil, disliked: Set<String>? = nil, sounds: [String: TrackSound]? = nil,
                     likedAt: [String: Int] = [:]) {
        if let liked {
            self.liked = liked
            likedRefs = Set(liked.map(\.ref))
        }
        self.likedAt = self.likedAt.merging(likedAt) { _, new in new }.filter { likedRefs.contains($0.key) }
        if let disliked { self.disliked = disliked }
        if let sounds { self.sounds = sounds }
        save()
    }
}

/// Списки без SwiftUI (`Array.move(fromOffsets:toOffset:)` есть только в нём, а ядро гоняется и на Linux).
enum ListMath {
    /// Как `MutableCollection.move` из SwiftUI: элементы с позиций `offsets` встают перед элементом,
    /// который до переноса стоял на `destination` (`count` — в конец), сохраняя свой порядок.
    static func move<T>(_ array: [T], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [T] {
        let valid: [Int] = offsets.filter { array.indices.contains($0) }
        guard !valid.isEmpty else { return array }
        let skip = Set(valid)
        let picked = valid.map { array[$0] }
        let before = valid.filter { $0 < destination }.count
        var rest = array.enumerated().filter { !skip.contains($0.offset) }.map(\.element)
        let at = max(0, min(destination - before, rest.count))
        rest.insert(contentsOf: picked, at: at)
        return rest
    }
}
