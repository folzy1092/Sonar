import Foundation

// Тональности для сведения (docs/BLEND.md §7.4) — порт `windows/src/player/blend/camelot.ts`, менять — в обоих
// местах и в тестах. Круг Camelot, совместимость двух тональностей и сдвиг тона входящего трека, при котором
// они станут совместимы. Тональность — как в анализе: 0…11 мажор (до = 0), 12…23 минор (ля минор = 21), nil — не знаем.
//
// Связанная скорость (тон едет вместе со скоростью) сама сдвигает тон на 12·log2(rate) — дробно. Поэтому всё
// считается в полутонах с дробью: «совместимо без сдвига» — если до совместимой тональности не больше четверти тона.

struct CamelotKey: Hashable, Sendable {
    /// 1…12.
    var num: Int
    /// A — минор, B — мажор.
    var minor: Bool
}

struct CamelotMatch: Hashable, Sendable {
    /// 0…1; тональность одного из треков неизвестна — 0.5.
    var score: Double
    /// Сдвиг тона B на время перехода, полутонов (−2…+2).
    var shift: Double
    /// Обе тональности известны, а совместить не вышло: долгое наложение — каша.
    var clash: Bool
}

enum BlendCamelot {
    /// Сдвиг тона входящего трека на время перехода — не больше, полутонов (решение владельца 8).
    static let maxShift = 2.0
    /// До совместимой тональности ближе — сдвиг не нужен, полутонов.
    static let inTune = 0.25
    /// Энергичный буст (+2 по кругу) — совместим, но слабее.
    static let boostScore = 0.6
    /// Тональность одного из треков неизвестна.
    static let unknownScore = 0.5

    /// До мажор = 8B, ля минор = 8A; шаг квинтой вверх — +1 по кругу.
    static func camelot(_ key: Int) -> CamelotKey {
        let minor = key >= 12
        let tonic = BlendMath.mod(key, 12)
        let major = minor ? tonic + 3 : tonic // параллельный по Camelot = относительный мажор
        return CamelotKey(num: BlendMath.mod(major * 7 + 7, 12) + 1, minor: minor)
    }

    /// «8B», «5A» — для отладки и подсказок.
    static func name(_ key: Int?) -> String {
        guard let key else { return "—" }
        let c = camelot(key)
        return "\(c.num)\(c.minor ? "A" : "B")"
    }

    /// Совместимость B после A, 0…1: та же клетка и ±1 по кругу, мажор ↔ минор с тем же номером — 1; +2 — 0.6.
    static func compat(_ a: Int, _ b: Int) -> Double {
        let ca = camelot(a)
        let cb = camelot(b)
        let step = BlendMath.mod(cb.num - ca.num, 12)
        if ca.minor != cb.minor { return step == 0 ? 1 : 0 }
        if step == 0 || step == 1 || step == 11 { return 1 }
        return step == 2 ? boostScore : 0
    }

    private struct Target {
        var interval: Int
        var minorB: Bool
        var score: Double
    }

    /// Интервал от тоники A до тоники B (0…11) и лад B, при которых B совместим с A.
    private static func compatibleTargets(_ a: Int) -> [Target] {
        let tonicA = BlendMath.mod(a, 12)
        return [false, true].flatMap { minorB in
            (0..<12).compactMap { interval -> Target? in
                let b = BlendMath.mod(tonicA + interval, 12) + (minorB ? 12 : 0)
                let score = compat(a, b)
                return score > 0 ? Target(interval: interval, minorB: minorB, score: score) : nil
            }
        }
    }

    /// Ближайший к 0 представитель x по модулю 12: −6…+6.
    private static func nearest(_ x: Double) -> Double {
        BlendMath.mod(x + 6, 12) - 6
    }

    /// Насколько B совместим с A и какой сдвиг тона B это даёт (§7.4).
    /// - Parameters:
    ///   - driftA, driftB: сдвиг тона A и B от связанной скорости, полутонов (12·log2(rate); 0 — тон сохраняется).
    ///   - allowShift: `audio.blend_key` — можно сдвигать тон B.
    static func keyMatch(_ a: Int?, _ b: Int?, driftA: Double = 0, driftB: Double = 0, allowShift: Bool) -> CamelotMatch {
        guard let a, let b else { return CamelotMatch(score: unknownScore, shift: 0, clash: false) }
        let minorB = b >= 12
        // где сейчас тоника B относительно тоники A, с дробью от скоростей
        let actual = Double(BlendMath.mod(b, 12)) + driftB - (Double(BlendMath.mod(a, 12)) + driftA)
        var best = CamelotMatch(score: 0, shift: 0, clash: true)
        for t in compatibleTargets(a) where t.minorB == minorB {
            let need = nearest(Double(t.interval) - actual)
            let isInTune = abs(need) <= inTune
            if !isInTune && (!allowShift || abs(need) > maxShift) { continue }
            let shift = isInTune ? 0 : BlendMath.jsRound(need * 100) / 100
            let better = t.score > best.score || (t.score == best.score && abs(shift) < abs(best.shift))
            if better { best = CamelotMatch(score: t.score, shift: shift, clash: false) }
        }
        return best
    }
}

/// Арифметика как в JS: остаток со знаком делителя (`jsRound` — в BlendFFT.swift).
extension BlendMath {
    static func mod(_ x: Int, _ m: Int) -> Int {
        ((x % m) + m) % m
    }

    static func mod(_ x: Double, _ m: Double) -> Double {
        (x.truncatingRemainder(dividingBy: m) + m).truncatingRemainder(dividingBy: m)
    }

    /// `Math.round(x · 10^digits) / 10^digits`.
    static func round(_ x: Double, _ digits: Int) -> Double {
        let p = pow(10, Double(digits))
        return jsRound(x * p) / p
    }

    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, x))
    }
}
