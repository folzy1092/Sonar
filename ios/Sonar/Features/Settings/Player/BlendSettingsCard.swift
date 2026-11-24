import SwiftUI

/// Профиль → Аудио → «Сведение» (docs/BLEND.md §10.2) — зеркало ПК `pages/settings/BlendSettings.svelte`:
/// вид, длина, «Можно срезать», допуск темпа, тональность и отладочная панель для Dev. Значения — `BlendPrefs`.
struct BlendSettingsCard: View {
    private enum Pick: String, Identifiable {
        case kind, length
        var id: String { rawValue }
    }

    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackEngine.self) private var engine
    @State private var picker: Pick?

    private var isDev: Bool {
        SonarDeep.subscriptionOf(username: settings.string(LookKey.profileUsername)).tier == .dev
    }

    var body: some View {
        let opts = engine.settings()
        PlayerCard(title: t("Сведение")) {
            PlayerPickRow(title: t("Вид сведения"), value: t(BlendView.kindText(opts.type).name),
                          icon: Self.icon(opts.type)) { picker = .kind }
            hint(t(BlendView.kindText(opts.type).about))
            PlayerRowDivider()
            PlayerPickRow(title: t("Длина сведения"), value: t(BlendView.lengthText(opts.lengthSec)),
                          icon: .clock) { picker = .length }
            hint(t("Сколько треки звучат вместе: около 6, 10 или 16 секунд, точно — по тактам"))
            PlayerRowDivider()
            slider(title: t("Можно срезать"),
                   hint: t("Сколько секунд конца трека можно пропустить ради лучшего момента; рекомендуется 16"),
                   value: opts.cutSec, max: BlendPrefs.cutMaxSec, unit: t("с"), key: "audio.blend_cut")
            PlayerRowDivider()
            slider(title: t("Допуск темпа"),
                   hint: t("Насколько можно ускорить или замедлить следующий трек, чтобы попасть в долю; дальше — без бита"),
                   value: opts.tempoTolPct, max: BlendPrefs.tempoTolMaxPct, unit: "%", key: "audio.blend_tempo")
            PlayerRowDivider()
            PlayerToggleRow(icon: .music, title: t("Подгонять тональность"),
                            subtitle: t("Сдвигает тон следующего трека на время перехода, если тональности не дружат"),
                            isOn: Binding(get: { opts.keyShift }, set: { settings.set("audio.blend_key", $0) }))
            if isDev {
                PlayerRowDivider()
                PlayerToggleRow(icon: .sliders, title: t("Отладочная панель"),
                                subtitle: t("Карточка у плеера: анализ треков, план перехода и его фазы — только для Dev"),
                                isOn: Binding(get: { settings.bool("audio.blend_debug") },
                                              set: { settings.set("audio.blend_debug", $0) }))
            }
        }
        .choiceSheet(item: $picker, height: { pick in
            pick == .kind ? ChoiceSheet.height(BlendPrefs.types.count, subtitles: true)
                : ChoiceSheet.height(BlendPrefs.lengths.count)
        }) { pick in
            switch pick {
            case .kind:
                ChoiceSheet(title: t("Вид сведения"), items: Self.kindItems, selected: opts.type.rawValue) {
                    settings.set("audio.blend_type", .string($0))
                }
            case .length:
                ChoiceSheet(title: t("Длина сведения"), items: Self.lengthItems, selected: "\(Int(opts.lengthSec))") {
                    settings.set("audio.blend_length", .int(Int($0) ?? 10))
                }
            }
        }
    }

    private static var kindItems: [ChoiceItem] {
        BlendPrefs.types.map {
            ChoiceItem(id: $0.rawValue, icon: icon($0), title: t(BlendView.kindText($0).name),
                       subtitle: t(BlendView.kindText($0).about))
        }
    }

    private static var lengthItems: [ChoiceItem] {
        BlendPrefs.lengths.map { ChoiceItem(id: "\(Int($0))", icon: .clock, title: t(BlendView.lengthText($0))) }
    }

    private static func icon(_ type: BlendType) -> IconName {
        switch type {
        case .auto: .sparkles
        case .bass: .volume
        case .filter: .filter
        case .echo: .waveLine
        case .smooth: .wave
        case .drop: .bolt
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 22)
            .padding(.top, -10)
            .padding(.bottom, 12)
            .contentTransition(.opacity)
    }

    private func slider(title: String, hint text: String, value: Double, max: Double, unit: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: value))
            }
            Slider(value: Binding(get: { value }, set: { settings.set(key, .int(Int($0.rounded()))) }),
                   in: 0 ... max, step: 1)
                .tint(Theme.accent)
                .accessibilityLabel(title)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .animation(Motion.spring, value: value)
    }
}
