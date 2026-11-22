import Foundation

/// Звук трека — «Для этого трека» в листе скорости (решение владельца 2026-11-22, как ПК
/// `store/track_sound.rs`): скорость, тон (свой или связанный со скоростью), реверб и кривая эквалайзера
/// для одного трека. Остальные треки играют по общим настройкам. Хранится в `LibraryStore.sounds`, едет
/// синком в `track_pref` (`{speed, lyrics_offset_ms, sound}`): `speed` = `rate` для старых клиентов.
struct TrackSound: Codable, Equatable, Sendable {
    /// Скорость 0.5…2.
    var rate: Double
    /// Свой сдвиг тона в полутонах −12…+12 (когда не связан со скоростью).
    var pitch: Double = 0
    /// Тон едет вместе со скоростью (slowed / sped up).
    var linked = false
    /// Реверб 0…1; 0 — выключен.
    var reverb: Double = 0
    /// Кривая эквалайзера, 12 полос в дБ; nil — общая кривая.
    var eq: [Double]?

    static let rateRange = 0.5 ... 2.0
    static let pitchRange = -12.0 ... 12.0

    /// В допустимых пределах; не числа — nil.
    func normalized() -> TrackSound? {
        guard rate.isFinite, pitch.isFinite, reverb.isFinite else { return nil }
        let curve = eq.flatMap { gains -> [Double]? in
            guard gains.count == Equalizer.frequencies.count, gains.allSatisfy(\.isFinite) else { return nil }
            return gains.map(Equalizer.clamp)
        }
        return TrackSound(rate: Self.round(rate.clamped(to: Self.rateRange), 100),
                          pitch: Self.round(pitch.clamped(to: Self.pitchRange), 10),
                          linked: linked,
                          reverb: Self.round(reverb.clamped(to: 0 ... 1), 100),
                          eq: curve)
    }

    /// Тон, который звучит: связан — от скорости (×2 — октава вверх), иначе свой.
    var semitones: Double { linked ? Self.linkedSemitones(rate) : pitch }

    static func linkedSemitones(_ rate: Double) -> Double {
        Self.round(12 * log2(rate), 10)
    }

    static func pitchRatio(_ semitones: Double) -> Double {
        pow(2, semitones / 12)
    }

    // MARK: - Плашка «Свой звук»

    /// Что у трека отличается от обычного звука — для плашки «Свой звук · x0.85 · Reverb» у названия
    /// (решение владельца 2026-11-22). Зеркало ПК `player/tempo.svelte.ts` `ownSoundParts`: скорость не 1×,
    /// свой тон (связанный со скоростью не пишем — его уже видно в скорости), реверб, не плоская кривая.
    var ownParts: [String] {
        var parts: [String] = []
        if rate != 1 { parts.append("x\(Self.trim(rate))") }
        if !linked, pitch != 0 { parts.append("\(pitch > 0 ? "+" : "−")\(Self.trim(abs(pitch))) st") }
        if reverb > 0 { parts.append("Reverb") }
        if let eq, !Equalizer.isFlat(eq) { parts.append("EQ") }
        return parts
    }

    /// 0.85 → «0.85», 1.50 → «1.5», 2 → «2» — как число в JS.
    private static func trim(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: - Синк

    var json: JSONValue {
        .object([
            "rate": .double(rate),
            "pitch": .double(pitch),
            "linked": .bool(linked),
            "reverb": .double(reverb),
            "eq": eq.map { .array($0.map { .double($0) }) } ?? .null,
        ])
    }

    /// Из значения `track_pref`: `sound`, а у старых клиентов (только «Запомнить скорость») — из `speed`:
    /// та же скорость, тон сохраняется. Ничего — nil.
    static func fromSync(_ value: JSONValue) -> TrackSound? {
        let sound = value["sound"]
        if case .object = sound {
            guard let rate = sound["rate"].number else { return nil }
            let eq = sound["eq"].array.map { $0.compactMap(\.number) }
            return TrackSound(rate: rate, pitch: sound["pitch"].number ?? 0, linked: sound["linked"].bool ?? false,
                              reverb: sound["reverb"].number ?? 0, eq: eq).normalized()
        }
        guard let speed = value["speed"].number else { return nil }
        return TrackSound(rate: speed).normalized()
    }

    private static func round(_ value: Double, _ per: Double) -> Double {
        (value * per).rounded() / per
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
