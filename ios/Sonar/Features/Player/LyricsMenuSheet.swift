import SwiftUI
import UIKit

/// Меню текста (`IMG_6787`, `IMG_6788`): круг размера (S → M → L → XL) и «По словам / По строкам», Стиль
/// текста и Анимация (тап — следующее значение, как в ПК-клиенте), смещение линейкой ±2 с (двойной тап —
/// сброс), «Перевод», «Найти заново».
struct LyricsMenuSheet: View {
    let track: Track
    /// Что показывает переключатель «По словам / По строкам» — капсула едет сразу, а текст за листом
    /// перестраивается после неё (иначе тяжёлая перекладка текста дёргает анимацию). nil — как в настройке.
    @State private var shownWords: Bool?

    private var store: LyricsStore { LyricsStore.shared }
    private var look: LyricsLook { LyricsLook.current() }
    private var offset: Double { store.offset(for: track.ref) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    let all = LyricsSize.allCases
                    let next = all[((all.firstIndex(of: look.size) ?? 0) + 1) % all.count]
                    store.size = next
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(look.size.rawValue)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                        .frame(width: 52, height: 52)
                        .background(Theme.raised, in: Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("Размер текста \(look.size.rawValue)")
                syncSwitch
            }

            VStack(spacing: 0) {
                cycleRow("Стиль текста", look.style.title) {
                    let all = LyricsTextStyle.allCases
                    let next = all[((all.firstIndex(of: look.style) ?? 0) + 1) % all.count]
                    store.style = next
                }
                cycleRow("Анимация", look.animation.title) {
                    let all = LyricsAnimation.allCases
                    let next = all[((all.firstIndex(of: look.animation) ?? 0) + 1) % all.count]
                    store.animation = next
                }
            }
            .padding(.top, 18)

            offsetRuler
                .padding(.top, 22)

            Button {
                Task {
                    if store.translationLanguage == nil { await store.translate(to: currentLang().rawValue) } else { store.clearTranslation() }
                }
            } label: {
                HStack(spacing: 10) {
                    SonarIcon(.translate, size: 21)
                    Text(t(store.translationLanguage == nil ? "Перевести" : "Без перевода"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .overlay(Capsule().strokeBorder(Theme.text.opacity(0.18), lineWidth: 1.2))
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .padding(.top, 26)

            Button {
                Task { await store.reload(for: track) }
            } label: {
                Text("Найти текст заново")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 8)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 30)
        .animation(Motion.spring, value: look)
        .animation(Motion.spring, value: store.translationLanguage == nil)
    }

    /// По словам / По строкам; без пословного времени «По словам» приглушено (закраска — по длительности строки).
    private var syncSwitch: some View {
        let words = shownWords ?? look.words
        return HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { option in
                let on = words == option
                Button {
                    guard option != words else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(Motion.spring) { shownWords = option }
                    // текст перестраивается, когда капсула доехала — анимация не дёргается
                    Task {
                        try? await Task.sleep(for: .milliseconds(280))
                        guard shownWords == option else { return }
                        store.mode = option ? .words : .lines
                    }
                } label: {
                    Text(option ? "По словам" : "По строкам")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(on ? Theme.background : Theme.textSecondary)
                        .contentTransition(.opacity)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        // капсула — одна, едет сдвигом (дешевле matchedGeometryEffect, не перестраивает кнопки)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(Theme.text)
                    .frame(width: proxy.size.width / 2)
                    .offset(x: words ? 0 : proxy.size.width / 2)
            }
        }
        .padding(6)
        .background(Theme.raised, in: Capsule())
    }

    private func cycleRow(_ title: String, _ value: String, action: @escaping @MainActor () -> Void) -> some View {
        Button {
            action()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.text)
                    Text(value)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                SonarIcon(.chevronRight, size: 22).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 6)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
    }

    /// Линейка смещения — «барабан», как на ПК (`DrumRuler`): тянешь вбок — текст раньше / позже, до ±2 с, шаг
    /// 10 мс; деление каждые 10 мс, среднее — каждые 100 мс, длинное с подписью — каждую секунду. Двойной тап — к нулю.
    private var offsetRuler: some View {
        HStack(spacing: 14) {
            DrumRuler(value: offset, range: -2 ... 2, step: 0.01, medium: 10, major: 100,
                      label: { seconds in
                          let s = Int(seconds.rounded())
                          return s == 0 ? "0" : (s > 0 ? "+" : "−") + "\(abs(s)) с"
                      }) { store.setOffset($0, for: track.ref) }
                .accessibilityLabel(t("Сдвиг текста"))
            Text(Self.label(offset))
                .font(.system(size: 16, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.text)
                .frame(minWidth: 70, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }

    static func label(_ seconds: Double) -> String {
        let ms = Int((seconds * 1000).rounded())
        if ms == 0 { return "0 мс" }
        return (ms > 0 ? "+" : "−") + "\(abs(ms)) мс"
    }
}
