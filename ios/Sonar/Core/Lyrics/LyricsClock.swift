import Foundation

/// Чистые функции синхронизации текста (docs/LYRICS.md §3–5): порт `find.ts`, `progress.ts`, `offset.ts`
/// и пауз из `LyricsView.svelte`. Время `time` — секунды трека **уже со сдвигом** (`position + offset`).
enum LyricsClock {
    /// Нулевая длительность считается как 50 мс — иначе деление на ноль.
    static let minDuration = 0.05
    /// Слово длиннее — лёгкая пульсация (`pulse`).
    static let longWord = 1.2
    /// Вступление длиннее — сверху «• • •» до первой строки.
    static let introGap = 2.0
    /// Сдвиг текста на трек — не больше ±15 с.
    static let offsetMax = 15.0

    // MARK: текущая строка (find.ts)

    /// Индекс текущей строки: последняя с `start <= time`. До первой строки — nil.
    static func activeLine(_ lines: [LyricLine], at time: Double) -> Int? {
        activeLine(lines, at: time, previous: nil)
    }

    /// То же, но сначала смотрит рядом с прошлым индексом (±2) — обычный случай на каждом кадре,
    /// иначе бинарный поиск.
    static func activeLine(_ lines: [LyricLine], at time: Double, previous: Int?) -> Int? {
        guard !lines.isEmpty else { return nil }
        let prev = previous ?? -1
        for d in 0 ... 2 {
            for i in d == 0 ? [prev] : [prev + d, prev - d] where i >= -1 && i < lines.count && isActive(lines, i, time) {
                return i == -1 ? nil : i
            }
        }
        let found = binary(lines, time)
        return found == -1 ? nil : found
    }

    private static func binary(_ lines: [LyricLine], _ t: Double) -> Int {
        var lo = 0
        var hi = lines.count - 1
        var answer = -1
        while lo <= hi {
            let mid = (lo + hi) >> 1
            if lines[mid].start <= t {
                answer = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return answer
    }

    private static func isActive(_ lines: [LyricLine], _ i: Int, _ t: Double) -> Bool {
        if i == -1 { return t < lines[0].start }
        return lines[i].start <= t && (i + 1 >= lines.count || lines[i + 1].start > t)
    }

    // MARK: прокрутка к строке (follow.ts)

    /// Дальше стольких строк от прошлой текущей — уже не «следующая строка», а переход.
    static let smoothLines = 3

    /// Ехать ли к новой текущей строке плавно. Строка за строкой — плавно, а открыли плеер на середине
    /// трека, пришёл текст позже, перемотали далеко — сразу на место (иначе текст ползёт с самого верха).
    /// nil — до первой строки: вступление → первая строка плавно, вступление → 24-я сразу.
    static func scrollsSmoothly(from old: Int?, to new: Int) -> Bool {
        abs(new - (old ?? -1)) <= smoothLines
    }

    // MARK: паузы «• • •»

    /// Есть ли «• • •» вступления над первой строкой (первая строка позже 2 с).
    static func hasIntro(_ lines: [LyricLine]) -> Bool {
        (lines.first?.start ?? 0) > introGap
    }

    /// Сейчас пауза: вступление (до первой строки, если оно длиннее 2 с) или строка-проигрыш
    /// (пустая строка LRC). Там показываются «• • •».
    static func isGap(_ lines: [LyricLine], at time: Double) -> Bool {
        guard !lines.isEmpty else { return false }
        guard let i = activeLine(lines, at: time) else { return hasIntro(lines) }
        return lines[i].isPause
    }

    /// 0…1 для трёх точек паузы: вступление — от 0 до первой строки, проигрыш — по его строке.
    /// Не пауза — 0.
    static func gapProgress(_ lines: [LyricLine], at time: Double) -> Double {
        guard !lines.isEmpty else { return 0 }
        guard let i = activeLine(lines, at: time) else {
            return hasIntro(lines) ? progress(start: 0, duration: lines[0].start, at: time) : 0
        }
        let line = lines[i]
        return line.isPause ? progress(start: line.start, duration: line.duration, at: time) : 0
    }

    // MARK: прогресс (progress.ts)

    /// Прогресс отрезка 0…1 (LYRICS.md §4): до начала 0, после конца 1.
    static func progress(start: Double, duration: Double, at time: Double) -> Double {
        let d = max(duration, minDuration)
        if time >= start + d { return 1 }
        if time < start { return 0 }
        return min(1, max(0, (time - start) / d))
    }

    /// Прогресс строки целиком (режим «По строкам», строки без слов).
    static func lineProgress(_ line: LyricLine, at time: Double) -> Double {
        progress(start: line.start, duration: line.duration, at: time)
    }

    /// 0…1 на каждое слово строки. Нет пословного тайминга — слова строятся по длине, как в Windows
    /// (`LyricsMotion.synthWords`); пустая строка — пусто.
    static func wordProgress(_ line: LyricLine, at time: Double) -> [Double] {
        words(of: line).map { progress(start: $0.start, duration: $0.duration, at: time) }
    }

    /// Слова строки для караоке: настоящие, а где их нет — по длине слов.
    static func words(of line: LyricLine) -> [LyricWord] {
        line.words.isEmpty ? LyricsMotion.synthWords(line) : line.words
    }

    /// Пульсация длинного слова: k = sin(π·p)², масштаб 1 + 0.04k.
    static func pulse(_ p: Double) -> Double {
        let s = sin(Double.pi * p)
        return s * s
    }

    // MARK: сдвиг (offset.ts)

    /// Секунды −15…+15, три знака.
    static func clampOffset(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        let v = min(offsetMax, max(-offsetMax, seconds))
        let rounded = (v * 1000).rounded() / 1000
        return rounded == 0 ? 0 : rounded
    }

    static func offsetToMs(_ seconds: Double) -> Int { Int((clampOffset(seconds) * 1000).rounded()) }
    static func offsetFromMs(_ ms: Int?) -> Double { clampOffset(Double(ms ?? 0) / 1000) }

    /// «+0.250 с», «−1.000 с», «0.000 с».
    static func formatOffset(_ seconds: Double) -> String {
        let v = clampOffset(seconds)
        let sign = v > 0 ? "+" : v < 0 ? "−" : ""
        return "\(sign)\(String(format: "%.3f", abs(v))) с"
    }
}

/// Часы текста (LYRICS.md §2, порт `clock.ts`): не дёргаются от редких обновлений позиции, идут плавно
/// между ними, не откатываются назад между кадрами (кроме явной перемотки). `ts` — монотонное время
/// кадра в секундах (`CACurrentMediaTime()` / `TimelineView` `date.timeIntervalSinceReferenceDate`).
struct LyricsPlaybackClock: Sendable, Equatable {
    /// Расхождение больше — жёсткий перенос якоря, меньше — мягкая подстройка.
    static let hardSync = 0.35
    static let soft = 0.25

    enum Mode: Sendable { case running, raw }

    var anchorTime = 0.0
    var anchorTs = 0.0
    var rate = 1.0
    var last = 0.0
    var mode = Mode.raw
    /// Позиция плеера на последнем событии — им живёт режим `raw`.
    var raw = 0.0
    var duration = Double.infinity

    /// Секунды трека на момент `ts`, без монотонности.
    func now(_ ts: Double) -> Double {
        mode == .raw ? raw : anchorTime + (ts - anchorTs) * rate
    }

    private mutating func anchor(_ time: Double, _ ts: Double) {
        anchorTime = time
        anchorTs = ts
    }

    /// На каждом обновлении позиции плеера.
    mutating func sample(_ playerTime: Double, ts: Double) {
        raw = playerTime
        guard mode == .running else { return }
        let diff = playerTime - now(ts)
        if abs(diff) > Self.hardSync { anchor(playerTime, ts) } else { anchor(now(ts) + diff * Self.soft, ts) }
    }

    /// Играет: новый якорь, часы идут.
    mutating func play(_ playerTime: Double, ts: Double, rate: Double? = nil) {
        raw = playerTime
        if let rate { self.rate = rate }
        anchor(playerTime, ts)
        mode = .running
    }

    /// Пауза, буферизация: стоим на позиции плеера.
    mutating func hold(_ playerTime: Double) {
        raw = playerTime
        mode = .raw
    }

    /// Перемотка: стоим и разрешаем откат назад.
    mutating func seek(_ playerTime: Double) {
        hold(playerTime)
        last = 0
    }

    /// Новая скорость: новый якорь.
    mutating func setRate(_ rate: Double, playerTime: Double, ts: Double) {
        self.rate = rate
        raw = playerTime
        if mode == .running { anchor(playerTime, ts) }
    }

    /// Время для кадра: монотонно и в пределах трека.
    mutating func read(_ ts: Double) -> Double {
        var t = max(now(ts), last)
        t = min(max(t, 0), duration)
        last = t
        return t
    }
}
