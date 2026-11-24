import Foundation

// Настройки сведения (docs/BLEND.md §7.3, §10.2) — порт `windows/src/player/blend/settings.ts` и `BlendSettings`
// из `controller.svelte.ts`, менять — в обоих местах и в тестах. Ключи `audio.blend_*` → `BlendSettings`
// контроллера и выбор «Переход между треками» (Обычный · Кроссфейд · Сведение) поверх `audio.blend` и
// `audio.crossfade`.

struct BlendSettings: Hashable, Sendable {
    var type: BlendType
    var lengthSec: Double
    var cutSec: Double
    var tempoTolPct: Double
    var keyShift: Bool
    /// Перевес 👍/👎 по видам за 60 дней (§8.6): «Авто» реже берёт вид с минусом.
    var ratings: [BlendKind: Double] = [:]

    /// Значения по умолчанию из §7.3.
    static let defaults = BlendSettings(type: .auto, lengthSec: 10, cutSec: 16, tempoTolPct: 8, keyShift: true)
}

/// Сырые значения ключей `audio.blend_type|length|cut|tempo|key` — что лежит в настройках, может быть старым или битым.
struct BlendKeys {
    var type: Any?
    var length: Any?
    var cut: Any?
    var tempo: Any?
    var key: Any?
}

/// «Переход между треками».
enum TransitionMode: String, Sendable, CaseIterable {
    case normal, crossfade, blend
}

enum BlendPrefs {
    static let types = BlendType.allCases
    static let lengths: [Double] = [6, 10, 16]
    static let cutMaxSec = 45.0
    /// Отметка на ползунке «Можно срезать».
    static let cutRecommendedSec = 16.0
    static let tempoTolMaxPct = 12.0
    /// Кроссфейд, который включается выбором «Кроссфейд», если длины ещё нет, с.
    static let crossfadeDefaultSec = 6.0

    static func blendSettings(_ k: BlendKeys) -> BlendSettings {
        let type = (k.type as? String).flatMap(BlendType.init(rawValue:)) ?? .auto
        return BlendSettings(
            type: type,
            lengthSec: nearestLength(number(k.length) ?? 10),
            cutSec: BlendMath.clamp(BlendMath.jsRound(number(k.cut) ?? cutRecommendedSec), 0, cutMaxSec),
            tempoTolPct: BlendMath.clamp(BlendMath.jsRound(number(k.tempo) ?? 8), 0, tempoTolMaxPct),
            keyShift: !isExplicitFalse(k.key)
        )
    }

    static func transitionMode(blend: Bool, crossfadeSec: Double) -> TransitionMode {
        if blend { return .blend }
        return crossfadeSec > 0 ? .crossfade : .normal
    }

    /// Что записать в `audio.blend` и `audio.crossfade`. Сведение длину кроссфейда не трогает — это подстраховка.
    static func applyMode(_ mode: TransitionMode, crossfadeSec: Double) -> (blend: Bool, crossfade: Double) {
        switch mode {
        case .blend: return (true, crossfadeSec)
        case .crossfade: return (false, crossfadeSec > 0 ? crossfadeSec : crossfadeDefaultSec)
        case .normal: return (false, 0)
        }
    }

    /// Ближайшая из трёх длин.
    private static func nearestLength(_ sec: Double) -> Double {
        lengths.reduce(10) { best, l in abs(l - sec) < abs(best - sec) ? l : best }
    }

    /// Конечное число, но не логическое (`true` в NSNumber — тоже число, а на ПК `typeof true !== 'number'`).
    private static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, !isBool(n) else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    /// Только явное `false` выключает: на ПК `key !== false`.
    private static func isExplicitFalse(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber, isBool(n) else { return false }
        return !n.boolValue
    }

    private static func isBool(_ n: NSNumber) -> Bool {
        CFGetTypeID(n) == CFBooleanGetTypeID()
    }
}
