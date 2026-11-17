import XCTest
@testable import Sonar

final class DeviceInfoTests: XCTestCase {
    func testKnownIPhones() {
        XCTAssertEqual(DeviceInfo.modelName("iPhone12,1"), "iPhone 11")
        XCTAssertEqual(DeviceInfo.modelName("iPhone12,8"), "iPhone SE (2-го поколения)")
        XCTAssertEqual(DeviceInfo.modelName("iPhone14,2"), "iPhone 13 Pro")
        XCTAssertEqual(DeviceInfo.modelName("iPhone15,3"), "iPhone 14 Pro Max")
        XCTAssertEqual(DeviceInfo.modelName("iPhone16,1"), "iPhone 15 Pro")
        XCTAssertEqual(DeviceInfo.modelName("iPhone17,1"), "iPhone 16 Pro")
        XCTAssertEqual(DeviceInfo.modelName("iPhone17,2"), "iPhone 16 Pro Max")
        XCTAssertEqual(DeviceInfo.modelName("iPhone17,5"), "iPhone 16e")
        XCTAssertEqual(DeviceInfo.modelName("iPhone18,4"), "iPhone Air")
    }

    func testTableCoversEveryGenerationFromIPhone11() {
        let names = Set(DeviceInfo.models.values)
        for generation in 11 ... 16 {
            for suffix in ["", " Pro", " Pro Max"] {
                XCTAssertTrue(names.contains("iPhone \(generation)\(suffix)"), "нет iPhone \(generation)\(suffix)")
            }
        }
        XCTAssertTrue(DeviceInfo.models.keys.allSatisfy { $0.hasPrefix("iPhone") })
        XCTAssertTrue(DeviceInfo.models.values.allSatisfy { $0.hasPrefix("iPhone ") })
    }

    func testUnknownModelsDoNotLie() {
        XCTAssertEqual(DeviceInfo.modelName("iPhone99,9"), "iPhone", "новее таблицы — без номера")
        XCTAssertEqual(DeviceInfo.modelName("iPad16,3"), "iPad")
        XCTAssertEqual(DeviceInfo.modelName("arm64"), "Симулятор")
        XCTAssertEqual(DeviceInfo.modelName(""), "iPhone")
    }

    func testDescriptorIsIOSWithVersion() {
        let d = DeviceInfo.descriptor(id: "abc")
        XCTAssertEqual(d.id, "abc")
        XCTAssertEqual(d.platform, .ios)
        XCTAssertTrue(d.os.hasPrefix("iOS "))
        XCTAssertFalse(d.name.isEmpty)
        XCTAssertFalse(d.appVersion.isEmpty)
    }

    func testDeviceIdIsStableUUIDAndSurvivesLogout() {
        let secrets = MemorySecrets()
        let id = SessionVault(secrets: secrets).deviceId
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(SessionVault(secrets: secrets).deviceId, id, "второй запуск — тот же id")
        let vault = SessionVault(secrets: secrets)
        vault.save(AuthResult(session: "tok", user: AccountUser(id: "u_1", login: "folzy", username: "folzy", displayName: "Folzy")))
        vault.clear()
        XCTAssertNil(vault.token)
        XCTAssertEqual(vault.deviceId, id, "выход не меняет id устройства")
    }

    func testDescriptorJSONMatchesAPI() throws {
        let d = DeviceDescriptor(id: "d1", name: "iPhone 15 Pro", platform: .ios, os: "iOS 18.1", appVersion: "0.1.0", build: 239)
        let json = try JSONValue(data: JSONEncoder().encode(d))
        XCTAssertEqual(json["app_version"].string, "0.1.0")
        XCTAssertEqual(json["platform"].string, "ios")
        XCTAssertEqual(json["build"].int, 239)
        let unknown = try JSONDecoder().decode(DevicePlatform.self, from: Data(#""macos""#.utf8))
        XCTAssertEqual(unknown, .other)
    }
}
