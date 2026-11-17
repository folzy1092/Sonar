import XCTest
@testable import Sonar

/// Интерфейс → Вид: поверхности и светлые формулы (`palette.ts` `SURFACES` / `SURFACES_LIGHT`), готовые
/// темы, выбор исходного цвета, стили, вкладки и локальный профиль.
final class LookThemeTests: XCTestCase {
    private let pink = RGB(245, 140, 160)

    func testDefaultEchoUnchanged() {
        // прежний вызов без поверхности — «Эхо» тёмной темы, те же значения, что до стилей
        let a = Palette.theme(from: pink)
        let b = Palette.theme(from: pink, surface: .echo, light: false)
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.light)
        XCTAssertEqual(a.softAlpha, 0.22)
    }

    func testEverySurfaceHasBothFormulas() {
        for surface in Surface.allCases {
            XCTAssertNotNil(Palette.surfaces[surface])
            XCTAssertNotNil(Palette.surfacesLight[surface])
        }
    }

    func testLightThemeIsLight() {
        for surface in Surface.allCases {
            let t = Palette.theme(from: pink, surface: surface, light: true)
            XCTAssertTrue(t.light)
            let bg = Palette.oklch(t.bg).l
            let text = Palette.oklch(t.text).l
            XCTAssertGreaterThan(bg, 0.94, "\(surface)")
            XCTAssertLessThan(text, 0.25, "\(surface)")
            // поверхности темнее фона, по порядку
            XCTAssertLessThan(Palette.oklch(t.s1).l, bg)
            XCTAssertLessThan(Palette.oklch(t.s2).l, Palette.oklch(t.s1).l)
            XCTAssertLessThan(Palette.oklch(t.s3).l, Palette.oklch(t.s2).l)
            // акцент темнее, текст на нём светлый
            XCTAssertLessThan(Palette.oklch(t.accent).l, 0.6)
            XCTAssertGreaterThan(Palette.oklch(t.ink).l, 0.95)
        }
    }

    func testLightMonoAccentIsDark() {
        let t = Palette.theme(from: nil, surface: .echo, light: true)
        XCTAssertTrue(t.mono)
        XCTAssertLessThan(Palette.oklch(t.accent).l, 0.3)
        XCTAssertEqual(t.softAlpha, 0.08)
    }

    func testMonolithKeepsSurfacesGray() {
        let t = Palette.theme(from: pink, surface: .monolith)
        for c in [t.bg, t.s1, t.s2, t.s3, t.text, t.t2] {
            XCTAssertEqual(c.r, c.g, accuracy: 1)
            XCTAssertEqual(c.g, c.b, accuracy: 1)
        }
        // цвет обложки — в акценте и свечении
        XCTAssertGreaterThan(Palette.oklch(t.accent).c, 0.05)
        XCTAssertGreaterThan(Palette.oklch(t.glow).c, 0.05)
        // текст на акценте — серый тёмный
        XCTAssertLessThan(Palette.oklch(t.ink).l, 0.2)
    }

    func testSignalTrackIsTinted() {
        let t = Palette.theme(from: pink, surface: .signal)
        XCTAssertNotEqual(t.track, t.s3)
        XCTAssertEqual(Palette.theme(from: pink, surface: .echo).track, Palette.theme(from: pink, surface: .echo).s3)
    }

    func testPresetsMatchWindows() {
        let ids = ThemePreset.all.map(\.id)
        XCTAssertEqual(ids, ["neutral", "amoled", "crimson", "nord", "sky", "mint", "violet", "blossom", "sakura",
                             "terminal", "aqua", "sunset", "slate"])
        XCTAssertEqual(ThemePreset.named("sky").accent, RGB(76, 154, 255))
        XCTAssertEqual(ThemePreset.named("нет такой").id, "neutral")
        XCTAssertTrue(ThemePreset.named("amoled").black)
    }

    func testCoverThemeUsesCoverAccent() {
        let inputs = LookInputs(mode: .dark, coverTheme: true, preset: "sky", surface: .echo)
        let t = LookTheme.tokens(inputs, coverAccent: pink, systemDark: true)
        XCTAssertEqual(t, Palette.theme(from: pink, surface: .echo))
        // нет обложки — монохром, готовая тема не подмешивается
        XCTAssertTrue(LookTheme.tokens(inputs, coverAccent: nil, systemDark: true).mono)
    }

    func testPresetIgnoresCover() {
        let inputs = LookInputs(mode: .dark, coverTheme: false, preset: "mint", surface: .echo)
        let t = LookTheme.tokens(inputs, coverAccent: pink, systemDark: true)
        XCTAssertEqual(t, Palette.theme(from: RGB(62, 207, 142), surface: .echo))
    }

    func testAmoledOnlyInDark() {
        let dark = LookTheme.tokens(LookInputs(mode: .dark, coverTheme: false, preset: "amoled"), coverAccent: nil, systemDark: true)
        XCTAssertEqual(dark.bg, RGB(0, 0, 0))
        XCTAssertEqual(dark.s3, RGB(24, 24, 27))
        let light = LookTheme.tokens(LookInputs(mode: .light, coverTheme: false, preset: "amoled"), coverAccent: nil, systemDark: true)
        XCTAssertGreaterThan(light.bg.r, 240)
        // «Под трек» включён — AMOLED не действует
        let cover = LookTheme.tokens(LookInputs(mode: .dark, coverTheme: true, preset: "amoled"), coverAccent: nil, systemDark: true)
        XCTAssertNotEqual(cover.bg, RGB(0, 0, 0))
    }

    func testSystemModeFollowsPhone() {
        let inputs = LookInputs(mode: .system, coverTheme: true, preset: "neutral", surface: .monolith)
        XCTAssertTrue(LookTheme.tokens(inputs, coverAccent: nil, systemDark: false).light)
        XCTAssertFalse(LookTheme.tokens(inputs, coverAccent: nil, systemDark: true).light)
        XCTAssertFalse(AppearanceMode.dark.isLight(systemDark: false))
        XCTAssertTrue(AppearanceMode.light.isLight(systemDark: true))
    }

    func testSwatchWithoutColor() {
        let neutral = LookTheme.swatch(nil, surface: .echo, light: false)
        XCTAssertEqual(neutral.accent, RGB(245, 245, 246))
        XCTAssertEqual(LookTheme.swatch(nil, black: true, surface: .echo, light: false).bg, RGB(0, 0, 0))
        let sky = LookTheme.swatch(RGB(76, 154, 255), surface: .echo, light: false)
        XCTAssertEqual(sky.bg, Palette.theme(from: RGB(76, 154, 255), surface: .echo).bg)
    }

    func testStylesMatchWindows() {
        XCTAssertEqual(StylePreset.all.map(\.id), ["sonar", "echo", "signal", "edge", "tactile", "monolith"])
        XCTAssertEqual(StylePreset.named("sonar")?.surface, .monolith)
        XCTAssertEqual(StylePreset.named("tactile")?.surface, .tactile)
        let axes = StylePreset.named("echo")!.axes
        XCTAssertEqual(axes["appearance.surface"], .string("echo"))
        XCTAssertEqual(axes["appearance.icon_stroke"], .double(1.75))
        XCTAssertEqual(axes.count, 10)
    }

    func testTabStyleLayout() {
        XCTAssertEqual(TabBarStyle.standard.barWidth(screen: 390, gutter: 16, tabs: 4), 390)
        XCTAssertEqual(TabBarStyle.rounded.barWidth(screen: 390, gutter: 16, tabs: 4), 390)
        XCTAssertEqual(TabBarStyle.floating.barWidth(screen: 390, gutter: 16, tabs: 4), 358)
        // компактная — уже плавающей
        XCTAssertLessThan(TabBarStyle.compact.barWidth(screen: 390, gutter: 16, tabs: 4), 358)
        XCTAssertEqual(TabBarStyle.standard.radii(height: 64).top, 0)
        XCTAssertEqual(TabBarStyle.rounded.radii(height: 64).bottom, 0)
        XCTAssertGreaterThan(TabBarStyle.rounded.radii(height: 64).top, 0)
        XCTAssertEqual(TabBarStyle.floating.radii(height: 64).top, 32)
        XCTAssertTrue(TabBarStyle.standard.showsTitles)
        XCTAssertFalse(TabBarStyle.compact.showsTitles)
    }

    func testBackdropModes() {
        XCTAssertEqual(BackdropMode(rawValue: "cover_color"), .coverColor)
        XCTAssertTrue(BackdropMode.cover.isPicture)
        XCTAssertFalse(BackdropMode.coverColor.isPicture)
        XCTAssertEqual(GlassType(rawValue: "no_blur"), .noBlur)
    }

    @MainActor
    func testDefaultsAndInputs() {
        let suite = "look-tests-\(UUID().uuidString)"
        let settings = SettingsStore(storage: UserDefaults(suiteName: suite)!)
        let inputs = LookInputs(settings)
        XCTAssertEqual(inputs, LookInputs(mode: .dark, coverTheme: true, preset: "neutral", surface: .echo))  // iPhone по умолчанию — «Эхо»
        XCTAssertEqual(settings.string("appearance.tab_style"), "floating")
        XCTAssertEqual(settings.string("appearance.background"), "cover_color")
        XCTAssertEqual(settings.number("appearance.opacity", fallback: 0), 80)
        XCTAssertEqual(settings.number("нет", fallback: 7), 7)
        // скругление без умолчания — мини-плеер берёт «Капсулу»
        XCTAssertEqual(settings.string("appearance.corner_radius"), "")
        settings.set("appearance.mode", .string("light"))
        settings.set("appearance.surface", .string("edge"))
        XCTAssertEqual(LookInputs(settings).mode, .light)
        XCTAssertEqual(LookInputs(settings).surface, .edge)
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    @MainActor
    func testLocalProfile() {
        let suite = "look-profile-\(UUID().uuidString)"
        let settings = SettingsStore(storage: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(LocalProfile.name(settings), "Sonar")
        settings.set("profile.name", .string("  Folzy "))
        XCTAssertEqual(LocalProfile.name(settings), "Folzy")
        XCTAssertEqual(LocalProfile.initial("folzy"), "F")
        XCTAssertEqual(LocalProfile.initial("  "), "S")
        XCTAssertEqual(LocalProfile.cleanName(String(repeating: "я", count: 50)).count, 40)
        XCTAssertEqual(LocalProfile.cleanUsername(" @@folzy "), "folzy")
        XCTAssertTrue(LocalProfile.usernameValid(""))
        XCTAssertTrue(LocalProfile.usernameValid("@folzy_1092"))
        XCTAssertFalse(LocalProfile.usernameValid("ab"))
        XCTAssertFalse(LocalProfile.usernameValid("фолзи"))
        XCTAssertFalse(LocalProfile.usernameValid("with space"))
        XCTAssertFalse(LocalProfile.usernameValid(String(repeating: "a", count: 33)))
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    func testProfileURL() {
        XCTAssertEqual(LocalProfile.profileURL("folzy"), "https://sonar.folzy.ru/@folzy")
        XCTAssertEqual(LocalProfile.profileURL("  @Folzy_1 "), "https://sonar.folzy.ru/@folzy_1")
        XCTAssertNil(LocalProfile.profileURL(""))
        XCTAssertNil(LocalProfile.profileURL("ab"))
        XCTAssertNil(LocalProfile.profileURL("фолзи"))
        XCTAssertNil(LocalProfile.profileURL("bad name"))
    }

    func testAvatarDataURL() {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0x00, 0x42])
        let url = LocalProfile.dataURL(jpeg: bytes)
        XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertEqual(LocalProfile.imageData(url), bytes)
        // ПК хранит WebP — тоже разбирается
        XCTAssertEqual(LocalProfile.imageData("data:image/webp;base64," + bytes.base64EncodedString()), bytes)
        XCTAssertNil(LocalProfile.imageData("https://example.com/a.png"))
        XCTAssertNil(LocalProfile.imageData("data:text/plain;base64,AAAA"))
        XCTAssertNil(LocalProfile.imageData(""))
    }
}
