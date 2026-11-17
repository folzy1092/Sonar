import XCTest
@testable import Sonar

/// Тема под обложку — те же правила, что `windows/src/theme/palette.ts`.
final class PaletteTests: XCTestCase {
    /// Картинка из одного цвета, RGBA.
    private func pixels(_ c: RGB, count: Int = 64) -> [UInt8] {
        (0 ..< count).flatMap { _ in [UInt8(c.r), UInt8(c.g), UInt8(c.b), 255] }
    }

    func testGrayCoverHasNoAccent() {
        XCTAssertNil(Palette.pickAccent(pixels(RGB(128, 128, 128))))
        XCTAssertNil(Palette.pickAccent(pixels(RGB(5, 5, 5))))
        XCTAssertNil(Palette.pickAccent(pixels(RGB(250, 250, 250))))
    }

    func testSaturatedClusterWins() {
        // 3/4 серого и 1/4 красного — акцент красный
        let px = pixels(RGB(120, 120, 120), count: 48) + pixels(RGB(220, 30, 40), count: 16)
        let accent = Palette.pickAccent(px)
        XCTAssertEqual(accent, RGB(220, 30, 40))
    }

    func testTransparentPixelsIgnored() {
        var px = pixels(RGB(30, 200, 90))
        for i in stride(from: 3, to: px.count, by: 8) { px[i] = 0 }
        XCTAssertEqual(Palette.pickAccent(px), RGB(30, 200, 90))
    }

    func testOklchRoundTrip() {
        for c in [RGB(255, 0, 0), RGB(0, 128, 255), RGB(250, 190, 0), RGB(20, 20, 24)] {
            let back = Palette.rgb(Palette.oklch(c))
            XCTAssertEqual(back.r, c.r, accuracy: 1)
            XCTAssertEqual(back.g, c.g, accuracy: 1)
            XCTAssertEqual(back.b, c.b, accuracy: 1)
        }
    }

    func testMonoThemeWithoutCover() {
        let t = Palette.theme(from: nil)
        XCTAssertTrue(t.mono)
        // акцент почти белый, фон почти чёрный, серые
        XCTAssertGreaterThan(t.accent.r, 230)
        XCTAssertEqual(t.accent.r, t.accent.b, accuracy: 1)
        XCTAssertLessThan(t.bg.r, 30)
        XCTAssertEqual(t.bg.r, t.bg.b, accuracy: 1)
    }

    func testColoredThemeKeepsHue() {
        let pink = RGB(245, 140, 160)
        let t = Palette.theme(from: pink)
        XCTAssertFalse(t.mono)
        let accentHue = Palette.oklch(t.accent).h
        XCTAssertEqual(accentHue, Palette.oklch(pink).h, accuracy: 4)
        // фон тёмный, но подкрашен тем же оттенком
        let bg = Palette.oklch(t.bg)
        XCTAssertLessThan(bg.l, 0.2)
        XCTAssertGreaterThan(bg.c, 0.005)
        // текст на акценте тёмный — акцент светлый
        XCTAssertLessThan(Palette.oklch(t.ink).l, 0.3)
        XCTAssertGreaterThan(Palette.oklch(t.accent).l, 0.7)
    }

    func testOutOfGamutIsFitted() {
        let fitted = Palette.fitGamut(Lch(l: 0.8, c: 0.4, h: 140))
        XCTAssertLessThan(fitted.c, 0.4)
        let rgb = Palette.rgb(Lch(l: 0.8, c: 0.4, h: 140))
        for v in [rgb.r, rgb.g, rgb.b] {
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 255)
        }
    }
}
