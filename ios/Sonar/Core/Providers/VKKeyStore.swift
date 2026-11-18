import Foundation

/// access_key треков VK на диске (`Sonar/vk-keys.json`) — порт `windows/src-tauri/src/services/vk_keys.rs`,
/// тот же формат `[[ref, key], …]` от давних к свежим. Без ключа `audio.getById` чужой трек не отдаёт, а ref
/// трека (`vk:<owner>_<id>`) ключа не несёт: трек из Любимых, плейлиста, очереди или волны после перезапуска
/// играет с тем ключом, который VK отдал при показе. Ключ трека — не секрет входа (без токена VK он ничего
/// не открывает). Переполнение — выкидываем самые давние, а не всё сразу.
struct VKKeyStore: Sendable {
    /// Сколько ключей помнить.
    static let maxKeys = 20_000
    /// После переполнения оставляем столько самых свежих (чтобы не чистить на каждом треке).
    static let keepAfterTrim = maxKeys * 9 / 10

    private struct Entry: Sendable {
        var key: String
        /// Когда видели последний раз — счётчик.
        var tick: Int
    }

    private let file: URL?
    private var keys: [String: Entry] = [:]
    private var tick = 0

    /// Только в памяти (тесты).
    init() {
        file = nil
    }

    /// С файла; нет файла или он битый — пусто.
    init(file: URL) {
        self.file = file
        guard let data = try? Data(contentsOf: file),
              let pairs = try? JSONDecoder().decode([[String]].self, from: data) else { return }
        for pair in pairs where pair.count == 2 {
            tick += 1
            keys[pair[0]] = Entry(key: pair[1], tick: tick)
        }
    }

    /// `Application Support/Sonar/vk-keys.json`.
    static var defaultFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Sonar/vk-keys.json")
    }

    var count: Int { keys.count }

    func key(for ref: String) -> String? {
        keys[ref]?.key
    }

    /// Запомнить пары ref → ключ; новые или сменившиеся сразу пишем на диск.
    mutating func remember(_ pairs: [(ref: String, key: String)]) {
        var changed = false
        for pair in pairs {
            tick += 1
            if keys[pair.ref]?.key != pair.key { changed = true }
            keys[pair.ref] = Entry(key: pair.key, tick: tick)
        }
        if keys.count > Self.maxKeys {
            trim()
            changed = true
        }
        if changed { save() }
    }

    /// Оставить `keepAfterTrim` самых свежих.
    private mutating func trim() {
        let ticks = keys.values.map(\.tick).sorted(by: >)
        guard ticks.count >= Self.keepAfterTrim else { return }
        let oldestKept = ticks[Self.keepAfterTrim - 1]
        keys = keys.filter { $0.value.tick >= oldestKept }
    }

    /// От давних к свежим, атомарно. Не записалось — ключи остаются в памяти до следующего раза.
    private func save() {
        guard let file else { return }
        let pairs = keys.sorted { $0.value.tick < $1.value.tick }.map { [$0.key, $0.value.key] }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(pairs).write(to: file, options: .atomic)
        } catch {
            // как у остальных хранилищ ядра: журнала здесь нет, следующая запись попробует снова
        }
    }
}
