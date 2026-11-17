import SwiftUI
import UIKit

/// Профиль → Аудио (по ПК `pages/settings/Audio.svelte`, SETTINGS.md «Аудио»): качество, SoundCloud через
/// Яндекс, нормализация, бесшовность, кроссфейд, эквалайзер, что делать после звонка. Всё применяется
/// сразу — `PlaybackEngine` следит за настройками сам.
struct AudioSettingsView: View {
    private enum Pick: String, Identifiable {
        case interruption
        var id: String { rawValue }
    }

    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackEngine.self) private var engine
    @State private var picker: Pick?
    @State private var showEqualizer = false

    private var quality: AudioQuality { .current(settings) }

    private func flag(_ key: String) -> Binding<Bool> {
        Binding(get: { settings.bool(key) }, set: { settings.set(key, $0) })
    }

    private var crossfade: Int { PlayerPrefs.crossfade(settings) }

    private var equalizerSummary: String {
        guard settings.bool(Equalizer.enabledKey) else { return "Выключен" }
        let gains = Equalizer.parse(settings.string(Equalizer.gainsKey))
        if Equalizer.isFlat(gains) { return "Ровно" }
        let user = EqualizerUserPresets.parse(settings.string(EqualizerUserPresets.key))
        return EqualizerUserPresets.matching(gains, user: user)?.name ?? "Своя кривая"
    }

    var body: some View {
        PlayerSettingsPage(title: "Аудио") {
            PlayerCard(title: "Качество", footer: "Потолок для Яндекса: на «Максимальном» — FLAC, если он есть, иначе 320. "
                + "SoundCloud отдаёт свой максимум сам: AAC 160 кбит/с, с Go+ — 256.") {
                VStack(spacing: 10) {
                    let items = AudioQuality.allCases.map { ChoiceItem(id: $0.rawValue, icon: $0.icon, title: $0.title, subtitle: $0.subtitle) }
                    ChoiceTiles(items: Array(items.prefix(2)), selected: quality.rawValue, height: 96) { pickQuality($0) }
                    ChoiceTiles(items: Array(items.suffix(2)), selected: quality.rawValue, height: 96) { pickQuality($0) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .cascade(0)

            PlayerCard(footer: "Если тот же трек есть на Яндексе (исполнитель, название и длительность совпадают) — "
                + "играть его оттуда, в качестве выше. Иначе — SoundCloud.") {
                PlayerToggleRow(icon: .soundcloud, title: "SoundCloud в качестве Яндекса", isOn: flag("audio.sc_via_yandex"))
            }
            .cascade(1)

            PlayerCard(title: "Громкость и переходы", footer: transitionsFooter) {
                PlayerToggleRow(icon: .volume, title: "Нормализация громкости",
                                subtitle: "Тихие и громкие треки звучат ровно — громкие Яндекса приглушаются по их громкости R128",
                                isOn: flag("audio.normalize"))
                PlayerRowDivider()
                PlayerToggleRow(icon: .link, title: "Бесшовное воспроизведение",
                                subtitle: "Следующий трек подгружается заранее и начинается без паузы",
                                isOn: flag("audio.gapless"))
                PlayerRowDivider()
                PlayerToggleRow(icon: .crossfade, title: "Кроссфейд",
                                subtitle: "Следующий начинается поверх конца текущего: один плавно затихает, другой нарастает",
                                isOn: Binding(get: { crossfade > 0 }, set: { settings.set("audio.crossfade", .int($0 ? 6 : 0)) }))
                if crossfade > 0 {
                    crossfadeSlider
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(Motion.spring, value: crossfade > 0)
            .cascade(2)

            PlayerCard(title: "Звук") {
                PlayerPickRow(title: "Эквалайзер", value: equalizerSummary, icon: .sliders) { showEqualizer = true }
                PlayerRowDivider()
                PlayerPickRow(title: "После звонка и Siri", value: InterruptionMode.current(settings).title,
                              icon: InterruptionMode.current(settings).icon) { picker = .interruption }
            }
            .cascade(3)

            Text("Звонок, Siri и будильник ставят музыку на паузу сами — так устроен iPhone. Здесь — что делать, когда они закончатся.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 6)
                .cascade(4)
        }
        .choiceSheet(item: $picker, height: { _ in ChoiceSheet.height(InterruptionMode.allCases.count, subtitles: true) }) { _ in
            ChoiceSheet(title: "После звонка и Siri",
                        items: InterruptionMode.allCases.map { ChoiceItem(id: $0.rawValue, icon: $0.icon, title: $0.title, subtitle: $0.subtitle) },
                        selected: InterruptionMode.current(settings).rawValue) { InterruptionMode.from($0).save(settings) }
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
    }

    private var transitionsFooter: String {
        "Эквалайзер и выравнивание на лету слышны на файлах: Яндекс, SoundCloud через Яндекс, скачанные треки. Потоки HLS "
            + "SoundCloud iPhone проигрывает мимо обработки звука — там тембр как есть. Громкость R128 Яндекса работает везде. "
            + "Кроссфейд — две деки, как на ПК: треки накладываются; выключен — бесшовно, без тишины между треками."
    }

    private var crossfadeSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Длительность")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(crossfade) с")
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(value: Double(crossfade)))
            }
            Slider(value: Binding(get: { Double(crossfade) },
                                  set: { settings.set("audio.crossfade", .int(Int($0.rounded()))) }),
                   in: 1 ... Double(Fades.maxCrossfade), step: 1)
                .tint(Theme.accent)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .animation(Motion.spring, value: crossfade)
    }

    private func pickQuality(_ raw: String) {
        AudioQuality.from(raw).save(settings)
    }
}

/// Эквалайзер (как на ПК, `EqButton.svelte`): 12 полос ±12 дБ — тянуть пальцем вверх-вниз, звучит сразу;
/// сверху — кривая (настоящая АЧХ фильтров), пресеты чипами: свои («Мои» на ПК, `audio.eq_presets`) первыми,
/// «+» сохраняет текущую кривую, долгое нажатие на свой — удалить; переключатель вкл/выкл. Кривая одна на
/// все треки. Сейчас играет поток HLS — подсказка, что на нём эквалайзер не слышен.
struct EqualizerSheet: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackEngine.self) private var engine
    @State private var gains: [Double] = Equalizer.flat
    @State private var dragging: Int?
    @State private var naming = false
    @State private var newName = ""

    private var enabled: Bool { settings.bool(Equalizer.enabledKey) }
    private var userPresets: [Equalizer.Preset] { EqualizerUserPresets.parse(settings.string(EqualizerUserPresets.key)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Эквалайзер")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Toggle("", isOn: Binding(get: { enabled }, set: { value in
                    withAnimation(Motion.spring) { settings.set(Equalizer.enabledKey, value) }
                    UISelectionFeedbackGenerator().selectionChanged()
                }))
                .labelsHidden()
                .tint(Theme.accent)
            }
            .padding(.horizontal, 8)

            if engine.isHLS, engine.current != nil {
                HintCard(icon: .info, text: "Сейчас играет поток HLS SoundCloud — iPhone проигрывает его мимо эквалайзера. "
                    + "Треки Яндекса, SoundCloud через Яндекс и скачанные звучат с ним.")
            }

            EqualizerCurveView(gains: gains, active: dragging, enabled: enabled)

            presets
                .opacity(enabled ? 1 : 0.4)
                .allowsHitTesting(enabled)

            ScrollView {
                bands
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(dragging != nil)
            .opacity(enabled ? 1 : 0.4)
            .allowsHitTesting(enabled)


        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 30)
        .animation(Motion.spring, value: enabled)
        .onAppear { gains = Equalizer.parse(settings.string(Equalizer.gainsKey)) }
        .alert(t("Сохранить текущий"), isPresented: $naming) {
            TextField(t("Название"), text: $newName)
            Button(t("Отмена"), role: .cancel) { newName = "" }
            Button(t("Сохранить")) {
                let list = EqualizerUserPresets.adding(newName, gains: gains, to: userPresets)
                settings.set(EqualizerUserPresets.key, .string(EqualizerUserPresets.encode(list)))
                newName = ""
                UISelectionFeedbackGenerator().selectionChanged()
            }
        } message: {
            Text(t("Подвигай полосы и сохрани кривую — она появится здесь"))
        }
    }

    /// Полосы сверху вниз (владелец, 2026-11-17): у каждой частоты — строка с горизонтальным ползунком,
    /// слева частота, справа дБ; середина — 0 дБ, влево — тише, вправо — громче.
    private var bands: some View {
        VStack(spacing: 4) {
            ForEach(0 ..< Equalizer.frequencies.count, id: \.self) { i in
                row(i)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func row(_ i: Int) -> some View {
        let gain = i < gains.count ? gains[i] : 0
        let active = dragging == i
        return HStack(spacing: 12) {
            Text(Equalizer.label(Equalizer.frequencies[i]))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(active ? Theme.text : Theme.textSecondary)
                .frame(width: 40, alignment: .leading)
            GeometryReader { proxy in
                let w = proxy.size.width
                let x: (Double) -> CGFloat = { db in w * CGFloat((db + Equalizer.maxDb) / (2 * Equalizer.maxDb)) }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                    // заливка от нуля к значению
                    Capsule()
                        .fill(Theme.accent.opacity(0.7))
                        .frame(width: abs(x(gain) - x(0)), height: 4)
                        .offset(x: min(x(gain), x(0)))
                    Rectangle().fill(Theme.line).frame(width: 1, height: 14).offset(x: x(0))
                    Circle()
                        .fill(active ? Theme.accent : Theme.text)
                        .frame(width: active ? 24 : 18, height: active ? 24 : 18)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .offset(x: x(gain) - (active ? 12 : 9))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            if dragging != i {
                                dragging = i
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                            let part = Double(drag.location.x / max(1, w))
                            let db = Equalizer.clamp(part * 2 * Equalizer.maxDb - Equalizer.maxDb)
                            // шаг 0.5 дБ — пальцем точнее не нужно
                            let stepped = (db * 2).rounded() / 2
                            guard stepped != gains[i] else { return }
                            gains[i] = stepped
                            // звучит сразу, сохраняется, когда отпустил
                            AudioTap.params.update(gains: gains, eqEnabled: true, normalize: settings.bool("audio.normalize"))
                        }
                        .onEnded { _ in
                            withAnimation(Motion.spring) { dragging = nil }
                            save()
                        }
                )
            }
            .frame(height: 36)
            Text(gain == 0 ? "0" : String(format: "%+.1f", gain))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(active ? Theme.text : Theme.textTertiary)
                .contentTransition(.numericText(value: gain))
                .frame(width: 44, alignment: .trailing)
        }
        .animation(Motion.quick, value: active)
    }

    private var presets: some View {
        let mine = userPresets
        let current = EqualizerUserPresets.matching(gains, user: mine)?.name
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    newName = ""
                    naming = true
                } label: {
                    SonarIcon(.plus, size: 18)
                        .foregroundStyle(Theme.text)
                        .frame(width: 40, height: 40)
                        .background(Theme.raised.opacity(0.8), in: Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(t("Сохранить текущий"))
                ForEach(mine) { preset in
                    presetChip(preset, on: preset.name == current, builtin: false)
                        .contextMenu {
                            Button(t("Удалить"), role: .destructive) {
                                let list = EqualizerUserPresets.removing(preset.name, from: mine)
                                settings.set(EqualizerUserPresets.key, .string(EqualizerUserPresets.encode(list)))
                            }
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                ForEach(Equalizer.presets) { preset in
                    presetChip(preset, on: preset.name == current, builtin: true)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -Theme.gutter)
        .animation(Motion.spring, value: current)
        .animation(Motion.spring, value: mine.map(\.name))
    }

    private func presetChip(_ preset: Equalizer.Preset, on: Bool, builtin: Bool) -> some View {
        Button {
            withAnimation(Motion.spring) { gains = preset.gains }
            save()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(builtin ? t(preset.name) : preset.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Theme.accentInk : Theme.text)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.raised.opacity(0.8)), in: Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
    }

    private func save() {
        settings.set(Equalizer.gainsKey, .string(Equalizer.isFlat(gains) ? "" : Equalizer.encode(gains)))
    }
}
