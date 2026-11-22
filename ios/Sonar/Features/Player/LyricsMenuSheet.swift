import SwiftUI
import UIKit

/// Меню текста (`IMG_6787`, `IMG_6788`): «По словам / По строкам» и круг размера (S → M → L → XL), Стиль
/// текста и Анимация (тап — следующее значение, как в ПК-клиенте), смещение линейкой ±2 с (двойной тап —
/// сброс), «Перевод», «Найти заново».
struct LyricsMenuSheet: View {
    let track: Track
    @State private var dragStart: Double?

    private var store: LyricsStore { LyricsStore.shared }
    private var look: LyricsLook { LyricsLook.current() }
    private var offset: Double { store.offset(for: track.ref) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                syncSwitch
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
                    if store.translation.isEmpty { await store.translate(to: "ru") } else { store.clearTranslation() }
                }
            } label: {
                HStack(spacing: 10) {
                    SonarIcon(.translate, size: 21)
                    Text(store.translation.isEmpty ? "Перевод" : "Убрать перевод")
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
        .animation(Motion.spring, value: store.translation.isEmpty)
    }

    /// По словам / По строкам; без пословного времени «По словам» приглушено (закраска — по длительности строки).
    private var syncSwitch: some View {
        HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { words in
                let on = look.words == words
                Button {
                    store.mode = words ? .words : .lines
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(words ? "По словам" : "По строкам")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(on ? Theme.background : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if on {
                                Capsule().fill(Theme.text).padding(0)
                                    .matchedGeometryEffect(id: "sync", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Theme.raised, in: Capsule())
    }

    @Namespace private var namespace

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

    /// Линейка смещения: тянешь вбок — текст раньше / позже, до ±2 с, шаг 10 мс; метка «+120 мс».
    private var offsetRuler: some View {
        HStack(spacing: 18) {
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack {
                    HStack(spacing: 3) {
                        ForEach(0 ..< 4, id: \.self) { _ in
                            Rectangle().fill(Theme.raised)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    // ползунок: центр — 0, края — ±2 с
                    Capsule()
                        .fill(offset == 0 ? Theme.textTertiary : Theme.accent)
                        .frame(width: 4, height: 30)
                        .offset(x: CGFloat(offset / 2) * (w / 2 - 10))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { drag in
                            let start = dragStart ?? offset
                            if dragStart == nil { dragStart = offset }
                            let next = start + Double(drag.translation.width / (w / 2)) * 2
                            let rounded = (min(2, max(-2, next)) * 100).rounded() / 100
                            if rounded != offset {
                                store.setOffset(rounded, for: track.ref)
                                if Int(rounded * 100) % 10 == 0 { UISelectionFeedbackGenerator().selectionChanged() }
                            }
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .onTapGesture(count: 2) {
                    store.setOffset(0, for: track.ref)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .frame(height: 50)
            Text(Self.label(offset))
                .font(.system(size: 16, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.text)
                .frame(minWidth: 70, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .animation(.easeOut(duration: 0.12), value: offset)
    }

    static func label(_ seconds: Double) -> String {
        let ms = Int((seconds * 1000).rounded())
        if ms == 0 { return "0 мс" }
        return (ms > 0 ? "+" : "−") + "\(abs(ms)) мс"
    }
}
