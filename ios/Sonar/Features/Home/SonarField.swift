import Combine
import SwiftUI
import UIKit

/// Герой Sonar Mix — SonarField, поле точек: сетка кружков, размер каждого — яркость
/// фигуры в этом месте. Фигуры по кругу перетекают друг в друга: знак Sonar → шар со светом → две волны.
/// Сами по себе точки всё время чуть плывут и дышат размером; когда играет музыка — сильнее и с бегущей
/// рябью. Цвет — акцент темы (под обложку). Касание — фигура целиком пружинит, как желе (сжалась,
/// качнулась к пальцу, успокоилась) и лёгкий тактильный отклик. Настроения — своей шестерёнкой рядом с
/// заголовком (долгое нажатие на поле убрано 2026-11-22: из-за него тап ждал, не долгое ли это нажатие, и
/// поле откликалось с задержкой). Рисует Canvas одним путём в фоне (`rendersAsynchronously` — кадр не ждёт
/// главный поток), ~1800 точек, 30 кадров/с (во время касания — 60, в режиме энергосбережения и когда
/// приложение не на переднем плане — 15); вне экрана — пауза.
/// Всё «на кадр» (фигуры, течение) — `FieldFrame`, на точку остаётся только сложение таблиц.
struct SonarField: View {
    var active: Bool
    var playing: Bool
    var color: Color
    /// Шаг сетки, pt.
    var step: CGFloat = 8

    /// Касание: где и когда.
    struct Poke: Sendable {
        let point: CGPoint
        let time: TimeInterval
        /// Какой эффект: по кругу — волна-разлёт, вихрь, подскок.
        var kind = 0
    }

    /// Сколько шевелятся точки после касания, с.
    nonisolated static let pokeLife = 1.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var size: CGSize = .zero
    @State private var logo: [Float] = []
    @State private var pokes: [Poke] = []
    @State private var kindCounter = -1

    var body: some View {
        let interval = Self.frameInterval(poking: !pokes.isEmpty, lowPower: lowPower, sceneActive: scenePhase == .active)
        TimelineView(.animation(minimumInterval: interval, paused: !active || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let logo = self.logo, playing = self.playing, color = self.color, step = self.step
            let pokes = self.pokes.filter { t - $0.time < Self.pokeLife }
            // @Sendable: в фоне Canvas зовёт рисование не из главного потока — внутри только nonisolated
            Canvas(rendersAsynchronously: true) { @Sendable gc, canvas in
                let grid = FieldGrid(size: canvas, step: step)
                guard grid.cols > 0, grid.rows > 0 else { return }
                let frame = FieldFrame(grid: grid, t: t, playing: playing)
                let maxR = Double(step) * 0.5
                // точка, которую даже все касания разом не надуют до видимой, — пропускается сразу
                let cutoff = Self.minRadius / maxR / pow(Self.pokeMaxScale, Double(pokes.count))
                var dots = Path()
                for row in 0 ..< grid.rows {
                    for col in 0 ..< grid.cols {
                        var v = frame.value(col: col, row: row, logo: logo)
                        if v < cutoff { continue }
                        var c = grid.center(col: col, row: row)
                        // сами по себе: медленное течение и лёгкое дыхание каждой точки
                        let drift = frame.drift(col: col, row: row)
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
                        if r < Self.minRadius { continue }
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { new in
            guard new != size else { return }
            size = new
            logo = Self.logoMask(FieldGrid(size: new, step: step))
        }
        .onAppear { Haptics.prepareNudge() }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        // последнее касание отыграло — убрать его, поле вернётся к спокойным 30 кадрам/с
        .task(id: kindCounter) {
            guard !pokes.isEmpty else { return }
            try? await Task.sleep(for: .seconds(Self.pokeLife))
            guard !Task.isCancelled else { return }
            let now = Date().timeIntervalSinceReferenceDate
            pokes = pokes.filter { now - $0.time < Self.pokeLife }
        }
        .accessibilityHidden(true)
    }

    /// Кадр без касаний и во время игры касания, с.
    static let calmInterval: TimeInterval = 1 / 30
    static let pokeInterval: TimeInterval = 1 / 60
    /// Энергосбережение или приложение не на переднем плане — поле живёт, но реже.
    static let saverInterval: TimeInterval = 1 / 15

    /// Шаг кадра. Пока играет касание — 60 кадров/с: точки разлетаются быстро, на 30 это видно как рывки.
    /// Энергосбережение и неактивная сцена важнее касания — батарея дороже плавности.
    static func frameInterval(poking: Bool, lowPower: Bool, sceneActive: Bool) -> TimeInterval {
        if lowPower || !sceneActive { return saverInterval }
        return poking ? pokeInterval : calmInterval
    }
    /// Меньше этого радиуса точка не рисуется, pt.
    nonisolated static let minRadius = 0.45
    /// Сильнее всего касание надувает точку (подскок) — граница для пропуска пустых точек.
    nonisolated static let pokeMaxScale = 1.45
    /// Сколько касаний играют разом: частые тычки не копят работу на кадр.
    static let maxPokes = 4

    private func poke(at point: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        kindCounter += 1
        pokes = Self.addPoke(Poke(point: point, time: now, kind: kindCounter % 3), to: pokes, now: now)
        Haptics.nudge()
    }

    /// Новое касание к живым: отжившие выпадают, живых не больше `maxPokes` (самые старые уходят).
    static func addPoke(_ poke: Poke, to pokes: [Poke], now: TimeInterval) -> [Poke] {
        let alive = pokes.filter { now - $0.time < pokeLife }
        return Array((alive + [poke]).suffix(maxPokes))
    }

    /// Течение без касаний: каждая точка плавает на ~1.5 pt по своей медленной синусоиде, соседние —
    /// почти в такт (видно как мягкое волнение), и чуть меняет размер. Формула-образец: в кадре она
    /// считается таблицами (`FieldFrame.drift`), тест сверяет их с ней.
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
    nonisolated static func play(_ poke: Poke, at c: CGPoint, t: TimeInterval) -> (dx: CGFloat, dy: CGFloat, scale: Double) {
        let age = t - poke.time
        guard age >= 0, age < pokeLife else { return (0, 0, 1) }
        let vx = Double(c.x - poke.point.x), vy = Double(c.y - poke.point.y)
        let d = max(1, (vx * vx + vy * vy).squareRoot())
        // фронт волны уходит от пальца со скоростью ~420 pt/с; точка «оживает», когда он до неё дошёл
        let local = age - d / 420
        guard local > 0 else { return (0, 0, 1) }
        let env = exp(-(local * 4.5 + d / 520))
        // затухшая волна (меньше сотой пункта сдвига) — не тратим на неё синусы
        guard env > 0.0007 else { return (0, 0, 1) }
        switch poke.kind {
        case 1:
            let wave = sin(local * 9)
            let angle = 0.5 * wave * env * min(1, 60 / d + 0.25)
            let ca = cos(angle), sa = sin(angle)
            let rx = vx * ca - vy * sa, ry = vx * sa + vy * ca
            return (CGFloat(rx - vx), CGFloat(ry - vy), 1 + 0.25 * abs(wave) * env)
        case 2:
            let hop = abs(sin(local * 10)) * env
            return (0, CGFloat(-10 * hop), 1 + 0.45 * hop)
        default:
            let wave = sin(local * 12)
            let push = 14 * wave * env
            return (CGFloat(vx / d * push), CGFloat(vy / d * push), 1 + 0.35 * max(0, wave) * env)
        }
    }

    // MARK: - Знак

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
