import Foundation

/// Жест «барабана» (`DrumRuler`) без SwiftUI: по сдвигу пальца считает значение под ним. Пока палец на ленте,
/// значение живёт только в `DrumRulerSession` (рисуется лента и число), наружу — ровно одно применение при
/// отпускании (`commit`). Так звук не перестраивается на каждый кадр жеста.
struct DrumRulerGeometry: Equatable {
    var range: ClosedRange<Double>
    var step: Double
    /// Точек ленты на шаг.
    var spacing: Double
    /// Среднее деление — каждые столько шагов (на нём вибрация).
    var medium: Int

    func snapped(_ value: Double) -> Double {
        let k = (min(range.upperBound, max(range.lowerBound, value)) / step).rounded()
        return k * step
    }

    /// Целый номер деления — без накопления ошибки дробей (0.05 / 0.01 и т. п.).
    private func index(_ value: Double) -> Int { Int((value / step).rounded()) }

    private func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }

    /// Лента прошла через среднее деление (кратное `medium`): пришла на него или проскочила за кадр.
    /// Уход с деления не считается — вибрация там, куда лента «встала», в обе стороны.
    func crossedMedium(from old: Double, to new: Double) -> Bool {
        let m = max(1, medium)
        let (a, b) = (index(old), index(new))
        if b > a { return floorDiv(b, m) != floorDiv(a, m) }
        if b < a { return floorDiv(-b, m) != floorDiv(-a, m) }
        return false
    }

    /// Палец сдвинулся на `translation` точек от места касания. `value` — значение ленты в момент касания (берётся
    /// один раз, на первом кадре жеста). `nil` — значение под пальцем не изменилось, перерисовывать нечего.
    func move(_ session: DrumRulerSession?, from value: Double, translation: Double)
        -> (session: DrumRulerSession, crossedMedium: Bool)? {
        let start = session?.start ?? value
        let previous = session?.current ?? start
        let next = snapped(start - translation / spacing * step)
        if abs(next - previous) < step / 2 {
            // первый кадр без сдвига: жест начался, показывать то же самое
            guard session == nil else { return nil }
            return (session: DrumRulerSession(start: start, current: start), crossedMedium: false)
        }
        return (session: DrumRulerSession(start: start, current: next), crossedMedium: crossedMedium(from: previous, to: next))
    }

    /// Палец отпущен: значение для единственного применения. `nil` — вернулся туда же, где начал, применять нечего.
    func commit(_ session: DrumRulerSession) -> Double? {
        abs(session.current - session.start) >= step / 2 ? session.current : nil
    }
}

/// Жест в процессе: где началась лента и что сейчас под пальцем.
struct DrumRulerSession: Equatable {
    let start: Double
    var current: Double
}
