import SwiftUI
import UIKit

/// Вид текста — из `LyricsStore` (ключи `lyrics.mode` / `size` / `style` / `animation`, SETTINGS.md,
/// общие с ПК-клиентом).
struct LyricsLook: Equatable {
    var words: Bool
    var size: LyricsSize
    var style: LyricsTextStyle
    var animation: LyricsAnimation

    @MainActor
    static func current() -> LyricsLook {
        let store = LyricsStore.shared
        return LyricsLook(words: store.mode == .words, size: store.size, style: store.style, animation: store.animation)
    }
}

/// Позиция трека между тиками плеера (они раз в 0,25 с): последняя известная + сколько прошло, если играет.
/// Нужна караоке — слова закрашиваются плавно, без ступенек.
@MainActor
@Observable
final class SmoothClock {
    private var base: Double = 0
    private var at = Date()
    private var running = false
    private var rate: Double = 1

    func sync(position: Double, playing: Bool, rate: Float) {
        base = position
        at = Date()
        running = playing
        self.rate = Double(rate)
    }

    func time(at date: Date) -> Double {
        running ? base + date.timeIntervalSince(at) * rate : base
    }
}

/// Текст песни (`IMG_6787..6790`): крупные строки слева, текущая — яркая и чёткая, остальные — тише и
/// размыты по расстоянию (формулы `LyricsMotion` = motion.ts ПК-клиента). По словам — слова текущей строки
/// закрашиваются по мере пения; в паузах — три точки. Текущая строка едет к ~40 % высоты. Тап по строке —
/// перемотка к ней; любое касание сообщает `onTouch` (полный плеер показывает кнопки).
struct LyricsView: View {
    let lyrics: Lyrics
    let offset: Double
    let look: LyricsLook
    let translation: [Int: String]
    /// Сверху и снизу — место под кнопки плеера, чтобы первая и последняя строки не прятались.
    var topInset: CGFloat = 120
    var bottomInset: CGFloat = 260
    let onSeek: @MainActor (Double) -> Void
    let onTouch: @MainActor () -> Void
    let onLineChange: @MainActor (Int?) -> Void

    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = SmoothClock()
    @State private var active: Int?
    @State private var manualUntil = Date.distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !engine.isPlaying)) { context in
            let t = clock.time(at: context.date) + offset
            let current = lyrics.synced ? LyricsClock.activeLine(lyrics.lines, at: t) : nil
            let gap = lyrics.synced && LyricsClock.isGap(lyrics.lines, at: t)
            let gapProgress = gap ? LyricsClock.gapProgress(lyrics.lines, at: t) : 0
            GeometryReader { geo in
            let width = geo.size.width
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(lyrics.lines) { line in
                            let index = line.id
                            // вступление: «• • •» над первой строкой, пока она не началась
                            if gap, current == nil, index == 0 {
                                GapDots(progress: gapProgress, time: t)
                                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                            }
                            lineView(line, index: index, current: current, t: t)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 22)
                    .frame(width: width, alignment: .leading)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
                }
                .scrollIndicators(.hidden)
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
                    // листают сами — не дёргаем к текущей строке 3 с
                    manualUntil = Date().addingTimeInterval(3)
                    onTouch()
                })
                .onChange(of: current) { _, line in
                    active = line
                    onLineChange(line)
                    guard let line, Date() > manualUntil else { return }
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.75, dampingFraction: 0.92)) {
                        proxy.scrollTo(line, anchor: UnitPoint(x: 0.5, y: LyricsMotion.anchor))
                    }
                }
                .onAppear {
                    if let current { proxy.scrollTo(current, anchor: UnitPoint(x: 0.5, y: LyricsMotion.anchor)) }
                }
            }
            }
        }
        .onAppear { clock.sync(position: engine.position, playing: engine.isPlaying, rate: engine.rate) }
        .onChange(of: engine.position) { _, position in
            clock.sync(position: position, playing: engine.isPlaying, rate: engine.rate)
        }
        .onChange(of: engine.isPlaying) { _, playing in
            clock.sync(position: engine.position, playing: playing, rate: engine.rate)
        }
    }

    @ViewBuilder
    private func lineView(_ line: LyricLine, index: Int, current: Int?, t: Double) -> some View {
        let delta = current.map { index - $0 } ?? (lyrics.synced ? index + 1 : 0)
        let m = LyricsMotion.lineLook(style: look.style, animation: look.animation, delta: delta,
                                      synced: lyrics.synced, reduced: reduceMotion)
        let isCurrent = delta == 0 && lyrics.synced
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if line.isPause, lyrics.synced {
                    // проигрыш: три точки наливаются, пока он идёт
                    GapDots(progress: isCurrent ? LyricsClock.gapProgress(lyrics.lines, at: t) : 0, time: isCurrent ? t : 0)
                } else if isCurrent, look.words {
                    karaoke(line, t: t)
                } else {
                    Text(line.text.isEmpty ? "♪" : line.text)
                        .foregroundStyle(Color.white)
                }
            }
            .font(.system(size: look.size.points, weight: .bold))
            .tracking(m.letterSpacing * look.size.points)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            if let translated = translation[line.id], !translated.isEmpty {
                Text(translated)
                    .font(.system(size: look.size.points * 0.55, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(m.opacity)
        .blur(radius: m.blur)
        .scaleEffect(m.scale, anchor: .leading)
        .rotation3DEffect(.degrees(m.rotateX), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.6)
        .rotationEffect(.degrees(m.rotateZ), anchor: .leading)
        .offset(x: m.dx, y: m.dy)
        .animation(m.bounce
            ? .spring(response: m.duration, dampingFraction: 0.62)
            : .timingCurve(0.22, 1, 0.36, 1, duration: max(0.2, m.duration)), value: delta)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.select()
            if lyrics.synced { onSeek(max(0, line.start - offset + 0.01)) }
            onTouch()
        }
    }

    /// Текущая строка по словам: спетые — белые, ещё нет — приглушённые, текущее слово — между.
    private func karaoke(_ line: LyricLine, t: Double) -> Text {
        let words = LyricsClock.words(of: line)
        let progress = LyricsClock.wordProgress(line, at: t)
        var out = Text("")
        for (i, word) in words.enumerated() {
            let p = i < progress.count ? progress[i] : 0
            let text = word.spaceAfter && i < words.count - 1 ? word.text + " " : word.text
            out = out + Text(text).foregroundStyle(Color.white.opacity(0.38 + 0.62 * p))
        }
        return out
    }
}

/// Пауза между строками: три точки наливаются по очереди и чуть дышат.
struct GapDots: View {
    let progress: Double
    /// Время трека — точки дышат волной, пока ждут строку (0 — стоят).
    var time: Double = 0

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0 ..< 3, id: \.self) { i in
                let local = min(1, max(0, progress * 3 - Double(i)))
                let breath = time > 0 ? sin(time * 3.2 - Double(i) * 0.9) : 0
                Circle()
                    .fill(Color.white.opacity(0.3 + 0.7 * local))
                    .frame(width: 15, height: 15)
                    .scaleEffect(0.85 + 0.25 * local + 0.12 * breath)
                    .offset(y: -3 * breath)
            }
        }
        .padding(.leading, 4)
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}
