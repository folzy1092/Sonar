import SwiftUI
import UIKit

/// Таймер сна — блок в листе скорости и отдельный лист из меню трека, как у Dotify и на ПК
/// (`player/SleepButton.svelte`): крупно минуты, «Остановится в HH:MM», ползунок 5–180 с шагом 1, пресеты
/// 15 · 30 · 45 · 60 · 90 (связаны с ползунком), «До конца трека» и «Запустить». Таймер идёт — обратный отсчёт
/// и «Отменить» / «Изменить». К концу громкость плавно уходит в ноль, потом пауза (`SleepTimer`,
/// `PlaybackEngine.setSleep`). Чистая часть выбора — `SleepPick`.
struct SleepTimerSection: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// На что ставили в прошлый раз — с этого ползунок начинает (у каждого устройства своё).
    @AppStorage("sleep.last_minutes") private var lastMinutes = SleepPick.fallback
    @State private var minutes = SleepPick.fallback
    /// Идущий таймер открыли на «Изменить» — снова ползунок вместо отсчёта.
    @State private var editing = false

    private var showsEditor: Bool { engine.sleep == nil || editing }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SonarIcon(.moon, filled: engine.sleep != nil, size: 20)
                    .foregroundStyle(engine.sleep != nil ? Theme.accent : Theme.textSecondary)
                Text(t("Таймер сна"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            Group {
                if showsEditor { editor } else { running }
            }
            .padding(.top, 10)
            .transition(.opacity)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.spring, value: showsEditor)
        .onAppear {
            minutes = SleepPick.clamp(Double(lastMinutes))
            editing = false
        }
    }

    // MARK: - Выбор минут

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(minutes)")
                    .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(value: Double(minutes)))
                Text(t("мин"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.text)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: minutes)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                stopLine(SleepPick.stopAt(now: context.date, minutes: minutes))
            }
            Slider(value: Binding(
                get: { Double(minutes) },
                set: { value in
                    let next = SleepPick.clamp(value)
                    guard next != minutes else { return }
                    minutes = next
                    if SleepPick.preset(of: next) != nil { Haptics.select() }
                }
            ), in: Double(SleepPick.min) ... Double(SleepPick.max), step: 1)
                .tint(Theme.text)
                .padding(.top, 14)
                .accessibilityLabel(t("Минуты до паузы"))
                .accessibilityValue(t("{n} мин", ["n": "\(minutes)"]))
            HStack(spacing: 6) {
                ForEach(SleepPick.presets, id: \.self) { preset in
                    let on = SleepPick.preset(of: minutes) == preset
                    Button {
                        minutes = preset
                        Haptics.select()
                    } label: {
                        Text("\(preset)")
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(on ? Theme.accentInk : Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(on ? AnyShapeStyle(Theme.text) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                            .animation(Motion.spring, value: on)
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .accessibilityLabel(t("{n} мин", ["n": "\(preset)"]))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.top, 12)
            HStack(spacing: 8) {
                wideButton(t("До конца трека"), primary: false, outlined: engine.sleep?.isEndOfTrack == true) {
                    engine.setSleep(.endOfTrack)
                    editing = false
                }
                wideButton(t("Запустить"), primary: true) {
                    lastMinutes = minutes
                    engine.setSleep(.minutes(minutes))
                    editing = false
                }
            }
            .padding(.top, 14)
        }
    }

    // MARK: - Идёт отсчёт

    @ViewBuilder
    private var running: some View {
        if let sleep = engine.sleep {
            VStack(spacing: 0) {
                if sleep.isEndOfTrack {
                    SonarIcon(.moon, filled: true, size: 34)
                        .foregroundStyle(Theme.accent)
                        .frame(height: 58)
                    Text(t("Пауза в конце трека"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = sleep.remaining(now: context.date) ?? 0
                        Text(SleepTimer.label(left))
                            .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.text)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    if case let .deadline(date) = sleep.mode {
                        stopLine(date)
                    }
                }
                HStack(spacing: 8) {
                    wideButton(t("таймер::Отменить"), primary: false) {
                        engine.setSleep(nil)
                        editing = false
                    }
                    wideButton(t("таймер::Изменить"), primary: true) {
                        if let left = sleep.remaining(now: Date()) {
                            minutes = SleepPick.minutes(fromLeft: left)
                        } else {
                            minutes = SleepPick.clamp(Double(lastMinutes))
                        }
                        editing = true
                    }
                }
                .padding(.top, 16)
            }
        }
    }

    // MARK: - Части

    /// «Остановится в 08:44» — 12 или 24 часа, как в системе.
    private func stopLine(_ date: Date) -> some View {
        Text(t("Остановится в {time}", ["time": date.formatted(date: .omitted, time: .shortened)]))
            .font(.system(size: 14).monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .contentTransition(.numericText())
    }

    private func wideButton(_ title: String, primary: Bool, outlined: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.spring) { action() }
            Haptics.select()
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(primary ? Theme.accentInk : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(primary ? AnyShapeStyle(Theme.text) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.text.opacity(outlined ? 0.5 : 0), lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }
}
