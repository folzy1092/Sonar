import Foundation

/// Повтор: выключен → весь список → один трек (как кнопка в Windows-клиенте).
enum RepeatMode: String, Codable, Sendable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// Очередь без побочных эффектов — порт `windows/src/player/queue.ts` (с теми же тестами).
enum QueueMath {
    /// Порядок индексов треков. При перемешивании текущий трек остаётся первым.
    static func makeOrder(length: Int, current: Int, shuffle: Bool, random: () -> Double = { Double.random(in: 0 ..< 1) }) -> [Int] {
        let order = Array(0 ..< length)
        guard shuffle, length >= 2 else { return order }
        var rest = order.filter { $0 != current }
        var i = rest.count - 1
        while i > 0 {
            let j = Int(random() * Double(i + 1))
            rest.swapAt(i, j)
            i -= 1
        }
        return [current] + rest
    }

    /// Следующая позиция в порядке. manual — нажали «вперёд» (повтор трека не держит). nil — очередь кончилась.
    static func nextPos(_ pos: Int, length: Int, repeat mode: RepeatMode, manual: Bool) -> Int? {
        guard length > 0 else { return nil }
        if mode == .one, !manual { return pos }
        if pos + 1 < length { return pos + 1 }
        return mode == .off ? nil : 0
    }

    static func prevPos(_ pos: Int, length: Int, repeat mode: RepeatMode) -> Int {
        if pos > 0 { return pos - 1 }
        return mode == .all && length > 0 ? length - 1 : 0
    }

    /// Засчитать прослушивание: дослушал хотя бы до min(30 с, половины трека) — SPEC §3.8.
    static func countsAsPlay(listenedMs: Int, durationMs: Int) -> Bool {
        listenedMs >= min(30_000, durationMs > 0 ? durationMs / 2 : 30_000)
    }

    /// Вставить трек в очередь: next — сразу после текущего, иначе в конец. Трек дописывается в конец
    /// списка; меняется только порядок.
    static func enqueue(order: [Int], pos: Int, newIndex: Int, next: Bool) -> [Int] {
        guard !order.isEmpty else { return [newIndex] }
        var out = order
        out.insert(newIndex, at: next ? min(pos + 1, out.count) : out.count)
        return out
    }
}
