import SwiftUI
import UIKit

/// Выполнить действие жеста (Профиль → Жесты): лайк, в очередь, следующим, переключение, удалить.
/// Каждое — с тактильным откликом и короткой плашкой, что произошло.
@MainActor
enum GestureRunner {
    /// - track: над каким треком жест (строка, мини-плеер, обложка).
    /// - remove: «Удалить» — убрать из списка, где показан (Любимые, плейлист, очередь); нет — не умеем.
    static func perform(_ action: GestureAction, track: Track?, remove: (@MainActor () -> Void)? = nil) {
        let engine = PlaybackEngine.shared
        let library = LibraryStore.shared
        // свайп сработал (смена трека, лайк, в очередь…) — лёгкий тык
        if action != .off { Haptics.tap() }
        switch action {
        case .off:
            return
        case .like:
            guard let track else { return }
            library.toggleLike(track)
            engine.message = library.isLiked(track) ? "В Любимых: «\(track.title)»" : "Убрано из Любимых"
        case .enqueue:
            guard let track else { return }
            engine.enqueue(track, next: false)
            engine.message = "В конце очереди: «\(track.title)»"
        case .play_next:
            guard let track else { return }
            engine.enqueue(track, next: true)
            engine.message = "Следующим: «\(track.title)»"
        case .next:
            engine.next()
        case .previous:
            engine.previous()
        case .delete:
            guard let remove else {
                engine.message = "Здесь удалять нечего"
                return
            }
            remove()
        }
        Haptics.tap()
    }
}

/// Горизонтальный свайп по UIKit: начинается, только если палец явно идёт вбок, — вертикальная
/// прокрутка списка не перехватывается (у `DragGesture` внутри `ScrollView` на iOS 18 бывает наоборот).
struct HorizontalPan: UIGestureRecognizerRepresentable {
    var changed: @MainActor (CGFloat) -> Void
    var ended: @MainActor (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view)
        switch recognizer.state {
        case .began, .changed:
            changed(translation.x)
        case .ended:
            ended(translation.x, translation.y)
        case .cancelled, .failed:
            ended(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.4
        }
    }
}

/// Свайп по строке трека: строка едет за пальцем, из-под неё — значок действия (цветом темы, когда
/// порог пройден, с откликом); отпустил за порогом — действие, строка возвращается пружиной.
struct TrackSwipe: ViewModifier {
    let context: GestureContext
    let track: Track
    var remove: (@MainActor () -> Void)?
    /// Своё выполнение действия (очередь переставляет, а не добавляет); нет — `GestureRunner`.
    var handle: (@MainActor (GestureAction) -> Void)?
    @Environment(SettingsStore.self) private var settings
    @State private var offset: CGFloat = 0
    @State private var armed = false

    static let threshold: CGFloat = 70

    private var leftAction: GestureAction { Gestures.action(settings, context, .left) }
    private var rightAction: GestureAction { Gestures.action(settings, context, .right) }

    @ViewBuilder
    func body(content: Content) -> some View {
        if leftAction == .off, rightAction == .off {
            content
        } else {
            content
                .offset(x: offset)
                .background {
                    HStack {
                        // палец едет вправо — из-под строки слева действие «вправо», и наоборот
                        hint(rightAction).opacity(offset > 0 ? min(1, offset / Self.threshold) : 0)
                        Spacer()
                        hint(leftAction).opacity(offset < 0 ? min(1, -offset / Self.threshold) : 0)
                    }
                    .padding(.horizontal, 18)
                }
                .gesture(HorizontalPan(changed: moved, ended: finished))
        }
    }

    private func hint(_ action: GestureAction) -> some View {
        SonarIcon(action.icon, filled: armed, size: 24)
            .foregroundStyle(armed ? Theme.accent : Theme.textSecondary)
            .scaleEffect(armed ? 1.15 : 0.9)
            .animation(Motion.spring, value: armed)
    }

    private func moved(_ dx: CGFloat) {
        let action = dx < 0 ? leftAction : rightAction
        guard action != .off else {
            offset = dx * 0.15
            return
        }
        // дальше порога строка тянется туже
        let limit = Self.threshold * 1.6
        offset = abs(dx) < Self.threshold ? dx : (dx < 0 ? -1 : 1) * min(limit, Self.threshold + (abs(dx) - Self.threshold) * 0.35)
        let nowArmed = abs(dx) >= Self.threshold
        if nowArmed != armed {
            armed = nowArmed
            if nowArmed { Haptics.select() }
        }
    }

    private func finished(_ dx: CGFloat, _ dy: CGFloat) {
        if let action = Gestures.resolve(settings, context, dx: Double(dx), dy: Double(dy)) {
            if let handle {
                handle(action)
            } else {
                GestureRunner.perform(action, track: track, remove: remove)
            }
        }
        armed = false
        withAnimation(Motion.spring) { offset = 0 }
    }
}

extension View {
    /// Жесты строки трека из настроек (`gestures.<context>.left/right`).
    func trackSwipe(_ context: GestureContext, track: Track, remove: (@MainActor () -> Void)? = nil,
                    handle: (@MainActor (GestureAction) -> Void)? = nil) -> some View {
        modifier(TrackSwipe(context: context, track: track, remove: remove, handle: handle))
    }
}
