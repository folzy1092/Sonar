import XCTest
@testable import Sonar

/// Подпись на устройстве (zsign) маленького фиктивного `.app` тестовой самоподписанной парой. Пару
/// генерирует CI перед тестами (`ios.yml`, шаг «Тестовая пара») и передаёт папку через
/// `TEST_RUNNER_SONAR_TEST_SIGNING`; настоящих `.p12` в репозитории нет. Без пары тест пропускается.
final class SigningTests: XCTestCase {
    private var temp: URL!
    private let password = "sonar"

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("sonar-sign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    private func pair() throws -> (p12: URL, profile: URL) {
        guard let folder = ProcessInfo.processInfo.environment["SONAR_TEST_SIGNING"], !folder.isEmpty else {
            throw XCTSkip("нет тестовой пары (её генерирует CI)")
        }
        let base = URL(fileURLWithPath: folder, isDirectory: true)
        let certificate = try Data(contentsOf: base.appendingPathComponent("cert.der"))
        let profile = temp.appendingPathComponent("test.mobileprovision")
        try SelfUpdateCoreTests.profileData(appId: "ABCDE12345.*", certificates: [certificate]).write(to: profile)
        return (base.appendingPathComponent("test.p12"), profile)
    }

    /// `.app` с Info.plist и настоящим Mach-O (исполняемый файл самого Sonar).
    private func makeApp() throws -> URL {
        let app = temp.appendingPathComponent("Payload/Dummy.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let executable = try XCTUnwrap(Bundle.main.executableURL, "нет исполняемого файла хоста тестов")
        try FileManager.default.copyItem(at: executable, to: app.appendingPathComponent("Dummy"))
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.folzy.sonar.dummy",
            "CFBundleExecutable": "Dummy",
            "CFBundleName": "Dummy",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Info.plist"))
        return app
    }

    func testPairCheck() throws {
        let (p12, profile) = try pair()
        XCTAssertNil(AppSigner.check(profile: profile, p12: p12, password: password))
        let wrong = AppSigner.check(profile: profile, p12: p12, password: "не тот")
        XCTAssertNotNil(wrong, "неверный пароль — ошибка")

        // профиль без этого сертификата — пара не подходит
        let other = temp.appendingPathComponent("other.mobileprovision")
        try SelfUpdateCoreTests.profileData(appId: "ABCDE12345.*", certificates: [Data([9, 9, 9])]).write(to: other)
        XCTAssertNotNil(AppSigner.check(profile: other, p12: p12, password: password))
    }

    func testSignsDummyApp() throws {
        let (p12, profile) = try pair()
        let app = try makeApp()
        XCTAssertNoThrow(try AppSigner.sign(app: app, profile: profile, p12: p12, password: password))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("_CodeSignature/CodeResources").path),
                      "после подписи есть _CodeSignature")
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("embedded.mobileprovision")), try Data(contentsOf: profile))
        // профиль запечатан в подписи: без этого iOS сочтёт бандл изменённым
        let resources = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: app.appendingPathComponent("_CodeSignature/CodeResources")), format: nil) as? [String: Any]
        let files2 = try XCTUnwrap(resources?["files2"] as? [String: Any])
        XCTAssertNotNil(files2["embedded.mobileprovision"], "embedded.mobileprovision есть в CodeResources")
    }

    func testSigningStoreImportsPair() throws {
        let (p12, profile) = try pair()
        let store = SigningStore(directory: temp.appendingPathComponent("store", isDirectory: true))
        XCTAssertFalse(store.isConfigured)
        try store.importCertificate(from: p12)
        try store.importProfile(from: profile)
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(store.profile?.teamId, "ABCDE12345")
        XCTAssertThrowsError(try store.importProfile(from: p12), "p12 — не профиль")
        let values = try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true, "пара не уходит в бэкап")
    }
}
