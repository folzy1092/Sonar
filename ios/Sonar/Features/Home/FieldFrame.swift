import Foundation

/// Кадр SonarField: всё, что зависит только от времени, строки или столбца, считается здесь раз на кадр,
/// а не для каждой из ~1800 точек. Раньше каждая точка звала по 6–10 синусов — на iPhone это и был
/// рывок, особенно на касании (поверх добавлялась игра касания). Течение точек — сумма «строка + столбец»
/// под синусом, поэтому раскладывается по формуле суммы углов на таблицы строк и столбцов.
struct FieldFrame {
    let grid: FieldGrid
    let t: Double
    let playing: Bool

    /// Текущая фигура (0 — знак, 1 — шар, 2 — волны) и доля перетекания в следующую.
    let index: Int
    let k: Double
    private let breath: Double
    /// Нормированные координаты точек: центр 0, по высоте −1…1.
    private let xs: [Double]
    private let ys: [Double]
    /// Края поля растворяются — множители по столбцу и строке.
    private let edgeX: [Double]
    private let edgeY: [Double]
    /// Блик знака: sin(x·2.2 − t·1.6 + y·1.4).
    private let sheenCol: SinCos
    private let sheenRow: SinCos
    private let orb: Orb
    /// Волны зависят только от столбца — центры и толщины лент на кадр.
    private let bands: [Bands]
    /// Течение: dx = 1.5·sin(row + col), dy = 1.5·cos(col + row), размер = 0.9 + 0.1·sin(col + row).
    private let dxRow: SinCos, dxCol: SinCos
    private let dyRow: SinCos, dyCol: SinCos
    private let scRow: SinCos, scCol: SinCos

    static let shapes = 3
    static let hold = 6.5
    static let morph = 2.5

    init(grid: FieldGrid, t: Double, playing: Bool) {
        self.grid = grid
        self.t = t
        self.playing = playing
        let period = Self.hold + Self.morph
        let phase = t.truncatingRemainder(dividingBy: period * Double(Self.shapes))
        let index = Int(phase / period)
        let local = phase - Double(index) * period
        self.index = index
        k = local < Self.hold ? 0 : Self.smooth((local - Self.hold) / Self.morph)
        breath = 1 + (playing ? 0.12 : 0.05) * sin(t * (playing ? 3.2 : 1.4))

        let rows = Double(grid.rows), cols = Double(grid.cols)
        let xs = (0 ..< grid.cols).map { (Double($0) + 0.5 - cols / 2) / (rows / 2) }
        let ys = (0 ..< grid.rows).map { (Double($0) + 0.5 - rows / 2) / (rows / 2) }
        let halfW = cols / rows
        self.xs = xs
        self.ys = ys
        edgeX = xs.map { max(0, 1 - pow(abs($0) / halfW, 6)) }
        edgeY = ys.map { max(0, 1 - pow(abs($0), 6)) }
        sheenCol = SinCos(xs.map { $0 * 2.2 - t * 1.6 })
        sheenRow = SinCos(ys.map { $0 * 1.4 })
        orb = Orb(t: t)
        let needsWaves = index == 2 || (k > 0 && (index + 1) % Self.shapes == 2)
        bands = needsWaves ? xs.map { Bands(x: $0, halfW: halfW, t: t) } : []

        let colIdx = (0 ..< grid.cols).map(Double.init), rowIdx = (0 ..< grid.rows).map(Double.init)
        dxRow = SinCos(rowIdx.map { t * 0.9 + $0 * 0.32 })
        dxCol = SinCos(colIdx.map { $0 * 0.07 })
        dyRow = SinCos(rowIdx.map { -$0 * 0.05 })
        dyCol = SinCos(colIdx.map { t * 0.75 + $0 * 0.28 })
        scRow = SinCos(rowIdx.map { $0 * 0.6 })
        scCol = SinCos(colIdx.map { t * 1.1 + $0 * 0.45 })
    }

    /// Яркость точки 0…1: смесь текущей и следующей фигуры, дыхание, рябь.
    func value(col: Int, row: Int, logo: [Float]) -> Double {
        let current = shape(index, col: col, row: row, logo: logo)
        var v = k == 0 ? current : current * (1 - k) + shape(index + 1, col: col, row: row, logo: logo) * k
        if v <= 0 { return 0 }
        v *= breath
        if playing {
            let x = xs[col], y = ys[row]
            v *= 0.86 + 0.14 * sin((x * x + y * y).squareRoot() * 7 - t * 4.5)
        }
        return min(1, max(0, v * edgeX[col] * edgeY[row]))
    }

    /// Течение точки без касаний — то же, что `SonarField.drift`, но без синусов на точку.
    func drift(col: Int, row: Int) -> (dx: CGFloat, dy: CGFloat, scale: Double) {
        let dx = 1.5 * (dxRow.sin[row] * dxCol.cos[col] + dxRow.cos[row] * dxCol.sin[col])
        let dy = 1.5 * (dyCol.cos[col] * dyRow.cos[row] - dyCol.sin[col] * dyRow.sin[row])
        let scale = 0.9 + 0.1 * (scCol.sin[col] * scRow.cos[row] + scCol.cos[col] * scRow.sin[row])
        return (CGFloat(dx), CGFloat(dy), scale)
    }

    private func shape(_ i: Int, col: Int, row: Int, logo: [Float]) -> Double {
        switch i % Self.shapes {
        case 0:
            let at = row * grid.cols + col
            guard at < logo.count, logo[at] > 0 else { return 0 }
            let sheen = sheenCol.sin[col] * sheenRow.cos[row] + sheenCol.cos[col] * sheenRow.sin[row]
            return Double(logo[at]) * (0.8 + 0.2 * sheen)
        case 1:
            return orb.value(x: xs[col], y: ys[row])
        default:
            return bands.isEmpty ? 0 : bands[col].value(y: ys[row])
        }
    }

    static func smooth(_ v: Double) -> Double {
        let x = min(1, max(0, v))
        return x * x * (3 - 2 * x)
    }
}

/// Синусы и косинусы набора углов — таблица на кадр.
struct SinCos {
    let sin: [Double]
    let cos: [Double]

    init(_ angles: [Double]) {
        sin = angles.map { Foundation.sin($0) }
        cos = angles.map { Foundation.cos($0) }
    }
}

/// Шар со светом, который ходит по кругу (объём — как полутоновая печать). Свет и центр — на кадр.
private struct Orb {
    let cx, cy, lx, ly, lz: Double
    static let radius = 0.82

    init(t: Double) {
        cx = 0.12 * sin(t * 0.35)
        cy = 0.05 * cos(t * 0.5)
        let x = cos(t * 0.6) * 0.6, y = sin(t * 0.6) * 0.45 - 0.35, z = 0.7
        let len = (x * x + y * y + z * z).squareRoot()
        lx = x / len
        ly = y / len
        lz = z / len
    }

    func value(x: Double, y: Double) -> Double {
        let dx = (x - cx) / Self.radius, dy = (y - cy) / Self.radius
        let d2 = dx * dx + dy * dy
        guard d2 < 1 else { return 0 }
        let light = max(0, dx * lx + dy * ly + (1 - d2).squareRoot() * lz)
        let rim = FieldFrame.smooth(min(1, (1 - d2) * 6))
        return (0.18 + 0.82 * light) * rim
    }
}

/// Две волны-ленты в одном столбце, тоньше к краям.
private struct Bands {
    let centerA, thickA, centerB, thickB: Double

    init(x: Double, halfW: Double, t: Double) {
        let taper = max(0, cos(x / halfW * .pi / 2)).squareRoot()
        func center(amp: Double, freq: Double, speed: Double, shift: Double) -> Double {
            amp * sin(x * freq + t * speed + shift) + 0.18 * sin(x * freq * 2.3 - t * speed * 0.7)
        }
        func thick(width: Double, shift: Double) -> Double {
            width * (0.7 + 0.3 * sin(x * 1.3 - t * 0.9 + shift)) * taper
        }
        centerA = center(amp: 0.26, freq: 1.5, speed: 1.1, shift: 0)
        thickA = thick(width: 0.5, shift: 0)
        centerB = center(amp: 0.2, freq: 2.0, speed: -0.8, shift: 1.9)
        thickB = thick(width: 0.34, shift: 1.9)
    }

    func value(y: Double) -> Double {
        max(Self.band(y: y, center: centerA, thick: thickA), Self.band(y: y, center: centerB, thick: thickB) * 0.8)
    }

    private static func band(y: Double, center: Double, thick: Double) -> Double {
        guard thick > 0.01 else { return 0 }
        let d = abs(y - center) / thick
        return d < 1 ? FieldFrame.smooth(1 - d).squareRoot() : 0
    }
}
