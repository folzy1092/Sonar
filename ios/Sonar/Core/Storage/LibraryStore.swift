import Foundation
import Observation

/// Медиатека на устройстве, пока нет базы и сервера: Любимые (новые сверху) и запомненная скорость
/// треков (`track_prefs.speed`). JSON в Application Support; когда появится SQLite по DB.md — переедут
/// туда с теми же полями.
@MainActor
@Observable
final class LibraryStore {
    static let shared = LibraryStore()

    private(set) var liked: [Track] = []
    private(set) var likedRefs: Set<String> = []
    /// ref → скорость, «Запомнить» в листе скорости.
    private(set) var speeds: [String: Float] = [:]

    private struct Snapshot: Codable {
        var liked: [Track]
        var speeds: [String: Float]
    }

    @ObservationIgnored private let file: URL

    init(file: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.file = file ?? base.appendingPathComponent("Sonar/library.json")
        if let data = try? Data(contentsOf: self.file), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            liked = snapshot.liked
            likedRefs = Set(snapshot.liked.map(\.ref))
            speeds = snapshot.speeds
        }
    }

    func isLiked(_ track: Track) -> Bool {
        likedRefs.contains(track.ref)
    }

    func toggleLike(_ track: Track) {
        if likedRefs.contains(track.ref) {
            liked.removeAll { $0.ref == track.ref }
            likedRefs.remove(track.ref)
        } else {
            liked.insert(track, at: 0)
            likedRefs.insert(track.ref)
        }
        save()
    }

    func speed(for ref: String) -> Float? {
        speeds[ref]
    }

    /// nil — забыть.
    func rememberSpeed(_ speed: Float?, for ref: String) {
        speeds[ref] = speed
        save()
    }

    private func save() {
        let snapshot = Snapshot(liked: liked, speeds: speeds)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
