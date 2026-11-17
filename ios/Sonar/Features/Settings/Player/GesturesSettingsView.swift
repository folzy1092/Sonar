import SwiftUI

/// Профиль → Жесты (`photo_18..20`, SETTINGS.md «Жесты»): четыре места × свайп влево и вправо и тапы по
/// обложке полного плеера; действие выбирается в нижнем листе, в каждом месте — только то, что там имеет
/// смысл (`GestureContext.allowed`). Применяются сразу: строки треков (`TrackRow`), очередь, мини-плеер,
/// обложка плеера.
struct GesturesSettingsView: View {
    private enum Slot: Identifiable, Hashable {
        case swipe(GestureContext, SwipeDirection)
        case tap(CoverTap)

        var id: String {
            switch self {
            case let .swipe(context, direction): Gestures.key(context, direction)
            case let .tap(tap): Gestures.key(tap)
            }
        }

        var key: String { id }

        var title: String {
            switch self {
            case let .swipe(context, direction): "\(context.title): \(direction.title.lowercased())"
            case let .tap(tap): "Обложка: \(tap.title.lowercased())"
            }
        }

        var allowed: [GestureAction] {
            switch self {
            case let .swipe(context, _): context.allowed
            case .tap: CoverTap.allowed
            }
        }
    }

    @Environment(SettingsStore.self) private var settings
    @State private var picker: Slot?

    private func action(_ slot: Slot) -> GestureAction {
        switch slot {
        case let .swipe(context, direction): Gestures.action(settings, context, direction)
        case let .tap(tap): Gestures.action(settings, tap)
        }
    }

    var body: some View {
        PlayerSettingsPage(title: "Жесты") {
            ForEach(Array(GestureContext.allCases.enumerated()), id: \.element) { index, context in
                PlayerCard(title: context.title, footer: context.subtitle) {
                    ForEach(SwipeDirection.allCases, id: \.self) { direction in
                        if direction == .right { PlayerRowDivider() }
                        row(.swipe(context, direction), label: direction.title, gestureIcon: direction.icon)
                    }
                }
                .cascade(index)
            }

            PlayerCard(title: "Обложка плеера", footer: "Двойной тап ставит лайк с большим сердцем; тройной выключен — двойной срабатывает без ожидания") {
                ForEach(CoverTap.allCases, id: \.self) { tap in
                    if tap == .triple_tap { PlayerRowDivider() }
                    row(.tap(tap), label: tap.title, gestureIcon: tap.icon)
                }
            }
            .cascade(GestureContext.allCases.count)
        }
        .choiceSheet(item: $picker, height: { ChoiceSheet.height($0.allowed.count) }) { slot in
            ChoiceSheet(title: slot.title,
                        items: slot.allowed.map { ChoiceItem(id: $0.rawValue, icon: $0.icon, title: title($0, slot: slot)) },
                        selected: action(slot).rawValue) { raw in settings.set(slot.key, .string(raw)) }
        }
    }

    /// «Удалить» в Медиатеке — убрать из плейлиста или Любимых, в очереди — из очереди.
    private func title(_ action: GestureAction, slot: Slot) -> String {
        guard action == .delete, case let .swipe(context, _) = slot else { return action.title }
        return context == .queue ? "Убрать из очереди" : "Убрать из плейлиста"
    }

    private func row(_ slot: Slot, label: String, gestureIcon: IconName) -> some View {
        let current = action(slot)
        return Button {
            picker = slot
        } label: {
            HStack(spacing: 16) {
                SonarIcon(gestureIcon, size: 22)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.text)
                    Text(title(current, slot: slot))
                        .font(.system(size: 15))
                        .foregroundStyle(current == .off ? Theme.textTertiary : Theme.textSecondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                SonarIcon(current.icon, filled: current != .off, size: 24)
                    .foregroundStyle(current == .off ? Theme.textTertiary : Theme.accent)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .animation(Motion.spring, value: current)
    }
}
