import Foundation

// Покадровые признаки для анализа сведения (docs/BLEND.md §4.3) — порт
// `windows/src/player/blend/features.ts`. Менять — в обоих местах.
//
// STFT 1024 / шаг 256 на 11 025 Гц, окно Ханна. Один проход по треку считает всё, что нужно дальше:
// громкость кадра, энергию низа и середины, спектральный поток по трём полосам (огибающая атак) и хрому.
// Спектры не храним — 5 минут трека это ~13 тысяч кадров, признаки занимают сотни килобайт.

/// Признаки кадров. Все массивы длиной `count`, кроме хромы (`count × 12`).
struct BlendFrames: Sendable {
    let count: Int
    /// RMS кадра во времени.
    let rms: [Float]
    /// Энергия спектра ниже 200 Гц.
    let low: [Float]
    /// Энергия 300 Гц – 3 кГц (грубый признак вокала).
    let mid: [Float]
    /// Спектральный поток (рост модулей в логарифме) по полосам.
    let fluxLow: [Float]
    let fluxMid: [Float]
    let fluxHigh: [Float]
    /// Хрома: `count × 12`, класс 0 — до. Энергия класса — средняя по его бинам.
    let chroma: [Float]
}

enum BlendFeatures {
    static let sampleRate = 11025
    static let frame = 1024
    static let hop = 256
    /// Шаг кадра, мс (~23.2).
    static let frameMs = (Double(hop) / Double(sampleRate)) * 1000
    static let binHz = Double(sampleRate) / Double(frame)
    static let lowMaxHz = 200.0
    static let midMinHz = 300.0
    static let midMaxHz = 3000.0
    static let fluxHighHz = 3000.0
    static let chromaMinHz = 55.0
    static let chromaMaxHz = 2000.0
    /// Тишина по краям — ниже стольких дБ от пика.
    static let silenceDb = -50.0
    /// Поток атак опережает сам удар: кадр «видит» его раньше середины окна. Сдвиг подобран по щелчкам
    /// (без него сетка встаёт на 12–15 мс раньше удара; тест сетки, `firstBeatMs` ±10 мс).
    static let onsetShiftMs = 13.0

    /// Кадр, на который приходится время `ms` (дробный).
    static func frameAt(_ ms: Double) -> Double {
        (((ms - onsetShiftMs) / 1000) * Double(sampleRate) - Double(frame / 2)) / Double(hop)
    }

    static func frameCount(_ samples: Int) -> Int {
        max(1, (samples + hop - 1) / hop)
    }

    /// Класс высоты бина: 0…11 (до = 0) или −1, если бин вне 55 Гц – 2 кГц; и сколько бинов в классе.
    private static func pitchClasses() -> (pc: [Int], perClass: [Double]) {
        var pc = [Int](repeating: -1, count: frame / 2 + 1)
        var perClass = [Double](repeating: 0, count: 12)
        for k in 1...(frame / 2) {
            let hz = Double(k) * binHz
            if hz < chromaMinHz || hz > chromaMaxHz { continue }
            let c = ((BlendMath.jsRoundInt(12 * log2(hz / 440)) + 9) % 12 + 12) % 12
            pc[k] = c
            perClass[c] += 1
        }
        return (pc, perClass)
    }

    /// Признаки всех кадров моно-сигнала 11 025 Гц.
    static func frames(of x: [Float]) -> BlendFrames {
        let count = frameCount(x.count)
        var rms = [Float](repeating: 0, count: count)
        var low = [Float](repeating: 0, count: count)
        var mid = [Float](repeating: 0, count: count)
        var fluxLow = [Float](repeating: 0, count: count)
        var fluxMid = [Float](repeating: 0, count: count)
        var fluxHigh = [Float](repeating: 0, count: count)
        var chroma = [Float](repeating: 0, count: count * 12)

        let fft = BlendFFT(size: frame)
        let win = BlendFFT.hann(frame)
        var re = [Float](repeating: 0, count: frame)
        var im = [Float](repeating: 0, count: frame)
        let bins = frame / 2 + 1
        var prev = [Float](repeating: 0, count: bins)
        var cur = [Float](repeating: 0, count: bins)
        let (pc, perClass) = pitchClasses()
        let lowTop = Int((lowMaxHz / binHz).rounded(.down))
        let midLo = Int((midMinHz / binHz).rounded(.up))
        let midHi = Int((midMaxHz / binHz).rounded(.down))
        let highLo = Int((fluxHighHz / binHz).rounded(.up))

        for f in 0..<count {
            let start = f * hop
            var sq = 0.0
            for i in 0..<frame {
                let s: Float = start + i < x.count ? x[start + i] : 0
                sq += Double(s) * Double(s)
                re[i] = Float(Double(s) * Double(win[i]))
                im[i] = 0
            }
            rms[f] = Float((sq / Double(frame)).squareRoot())
            fft.transform(&re, &im)
            var bandLow = 0.0
            var bandMid = 0.0
            var fl = 0.0
            var fm = 0.0
            var fh = 0.0
            let base = f * 12
            for k in 1..<bins {
                let r = Double(re[k])
                let j = Double(im[k])
                let e = r * r + j * j
                let m = log1p(e.squareRoot())
                cur[k] = Float(m)
                let p = Double(prev[k])
                let rise = f > 0 && m > p ? m - p : 0
                if k <= lowTop {
                    bandLow += e
                    fl += rise
                } else if k < highLo {
                    fm += rise
                } else {
                    fh += rise
                }
                if k >= midLo && k <= midHi { bandMid += e }
                let c = pc[k]
                if c >= 0 { chroma[base + c] = Float(Double(chroma[base + c]) + e) }
            }
            for c in 0..<12 {
                let n = perClass[c] == 0 ? 1 : perClass[c]
                chroma[base + c] = Float(Double(chroma[base + c]) / n)
            }
            low[f] = Float(bandLow)
            mid[f] = Float(bandMid)
            fluxLow[f] = Float(fl)
            fluxMid[f] = Float(fm)
            fluxHigh[f] = Float(fh)
            swap(&prev, &cur)
        }
        return BlendFrames(
            count: count, rms: rms, low: low, mid: mid,
            fluxLow: fluxLow, fluxMid: fluxMid, fluxHigh: fluxHigh, chroma: chroma
        )
    }

    /// Тишина по краям: первый и последний кадр громче −50 дБ от пика.
    static func silenceBounds(_ f: BlendFrames, durationMs: Double) -> (startMs: Double, endMs: Double) {
        var peak = 0.0
        for i in 0..<f.count { peak = max(peak, Double(f.rms[i])) }
        if peak <= 0 { return (0, durationMs) }
        let floor = peak * pow(10, silenceDb / 20)
        var first = 0
        while first < f.count - 1 && Double(f.rms[first]) < floor { first += 1 }
        var last = f.count - 1
        while last > first && Double(f.rms[last]) < floor { last -= 1 }
        let startMs = (Double(first * hop) / Double(sampleRate)) * 1000
        let endMs = min(durationMs, (Double(last * hop + frame) / Double(sampleRate)) * 1000)
        return (startMs, endMs)
    }
}
