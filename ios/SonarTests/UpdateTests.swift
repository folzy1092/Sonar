import XCTest
@testable import Sonar

/// Манифест `ios-update.json`, `changelog.json`, релизы GitHub — без сети, на фикстурах.
final class UpdateManifestTests: XCTestCase {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testManifestDefaultsToReleaseLinks() throws {
        let manifest = try XCTUnwrap(UpdateManifest.parse(json(#"{"enabled": true, "build": 123, "version": "0.1.0"}"#)))
        XCTAssertTrue(manifest.enabled)
        XCTAssertEqual(manifest.build, 123)
        XCTAssertEqual(manifest.version, "0.1.0")
        XCTAssertEqual(manifest.downloadURL?.absoluteString, "https://github.com/folzy1092/Sonar/releases/download/ios-build-123/Sonar.ipa")
        XCTAssertEqual(manifest.pageURL.absoluteString, "https://github.com/folzy1092/Sonar/releases/tag/ios-build-123")
    }

    func testManifestTakesOnlyHTTPSLinks() throws {
        let manifest = try XCTUnwrap(UpdateManifest.parse(json(#"""
        {"build": 5, "ipa_url": "http://evil/Sonar.ipa", "url": "https://example.com/page", "title": "  ", "notes": " Привет "}
        """#)))
        XCTAssertEqual(manifest.downloadURL, UpdateFeed.ipaURL(build: 5))
        XCTAssertEqual(manifest.pageURL.absoluteString, "https://example.com/page")
        XCTAssertNil(manifest.title)
        XCTAssertEqual(manifest.notes, "Привет")
    }

    func testDisabledManifestWithoutBuildAnnouncesNothing() throws {
        let manifest = try XCTUnwrap(UpdateManifest.parse(json(#"{"enabled": false, "build": 0}"#)))
        XCTAssertFalse(manifest.enabled)
        XCTAssertEqual(UpdateStatus.from(manifest: manifest, installedBuild: 10), .upToDate(nil))
        XCTAssertNil(UpdateManifest.parse(json(#"{"enabled": true, "build": 0}"#)))
        XCTAssertNil(UpdateManifest.parse(json("не json")))
    }

    func testStatusComparesBuilds() throws {
        let manifest = try XCTUnwrap(UpdateManifest.parse(json(#"{"build": 20, "minimum_build": 15}"#)))
        guard case let .available(release) = UpdateStatus.from(manifest: manifest, installedBuild: 12) else {
            return XCTFail("сборка 20 новее 12")
        }
        XCTAssertTrue(release.isRequired, "12 ниже minimum_build 15")
        guard case let .available(soft) = UpdateStatus.from(manifest: manifest, installedBuild: 16) else {
            return XCTFail("сборка 20 новее 16")
        }
        XCTAssertFalse(soft.isRequired)
        guard case .upToDate = UpdateStatus.from(manifest: manifest, installedBuild: 20) else {
            return XCTFail("та же сборка — актуально")
        }
        guard case .available = UpdateStatus.from(manifest: manifest, installedBuild: nil) else {
            return XCTFail("неизвестная сборка — предлагаем")
        }
    }

    func testChangelogKeepsOnlyIPhoneBuilds() {
        let entries = ChangelogEntry.parse(json(#"""
        [
          {"version": "0.1.1", "date": "2026-11-16", "platform": "windows", "changes": ["ПК"]},
          {"version": "0.1.0", "build": 30, "date": "2026-11-18", "platform": "ios", "title": "Первая",
           "new": [{"text": "Автообновление"}, "Плеер"], "fixed": ["Тексты"]},
          {"version": "0.1.0", "build": 31, "date": "2026-11-19", "changes": ["Общее для всех"]},
          {"version": "0.0.9", "platform": "ios", "changes": ["без сборки"]},
          {"build": 29, "platform": "ios", "changes": []}
        ]
        """#))
        XCTAssertEqual(entries.map(\.build), [31, 30])
        XCTAssertEqual(entries[1].newItems, ["Автообновление", "Плеер"])
        XCTAssertEqual(entries[1].fixedItems, ["Тексты"])
        XCTAssertEqual(entries[1].lines.map(\.label), ["НОВОЕ", "НОВОЕ", "ИСПРАВЛЕНО"])
        XCTAssertEqual(entries[0].items, ["Общее для всех"])
    }

    func testChangelogUnderstandsShadowFormat() {
        let entries = ChangelogEntry.parse(json(#"{"entries": [{"build": 7, "date": "2026-10-06", "items": ["Раз"]}]}"#))
        XCTAssertEqual(entries.first?.build, 7)
        XCTAssertEqual(entries.first?.items, ["Раз"])
    }

    func testChangesBetweenInstalledAndAnnounced() {
        let entries = (1...40).map { ChangelogEntry(build: $0, date: "", items: ["\($0)"]) }
        XCTAssertEqual(ChangelogEntry.changes(installedBuild: 10, announcedBuild: 13, entries: entries).map(\.build), [13, 12, 11])
        XCTAssertEqual(ChangelogEntry.changes(installedBuild: nil, announcedBuild: 13, entries: entries).map(\.build), [13])
        XCTAssertEqual(ChangelogEntry.changes(installedBuild: 0, announcedBuild: 40, entries: entries).count, 20, "не больше 20")
    }

    func testReleasesFallbackPicksNewestIPhoneBuild() throws {
        let release = try XCTUnwrap(UpdateRelease.parseReleases(json(#"""
        [
          {"tag_name": "windows-v0.1.40", "name": "Sonar 0.1.40 для Windows", "html_url": "https://github.com/x/1", "assets": []},
          {"tag_name": "ios-latest", "name": "Sonar для iPhone — последняя сборка", "html_url": "https://github.com/x/2", "assets": []},
          {"tag_name": "ios-build-41", "name": "Sonar 0.1.0 (41) для iPhone", "html_url": "https://github.com/x/41",
           "assets": [{"name": "Sonar.ipa", "browser_download_url": "https://github.com/x/41/Sonar.ipa"}]},
          {"tag_name": "ios-build-40", "name": "Sonar 0.1.0 (40) для iPhone", "html_url": "https://github.com/x/40", "assets": []},
          {"tag_name": "ios-build-99", "draft": true, "name": "черновик", "html_url": "https://github.com/x/99", "assets": []}
        ]
        """#)))
        XCTAssertEqual(release.build, 41)
        XCTAssertEqual(release.version, "0.1.0")
        XCTAssertEqual(release.downloadURL?.absoluteString, "https://github.com/x/41/Sonar.ipa")
        XCTAssertEqual(release.label, "0.1.0 (41)")
        XCTAssertNil(UpdateFeed.buildNumber(fromTag: "ios-latest"))
    }

    func testCountsText() {
        var release = UpdateRelease(build: 3, version: nil, title: nil, pageURL: UpdateFeed.releasesPageURL, notes: "")
        release.changelog = [
            ChangelogEntry(build: 3, date: "", items: [], newItems: ["а", "б"], fixedItems: ["в"]),
            ChangelogEntry(build: 2, date: "", items: ["г"]),
        ]
        XCTAssertEqual(UpdateCounts(release).text, "2 новые функции · 1 исправление · 1 изменение · 2 выпуска")
        release.changelog = []
        XCTAssertEqual(UpdateCounts(release).text, "1 выпуск")
    }

    func testRussianPlural() {
        XCTAssertEqual([1, 2, 5, 11, 12, 21, 22, 25, 111].map { ruPlural($0, "трек", "трека", "треков") },
                       ["трек", "трека", "треков", "треков", "треков", "трек", "трека", "треков", "треков"])
    }

    func testDateText() {
        XCTAssertEqual(ChangelogEntry.dateText("2026-11-18"), "18 ноября 2026")
        XCTAssertEqual(ChangelogEntry.dateText("вчера"), "вчера")
    }
}

/// Профиль, подготовка бандла, ссылки и диагностика установки.
final class SelfUpdateCoreTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("sonar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    static func profileData(appId: String = "ABCDE12345.com.folzy.*", expires: Date = Date(timeIntervalSinceNow: 86400), certificates: [Data] = [Data([1, 2, 3])]) throws -> Data {
        let plist: [String: Any] = [
            "Name": "Sonar Dev",
            "TeamName": "Folzy Team",
            "TeamIdentifier": ["ABCDE12345"],
            "ExpirationDate": expires,
            "ProvisionedDevices": ["dev1", "dev2"],
            "DeveloperCertificates": certificates,
            "Entitlements": ["application-identifier": appId, "aps-environment": "production"],
        ]
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        // как настоящий профиль: plist внутри двоичной обёртки CMS
        return Data([0x30, 0x82, 0x01, 0x00, 0x06, 0x09]) + xml + Data([0xA0, 0x82, 0x00])
    }

    func testProfileParse() throws {
        let profile = try XCTUnwrap(ProvisioningProfile.parse(Self.profileData()))
        XCTAssertEqual(profile.teamId, "ABCDE12345")
        XCTAssertEqual(profile.teamName, "Folzy Team")
        XCTAssertEqual(profile.bundleIdPattern, "com.folzy.*")
        XCTAssertTrue(profile.isWildcard)
        XCTAssertEqual(profile.deviceCount, 2)
        XCTAssertEqual(profile.apsEnvironment, "production")
        XCTAssertEqual(profile.developerCertificates, [Data([1, 2, 3])])
        XCTAssertFalse(profile.isExpired())
        XCTAssertTrue(profile.allows(bundleId: "com.folzy.sonar"))
        XCTAssertFalse(profile.allows(bundleId: "ph.telegra.Telegraph"))

        let exact = try XCTUnwrap(ProvisioningProfile.parse(Self.profileData(appId: "ABCDE12345.com.folzy.sonar", expires: Date(timeIntervalSinceNow: -60))))
        XCTAssertFalse(exact.isWildcard)
        XCTAssertTrue(exact.isExpired())
        XCTAssertTrue(exact.allows(bundleId: "com.folzy.sonar"))
        XCTAssertFalse(exact.allows(bundleId: "com.folzy.sonar2"))

        XCTAssertNil(ProvisioningProfile.parse(Data("нет plist".utf8)))
    }

    func testRebase() {
        XCTAssertEqual(BundlePreparer.rebase("com.folzy.sonar", from: "com.folzy.sonar", to: "x.y"), "x.y")
        XCTAssertEqual(BundlePreparer.rebase("com.folzy.sonar.Widgets", from: "com.folzy.sonar", to: "x.y"), "x.y.Widgets")
        XCTAssertEqual(BundlePreparer.rebase("com.folzy.sonarx", from: "com.folzy.sonar", to: "x.y"), "com.folzy.sonarx")
        XCTAssertEqual(BundlePreparer.rebase("other.id", from: "com.folzy.sonar", to: "x.y"), "other.id")
    }

    private func writePlist(_ dict: [String: Any], to url: URL, format: PropertyListSerialization.PropertyListFormat = .xml) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0).write(to: url)
    }

    private func readPlist(_ url: URL) throws -> ([String: Any], PropertyListSerialization.PropertyListFormat) {
        var format = PropertyListSerialization.PropertyListFormat.xml
        let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: &format)
        return (try XCTUnwrap(object as? [String: Any]), format)
    }

    func testPrepareMakesBuildLookLikeInstalledCopy() throws {
        let app = temp.appendingPathComponent("Payload/Sonar.app", isDirectory: true)
        try writePlist([
            "CFBundleIdentifier": "com.folzy.sonar",
            "CFBundleVersion": "42",
            "BGTaskSchedulerPermittedIdentifiers": ["com.folzy.sonar.refresh", "other.task"],
        ], to: app.appendingPathComponent("Info.plist"), format: .binary)
        try writePlist(["CFBundleIdentifier": "com.folzy.sonar.Widgets"], to: app.appendingPathComponent("PlugIns/Widgets.appex/Info.plist"))
        try writePlist(["CFBundleIdentifier": "com.folzy.sonar.Share"], to: app.appendingPathComponent("PlugIns/Share.appex/Info.plist"))
        try Data("old".utf8).write(to: app.appendingPathComponent("PlugIns/Widgets.appex/embedded.mobileprovision"))
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Watch/App.app"), withIntermediateDirectories: true)
        let profile = temp.appendingPathComponent("signing.mobileprovision")
        try Self.profileData().write(to: profile)

        XCTAssertEqual(BundlePreparer.findApp(inPayloadParent: temp)?.lastPathComponent, "Sonar.app")
        let installed = BundlePreparer.Installed(bundleId: "com.esign.sonar", plugIns: ["Widgets.appex"], hasWatch: false)
        let summary = try BundlePreparer.prepare(app: app, installed: installed, profileURL: profile)

        XCTAssertEqual(summary.previousBundleId, "com.folzy.sonar")
        XCTAssertEqual(summary.removedPlugIns, ["Share.appex"])
        XCTAssertEqual(summary.keptPlugIns, ["Widgets.appex"])
        XCTAssertTrue(summary.removedWatch)

        let (info, format) = try readPlist(app.appendingPathComponent("Info.plist"))
        XCTAssertEqual(format, .binary, "формат Info.plist сохраняется")
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "com.esign.sonar")
        XCTAssertEqual(info["BGTaskSchedulerPermittedIdentifiers"] as? [String], ["com.esign.sonar.refresh", "other.task"])
        XCTAssertEqual(info["CFBundleVersion"] as? String, "42")
        let (widget, _) = try readPlist(app.appendingPathComponent("PlugIns/Widgets.appex/Info.plist"))
        XCTAssertEqual(widget["CFBundleIdentifier"] as? String, "com.esign.sonar.Widgets")
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("PlugIns/Widgets.appex/embedded.mobileprovision")), try Data(contentsOf: profile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("PlugIns/Share.appex").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("Watch").path))
    }

    func testPrepareRemovesEmptyPlugInsAndNeedsInstalledId() throws {
        let app = temp.appendingPathComponent("Payload/Sonar.app", isDirectory: true)
        try writePlist(["CFBundleIdentifier": "com.folzy.sonar"], to: app.appendingPathComponent("Info.plist"))
        try writePlist(["CFBundleIdentifier": "com.folzy.sonar.Widgets"], to: app.appendingPathComponent("PlugIns/Widgets.appex/Info.plist"))
        XCTAssertThrowsError(try BundlePreparer.prepare(app: app, installed: .init(bundleId: "", plugIns: [], hasWatch: false), profileURL: nil))
        try BundlePreparer.prepare(app: app, installed: .init(bundleId: "com.folzy.sonar", plugIns: [], hasWatch: false), profileURL: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("PlugIns").path))
        XCTAssertThrowsError(try BundlePreparer.prepare(app: temp, installed: .init(bundleId: "x", plugIns: [], hasWatch: false), profileURL: nil)) { error in
            XCTAssertEqual(error as? BundlePreparer.PrepareError, .badInfoPlist)
        }
    }

    func testInstallLinks() throws {
        XCTAssertEqual(InstallLinks.encode("a b/ё&=~"), "a%20b%2F%D1%91%26%3D~")
        XCTAssertEqual(InstallLinks.plainTitle("Sonar 0.1.0 — «бета»"), "Sonar 0.1.0")
        XCTAssertEqual(InstallLinks.plainTitle("«»"), "Sonar")
        let payload = InstallLinks.payloadURL(port: 8123)
        XCTAssertEqual(payload.absoluteString, "http://127.0.0.1:8123/sonar.ipa")
        XCTAssertEqual(InstallLinks.pageURL(port: 8123).absoluteString, "http://127.0.0.1:8123/install")
        let manifest = try XCTUnwrap(InstallLinks.externalManifestURL(bundleId: "com.folzy.sonar", bundleVersion: "42", title: "Sonar 0.1.0", payload: payload))
        XCTAssertEqual(manifest.absoluteString,
                       "https://api.palera.in/genPlist?bundleid=com.folzy.sonar&name=Sonar%200.1.0&version=42&fetchurl=http%3A%2F%2F127.0.0.1%3A8123%2Fsonar.ipa")
        XCTAssertNil(InstallLinks.externalManifestURL(bundleId: "com.folzy.<x>", bundleVersion: "42", title: "", payload: payload))
        XCTAssertNil(InstallLinks.externalManifestURL(bundleId: "com.folzy.sonar", bundleVersion: "", title: "", payload: payload))
        let itms = try XCTUnwrap(InstallLinks.itmsURL(manifest: manifest))
        XCTAssertTrue(itms.absoluteString.hasPrefix("itms-services://?action=download-manifest&url=https%3A%2F%2Fapi.palera.in%2FgenPlist%3Fbundleid%3D"))
        let page = InstallLinks.installPage(itms: itms)
        XCTAssertTrue(page.contains("href=\"itms-services://?action=download-manifest&amp;url="))
        XCTAssertTrue(page.contains("window.location=\"itms-services://?action=download-manifest&url="))
    }

    /// Запасной манифест из репо — только для постоянных портов и нашего bundle id.
    func testFallbackManifest() {
        XCTAssertEqual(InstallLinks.fallbackManifestURL(bundleId: "com.folzy.sonar", port: 47231)?.absoluteString,
                       "https://raw.githubusercontent.com/folzy1092/Sonar/main/updates/ios-install/47231.plist")
        XCTAssertNil(InstallLinks.fallbackManifestURL(bundleId: "com.folzy.sonar", port: 50000))
        XCTAssertNil(InstallLinks.fallbackManifestURL(bundleId: "com.other.sonar", port: 47231))
        var diagnostics = InstallDiagnostics()
        diagnostics.server.isReady = true
        diagnostics.externalManifest = .failed("HTTP 521")
        XCTAssertTrue(diagnostics.cause.contains("api.palera.in"))
        diagnostics.fallbackManifest = .ok
        XCTAssertFalse(diagnostics.cause.contains("api.palera.in"))
        XCTAssertTrue(diagnostics.line.contains("репо ✓"))
    }

    /// Лист «выйди на рабочий стол» — только когда iOS уже забирает IPA, не поверх окна «Открыть в iTunes?».
    func testHomeHintOnlyAfterInstallStarted() {
        XCTAssertNil(HomeScreenHint.text(for: .startingServer))
        XCTAssertNil(HomeScreenHint.text(for: .waitingForConfirmation(hint: false)))
        XCTAssertNil(HomeScreenHint.text(for: .waitingForConfirmation(hint: true)))
        XCTAssertNotNil(HomeScreenHint.text(for: .sending(sent: 1, total: 2)))
        XCTAssertNotNil(HomeScreenHint.text(for: .installing))
    }

    func testExternalManifestProblem() {
        let payload = InstallLinks.payloadURL(port: 1)
        XCTAssertEqual(InstallLinks.externalManifestProblem(data: nil, statusCode: nil, error: URLError(.timedOut), payload: payload), "нет ответа")
        XCTAssertEqual(InstallLinks.externalManifestProblem(data: nil, statusCode: nil, error: URLError(.cannotFindHost), payload: payload), "DNS")
        XCTAssertEqual(InstallLinks.externalManifestProblem(data: nil, statusCode: nil, error: URLError(.serverCertificateUntrusted), payload: payload), "TLS")
        XCTAssertEqual(InstallLinks.externalManifestProblem(data: nil, statusCode: 503, error: nil, payload: payload), "HTTP 503")
        XCTAssertEqual(InstallLinks.externalManifestProblem(data: Data("<html>".utf8), statusCode: 200, error: nil, payload: payload), "неверный ответ")
        let good = Data("<plist><string>software-package</string><string>\(payload.absoluteString)</string></plist>".utf8)
        XCTAssertNil(InstallLinks.externalManifestProblem(data: good, statusCode: 200, error: nil, payload: payload))
    }

    func testRange() {
        XCTAssertNil(HTTPRange.parse(nil, size: 100))
        XCTAssertEqual(HTTPRange.parse("bytes=0-9", size: 100), 0 ... 9)
        XCTAssertEqual(HTTPRange.parse("bytes=90-", size: 100), 90 ... 99)
        XCTAssertEqual(HTTPRange.parse("bytes=-10", size: 100), 90 ... 99)
        XCTAssertEqual(HTTPRange.parse("bytes=-500", size: 100), 0 ... 99)
        XCTAssertEqual(HTTPRange.parse("bytes=50-500", size: 100), 50 ... 99)
        XCTAssertNil(HTTPRange.parse("bytes=100-", size: 100))
        XCTAssertNil(HTTPRange.parse("bytes=9-3", size: 100))
        XCTAssertNil(HTTPRange.parse("items=0-1", size: 100))
    }

    func testDiagnosticsCauses() {
        var diagnostics = InstallDiagnostics()
        XCTAssertTrue(diagnostics.cause.hasPrefix("Локальный сервер не работает (запуск)."))
        XCTAssertTrue(diagnostics.cause.hasSuffix("Или «Поделиться подписанной IPA» и установить её через ESign."))
        diagnostics.server.isReady = true
        diagnostics.server.listener = "работает"
        XCTAssertTrue(diagnostics.cause.hasPrefix("Safari не открыл страницу установки"))
        diagnostics.externalManifest = .failed("DNS")
        XCTAssertTrue(diagnostics.cause.hasPrefix("Не удалось получить манифест с api.palera.in (DNS)"))
        diagnostics.opener = .openURL
        diagnostics.openResult = false
        XCTAssertTrue(diagnostics.cause.hasPrefix("iOS отказалась открыть ссылку itms-services."))
        diagnostics.server.payloadRequested = true
        XCTAssertTrue(diagnostics.cause.hasPrefix("iOS начала загрузку, но не закончила."))

        var seen = InstallDiagnostics()
        seen.server.isReady = true
        seen.externalManifest = .ok
        seen.promptSeen = true
        XCTAssertTrue(seen.cause.hasPrefix("Окно установки было"))
        seen.promptSeen = false
        seen.server.pageRequested = true
        XCTAssertTrue(seen.cause.hasPrefix("Ссылка установки открыта, но iOS не показала окно."))
        XCTAssertEqual(seen.line, "HTTP 127.0.0.1 · манифест palera ✓ · Safari ✓ · сервер запуск · подкл. 0 · ipa —")
    }
}
