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
        return Equalizer.preset(matching: gains)?.name ?? "Своя кривая"
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
                                subtitle: "Тихие и громкие треки звучат ровно — без докручивания громкости",
                                isOn: flag("audio.normalize"))
                PlayerRowDivider()
                PlayerToggleRow(icon: .link, title: "Бесшовное воспроизведение",
                                subtitle: "Следующий трек подгружается заранее и начинается без паузы",
                                isOn: flag("audio.gapless"))
                PlayerRowDivider()
                PlayerToggleRow(icon: .crossfade, title: "Кроссфейд",
                                subtitle: "Конец трека плавно затихает, следующий плавно нарастает",
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
        "Нормализация и эквалайзер слышны на файлах: Яндекс, SoundCloud через Яндекс, скачанные треки. Потоки HLS "
            + "SoundCloud iPhone проигрывает мимо обработки звука — там громкость и тембр как есть. Кроссфейд на iPhone — "
            + "затухание и нарастание без наложения двух треков."
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
/// пресеты чипами; переключатель вкл/выкл. Кривая одна на все треки. Сейчас играет поток HLS — подсказка,
/// что на нём эквалайзер не слышен.
struct EqualizerSheet: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlaybackEngine.self) private var engine
    @State private var gains: [Double] = Equalizer.flat
    @State private var dragging: Int?

    private var enabled: Bool { settings.bool(Equalizer.enabledKey) }

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

            bands
                .frame(height: 280)
                .opacity(enabled ? 1 : 0.4)
                .allowsHitTesting(enabled)
                .padding(.vertical, 8)
                .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))

            presets
                .opacity(enabled ? 1 : 0.4)
                .allowsHitTesting(enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 30)
        .animation(Motion.spring, value: enabled)
        .onAppear { gains = Equalizer.parse(settings.string(Equalizer.gainsKey)) }
    }

    /// Полосы: вертикальные дорожки с ручкой, над ними — дБ, под ними — частота; кривая — за ними.
    private var bands: some View {
        GeometryReader { proxy in
            let count = Equalizer.frequencies.count
            let columnWidth = proxy.size.width / CGFloat(count)
            let top: CGFloat = 26, bottom: CGFloat = 26
            let height = proxy.size.height - top - bottom
            let y: (Double) -> CGFloat = { db in top + height * CGFloat((Equalizer.maxDb - db) / (2 * Equalizer.maxDb)) }
            ZStack(alignment: .topLeading) {
                // ноль
                Rectangle().fill(Theme.line)
                    .frame(height: 1)
                    .offset(y: y(0))
                // кривая через ручки
                Path { path in
                    let points = gains.indices.map { CGPoint(x: columnWidth * (CGFloat($0) + 0.5), y: y(gains[$0])) }
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for i in 1 ..< points.count {
                        let previous = points[i - 1], point = points[i]
                        let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
                        path.addQuadCurve(to: mid, control: previous)
                        if i == points.count - 1 { path.addQuadCurve(to: point, control: point) }
                    }
                }
                .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                HStack(spacing: 0) {
                    ForEach(0 ..< count, id: \.self) { i in
                        column(i, y: y, top: top, height: height)
                            .frame(width: columnWidth)
                    }
                }
            }
        }
    }

    private func column(_ i: Int, y: @escaping (Double) -> CGFloat, top: CGFloat, height: CGFloat) -> some View {
        let gain = i < gains.count ? gains[i] : 0
        let active = dragging == i
        return ZStack(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: 4, height: height)
                .offset(y: top)
            Circle()
                .fill(active ? Theme.accent : Theme.text)
                .frame(width: active ? 22 : 16, height: active ? 22 : 16)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .offset(y: y(gain) - (active ? 11 : 8))
            Text(gain == 0 ? "0" : String(format: "%+.0f", gain))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(active ? Theme.text : Theme.textTertiary)
                .contentTransition(.numericText(value: gain))
            Text(Equalizer.label(Equalizer.frequencies[i]))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .offset(y: top + height + 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if dragging != i {
                        dragging = i
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    let part = Double((drag.location.y - top) / max(1, height))
                    let db = Equalizer.clamp(Equalizer.maxDb - part * 2 * Equalizer.maxDb)
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
        .animation(Motion.quick, value: active)
    }

    private var presets: some View {
        let current = Equalizer.preset(matching: gains)?.name
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Equalizer.presets) { preset in
                    let on = preset.name == current
                    Button {
                        withAnimation(Motion.spring) { gains = preset.gains }
                        save()
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(preset.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(on ? Theme.accentInk : Theme.text)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.raised.opacity(0.8)), in: Capsule())
                    }
                    .buttonStyle(PressableStyle(scale: 0.94))
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -Theme.gutter)
        .animation(Motion.spring, value: current)
    }

    private func save() {
        settings.set(Equalizer.gainsKey, .string(Equalizer.isFlat(gains) ? "" : Equalizer.encode(gains)))
    }
}
