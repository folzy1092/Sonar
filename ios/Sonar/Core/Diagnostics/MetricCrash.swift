import Foundation

// MetricKit: iOS сама записывает сбои (`MXCrashDiagnostic`) и отдаёт их приложению при следующем
// запуске (или позже, раз в сутки). Ловит то, что наш обработчик не видит: нехватка памяти, сторож
// iOS, сбой до запуска журнала. Здесь — разбор `jsonRepresentation()` (Foundation, тестируется на
// Linux); подписка — `MetricKitReceiver` ниже, только на устройстве.

/// Сбой глазами iOS.
struct MetricCrash: Equatable, Sendable, Codable {
    var signal: Int32?
    var exceptionType: Int?
    var exceptionCode: Int?
    var terminationReason: String?
    var exceptionReason: String?
    var appVersion: String?
    var appBuild: String?
    var osVersion: String?
    var deviceType: String?
    /// Стек потока, на котором упало: `Sonar + 12345`, сверху — место сбоя.
    var frames: [String] = []

    /// Разобрать JSON `MXCrashDiagnostic.jsonRepresentation()`.
    static func parse(_ data: Data) -> MetricCrash? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let meta = root["diagnosticMetaData"] as? [String: Any] ?? [:]
        var crash = MetricCrash()
        crash.signal = (meta["signal"] as? NSNumber).map { $0.int32Value }
        crash.exceptionType = (meta["exceptionType"] as? NSNumber)?.intValue
        crash.exceptionCode = (meta["exceptionCode"] as? NSNumber)?.intValue
        crash.terminationReason = meta["terminationReason"] as? String
        crash.appVersion = meta["appVersion"] as? String
        crash.appBuild = meta["appBuildVersion"] as? String
        crash.osVersion = meta["osVersion"] as? String
        crash.deviceType = meta["deviceType"] as? String
        if let objc = meta["objectiveCexceptionReason"] as? [String: Any] {
            let composed = objc["composedMessage"] as? String
            let name = objc["exceptionName"] as? String ?? objc["className"] as? String
            crash.exceptionReason = [name, composed].compactMap { $0 }.joined(separator: ": ")
        }
        if let tree = root["callStackTree"] as? [String: Any],
           let stacks = tree["callStacks"] as? [[String: Any]] {
            // поток, которому приписан сбой; нет пометки — первый
            let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
            var frame = (stack?["callStackRootFrames"] as? [[String: Any]])?.first
            while let current = frame, crash.frames.count < 200 {
                let binary = current["binaryName"] as? String ?? "?"
                let offset = (current["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value ?? 0
                let address = (current["address"] as? NSNumber)?.uint64Value ?? 0
                crash.frames.append("\(binary) + \(offset)  (0x\(String(address, radix: 16)))")
                frame = (current["subFrames"] as? [[String: Any]])?.first
            }
        }
        return crash
    }

    var cause: CrashCause {
        if let signal, signal != 0 { return .signal(signal) }
        if let exceptionReason, !exceptionReason.isEmpty { return .exception(name: exceptionReason, reason: nil) }
        return .system(terminationReason ?? "EXC \(exceptionType ?? 0)")
    }

    /// Раздел отчёта «MetricKit».
    var text: String {
        var lines: [String] = []
        if let appVersion { lines.append("Версия: \(appVersion) (\(appBuild ?? "?"))") }
        if let osVersion { lines.append("Система: \(osVersion) · \(deviceType ?? "?")") }
        if let signal { lines.append("Сигнал: \(CrashCause.signalName(signal)) (\(signal))") }
        if let exceptionType { lines.append("Исключение Mach: \(exceptionType), код \(exceptionCode ?? 0)") }
        if let exceptionReason { lines.append("Objective-C: \(exceptionReason)") }
        if let terminationReason { lines.append("Причина: \(terminationReason)") }
        if !frames.isEmpty {
            lines.append("Стек:")
            lines += frames.enumerated().map { "  \($0.offset)  \($0.element)" }
        }
        return lines.joined(separator: "\n")
    }
}

#if canImport(MetricKit) && os(iOS)
import MetricKit

/// Подписчик MetricKit: сбои из прошлых запусков → `CrashLog.attach(metric:)`.
final class MetricKitReceiver: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitReceiver()

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = (payload.crashDiagnostics ?? []).compactMap { MetricCrash.parse($0.jsonRepresentation()) }
            guard !crashes.isEmpty else { continue }
            CrashLog.attach(metric: crashes, from: payload.timeStampBegin, to: payload.timeStampEnd)
        }
    }
}
#endif
