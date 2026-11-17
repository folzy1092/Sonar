import SwiftUI
import UIKit

/// Настроения «Моей волны» — долгое нажатие на поле точек (вид — `IMG` 09:51 владельца). Режимы те же,
/// что в ПК-клиенте (`wave.rs` MODES): Своя, Жёсткая, Спокойная, Грустная, Весёлая, Незнакомое. Плитки
/// в две колонки, у каждой свой цвет — подсветка справа и значок; выбранная — светлая. «Готово» —
/// закрыть; если волна играет, она перезапускается в новом настроении.
struct WaveModeSheet: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var picked: WaveMode = .own

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Настроения")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 4)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(WaveMode.allCases.enumerated()), id: \.element) { index, mode in
                    tile(mode)
                        .cascade(index)
                }
            }
            .padding(.top, 14)
            Text(picked.subtitle)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .id(picked)
                .transition(.opacity)
            Spacer(minLength: 16)
            Button {
                if picked != engine.waveMode { engine.setWaveMode(picked) }
                dismiss()
            } label: {
                Text("Готово")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Theme.text, in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.97))
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 30)
        .padding(.bottom, 12)
        .animation(Motion.spring, value: picked)
        .onAppear { picked = engine.waveMode }
    }

    private func tile(_ mode: WaveMode) -> some View {
        let selected = picked == mode
        let hue = Self.hue(mode)
        return Button {
            picked = mode
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 14) {
                SonarIcon(Self.icon(mode), filled: selected, size: 24)
                    .foregroundStyle(selected ? Color.black : hue)
                Text(mode.title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? Color.black : Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.raised)
                    // подсветка цветом настроения справа, как свет из-за края
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [.clear, hue.opacity(0.28)], startPoint: .init(x: 0.4, y: 0.5), endPoint: .trailing))
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white)
                        .opacity(selected ? 1 : 0)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func icon(_ mode: WaveMode) -> IconName {
        switch mode {
        case .own: .heart
        case .hard: .bolt
        case .calm: .moon
        case .sad: .rain
        case .fun: .sun
        case .new: .compass
        }
    }

    /// Свой цвет у каждого настроения — не зависит от обложки, чтобы плитки различались.
    static func hue(_ mode: WaveMode) -> Color {
        switch mode {
        case .own: Color(red: 0.96, green: 0.55, blue: 0.66)
        case .hard: Color(red: 0.95, green: 0.45, blue: 0.38)
        case .calm: Color(red: 0.55, green: 0.78, blue: 0.85)
        case .sad: Color(red: 0.6, green: 0.62, blue: 0.95)
        case .fun: Color(red: 0.98, green: 0.82, blue: 0.4)
        case .new: Color(red: 0.55, green: 0.88, blue: 0.62)
        }
    }
}
