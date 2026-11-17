import SwiftUI
import UIKit

/// Герой «Моей волны» — SonarField, поле точек: сетка кружков, размер каждого — яркость
/// фигуры в этом месте. Фигуры по кругу перетекают друг в друга: знак Sonar → шар со светом → две волны.
/// Сами по себе точки всё время чуть плывут и дышат размером; когда играет музыка — сильнее и с бегущей
/// рябью. Цвет — акцент темы (под обложку). Касание — фигура целиком пружинит, как желе (сжалась,
/// качнулась к пальцу, успокоилась) и лёгкий тактильный отклик; долгое нажатие — лист настроений волны (`onHold`). Рисует Canvas одним путём, ~1800 точек, 30 кадров/с; вне экрана — пауза.
struct SonarField: View {
    var active: Bool
    var playing: Bool
    var color: Color
    /// Шаг сетки, pt.
    var step: CGFloat = 8
    var onHold: (@MainActor () -> Void)?

    /// Касание: где и когда.
    struct Poke: Sendable {
        let point: CGPoint
        let time: TimeInterval
        /// Какой эффект: по кругу — волна-разлёт, вихрь, подскок.
        var kind = 0
    }

    /// Сколько шевелятся точки после касания, с.
    static let pokeLife = 1.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size: CGSize = .zero
    @State private var logo: [Float] = []
    @State private var pokes: [Poke] = []
    @State private var kindCounter = -1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let logo = self.logo, playing = self.playing, color = self.color, step = self.step
            let pokes = self.pokes.filter { t - $0.time < Self.pokeLife }
            Canvas { gc, canvas in
                let grid = FieldGrid(size: canvas, step: step)
                guard grid.cols > 0, grid.rows > 0 else { return }
                var dots = Path()
                let maxR = Double(step) * 0.5
                for row in 0 ..< grid.rows {
                    for col in 0 ..< grid.cols {
                        var c = grid.center(col: col, row: row)
                        var v = Self.value(col: col, row: row, grid: grid, logo: logo, t: t, playing: playing)
                        // сами по себе: медленное течение и лёгкое дыхание каждой точки
                        let drift = Self.drift(col: col, row: row, t: t)
                        c.x += drift.dx
                        c.y += drift.dy
                        v *= drift.scale
                        for poke in pokes {
                            let fx = Self.play(poke, at: c, t: t)
                            c.x += fx.dx
                            c.y += fx.dy
                            v = min(1, v * fx.scale)
                        }
                        let r = maxR * v
                        if r < 0.45 { continue }
                        dots.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    }
                }
                gc.fill(dots, with: .color(color))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { point in
            poke(at: point)
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onHold?()
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { new in
            guard new != size else { return }
            size = new
            logo = Self.logoMask(FieldGrid(size: new, step: step))
        }
        .accessibilityHidden(true)
    }

    private func poke(at point: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        kindCounter += 1
        pokes = pokes.filter { now - $0.time < Self.pokeLife } + [Poke(point: point, time: now, kind: kindCounter % 3)]
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }

    /// Течение без касаний: каждая точка плавает на ~1.5 pt по своей медленной синусоиде, соседние —
    /// почти в такт (видно как мягкое волнение), и чуть меняет размер.
    static func drift(col: Int, row: Int, t: TimeInterval) -> (dx: CGFloat, dy: CGFloat, scale: Double) {
        let c = Double(col), r = Double(row)
        let dx = 1.5 * sin(t * 0.9 + r * 0.32 + c * 0.07)
        let dy = 1.5 * cos(t * 0.75 + c * 0.28 - r * 0.05)
        let scale = 0.9 + 0.1 * sin(t * 1.1 + c * 0.45 + r * 0.6)
        return (CGFloat(dx), CGFloat(dy), scale)
    }

    /// Игра от касания — волна идёт от пальца через всю фигуру (не продавливает точку под ним):
    /// 0 — точки разлетаются кольцом и пружиной собираются обратно; 1 — вихрь, фигура закручивается
    /// вокруг пальца и раскручивается; 2 — подскок: точки по очереди прыгают вверх и надуваются.
    static func play(_ poke: Poke, at c: CGPoint, t: TimeInterval) -> (dx: CGFloat, dy: CGFloat, scale: Double) {
        let age = t - poke.time
        guard age >= 0, age < pokeLife else { return (0, 0, 1) }
        let vx = Double(c.x - poke.point.x), vy = Double(c.y - poke.point.y)
        let d = max(1, (vx * vx + vy * vy).squareRoot())
        let ux = vx / d, uy = vy / d
        // фронт волны уходит от пальца со скоростью ~420 pt/с; точка «оживает», когда он до неё дошёл
        let local = age - d / 420
        guard local > 0 else { return (0, 0, 1) }
        let env = exp(-local * 4.5) * exp(-d / 520)
        switch poke.kind {
        case 1:
            let angle = 0.5 * sin(local * 9) * env * min(1, 60 / d + 0.25)
            let ca = cos(angle), sa = sin(angle)
            let rx = vx * ca - vy * sa, ry = vx * sa + vy * ca
            return (CGFloat(rx - vx), CGFloat(ry - vy), 1 + 0.25 * abs(sin(local * 9)) * env)
        case 2:
            let hop = abs(sin(local * 10)) * env
            return (0, CGFloat(-10 * hop), 1 + 0.45 * hop)
        default:
            let push = 14 * sin(local * 12) * env
            return (CGFloat(ux * push), CGFloat(uy * push), 1 + 0.35 * max(0, sin(local * 12)) * env)
        }
    }

    // MARK: - Фигуры

    /// Яркость точки 0…1: смесь текущей и следующей фигуры, дыхание, рябь.
    static func value(col: Int, row: Int, grid: FieldGrid, logo: [Float], t: Double, playing: Bool) -> Double {
        let hold = 6.5, morph = 2.5, period = hold + morph
        let shapes = 3
        let phase = t.truncatingRemainder(dividingBy: period * Double(shapes))
        let index = Int(phase / period)
        let local = phase - Double(index) * period
        let k = local < hold ? 0 : smooth((local - hold) / morph)

        // нормированные координаты: центр 0, по высоте −1…1
        let x = (Double(col) + 0.5 - Double(grid.cols) / 2) / (Double(grid.rows) / 2)
        let y = (Double(row) + 0.5 - Double(grid.rows) / 2) / (Double(grid.rows) / 2)
        let halfW = Double(grid.cols) / Double(grid.rows)

        func shape(_ i: Int) -> Double {
            switch i % shapes {
            case 0: return logoValue(col: col, row: row, grid: grid, logo: logo, x: x, y: y, t: t)
            case 1: return orb(x: x, y: y, t: t)
            default: return waves(x: x, y: y, halfW: halfW, t: t)
            }
        }
        var v = k == 0 ? shape(index) : shape(index) * (1 - k) + shape(index + 1) * k

        // дыхание и рябь от центра
        let breath = playing ? 0.12 : 0.05
        v *= 1 + breath * sin(t * (playing ? 3.2 : 1.4))
        if playing {
            let d = (x * x + y * y).squareRoot()
            v *= 0.86 + 0.14 * sin(d * 7 - t * 4.5)
        }
        // края поля растворяются
        let ex = max(0, 1 - pow(abs(x) / halfW, 6))
        let ey = max(0, 1 - pow(abs(y), 6))
        return min(1, max(0, v * ex * ey))
    }

    /// Знак Sonar с бегущим бликом.
    private static func logoValue(col: Int, row: Int, grid: FieldGrid, logo: [Float], x: Double, y: Double, t: Double) -> Double {
        let i = row * grid.cols + col
        guard i < logo.count else { return 0 }
        let m = Double(logo[i])
        let sheen = 0.8 + 0.2 * sin(x * 2.2 + y * 1.4 - t * 1.6)
        return m * sheen
    }

    /// Шар со светом, который ходит по кругу (объём — как полутоновая печать).
    private static func orb(x: Double, y: Double, t: Double) -> Double {
        let cx = 0.12 * sin(t * 0.35)
        let cy = 0.05 * cos(t * 0.5)
        let radius = 0.82
        let dx = (x - cx) / radius, dy = (y - cy) / radius
        let d2 = dx * dx + dy * dy
        guard d2 < 1 else { return 0 }
        let nz = (1 - d2).squareRoot()
        let lx = cos(t * 0.6) * 0.6, ly = sin(t * 0.6) * 0.45 - 0.35, lz = 0.7
        let len = (lx * lx + ly * ly + lz * lz).squareRoot()
        let light = max(0, (dx * lx + dy * ly + nz * lz) / len)
        let rim = smooth(min(1, (1 - d2) * 6))
        return (0.18 + 0.82 * light) * rim
    }

    /// Две волны-ленты, тоньше к краям.
    private static func waves(x: Double, y: Double, halfW: Double, t: Double) -> Double {
        let taper = max(0, cos(x / halfW * .pi / 2))
        func band(amp: Double, freq: Double, speed: Double, shift: Double, width: Double) -> Double {
            let center = amp * sin(x * freq + t * speed + shift) + 0.18 * sin(x * freq * 2.3 - t * speed * 0.7)
            let thick = width * (0.7 + 0.3 * sin(x * 1.3 - t * 0.9 + shift)) * taper.squareRoot()
            guard thick > 0.01 else { return 0 }
            let d = abs(y - center) / thick
            return d < 1 ? smooth(1 - d).squareRoot() : 0
        }
        let a = band(amp: 0.26, freq: 1.5, speed: 1.1, shift: 0, width: 0.5)
        let b = band(amp: 0.2, freq: 2.0, speed: -0.8, shift: 1.9, width: 0.34) * 0.8
        return max(a, b)
    }

    private static func smooth(_ v: Double) -> Double {
        let x = min(1, max(0, v))
        return x * x * (3 - 2 * x)
    }

    /// Маска знака: точка внутри — 1, края смягчены размытием.
    static func logoMask(_ grid: FieldGrid) -> [Float] {
        guard grid.cols > 0, grid.rows > 0 else { return [] }
        let side = min(grid.size.width, grid.size.height) * 0.92
        let rect = CGRect(x: (grid.size.width - side) / 2, y: (grid.size.height - side) / 2, width: side, height: side)
        let path = IconShape(name: .logo).path(in: rect)
        var mask = [Float](repeating: 0, count: grid.cols * grid.rows)
        for row in 0 ..< grid.rows {
            for col in 0 ..< grid.cols {
                let c = grid.center(col: col, row: row)
                // 4 пробы на клетку — тонкие хвосты знака не теряются
                var hit: Float = 0
                for (ox, oy) in [(-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25)] {
                    let p = CGPoint(x: c.x + grid.step * ox, y: c.y + grid.step * oy)
                    if path.contains(p, eoFill: true) { hit += 0.25 }
                }
                mask[row * grid.cols + col] = hit
            }
        }
        // лёгкое размытие 3×3 — мягкий край, как у полутона
        var blurred = mask
        for row in 0 ..< grid.rows {
            for col in 0 ..< grid.cols {
                var sum: Float = 0
                var n: Float = 0
                for dy in -1 ... 1 {
                    for dx in -1 ... 1 {
                        let r = row + dy, c = col + dx
                        guard r >= 0, r < grid.rows, c >= 0, c < grid.cols else { continue }
                        let w: Float = (dx == 0 && dy == 0) ? 4 : 1
                        sum += mask[r * grid.cols + c] * w
                        n += w
                    }
                }
                blurred[row * grid.cols + col] = min(1, sum / n * 1.25)
            }
        }
        return blurred
    }
}

/// Сетка точек по центру области.
struct FieldGrid {
    let size: CGSize
    let step: CGFloat
    let cols: Int
    let rows: Int
    let origin: CGPoint

    init(size: CGSize, step: CGFloat) {
        self.size = size
        self.step = step
        cols = max(0, Int(size.width / step))
        rows = max(0, Int(size.height / step))
        origin = CGPoint(x: (size.width - CGFloat(cols) * step) / 2, y: (size.height - CGFloat(rows) * step) / 2)
    }

    func center(col: Int, row: Int) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(col) + 0.5) * step, y: origin.y + (CGFloat(row) + 0.5) * step)
    }
}
