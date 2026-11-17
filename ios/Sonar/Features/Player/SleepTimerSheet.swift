import SwiftUI
import UIKit

/// Таймер сна — блок в листе скорости (кнопка ползунков в плеере): 15 · 30 · 45 · 60 мин · «Конец трека».
/// Включён — сверху сколько осталось, тап по выбранному — выключить. К концу громкость плавно уходит в
/// ноль, потом пауза (`SleepTimer`, `PlaybackEngine.setSleep`).
struct SleepTimerSection: View {
    @Environment(PlaybackEngine.self) private var engine

    private func isSelected(_ option: SleepOption) -> Bool {
        guard let sleep = engine.sleep else { return false }
        switch (option, sleep.mode) {
        case (.endOfTrack, .endOfTrack): return true
        case (.minutes, .deadline): return selectedMinutes == option
        default: return false
        }
    }

    /// Какие минуты выбраны — запоминаем при нажатии (у таймера только время конца).
    @State private var selectedMinutes: SleepOption?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SonarIcon(.moon, filled: engine.sleep != nil, size: 20)
                    .foregroundStyle(engine.sleep != nil ? Theme.accent : Theme.textSecondary)
                Text("Таймер сна")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                status
            }
            HStack(spacing: 8) {
                ForEach(SleepOption.all) { option in
                    let on = isSelected(option)
                    Button {
                        withAnimation(Motion.spring) {
                            if on {
                                engine.setSleep(nil)
                                selectedMinutes = nil
                            } else {
                                engine.setSleep(option)
                                if case .minutes = option { selectedMinutes = option } else { selectedMinutes = nil }
                            }
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(option.shortTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? Theme.accentInk : Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .accessibilityLabel(option.title)
                }
            }
        }
        .animation(Motion.spring, value: engine.sleep)
        .onAppear {
            // лист открыли заново — подсветить ближайшие минуты к оставшемуся времени
            if selectedMinutes == nil, let left = engine.sleep?.remaining(now: Date()) {
                selectedMinutes = SleepOption.all.first { option in
                    guard case let .minutes(n) = option else { return false }
                    return Double(n) * 60 >= left
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let sleep = engine.sleep {
            if sleep.isEndOfTrack {
                Text("после этого трека")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = sleep.remaining(now: context.date) ?? 0
                    Text(SleepTimer.label(left))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText(countsDown: true))
                }
                .transition(.opacity)
            }
        }
    }
}

extension SleepOption {
    /// Подпись на кнопке: «15 мин», …, «Трек».
    var shortTitle: String {
        switch self {
        case let .minutes(n): "\(n) мин"
        case .endOfTrack: "Трек"
        }
    }
}
