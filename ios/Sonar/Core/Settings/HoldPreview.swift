import Foundation

/// «Удержи, чтобы послушать» — порт ядра `HoldGate` из `windows/src/lib/hold-preview.ts` (на ПК — `use:holdPreview` у
/// пресетов в `player/EqButton.svelte`). Пока палец на чипе дольше порога, звучит предпросмотр, отпустил — всё
/// возвращается, а касание, которым закончилось удержание, съедается: пресет не применяется. Короткое касание
/// проходит как обычно.
///
/// Без SwiftUI и таймеров: порог отсчитывает сама система (`onLongPressGesture(minimumDuration:)`), структура только
/// ведёт состояние и говорит, когда включить и когда вернуть звук. Экран — `EqualizerSheet` (`AudioSettingsView.swift`).
struct HoldGate: Equatable {
    /// Сколько держать до предпросмотра, секунд (на ПК — `HOLD_DELAY` 350 мс).
    static let delay: TimeInterval = 0.35

    enum Action: Equatable {
        /// Включить предпросмотр.
        case begin
        /// Вернуть прежний звук.
        case end
    }

    /// Удержание состоялось — ближайшее касание съедается.
    private(set) var held = false
    /// Предпросмотр звучит сейчас.
    private(set) var peeking = false

    /// Палец лёг (`true`) или поднялся / ушёл с чипа / касание отменили (`false`).
    /// Новое касание сбрасывает «съедание»; отпускание и отмена приходят подряд — звук возвращается один раз.
    mutating func pressChanged(_ pressing: Bool) -> Action? {
        if pressing {
            held = false
            return nil
        }
        return release()
    }

    /// Палец продержался до порога.
    mutating func fired() -> Action? {
        guard !peeking else { return nil }
        held = true
        peeking = true
        return .begin
    }

    /// Касание после удержания не считается нажатием. Вернёт `true` один раз.
    mutating func consumeTap() -> Bool {
        let was = held
        held = false
        return was
    }

    /// Экран закрыли посреди удержания — звук возвращается, касание съедать некому.
    mutating func cancel() -> Action? {
        held = false
        return release()
    }

    private mutating func release() -> Action? {
        guard peeking else { return nil }
        peeking = false
        return .end
    }
}

/// Какая кривая звучит и рисуется: пока держат пресет — он, иначе рабочая (как `eq.gains` на ПК, куда `peek` кладёт
/// пресет, а `unpeek` возвращает прежнюю, в том числе несохранённую).
enum EqualizerPeek {
    static func shown(peek: [Double]?, working: [Double]) -> [Double] {
        guard let peek, peek.count == working.count else { return working }
        return peek
    }
}
