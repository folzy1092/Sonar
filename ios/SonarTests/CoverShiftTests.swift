import XCTest
@testable import Sonar

/// Поверхности уходят за обложкой — те же правила, что `windows/src/theme/cover-shift.test.ts`.
final class CoverShiftTests: XCTestCase {
    private let covers = [RGB(220, 30, 40), RGB(30, 120, 220), RGB(250, 190, 0), RGB(40, 180, 90), RGB(200, 60, 200)]
    private let darkCover = 0.15
    private let lightCover = 0.95

    private func pixels(_ c: RGB, count: Int = 64) -> [UInt8] {
        (0 ..< count).flatMap { _ in [UInt8(c.r), UInt8(c.g), UInt8(c.b), 255] }
    }

    private func surfaces(_ t: ThemeTokens) -> [RGB] { [t.bg, t.s0, t.s1, t.s2, t.s3] }

    private func lightness(_ c: RGB) -> Double { Palette.oklch(c).l }

    // MARK: Светлота обложки и сила

    func testCoverLightnessFollowsPixels() {
        XCTAssertLessThan(Palette.coverLightness(pixels(RGB(10, 10, 12))), 0.25)
        XCTAssertGreaterThan(Palette.coverLightness(pixels(RGB(245, 245, 240))), 0.9)
        XCTAssertEqual(Palette.coverLightness([]), Palette.pivotLightness)
    }

    func testTransparentPixelsDoNotCount() {
        let px = pixels(RGB(250, 250, 250), count: 8).enumerated().map { $0.offset % 4 == 3 ? UInt8(0) : $0.element }
        XCTAssertEqual(Palette.coverLightness(px + pixels(RGB(10, 10, 10))), Palette.coverLightness(pixels(RGB(10, 10, 10))), accuracy: 1e-9)
    }

    func testBiasDirectionAndLimit() {
        for strength in CoverStrength.allCases {
            XCTAssertLessThan(Palette.coverBias(CoverShift(strength: strength, lightness: darkCover)), 0)
            XCTAssertGreaterThan(Palette.coverBias(CoverShift(strength: strength, lightness: lightCover)), 0)
            XCTAssertEqual(Palette.coverBias(CoverShift(strength: strength, lightness: Palette.pivotLightness)), 0, accuracy: 1e-9)
            for l in stride(from: 0.0, through: 1.0, by: 0.05) {
                XCTAssertLessThanOrEqual(abs(Palette.coverBias(CoverShift(strength: strength, lightness: l))), Palette.maxCoverShift + 1e-9)
            }
        }
    }

    func testStrengthOrderAndMediumRange() {
        let bias = { (s: CoverStrength) in abs(Palette.coverBias(CoverShift(strength: s, lightness: 0))) }
        XCTAssertLessThan(bias(.weak), bias(.medium))
        XCTAssertLessThan(bias(.medium), bias(.strong))
        XCTAssertGreaterThanOrEqual(bias(.medium), 0.1)
        XCTAssertLessThanOrEqual(bias(.medium), 0.15)
    }

    func testStrengthFromSetting() {
        XCTAssertEqual(CoverStrength(setting: "weak"), .weak)
        XCTAssertEqual(CoverStrength(setting: "strong"), .strong)
        XCTAssertEqual(CoverStrength(setting: ""), .medium)
        XCTAssertEqual(CoverStrength(setting: "max"), .medium)
    }

    func testShiftLightnessBounds() {
        XCTAssertEqual(Palette.shiftLightness(0.2, f: 0, light: false), 0.2)
        XCTAssertLessThan(Palette.shiftLightness(0.2, f: -0.2, light: false), 0.2)
        XCTAssertGreaterThanOrEqual(Palette.shiftLightness(0.05, f: -0.2, light: false), 0.075)
        XCTAssertGreaterThan(Palette.shiftLightness(0.95, f: 0.2, light: true), 0.95)
        XCTAssertLessThanOrEqual(Palette.shiftLightness(0.99, f: 0.2, light: true), 0.992)
    }

    // MARK: Тема

    func testNoShiftKeepsTheme() {
        for surface in Surface.allCases {
            for light in [false, true] {
                let plain = Palette.theme(from: covers[0], surface: surface, light: light)
                let none = Palette.theme(from: covers[0], surface: surface, light: light, cover: nil)
                XCTAssertEqual(plain, none)
                XCTAssertEqual(plain.shift, 0)
            }
        }
    }

    func testDarkCoverDarkensLightCoverLightens() {
        for surface in Surface.allCases {
            for light in [false, true] {
                let base = Palette.theme(from: covers[1], surface: surface, light: light)
                let dark = Palette.theme(from: covers[1], surface: surface, light: light,
                                         cover: CoverShift(strength: .medium, lightness: darkCover))
                let bright = Palette.theme(from: covers[1], surface: surface, light: light,
                                           cover: CoverShift(strength: .medium, lightness: lightCover))
                for (b, d, l) in zip(zip(surfaces(base), surfaces(dark)), surfaces(bright)).map({ ($0.0, $0.1, $1) }) {
                    XCTAssertLessThanOrEqual(lightness(d), lightness(b) + 0.002, "\(surface) light=\(light)")
                    XCTAssertGreaterThanOrEqual(lightness(l), lightness(b) - 0.002, "\(surface) light=\(light)")
                }
                XCTAssertLessThan(dark.shift, 0)
                XCTAssertGreaterThan(bright.shift, 0)
            }
        }
    }

    func testDarkThemeNeverBlack() {
        for surface in Surface.allCases {
            let t = Palette.theme(from: covers[2], surface: surface, light: false,
                                  cover: CoverShift(strength: .strong, lightness: 0))
            XCTAssertGreaterThan(lightness(t.bg), 0.07, "\(surface)")
        }
    }

    func testTintKeepsCoverHueButGrayStaysGray() {
        let tinted = Palette.theme(from: covers[0], surface: .monolith, light: false,
                                   cover: CoverShift(strength: .medium, lightness: darkCover))
        XCTAssertGreaterThan(Palette.oklch(tinted.bg).c, 0.003)
        let gray = Palette.theme(from: nil, surface: .echo, light: false,
                                 cover: CoverShift(strength: .strong, lightness: darkCover))
        XCTAssertLessThan(Palette.oklch(gray.bg).c, 0.003)
    }

    /// Обложки, на которых тема и без сдвига держит AA целиком (как `COVERS` в тесте ПК).
    private let readableCovers: [RGB?] = [RGB(28, 36, 104), RGB(255, 24, 178), RGB(26, 22, 20),
                                          RGB(250, 222, 32), RGB(246, 246, 244), RGB(128, 128, 128), nil]

    private func eachCase(_ accents: [RGB?], _ check: (ThemeTokens, ThemeTokens, String) -> Void) {
        for surface in Surface.allCases {
            for light in [false, true] {
                for accent in accents {
                    for strength in CoverStrength.allCases {
                        let base = Palette.theme(from: accent, surface: surface, light: light,
                                                 cover: CoverShift(strength: strength, lightness: Palette.pivotLightness))
                        for l in [0.0, darkCover, 0.5, 0.8, lightCover, 1.0] {
                            let t = Palette.theme(from: accent, surface: surface, light: light,
                                                  cover: CoverShift(strength: strength, lightness: l))
                            check(t, base, "\(surface) light=\(light) \(String(describing: accent)) \(strength) L=\(l)")
                        }
                    }
                }
            }
        }
    }

    func testTextStaysReadableEverywhere() {
        eachCase(readableCovers) { t, _, tag in
            XCTAssertTrue(Palette.readable(t), tag)
            XCTAssertGreaterThanOrEqual(Palette.contrast(t.t2, t.s3), 4.5, tag)
            XCTAssertLessThanOrEqual(abs(t.shift), Palette.maxCoverShift + 1e-9, tag)
        }
    }

    func testShiftNeverWorsensContrast() {
        eachCase(covers.map { Optional($0) }) { t, base, tag in
            XCTAssertEqual(base.shift, 0, tag)
            XCTAssertTrue(Palette.keepsContrast(t, base: base), tag)
            XCTAssertLessThanOrEqual(abs(t.shift), Palette.maxCoverShift + 1e-9, tag)
        }
    }

    func testUntouchedPairDoesNotDisableShift() {
        // зелёная обложка, светлая «Грань»: акцент / ink ниже 4.5 и без сдвига — поверхности всё равно идут за обложкой
        let green = RGB(40, 180, 90)
        XCTAssertFalse(Palette.readable(Palette.theme(from: green, surface: .edge, light: true)))
        let t = Palette.theme(from: green, surface: .edge, light: true, cover: CoverShift(strength: .medium, lightness: darkCover))
        XCTAssertLessThan(t.shift, 0)
    }

    // MARK: Настройки

    func testLookThemeAppliesStrengthOnlyUnderCover() {
        let accent = covers[1]
        let onCover = LookInputs(mode: .dark, coverTheme: true, surface: .echo, coverStrength: .strong)
        let shifted = LookTheme.tokens(onCover, coverAccent: accent, coverLightness: darkCover, systemDark: true)
        XCTAssertLessThan(shifted.shift, 0)
        XCTAssertEqual(LookTheme.tokens(onCover, coverAccent: accent, systemDark: true).shift, 0)

        let preset = LookInputs(mode: .dark, coverTheme: false, preset: "mint", surface: .echo, coverStrength: .strong)
        XCTAssertEqual(LookTheme.tokens(preset, coverAccent: accent, coverLightness: darkCover, systemDark: true).shift, 0)
    }
}
