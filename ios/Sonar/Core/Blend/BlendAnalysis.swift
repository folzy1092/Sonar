import Foundation

// Результат анализа трека для сведения (docs/BLEND.md §4.3–4.4) — зеркало `BlendAnalysis` из
// `windows/src/player/blend/analysis.ts`: те же поля и те же ключи JSON, чтобы позже их можно было
// синхронизировать. Считает `BlendAnalyzer`, хранит `BlendAnalysisStore`.

/// Поменяли алгоритм — поднять: старые результаты пересчитаются при следующем проигрывании.
/// Совпадает с `ANALYSIS_VERSION` на ПК: алгоритм тот же.
let blendAnalysisVersion = 1

enum PhraseKind: String, Codable, Sendable, CaseIterable {
    case intro, body, build, drop, outro
}

struct BlendPhrase: Codable, Hashable, Sendable {
    var bar: Int
    var kind: PhraseKind
}

/// Признаки по тактам, 0…1.
struct BlendBars: Codable, Hashable, Sendable {
    var energy: [Double]
    var low: [Double]
    var mid: [Double]
    var onsets: [Double]
}

struct BlendAnalysis: Codable, Hashable, Sendable {
    var version: Int
    var ref: String
    var durationMs: Double
    /// Без тишины по краям.
    var startMs: Double
    var endMs: Double
    var bpm: Double
    var bpmConf: Double
    /// Длина доли, 60000 / bpm.
    var beatMs: Double
    /// Первая доля сетки.
    var firstBeatMs: Double
    /// Какая доля сетки — «раз», 0…3.
    var downbeat: Int
    var gridStable: Bool
    /// 0…11 мажор, 12…23 минор, nil — не знаем.
    var key: Int?
    var keyConf: Double
    /// ~LUFS.
    var loudness: Double
    var bars: BlendBars
    var phrases: [BlendPhrase]
}

let beatsPerBar = 4
