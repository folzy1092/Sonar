import Foundation

// Анализ трека для сведения (docs/BLEND.md §4.3–4.4) — порт `windows/src/player/blend/analysis.ts`:
// из моно 11 025 Гц — края без тишины, темп, сетка, «раз», такты, фразы, тональность, громкость.
// Менять — в обоих местах (и `blendAnalysisVersion` вместе с `ANALYSIS_VERSION`): тот же трек должен
// давать тот же результат на ПК и на iPhone. Части — BlendFeatures / BlendTempo / BlendStructure /
// BlendKey / BlendLoudness. Всё чистое и синхронное: звать не с главного потока.

enum BlendAnalyzer {
    static let sampleRate = BlendFeatures.sampleRate

    /// Каналы → моно (среднее).
    static func toMono(_ channels: [[Float]]) -> [Float] {
        guard let first = channels.first else { return [] }
        if channels.count == 1 { return first }
        let n = channels.map(\.count).min() ?? 0
        let count = Double(channels.count)
        var out = [Float](repeating: 0, count: n)
        for c in channels {
            for i in 0..<n { out[i] = Float(Double(out[i]) + Double(c[i]) / count) }
        }
        return out
    }

    private static func round(_ x: Double, _ digits: Int) -> Double {
        let scale = pow(10, Double(digits))
        return BlendMath.jsRound(x * scale) / scale
    }

    /// Анализ моно-сигнала, уже приведённого к 11 025 Гц.
    static func analyze(_ mono: [Float], ref: String) -> BlendAnalysis {
        let durationMs = BlendMath.jsRound((Double(mono.count) / Double(sampleRate)) * 1000)
        let frames = BlendFeatures.frames(of: mono)
        let (startMs, endMs) = BlendFeatures.silenceBounds(frames, durationMs: durationMs)
        let grid = BlendTempo.grid(frames, startMs: startMs, endMs: endMs)
        let downbeat = BlendTempo.downbeat(frames, grid: grid, endMs: endMs)
        let starts = BlendStructure.barStarts(grid, downbeat: downbeat, endMs: endMs)
        let (bars, chroma) = BlendStructure.barFeatures(frames, starts: starts, barMs: Double(beatsPerBar) * grid.beatMs)
        let (key, keyConf) = BlendKey.key(frames, startMs: startMs, endMs: endMs)
        return BlendAnalysis(
            version: blendAnalysisVersion,
            ref: ref,
            durationMs: durationMs,
            startMs: BlendMath.jsRound(startMs),
            endMs: BlendMath.jsRound(endMs),
            bpm: round(grid.bpm, 2),
            bpmConf: round(grid.bpmConf, 3),
            beatMs: round(grid.beatMs, 3),
            firstBeatMs: round(grid.firstBeatMs, 1),
            downbeat: downbeat,
            gridStable: grid.gridStable,
            key: key,
            keyConf: keyConf,
            loudness: BlendLoudness.loudness(of: mono),
            bars: bars,
            phrases: BlendStructure.phrases(bars, chroma: chroma)
        )
    }
}
