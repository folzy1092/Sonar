import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// Это устройство для списка «Устройства»: человекочитаемая модель («iPhone 15 Pro»), постоянный id,
/// версия iOS и Sonar. На ПК то же самое собирает Windows-клиент: «Windows 10 (Folzy)» — имя ПК в скобках.
enum DeviceInfo {
    /// Идентификатор железа (`utsname.machine`): «iPhone16,1». На симуляторе — то, что он изображает.
    static var machine: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        return rawMachine
    }

    static var isSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] != nil
    }

    private static var rawMachine: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    /// «iPhone 15 Pro»; симулятор — «iPhone 16 Pro (симулятор)».
    static var name: String {
        let model = modelName(machine)
        return isSimulator ? "\(model) (симулятор)" : model
    }

    /// «iOS 18.1».
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let patch = v.patchVersion > 0 ? ".\(v.patchVersion)" : ""
        return "iOS \(v.majorVersion).\(v.minorVersion)\(patch)"
    }

    /// Версия Sonar из Info.plist (`CFBundleShortVersionString`) и номер сборки.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var build: Int? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init)
    }

    /// Что уходит на сервер при входе и при каждом запуске.
    static func descriptor(id: String) -> DeviceDescriptor {
        DeviceDescriptor(id: id, name: name, platform: .ios, os: osVersion, appVersion: appVersion, build: build)
    }

    /// Модель по идентификатору. Неизвестный iPhone (новее таблицы) — «iPhone» без номера, чтобы не врать.
    static func modelName(_ id: String) -> String {
        if let known = models[id] { return known }
        if id.hasPrefix("iPhone") { return "iPhone" }
        if id.hasPrefix("iPad") { return "iPad" }
        if id.hasPrefix("iPod") { return "iPod touch" }
        if id == "arm64" || id == "x86_64" { return "Симулятор" }
        return id.isEmpty ? "iPhone" : id
    }

    /// iPhone, на которые ставится iOS 18+ (от XS / XR), и новее.
    static let models: [String: String] = [
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2-го поколения)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE (3-го поколения)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,3": "iPhone 17",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,4": "iPhone Air",
    ]
}
