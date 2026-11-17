import SwiftUI
import UIKit

/// Профиль → Вид плеера (по ПК `pages/settings/PlayerView.svelte`, SETTINGS.md «Плеер»): стиль, фон,
/// выравнивание названия, ползунок, кнопка «играть», аватарки артистов. Сверху — живой пример с текущим
/// треком; полный плеер (`FullPlayerView`) меняется сразу.
struct PlayerViewSettingsView: View {
    private enum Pick: String, Identifiable {
        case background
        var id: String { rawValue }
    }

    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackEngine.self) private var engine
    @State private var picker: Pick?

    private var style: PlayerStyle { .current(settings) }

    var body: some View {
        PlayerSettingsPage(title: "Вид плеера") {
            PlayerPreview()
                .cascade(0)

            PlayerCard(title: "Стиль плеера") {
                ChoiceTiles(items: PlayerStyle.allCases.map(\.item), selected: style.rawValue) { PlayerStyle.from($0).save(settings) }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                PlayerPickRow(title: "Фон", value: style == .large ? "Обложка на весь экран" : PlayerBackground.current(settings).title,
                              icon: style == .large ? .fullscreen : PlayerBackground.current(settings).icon,
                              enabled: style != .large) { picker = .background }
            }
            .cascade(1)

            PlayerCard(title: "Выравнивание названия") {
                ChoiceTiles(items: TitleAlign.allCases.map(\.item), selected: TitleAlign.current(settings).rawValue, height: 80) {
                    TitleAlign.from($0).save(settings)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .cascade(2)

            PlayerCard(title: "Ползунок") {
                ForEach(SliderStyle.allCases) { slider in
                    sliderRow(slider)
                }
            }
            .cascade(3)

            PlayerCard(title: "Кнопка «играть»") {
                ChoiceTiles(items: PlayButtonStyle.allCases.map(\.item), selected: PlayButtonStyle.current(settings).rawValue, height: 80) {
                    PlayButtonStyle.from($0).save(settings)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .cascade(4)

            PlayerCard {
                PlayerToggleRow(icon: .user, title: "Аватарки артистов",
                                subtitle: "Перед именем исполнителя в плеере",
                                isOn: Binding(get: { settings.bool("player.artist_avatars") }, set: { settings.set("player.artist_avatars", $0) }))
            }
            .cascade(5)
        }
        .animation(Motion.spring, value: style)
        .choiceSheet(item: $picker, height: { _ in ChoiceSheet.height(PlayerBackground.allCases.count) }) { _ in
            ChoiceSheet(title: "Фон плеера", items: PlayerBackground.allCases.map(\.item),
                        selected: PlayerBackground.current(settings).rawValue) { PlayerBackground.from($0).save(settings) }
        }
    }

    private func sliderRow(_ slider: SliderStyle) -> some View {
        let on = SliderStyle.current(settings) == slider
        return Button {
            slider.save(settings)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 16) {
                Text(slider.title)
                    .font(.system(size: 16, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Theme.text : Theme.textSecondary)
                    .frame(width: 96, alignment: .leading)
                PlayerSlider(style: slider, fraction: 0.45, playing: on && engine.isPlaying, seed: "sonar",
                             onScrub: { _ in }, onCommit: {})
                    .allowsHitTesting(false)
                SonarIcon(.check, size: 22)
                    .foregroundStyle(Theme.accent)
                    .opacity(on ? 1 : 0)
                    .scaleEffect(on ? 1 : 0.5)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(on ? Theme.raisedHigh.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .animation(Motion.spring, value: on)
    }
}

/// Живой пример полного плеера в карточке: обложка в выбранном стиле, название с выбранным выравниванием,
/// ползунок и кнопка — с текущим треком (ничего не играет — заглушка).
private struct PlayerPreview: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        let style = PlayerStyle.current(settings)
        let align = TitleAlign.current(settings)
        let horizontal: HorizontalAlignment = align == .left ? .leading : align == .right ? .trailing : .center
        let frame: Alignment = align == .left ? .leading : align == .right ? .trailing : .center
        let track = engine.current
        let fraction = engine.duration > 0 ? min(1, engine.position / engine.duration) : 0.4
        HStack(spacing: 16) {
            cover(style, url: track?.coverURL)
                .frame(width: 92, height: 92)
            VStack(alignment: horizontal, spacing: 8) {
                VStack(alignment: horizontal, spacing: 2) {
                    Text(track?.title ?? "Название трека")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if settings.bool("player.artist_avatars") {
                            Circle().fill(Theme.raisedHigh)
                                .overlay {
                                    if let avatar = track?.artists.first?.avatarURL { CoverImage(url: avatar, cornerRadius: 8) }
                                }
                                .frame(width: 16, height: 16)
                                .clipShape(Circle())
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(track?.artist ?? "Исполнитель")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: frame)
                PlayerSlider(style: .current(settings), fraction: fraction, playing: engine.isPlaying, seed: track?.ref ?? "sonar",
                             onScrub: { _ in }, onCommit: {})
                    .allowsHitTesting(false)
                playButton
                    .frame(maxWidth: .infinity, alignment: frame)
            }
        }
        .padding(16)
        .background {
            ZStack {
                Theme.raised.opacity(0.6)
                if style != .large, PlayerBackground.current(settings) == .cover_color {
                    LinearGradient(colors: [Theme.tint.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .animation(Motion.spring, value: style)
        .animation(Motion.spring, value: align)
        .animation(Motion.spring, value: settings.bool("player.artist_avatars"))
        .animation(Motion.spring, value: PlayButtonStyle.current(settings))
    }

    @ViewBuilder
    private func cover(_ style: PlayerStyle, url: String?) -> some View {
        switch style {
        case .standard:
            CoverImage(url: url, cornerRadius: 14)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        case .large:
            CoverImage(url: url, cornerRadius: 6)
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        case .vinyl:
            ZStack {
                Circle().fill(Color(white: 0.06))
                Circle().stroke(Color.white.opacity(0.06), lineWidth: 1).padding(8)
                Circle().stroke(Color.white.opacity(0.06), lineWidth: 1).padding(16)
                CoverImage(url: url, cornerRadius: 40).frame(width: 38, height: 38)
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var playButton: some View {
        let icon = SonarIcon(engine.isPlaying ? .pause : .play, filled: true, size: 16)
        switch PlayButtonStyle.current(settings) {
        case .circle:
            icon.foregroundStyle(Theme.accentInk).frame(width: 34, height: 34).background(Theme.accent, in: Circle())
        case .square:
            icon.foregroundStyle(Theme.accentInk).frame(width: 34, height: 34)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .clean:
            SonarIcon(engine.isPlaying ? .pause : .play, filled: true, size: 22).foregroundStyle(Theme.text).frame(width: 34, height: 34)
        }
    }
}
