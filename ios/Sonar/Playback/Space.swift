import Foundation

// Пространство 1D–16D на iPhone — зеркало ПК `windows/src/player/space.ts`: та же таблица опорных точек и тот же
// алгоритм (**менять в обоих местах**, чтобы звучало одинаково). Только числа — их гоняют XCTest; к звуку
// применяет `AudioTap` (память выделяется заранее — в звуковом потоке ничего не создаётся). Как и реверб,
// на потоке HLS не слышно.

/// Параметры пространства (одинаковые на ПК и iPhone, docs/SETTINGS.md «Пространство»).
struct SpaceParams: Equatable, Sendable {
    /// Скорость орбиты, Гц.
    var rate: Double = 0
    /// Размах по сторонам 0…1.
    var amp: Double = 0
    /// 0 — качание лево-право, 1 — полный круг.
    var circle: Double = 0
    /// Боковая часть записи (L−R): 1 — как есть.
    var side: Double = 1
    /// «Ближе-дальше» 0…1.
    var depth: Double = 0
    /// Плавание по высоте 0…1.
    var height: Double = 0
    /// Второе «эхо» с другой стороны 0…1.
    var echo: Double = 0
    /// Медленное изменение орбиты и «дыхание» объёма 0…1.
    var drift: Double = 0
    /// Подмес реверба 0…1.
    var send: Double = 0

    static let off = SpaceParams()

    /// Опорные точки — как `SPACE_TABLE` на ПК.
    static let table: [(Int, SpaceParams)] = [
        (1, SpaceParams(rate: 0, amp: 0, circle: 0, side: 1.25)),
        (2, SpaceParams(rate: 0.05, amp: 0.5, circle: 0, side: 0.8, send: 0.05)),
        (3, SpaceParams(rate: 0.08, amp: 1, circle: 1, side: 0.5, send: 0.1)),
        (8, SpaceParams(rate: 0.14, amp: 1, circle: 1, side: 0.45, depth: 0.35, send: 0.22)),
        (12, SpaceParams(rate: 0.2, amp: 1, circle: 1, side: 0.4, depth: 0.6, height: 0.5, echo: 0.22, send: 0.32)),
        (16, SpaceParams(rate: 0.26, amp: 1, circle: 1, side: 0.4, depth: 0.8, height: 0.8, echo: 0.3, drift: 1, send: 0.4)),
    ]

    static let maxD = 16
    /// Чипы в листе скорости.
    static let presets = table.map { $0.0 }
    /// Включили без выбора — классическое 8D.
    static let defaultD = 8

    /// D в пределах 0…16, целое; не число — 0.
    static func clamp(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(Double(maxD), max(0, value.rounded())))
    }

    /// D → параметры: опорная точка или линейно между соседними; 0 — выключено.
    static func of(_ d: Int) -> SpaceParams {
        let n = min(maxD, max(0, d))
        guard n > 0 else { return .off }
        for (i, (at, p)) in table.enumerated() {
            if n == at { return p }
            if i + 1 < table.count, n > at, n < table[i + 1].0 {
                let k = Double(n - at) / Double(table[i + 1].0 - at)
                let q = table[i + 1].1
                func mix(_ a: Double, _ b: Double) -> Double { ((a + (b - a) * k) * 1000).rounded() / 1000 }
                return SpaceParams(rate: mix(p.rate, q.rate), amp: mix(p.amp, q.amp), circle: mix(p.circle, q.circle),
                                   side: mix(p.side, q.side), depth: mix(p.depth, q.depth), height: mix(p.height, q.height),
                                   echo: mix(p.echo, q.echo), drift: mix(p.drift, q.drift), send: mix(p.send, q.send))
            }
        }
        return table[table.count - 1].1
    }

    /// Реверб, который звучит: свой + подмес пространства (как ПК `withSpaceReverb`).
    static func reverb(_ reverb: Double, space: Int) -> Double {
        let send = of(space).send
        return ((1 - (1 - min(1, max(0, reverb))) * (1 - send)) * 1000).rounded() / 1000
    }

    /// «8D»; выключено — пусто.
    static func label(_ d: Int) -> String { d > 0 ? "\(min(maxD, d))D" : "" }
}

/// Процессор пространства на пару каналов — построчно тот же, что AudioWorklet ПК `SPACE_WORKLET`.
final class Spatializer {
    private static let size = 16384
    private static let mask = size - 1
    private static let tau = 2 * Double.pi

    private let buffer: UnsafeMutablePointer<Float>
    private var write = 0
    private let sampleRate: Double
    private let smooth: Double
    private let lpA: Float
    private let itd: Double
    private let echoDelay: Double

    private var target = SpaceParams.off
    private var current = SpaceParams.off
    private var mixTarget = 0.0
    private(set) var mix = 0.0
    private var ph = 0.0, ph2 = 0.0, ph3 = 0.0, u = 0.0
    private var lpL: Float = 0, lpR: Float = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        smooth = 1 - exp(-1 / (0.1 * sampleRate))
        lpA = Float(1 - exp(-Self.tau * 1800 / sampleRate))
        itd = 0.00066 * sampleRate
        echoDelay = 0.023 * sampleRate
        buffer = .allocate(capacity: Self.size)
        buffer.initialize(repeating: 0, count: Self.size)
    }

    deinit { buffer.deallocate() }

    /// Нечего делать: выключено и доля обработки дошла до нуля — сигнал идёт как есть.
    var idle: Bool { mix == 0 && mixTarget == 0 }

    /// Новые настройки: включили с нуля — с чистой памятью и сразу целевыми параметрами (плавность — доля
    /// обработки); выключили — параметры прежние, затухает тот же звук.
    func set(on: Bool, params: SpaceParams) {
        if on { target = params }
        mixTarget = on ? 1 : 0
        if on, mix == 0 {
            buffer.update(repeating: 0, count: Self.size)
            lpL = 0
            lpR = 0
            current = target
        }
    }

    @inline(__always)
    private func read(_ delay: Double) -> Float {
        let pos = Double(write) - delay
        let i = Int(pos.rounded(.down))
        let f = Float(pos - Double(i))
        return buffer[i & Self.mask] * (1 - f) + buffer[(i + 1) & Self.mask] * f
    }

    /// Один кадр стерео на месте.
    @inline(__always)
    func process(_ l: inout Float, _ r: inout Float) {
        let a = smooth
        current.rate += (target.rate - current.rate) * a
        current.amp += (target.amp - current.amp) * a
        current.circle += (target.circle - current.circle) * a
        current.side += (target.side - current.side) * a
        current.depth += (target.depth - current.depth) * a
        current.height += (target.height - current.height) * a
        current.echo += (target.echo - current.echo) * a
        current.drift += (target.drift - current.drift) * a
        mix += (mixTarget - mix) * a
        if mixTarget == 0, mix < 0.0005 { mix = 0 }
        let c = current, sr = sampleRate, tau = Self.tau
        let mid = (l + r) * 0.5
        let side = (l - r) * 0.5
        buffer[write & Self.mask] = mid
        u += 0.013 / sr
        if u >= 1 { u -= 1 }
        let wobble = sin(tau * u)
        ph += c.rate * (1 + 0.3 * c.drift * wobble) / sr
        ph -= ph.rounded(.down)
        ph2 += c.rate * 0.37 / sr
        ph2 -= ph2.rounded(.down)
        ph3 += (c.rate * 0.23 + 0.02) / sr
        ph3 -= ph3.rounded(.down)
        let pan = c.amp * sin(tau * ph)
        let front = 1 - c.circle + c.circle * cos(tau * ph)
        let k = 0.85
        let gL = Float((0.5 * (1 - k * pan)).squareRoot())
        let gR = Float((0.5 * (1 + k * pan)).squareRoot())
        let xL = read(pan > 0 ? pan * itd : 0)
        let xR = read(pan < 0 ? -pan * itd : 0)
        let dist = c.depth * (0.5 + 0.5 * sin(tau * ph2))
        let tilt = c.height * sin(tau * ph3)
        let back = max(0, -front) * 0.35
        let darkL = Float(min(0.9, (pan > 0 ? 0.6 * pan : 0) + back + 0.3 * dist))
        let darkR = Float(min(0.9, (pan < 0 ? -0.6 * pan : 0) + back + 0.3 * dist))
        lpL += (xL - lpL) * lpA
        lpR += (xR - lpR) * lpA
        let bright = Float(1 + 0.6 * tilt)
        var eL = lpL + (xL - lpL) * (1 - darkL) * bright
        var eR = lpR + (xR - lpR) * (1 - darkR) * bright
        if c.echo > 0.0005 {
            let e = read(echoDelay) * Float(c.echo)
            eL += e * gR
            eR += e * gL
        }
        let norm = 1 / (1 + c.echo * c.echo).squareRoot()
        let gd = Float((1 - 0.3 * dist + 0.15 * c.depth) * norm * 2.0.squareRoot())
        let sg = Float(c.side * (1 + 0.25 * c.drift * sin(tau * ph2 * 0.5 + 1)))
        let wL = gL * eL * gd + side * sg
        let wR = gR * eR * gd - side * sg
        let m = Float(mix)
        l += (wL - l) * m
        r += (wR - r) * m
        write = (write + 1) & Self.mask
    }
}
