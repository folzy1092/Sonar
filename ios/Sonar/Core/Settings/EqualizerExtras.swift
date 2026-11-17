import Foundation

/// Свои пресеты эквалайзера («Мои» на ПК, `audio.eq_presets`): на ПК — массив `[{name, gains}]`, на
/// iPhone настройки бывают только простыми значениями, поэтому тот же JSON лежит строкой. Новые сверху,
/// одинаковое название заменяет старый.
enum EqualizerUserPresets {
    static let key = "audio.eq_presets"
    static let maxName = 24

    private struct Item: Codable {
        var name: String
        var gains: [Double]
    }

    static func parse(_ raw: String) -> [Equalizer.Preset] {
        guard let data = raw.data(using: .utf8), let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        var seen = Set<String>()
        return items.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, item.gains.count == Equalizer.frequencies.count, !seen.contains(name) else { return nil }
            seen.insert(name)
            return Equalizer.Preset(name: name, gains: item.gains.map(Equalizer.clamp))
        }
    }

    static func encode(_ presets: [Equalizer.Preset]) -> String {
        guard !presets.isEmpty else { return "" }
        let items = presets.map { Item(name: $0.name, gains: $0.gains) }
        guard let data = try? JSONEncoder().encode(items) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Сохранить текущую кривую под названием; пустое название — без изменений.
    static func adding(_ name: String, gains: [Double], to list: [Equalizer.Preset]) -> [Equalizer.Preset] {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxName))
        guard !clean.isEmpty else { return list }
        return [Equalizer.Preset(name: clean, gains: gains.map(Equalizer.clamp))] + list.filter { $0.name != clean }
    }

    static func removing(_ name: String, from list: [Equalizer.Preset]) -> [Equalizer.Preset] {
        list.filter { $0.name != name }
    }

    /// Какой пресет сейчас: сначала свои, потом встроенные (как `activePreset` на ПК).
    static func matching(_ gains: [Double], user: [Equalizer.Preset]) -> Equalizer.Preset? {
        let same: (Equalizer.Preset) -> Bool = { preset in
            preset.gains.count == gains.count && zip(preset.gains, gains).allSatisfy { abs($0 - $1) < 0.05 }
        }
        return user.first(where: same) ?? Equalizer.preset(matching: gains)
    }
}

/// Кривая эквалайзера для рисунка: настоящая АЧХ тех же фильтров, что звучат (`Equalizer.filters`),
/// в дБ на логарифмической шкале 20 Гц … 20 кГц.
enum EqualizerCurve {
    static let sampleRate = 48_000.0
    static let minFrequency = 20.0
    static let maxFrequency = 20_000.0

    /// Усиление одного биквада на частоте, дБ.
    static func response(_ filter: Biquad, frequency: Double, sampleRate: Double = sampleRate) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let c1 = cos(w), s1 = sin(w), c2 = cos(2 * w), s2 = sin(2 * w)
        let numRe = filter.b0 + filter.b1 * c1 + filter.b2 * c2
        let numIm = -(filter.b1 * s1 + filter.b2 * s2)
        let denRe = 1 + filter.a1 * c1 + filter.a2 * c2
        let denIm = -(filter.a1 * s1 + filter.a2 * s2)
        let num = numRe * numRe + numIm * numIm
        let den = max(1e-12, denRe * denRe + denIm * denIm)
        return 10 * log10(max(1e-12, num) / den)
    }

    /// Частота точки `part` (0…1) логарифмической шкалы.
    static func frequency(at part: Double) -> Double {
        minFrequency * pow(maxFrequency / minFrequency, min(1, max(0, part)))
    }

    /// Доля шкалы (0…1) для частоты — где подписать полосу.
    static func position(of frequency: Double) -> Double {
        log(frequency / minFrequency) / log(maxFrequency / minFrequency)
    }

    /// `count` точек кривой: (доля шкалы, дБ), дБ зажаты в ±maxDb.
    static func points(_ gains: [Double], count: Int = 96) -> [(x: Double, db: Double)] {
        let filters = Equalizer.filters(gains, sampleRate: sampleRate).filter { !$0.isIdentity }
        let n = max(2, count)
        return (0 ..< n).map { (i: Int) -> (x: Double, db: Double) in
            let part = Double(i) / Double(n - 1)
            let f = frequency(at: part)
            let db = filters.reduce(0.0) { sum, filter in sum + response(filter, frequency: f) }
            return (x: part, db: min(Equalizer.maxDb, max(-Equalizer.maxDb, db)))
        }
    }
}
