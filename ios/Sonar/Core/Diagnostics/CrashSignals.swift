import Foundation
#if canImport(Darwin)
import Darwin
import MachO
#endif

// Ловля сбоев: необработанное исключение Objective-C (`NSSetUncaughtExceptionHandler`) и сигналы
// SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP (Swift-ловушки — `fatalError`, `!` на nil,
// выход за массив — приходят как SIGTRAP). Формат маркера — `CrashMarker.swift`.
//
// В обработчике сигнала можно только async-signal-safe: никаких Swift-строк, массивов, Foundation,
// malloc и блокировок. Поэтому файл открыт заранее (`markerFD`), буферы выделены заранее, строки —
// `StaticString`, числа печатаются своим кодом; стек — `backtrace()` голыми адресами (имена ищем при
// следующем запуске через `dladdr`, `CrashStack`). Обработчик идёт на отдельном стеке (`sigaltstack`),
// чтобы переполнение стека тоже записалось. После записи возвращаем прежний обработчик и повторяем
// сигнал — сбой доходит до iOS (и MetricKit) как обычно.

enum CrashSignals {
    #if canImport(Darwin)
    static let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
    #endif

    /// Открыть маркер и поставить обработчики. Повторный вызов ничего не делает.
    static func install(markerPath: String) {
        #if canImport(Darwin)
        guard crashFD < 0 else { return }
        let fd = open(markerPath, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        crashFD = fd
        // глобальные переменные Swift создаются лениво (swift_once + malloc) — создаём их здесь,
        // а не при первом обращении из обработчика сигнала
        frameBuffer.initialize(repeating: nil, count: 128)
        numberBuffer.initialize(repeating: 0, count: 24)
        handlingSignal = 0

        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(sonarExceptionHandler)

        // отдельный стек для обработчика (переполнение стека — тоже SIGSEGV)
        let altSize = 64 * 1024
        if let altStack = malloc(altSize) {
            var stack = stack_t(ss_sp: altStack, ss_size: altSize, ss_flags: 0)
            sigaltstack(&stack, nil)
        }
        for signal in signals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = sonarSignalHandler
            action.sa_flags = SA_ONSTACK
            sigemptyset(&action.sa_mask)
            sigaction(signal, &action, previousActions.advanced(by: Int(signal)))
        }
        #endif
    }

    /// Сегмент `__TEXT` приложения в этом запуске — для разбора адресов стека в следующем.
    static func imageRange() -> (start: UInt64, end: UInt64)? {
        #if canImport(Darwin)
        guard let header = _dyld_get_image_header(0) else { return nil }
        var size: UInt = 0
        let start = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) { getsegmentdata($0, "__TEXT", &size) }
        guard start != nil, size > 0 else { return nil }
        let base = UInt64(UInt(bitPattern: header))
        return (base, base + UInt64(size))
        #else
        return nil
        #endif
    }

    /// Имя по адресу этого запуска: `libswiftCore.dylib swift_retain + 12`.
    static func symbol(_ address: UInt64) -> String? {
        #if canImport(Darwin)
        guard let pointer = UnsafeRawPointer(bitPattern: UInt(address)) else { return nil }
        var info = Dl_info()
        guard dladdr(pointer, &info) != 0 else { return nil }
        let image = info.dli_fname.map { String(cString: $0) }.map { ($0 as NSString).lastPathComponent } ?? "?"
        guard let name = info.dli_sname else { return image }
        let offset = info.dli_saddr.map { address &- UInt64(UInt(bitPattern: $0)) } ?? 0
        return "\(image) \(String(cString: name)) + \(offset)"
        #else
        return nil
        #endif
    }
}

#if canImport(Darwin)
// Глобальное состояние обработчиков: пишется один раз при установке, читается в обработчике.
nonisolated(unsafe) private var crashFD: Int32 = -1
nonisolated(unsafe) private var previousExceptionHandler: (@convention(c) (NSException) -> Void)?
nonisolated(unsafe) private let previousActions = UnsafeMutablePointer<sigaction>.allocate(capacity: 64)
nonisolated(unsafe) private let frameBuffer = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 128)
nonisolated(unsafe) private let numberBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 24)
nonisolated(unsafe) private var handlingSignal: sig_atomic_t = 0

/// Исключение Objective-C: обычный контекст, Foundation можно. Дальше `abort()` → SIGABRT.
private func sonarExceptionHandler(_ exception: NSException) {
    if crashFD >= 0 {
        let block = CrashMarker.exceptionBlock(name: exception.name.rawValue, reason: exception.reason,
                                               symbols: exception.callStackSymbols)
        block.utf8CString.withUnsafeBufferPointer { buffer in
            _ = write(crashFD, buffer.baseAddress, max(0, buffer.count - 1))
        }
    }
    previousExceptionHandler?(exception)
}

private func put(_ text: StaticString) {
    _ = write(crashFD, text.utf8Start, text.utf8CodeUnitCount)
}

/// Число в десятичной записи без malloc.
private func putDecimal(_ value: Int64) {
    var v = value < 0 ? UInt64(bitPattern: -value) : UInt64(value)
    var i = 23
    repeat {
        numberBuffer[i] = 48 + UInt8(v % 10)
        v /= 10
        i -= 1
    } while v > 0 && i > 0
    if value < 0 { numberBuffer[i] = 45; i -= 1 }
    _ = write(crashFD, numberBuffer.advanced(by: i + 1), 23 - i)
}

/// Адрес `0x…` без malloc.
private func putHex(_ value: UInt) {
    let digits: StaticString = "0123456789abcdef"
    var v = value
    var i = 23
    repeat {
        numberBuffer[i] = digits.utf8Start[Int(v & 0xf)]
        v >>= 4
        i -= 1
    } while v > 0 && i > 1
    numberBuffer[i] = 120 // x
    numberBuffer[i - 1] = 48 // 0
    _ = write(crashFD, numberBuffer.advanced(by: i - 1), 25 - i)
}

private func sonarSignalHandler(_ signal: Int32) {
    // сбой внутри обработчика — не пишем второй раз
    if handlingSignal == 0, crashFD >= 0 {
        handlingSignal = 1
        put("signal "); putDecimal(Int64(signal)); put("\n")
        put("time "); putDecimal(Int64(time(nil))); put("\n")
        put("frames\n")
        let count = backtrace(frameBuffer, 128)
        for index in 0..<Int(max(0, count)) {
            putHex(UInt(bitPattern: frameBuffer[index]))
            put("\n")
        }
        put("end\n")
        fsync(crashFD)
    }
    // прежний обработчик (по умолчанию — завершение) и тот же сигнал ещё раз
    sigaction(signal, previousActions.advanced(by: Int(signal)), nil)
    raise(signal)
}
#endif
