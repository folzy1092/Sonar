import XCTest
@testable import Sonar

/// Ядро текста: часы, текущая строка, прогресс, паузы, сдвиг (порт `core.test.ts`) и формулы вида
/// (порт `motion.test.ts`), аннотации (`annotations.test.ts`).
final class LyricsCoreTests: XCTestCase {
    private func line(_ start: Double, _ duration: Double = 1, _ text: String? = nil, id: Int = 0) -> LyricLine {
        LyricLine(id: id, start: start, end: start + duration, text: text ?? String(start), words: [])
    }

    // MARK: часы (clock.ts)

    func testClockRunsSmoothlyBetweenRareUpdates() {
        var c = LyricsPlaybackClock()
        c.play(10, ts: 0)
        XCTAssertEqual(c.read(0.25), 10.25, accuracy: 1e-9)
        c.sample(10.5, ts: 0.5) // обновление раз в 500 мс — совпадает
        XCTAssertEqual(c.read(0.75), 10.75, accuracy: 1e-9)
    }

    func testClockSoftAndHardSync() {
        var c = LyricsPlaybackClock()
        c.play(0, ts: 0)
        c.sample(1.2, ts: 1) // часы 1.0, звук 1.2
        XCTAssertEqual(c.now(1), 1.05, accuracy: 1e-9)
        var h = LyricsPlaybackClock()
        h.play(0, ts: 0)
        h.sample(5, ts: 1)
        XCTAssertEqual(h.now(1), 5, accuracy: 1e-9)
    }

    func testClockPauseAndPlay() {
        var c = LyricsPlaybackClock()
        c.play(3, ts: 0)
        c.hold(3.4)
        XCTAssertEqual(c.read(10), 3.4, accuracy: 1e-9)
        c.play(3.4, ts: 10)
        XCTAssertEqual(c.read(11), 4.4, accuracy: 1e-9)
    }

    func testClockMonotonicButSeekBackAllowed() {
        var c = LyricsPlaybackClock()
        c.play(10, ts: 0)
        XCTAssertEqual(c.read(1), 11, accuracy: 1e-9)
        c.sample(10.9, ts: 1) // звук чуть позади — назад не прыгаем
        XCTAssertGreaterThanOrEqual(c.read(1), 11)
        c.seek(2)
        XCTAssertEqual(c.read(1), 2, accuracy: 1e-9)
    }

    func testClockSeekForwardRatesAndBounds() {
        var c = LyricsPlaybackClock()
        c.play(1, ts: 0)
        c.seek(60)
        c.play(60, ts: 0.1)
        XCTAssertEqual(c.read(0.6), 60.5, accuracy: 1e-9)

        var r = LyricsPlaybackClock()
        r.play(0, ts: 0, rate: 0.5)
        XCTAssertEqual(r.read(1), 0.5, accuracy: 1e-9)
        r.setRate(2, playerTime: 0.5, ts: 1)
        XCTAssertEqual(r.read(2), 2.5, accuracy: 1e-9)

        var b = LyricsPlaybackClock()
        b.duration = 3
        b.play(2.9, ts: 0)
        XCTAssertEqual(b.read(5), 3)
        b.seek(-1)
        XCTAssertEqual(b.read(0), 0)
    }

    // MARK: текущая строка (find.ts)

    func testActiveLine() {
        let lines = [line(1), line(3), line(5), line(8)]
        XCTAssertNil(LyricsClock.activeLine(lines, at: 0.5))
        XCTAssertEqual(LyricsClock.activeLine(lines, at: 100, previous: 3), 3)
        XCTAssertEqual(LyricsClock.activeLine(lines, at: 3.2, previous: 0), 1)
        XCTAssertEqual(LyricsClock.activeLine(lines, at: 8.1, previous: 0), 3)
        XCTAssertEqual(LyricsClock.activeLine(lines, at: 1.5, previous: 3), 0)
        XCTAssertEqual(LyricsClock.activeLine(lines, at: 5), 2)
        XCTAssertNil(LyricsClock.activeLine([], at: 5))
    }

    // MARK: прогресс (progress.ts)

    func testProgress() {
        XCTAssertEqual(LyricsClock.progress(start: 1, duration: 2, at: 0.5), 0)
        XCTAssertEqual(LyricsClock.progress(start: 1, duration: 2, at: 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LyricsClock.progress(start: 1, duration: 2, at: 3), 1)
        // слово нулевой длительности — 50 мс
        XCTAssertEqual(LyricsClock.progress(start: 1, duration: 0, at: 1.025), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LyricsClock.progress(start: 1, duration: 0, at: 1.06), 1)
        XCTAssertEqual(LyricsClock.pulse(0.5), 1, accuracy: 1e-9)
    }

    func testWordProgressRealAndSynthesized() {
        let words = [LyricWord(start: 1, end: 1.5, text: "Hello"), LyricWord(start: 1.5, end: 2.4, text: "world", spaceAfter: false)]
        let real = LyricLine(id: 0, start: 1, end: 3, text: "Hello world", words: words)
        let p = LyricsClock.wordProgress(real, at: 1.95)
        XCTAssertEqual(p[0], 1)
        XCTAssertEqual(p[1], 0.5, accuracy: 1e-9)

        // без слов — делится по длине слов на длительность строки (как synthWords в Windows)
        let plain = LyricLine(id: 0, start: 10, end: 14, text: "раз два три", words: [])
        let synth = LyricsClock.wordProgress(plain, at: 12)
        XCTAssertEqual(synth.count, 3)
        XCTAssertEqual(synth[0], 1)
        XCTAssertEqual(synth[1], 0.5, accuracy: 1e-9) // слова равной длины: 10…11.33…12.67…14
        XCTAssertEqual(synth[2], 0)
        XCTAssertEqual(LyricsClock.wordProgress(LyricLine(id: 0, start: 1, end: 2, text: "", words: []), at: 1.5), [])
        XCTAssertEqual(LyricsClock.lineProgress(plain, at: 11), 0.25, accuracy: 1e-9)
    }

    // MARK: паузы «• • •»

    func testGapsIntroAndInstrumental() {
        let lines = [line(5, 2, "раз"), line(7, 4, ""), line(11, 2, "два")]
        XCTAssertTrue(LyricsClock.isGap(lines, at: 1)) // вступление 5 с
        XCTAssertEqual(LyricsClock.gapProgress(lines, at: 2.5), 0.5, accuracy: 1e-9)
        XCTAssertFalse(LyricsClock.isGap(lines, at: 6))
        XCTAssertEqual(LyricsClock.gapProgress(lines, at: 6), 0)
        XCTAssertTrue(LyricsClock.isGap(lines, at: 8)) // проигрыш — пустая строка
        XCTAssertEqual(LyricsClock.gapProgress(lines, at: 9), 0.5, accuracy: 1e-9)
        XCTAssertFalse(LyricsClock.isGap(lines, at: 12))
        // вступление короче 2 с — без точек
        XCTAssertFalse(LyricsClock.isGap([line(1.5, 2, "раз")], at: 1))
        XCTAssertFalse(LyricsClock.isGap([], at: 1))
        XCTAssertEqual(LyricsMotion.gapDots(progress: 0.5), [1, 0.5, 0.25])
        XCTAssertEqual(LyricsMotion.gapDots(progress: 0), [0.25, 0.25, 0.25])
    }

    // MARK: сдвиг (offset.ts)

    func testOffset() {
        XCTAssertEqual(LyricsClock.clampOffset(20), 15)
        XCTAssertEqual(LyricsClock.clampOffset(-16), -15)
        XCTAssertEqual(LyricsClock.clampOffset(0.12345), 0.123)
        XCTAssertEqual(LyricsClock.offsetToMs(-0.25), -250)
        XCTAssertEqual(LyricsClock.offsetFromMs(nil), 0)
        XCTAssertEqual(LyricsClock.formatOffset(0.25), "+0.250 с")
        XCTAssertEqual(LyricsClock.formatOffset(-1), "−1.000 с")
        XCTAssertEqual(LyricsClock.formatOffset(0), "0.000 с")
        XCTAssertEqual(LyricsClock.clampOffset(.nan), 0)
    }

    // MARK: вид строк и слов (motion.ts)

    func testLineOpacity() {
        XCTAssertEqual(LyricsMotion.lineOpacity(0, synced: true, isBg: false), 1)
        XCTAssertEqual(LyricsMotion.lineOpacity(1, synced: true, isBg: false), 0.58)
        XCTAssertEqual(LyricsMotion.lineOpacity(-1, synced: true, isBg: false), 0.42)
        XCTAssertEqual(LyricsMotion.lineOpacity(2, synced: true, isBg: false), 0.4)
        XCTAssertEqual(LyricsMotion.lineOpacity(-9, synced: true, isBg: false), 0.16)
        XCTAssertEqual(LyricsMotion.lineOpacity(3, synced: false, isBg: false), 0.85)
        XCTAssertEqual(LyricsMotion.lineOpacity(0, synced: true, isBg: true), 0.88)
        XCTAssertEqual(LyricsMotion.lineOpacity(1, synced: true, isBg: true), 0.8 * 0.58, accuracy: 1e-9)
        XCTAssertEqual(LyricsMotion.lineOpacity(4, synced: true, isBg: false), 0.23, accuracy: 1e-9)
    }

    func testLineLook() {
        let plain = LyricsMotion.lineLook(style: .normal, animation: .normal, delta: 2, synced: true)
        XCTAssertEqual(plain.scale, 1)
        XCTAssertEqual(plain.blur, 0)
        XCTAssertEqual(plain.dy, 0)
        XCTAssertEqual(plain.duration, 0.868, accuracy: 1e-9)

        // «Размытие» не размывает текущую строку
        XCTAssertEqual(LyricsMotion.lineLook(style: .blur, animation: .normal, delta: 0, synced: true).blur, 0)
        XCTAssertEqual(LyricsMotion.lineLook(style: .blur, animation: .normal, delta: 1, synced: true).blur, 2.5)
        XCTAssertEqual(LyricsMotion.lineLook(style: .blur, animation: .normal, delta: 6, synced: true).blur, 7)
        XCTAssertEqual(LyricsMotion.lineLook(style: .blur, animation: .normal, delta: 0, synced: true).scale, 1.05)
        XCTAssertEqual(LyricsMotion.lineLook(style: .blur, animation: .normal, delta: 0, synced: true).duration, 0.7, accuracy: 1e-9)

        let cinema = LyricsMotion.lineLook(style: .cinema, animation: .fade, delta: 1, synced: true)
        XCTAssertEqual(cinema.letterSpacing, 0.02)
        XCTAssertEqual(cinema.scale, 0.95)

        let shift = LyricsMotion.lineLook(style: .shift, animation: .normal, delta: 0, synced: true)
        XCTAssertEqual(shift.dx, 14)
        XCTAssertEqual(shift.scale, 1.04)

        let flip = LyricsMotion.lineLook(style: .normal, animation: .flip3d, delta: 1, synced: true)
        XCTAssertEqual(flip.rotateX, 10)
        XCTAssertEqual(flip.dz, -4)
        XCTAssertEqual(flip.dy, 3)
        XCTAssertEqual(flip.scale, 0.98)
        XCTAssertEqual(flip.duration, 1.092, accuracy: 1e-9)

        let bounce = LyricsMotion.lineLook(style: .scale, animation: .bounce, delta: 0, synced: true)
        XCTAssertTrue(bounce.bounce)
        XCTAssertEqual(bounce.scale, 1.08) // у «Масштаба» масштаб — только от стиля

        let blurAnim = LyricsMotion.lineLook(style: .normal, animation: .blur, delta: -2, synced: true)
        XCTAssertEqual(blurAnim.blur, 5.5)
        XCTAssertEqual(blurAnim.dy, -3) // side(3, -3) перекрывает ty анимации, как в TS

        // «Лесенка» — строки как в «Обычной»
        XCTAssertEqual(LyricsMotion.lineLook(style: .scale, animation: .ladder, delta: 2, synced: true),
                       LyricsMotion.lineLook(style: .scale, animation: .normal, delta: 2, synced: true))

        // без движения — только прозрачность
        let reduced = LyricsMotion.lineLook(style: .scale, animation: .flip3d, delta: 1, synced: true, reduced: true)
        XCTAssertEqual(reduced.scale, 1)
        XCTAssertEqual(reduced.blur, 0)
        XCTAssertEqual(reduced.rotateX, 0)
        XCTAssertEqual(reduced.opacity, 0.58)
        XCTAssertEqual(reduced.duration, 0.42)
    }

    func testWordAndHoldLook() {
        XCTAssertEqual(LyricsMotion.wordLook(animation: .fade, progress: 0, past: false, current: false).opacity, 0.52)
        XCTAssertEqual(LyricsMotion.wordLook(animation: .fade, progress: 1, past: true, current: false).opacity, 1)
        XCTAssertEqual(LyricsMotion.wordLook(animation: .fade, progress: 0.5, past: false, current: true).opacity, 0.75)
        XCTAssertTrue(LyricsMotion.wordLook(animation: .normal, progress: 0.5, past: false, current: true).usesFill)
        XCTAssertEqual(LyricsMotion.wordLook(animation: .blur, progress: 0.5, past: false, current: true).blur, 1.75, accuracy: 1e-9)
        XCTAssertEqual(LyricsMotion.wordLook(animation: .blur, progress: 0.97, past: false, current: true).blur, 0)
        XCTAssertEqual(LyricsMotion.wordLook(animation: .zoom, progress: 0.5, past: false, current: true).scale, 0.94, accuracy: 1e-9)
        XCTAssertEqual(LyricsMotion.wordLook(animation: .flip3d, progress: 0, past: false, current: false).rotateX, 45)
        XCTAssertEqual(LyricsMotion.holdLook(animation: .zoom, progress: 0.5, duration: 2, current: true).scale, 1.055, accuracy: 1e-9)
        XCTAssertEqual(LyricsMotion.holdLook(animation: .zoom, progress: 0.5, duration: 1, current: true), .none)
        XCTAssertEqual(LyricsMotion.holdLook(animation: .normal, progress: 0.5, duration: 2, current: true).brightness, 1.1, accuracy: 1e-9)
        let fill = LyricsMotion.fill(progress: 1)
        XCTAssertEqual(fill.solid, 1, accuracy: 1e-9)
    }

    func testSynthWords() {
        let w = LyricsMotion.synthWords(LyricLine(id: 0, start: 10, end: 14, text: "раз два три", words: []))
        XCTAssertEqual(w.map(\.text), ["раз", "два", "три"])
        XCTAssertEqual(w[0].start, 10)
        XCTAssertEqual(w[2].end, 14, accuracy: 1e-9)
        XCTAssertFalse(w[2].spaceAfter)
        XCTAssertTrue(w[0].spaceAfter)
        // строка без длительности — по длине текста, не меньше 2,5 с
        let long = LyricsMotion.synthWords(LyricLine(id: 0, start: 0, end: 0, text: "a b", words: []))
        XCTAssertEqual(long.last?.end ?? 0, 2.5, accuracy: 1e-9)
    }

    func testScrollAndMagnet() {
        XCTAssertEqual(LyricsMotion.glideDuration(distance: 0), 0.75, accuracy: 1e-9)
        XCTAssertEqual(LyricsMotion.glideDuration(distance: 5000), 1.3, accuracy: 1e-9)
        XCTAssertEqual(LyricsMotion.glideEase(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LyricsMotion.glideEase(1), 1, accuracy: 1e-9)
        XCTAssertTrue(LyricsMotion.usesMagnet(animation: .ladder, from: 2, to: 3, reduced: false))
        XCTAssertFalse(LyricsMotion.usesMagnet(animation: .ladder, from: 2, to: 9, reduced: false))
        XCTAssertFalse(LyricsMotion.usesMagnet(animation: .ladder, from: 3, to: 2, reduced: false))
        XCTAssertFalse(LyricsMotion.usesMagnet(animation: .normal, from: 2, to: 3, reduced: false))
        XCTAssertFalse(LyricsMotion.usesMagnet(animation: .ladder, from: 2, to: 3, reduced: true))
        XCTAssertEqual(LyricsMotion.magnetOrder(line: 9, previous: 1), 6)
        XCTAssertEqual(LyricsMotion.magnetDelay(order: 2), 0.09, accuracy: 1e-9)
        XCTAssertEqual(LyricsMotion.magnetDuration(order: 0), 0.78, accuracy: 1e-9)
        XCTAssertEqual(LyricsMotion.magnetDuration(order: 6), 0.54, accuracy: 1e-9)
    }

    func testSettingsEnums() {
        XCTAssertEqual(LyricsSize.l.points, 32)
        XCTAssertEqual(LyricsSize.m.points, 25.6, accuracy: 1e-6)
        XCTAssertEqual(LyricsSize(rawValue: "XL"), .xl)
        XCTAssertEqual(LyricsAnimation.allCases.count, 10)
        XCTAssertEqual(LyricsTextStyle.cinema.title, "Кино")
        XCTAssertEqual(LyricsAnimation.zoom.title, "Глубина")
    }

    // MARK: аннотации (annotations.ts)

    func testAnnotationsMapping() {
        XCTAssertEqual(LyricsAnnotations.likeness("Жить этот момент, вокруг меня леса (Леса)", "жить этот момент вокруг меня леса"), 1)
        XCTAssertEqual(LyricsAnnotations.likeness("Трясутся мои руки", "Гуляю по ветру"), 0)
        let lines = ["Жить этот момент, вокруг меня леса (леса)", "Трясутся мои руки, трещит голова (а-а)",
                     "Давай оставим это на старых местах", "Гуляю по ветру"]
        let note = LyricsAnnotation(lines: ["Жить этот момент, вокруг меня леса (Леса)", "Трясутся мои руки, трещит голова (А-а)",
                                            "Давай оставим это на старых местах"], body: "Вся строфа", reviewed: false)
        let map = LyricsAnnotations.map(lines, [note])
        XCTAssertEqual(map.keys.sorted(), [0])
        XCTAssertNil(map[3])
    }
}
