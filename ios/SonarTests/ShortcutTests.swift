import XCTest
@testable import Sonar

/// Виджет и Siri: ссылки `sonar://play/…` (`App/DeepLink.swift`), настройка быстрого плейлиста
/// (`Core/Shortcuts/PlayTarget.swift`) и новые расширения при автообновлении (`BundlePreparer`).
final class ShortcutTests: XCTestCase {
    func testPlayLinks() {
        XCTAssertEqual(DeepLink(URL(string: "sonar://play/liked")!), .play(.liked))
        XCTAssertEqual(DeepLink(URL(string: "sonar://play/wave")!), .play(.wave))
        XCTAssertEqual(DeepLink(URL(string: "sonar://play/quick")!), .play(.quick))
        // регистр не важен, хвостовой слэш тоже
        XCTAssertEqual(DeepLink(URL(string: "SONAR://Play/Wave")!), .play(.wave))
        XCTAssertEqual(DeepLink(URL(string: "sonar://play/liked/")!), .play(.liked))
        XCTAssertNil(DeepLink(URL(string: "sonar://play/radio")!))
        XCTAssertNil(DeepLink(URL(string: "sonar://play")!))
        XCTAssertNil(DeepLink(URL(string: "sonar://play/")!))
        XCTAssertNil(DeepLink(URL(string: "https://play/liked")!))
        // прежние ссылки не сломались
        XCTAssertEqual(DeepLink(URL(string: "sonar://auth/abc123")!), .auth("abc123"))
        XCTAssertEqual(DeepLink(URL(string: "sonar://track/ym:42")!), .track("ym:42"))
    }

    func testTargetURLsRoundTrip() {
        for target in PlayTarget.allCases {
            XCTAssertEqual(DeepLink(target.url), .play(target), target.rawValue)
        }
        XCTAssertEqual(PlayTarget.quick.url.absoluteString, "sonar://play/quick")
    }

    func testQuickPlaylistSetting() {
        XCTAssertEqual(QuickPlaylist(setting: "liked"), .liked)
        XCTAssertEqual(QuickPlaylist(setting: "downloaded"), .downloaded)
        XCTAssertEqual(QuickPlaylist(setting: "scpl:12345"), .service("scpl:12345"))
        XCTAssertEqual(QuickPlaylist(setting: "ympl:42:1003"), .service("ympl:42:1003"))
        XCTAssertEqual(QuickPlaylist(setting: " ympl:likes "), .service("ympl:likes"))
        XCTAssertEqual(QuickPlaylist(setting: "vkpl:-2000_9_ab"), .service("vkpl:-2000_9_ab"))
        XCTAssertEqual(QuickPlaylist(setting: "vkpl:"), .liked)
        // пусто, обрывок или чужое — Любимые
        XCTAssertEqual(QuickPlaylist(setting: ""), .liked)
        XCTAssertEqual(QuickPlaylist(setting: "scpl:"), .liked)
        XCTAssertEqual(QuickPlaylist(setting: "spotify:1"), .liked)
        for choice in [QuickPlaylist.liked, .downloaded, .service("scpl:likes")] {
            XCTAssertEqual(QuickPlaylist(setting: choice.setting), choice)
        }
    }

    @MainActor
    func testQuickPlaylistDefault() {
        XCTAssertEqual(SettingsDefaults.system[QuickPlaylist.key], .string("liked"))
        XCTAssertEqual(SettingsDefaults.system[QuickPlaylist.titleKey], .string(""))
    }

    func testWidgetKeptOnlyWithWildcardProfile() throws {
        let temp = tempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        func makeApp() throws -> URL {
            let app = temp.appendingPathComponent("Payload/Sonar.app", isDirectory: true)
            try? FileManager.default.removeItem(at: app)
            let widget = app.appendingPathComponent("PlugIns/SonarWidget.appex", isDirectory: true)
            try FileManager.default.createDirectory(at: widget, withIntermediateDirectories: true)
            let main = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.folzy.sonar"], format: .xml, options: 0)
            try main.write(to: app.appendingPathComponent("Info.plist"))
            let ext = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.folzy.sonar.widget"], format: .xml, options: 0)
            try ext.write(to: widget.appendingPathComponent("Info.plist"))
            return app
        }
        // установленная копия без виджета (старая сборка) и профиль не на «*» — виджет убирается
        let installed = BundlePreparer.Installed(bundleId: "com.esign.sonar", plugIns: [], hasWatch: false)
        var app = try makeApp()
        var summary = try BundlePreparer.prepare(app: app, installed: installed, profileURL: nil)
        XCTAssertEqual(summary.removedPlugIns, ["SonarWidget.appex"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("PlugIns").path))

        // профиль на «*» — виджет остаётся, его id — под установленный
        app = try makeApp()
        summary = try BundlePreparer.prepare(app: app, installed: installed, profileURL: nil, keepNewPlugIns: true)
        XCTAssertEqual(summary.keptPlugIns, ["SonarWidget.appex"])
        let data = try Data(contentsOf: app.appendingPathComponent("PlugIns/SonarWidget.appex/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertEqual(info?["CFBundleIdentifier"] as? String, "com.esign.sonar.widget")
    }
}
