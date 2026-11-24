import SwiftUI

/// Шторка «Сведение» у полноэкранного плеера (docs/BLEND.md §10.1) — зеркало `BlendButton.svelte`: включить,
/// оценить прошлый переход, вид, длина, срез, тональность, «Следующий переход», вечеринка и отладка для Dev.
/// Что показать в карточке — `BlendView.card`; строки — те же русские ключи `t()`, что на ПК.
struct BlendSheet: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings

    private var hub: BlendAnalysisHub { .shared }
    private var party: BlendPartyStore { .shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                mainCard
                if BlendRatings.shared.ask != nil {
                    BlendRateRow()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if engine.blendOn {
                    nextCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                optionsCard
                partyButton
                // HLS играет мимо `AudioTap`: из перехода слышна только громкость (BLEND §13). Склеенный файл
                // SoundCloud играет как файл (`isHLS` = false) — тогда подсказки нет
                if engine.blendOn, engine.isHLS {
                    HintCard(icon: .info, text: t("Этот трек идёт потоком HLS — в переходе слышна только громкость, без фильтров и эха"))
                        .transition(.opacity)
                }
                if showDebug {
                    BlendDebugCard()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 24)
            .animation(Motion.spring, value: engine.blendOn)
            .animation(Motion.spring, value: BlendRatings.shared.ask)
        }
        .scrollIndicators(.hidden)
    }

    private var showDebug: Bool {
        engine.blendOn && settings.bool("audio.blend_debug")
            && SonarDeep.subscriptionOf(username: settings.string(LookKey.profileUsername)).tier == .dev
    }

    // MARK: - Включить

    private var mainCard: some View {
        BlendToggleRow(
            title: t("Сведение"),
            subtitle: t("Переход по долям, как у диджея, вместо кроссфейда"),
            isOn: Binding(get: { engine.blendOn }, set: { on in
                settings.set("audio.blend", on)
                if !on, party.isActive { party.end() }
            })
        )
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Следующий переход

    private var cardInput: BlendView.CardInput {
        let a = engine.current?.ref
        let b = engine.upNext.first?.ref
        var failed = false
        if let a, let b { failed = engine.blend.failedFor(a, b) }
        return BlendView.CardInput(
            on: engine.blendOn, repeatOne: engine.repeatMode == .one, a: a, b: b,
            stateA: a.map(hub.state) ?? .none, stateB: b.map(hub.state) ?? .none, failed: failed,
            next: engine.blend.next, anA: a.flatMap(hub.peek), anB: b.flatMap(hub.peek), rateA: Double(engine.rate)
        )
    }

    private var nextCard: some View {
        let card = BlendView.card(cardInput)
        let previewMs = engine.blend.previewAtMs()
        return VStack(alignment: .leading, spacing: 10) {
            label(t("Следующий переход"))
            if case .plan(let plan) = card {
                planLines(plan)
            } else if let state = card.stateText {
                Text(t(state))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                if card == .noAnalysis { failureLines }
            }
            HStack(spacing: 8) {
                if card == .noAnalysis {
                    pill(t("Повторить"), selected: false) { retryAnalysis() }
                } else {
                    pill(t("Другой момент"), selected: false, enabled: Self.canSwap(card)) {
                        _ = engine.blend.another()
                    }
                }
                pill(t("К переходу"), selected: false, enabled: previewMs != nil) {
                    if let ms = engine.blend.previewAtMs() { engine.seek(to: ms / 1000) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Сырые причины сбоя анализа играющего и следующего трека (без повторов).
    private var failures: [String] {
        var out: [String] = []
        for ref in [engine.current?.ref, engine.upNext.first?.ref].compactMap({ $0 }) {
            if let raw = hub.failure(ref), !out.contains(raw) { out.append(raw) }
        }
        return out
    }

    /// Почему нет анализа — человеческими словами; Dev видит и саму ошибку.
    private var failureLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(failures, id: \.self) { raw in
                Text(t(BlendView.failureText(raw)))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                if showDebug {
                    Text(raw)
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Забыть сбои и посчитать играющий и следующий заново (сеть вернулась, сервис ожил).
    private func retryAnalysis() {
        hub.forgetFailures()
        for ref in [engine.current?.ref, engine.upNext.first?.ref].compactMap({ $0 }) { hub.request(ref) }
    }

    private static func canSwap(_ card: BlendView.Card) -> Bool {
        if case .plan(let plan) = card { return plan.total >= 2 }
        return false
    }

    @ViewBuilder
    private func planLines(_ plan: BlendView.PlanCard) -> some View {
        let head = [
            t(BlendView.kindText(plan.kind).name),
            plan.sync ? t("бит в бит") : t("без бита"),
            t("{n} с", ["n": String(format: "%g", plan.sec)]),
            t("момент {rank} из {total}", ["rank": "\(plan.rank)", "total": "\(plan.total)"]),
        ].joined(separator: " · ")
        Text(head)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.text)
        Text(t("выход из «{a}» на {at}, вход в «{b}» с {from}", [
            "a": engine.current?.title ?? "", "at": FullPlayerView.time(plan.outMs / 1000),
            "b": engine.upNext.first?.title ?? "", "from": FullPlayerView.time(plan.inMs / 1000),
        ]))
        .font(.system(size: 13))
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        Text(t("темп {a} → {b} · тон {ka} → {kb}", [
            "a": "\(plan.tempoA)", "b": "\(plan.tempoB)", "ka": plan.keyA, "kb": plan.keyB,
        ]))
        .font(.system(size: 13).monospacedDigit())
        .foregroundStyle(Theme.textSecondary)
    }

    // MARK: - Вид, длина, срез, тональность

    private var optionsCard: some View {
        let current = engine.settings()
        return VStack(alignment: .leading, spacing: 12) {
            label(t("Сведение::Вид"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(BlendPrefs.types, id: \.self) { type in
                    pill(t(BlendView.kindText(type).name), selected: current.type == type) {
                        settings.set("audio.blend_type", .string(type.rawValue))
                    }
                }
            }
            Text(t(BlendView.kindText(current.type).about))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            label(t("Длина"))
            HStack(spacing: 8) {
                ForEach(BlendPrefs.lengths, id: \.self) { sec in
                    pill(t(BlendView.lengthText(sec)), selected: current.lengthSec == sec) {
                        settings.set("audio.blend_length", .int(Int(sec)))
                    }
                }
            }
            cutRuler(current.cutSec)
            Divider().overlay(Theme.line)
            BlendToggleRow(
                title: t("Подгонять тональность"),
                subtitle: t("Сдвигает тон следующего трека на время перехода, если тональности не дружат"),
                isOn: Binding(get: { engine.settings().keyShift }, set: { settings.set("audio.blend_key", $0) })
            )
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func cutRuler(_ cut: Double) -> some View {
        let recommended = cut == BlendPrefs.cutRecommendedSec
        let n = ["n": "\(Int(cut))"]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                label(t("Можно срезать"))
                Spacer()
                Text(recommended ? t("{n} с — рекомендуется", n) : t("{n} с", n))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(recommended ? Theme.accent : Theme.text)
                    .contentTransition(.numericText(value: cut))
            }
            // шаг 1 с, деление каждые 5, подпись каждые 15; двойной тап — рекомендуемые 16 с
            DrumRuler(value: cut, range: 0 ... BlendPrefs.cutMaxSec, step: 1, medium: 5, major: 15,
                      label: { "\(Int($0))" }, reset: BlendPrefs.cutRecommendedSec, height: 50) {
                settings.set("audio.blend_cut", .int(Int($0.rounded())))
            }
            .accessibilityLabel(t("Можно срезать"))
        }
        .animation(Motion.spring, value: cut)
    }

    // MARK: - Вечеринка

    private var partyButton: some View {
        let active = party.isActive
        let enabled = active || engine.tracks.count >= 2
        return Button {
            withAnimation(Motion.spring) {
                if active {
                    party.end()
                } else {
                    let name = engine.contextTitle.isEmpty ? t("Очередь") : engine.contextTitle
                    party.start(engine.tracks, name: name)
                }
            }
        } label: {
            HStack(spacing: 8) {
                SonarIcon(.crossfade, size: 18)
                Text(active ? t("Закончить вечеринку") : t("Свести для вечеринки"))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(active ? Theme.accentInk : Theme.text)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(active ? AnyShapeStyle(Theme.text) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: - Общее

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
    }

    private func pill(_ title: String, selected: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.spring) { action() }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Theme.accentInk : Theme.text)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(selected ? AnyShapeStyle(Theme.text) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Переключатель с подписью, как в листе скорости.
private struct BlendToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: Binding(get: { isOn.wrappedValue }, set: { value in
            withAnimation(Motion.spring) { isOn.wrappedValue = value }
            Haptics.select()
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.accent)
        .padding(.vertical, 10)
    }
}

/// «Как прошлый переход?» 👍/👎 — минуту после перехода (`BlendRate.svelte`).
private struct BlendRateRow: View {
    private var ratings: BlendRatings { .shared }

    var body: some View {
        if let ask = ratings.ask {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Как прошлый переход?"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text(t(BlendView.kindText(ask.kind).name))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                rateButton(score: 1, label: t("Хороший переход"))
                rateButton(score: -1, label: t("Плохой переход"))
            }
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func rateButton(score: Int, label: String) -> some View {
        let chosen = ratings.answer == score
        return Button {
            withAnimation(Motion.spring) { ratings.rate(score) }
        } label: {
            // значка «нравится» нет — тот же палец, перевёрнутый вверх
            SonarIcon(.dislike, filled: chosen, size: 18)
                .scaleEffect(y: score > 0 ? -1 : 1)
                .foregroundStyle(chosen ? Theme.accent : Theme.text)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .disabled(ratings.answer != nil)
        .accessibilityLabel(label)
    }
}

/// Отладочная панель (только Dev, `audio.blend_debug`) — зеркало `BlendDebug.svelte`: анализ играющего и
/// следующего, фаза перехода, память очереди анализа, план.
private struct BlendDebugCard: View {
    @Environment(PlaybackEngine.self) private var engine
    private var hub: BlendAnalysisHub { .shared }

    var body: some View {
        let blend = engine.blend
        let stats = hub.stats()
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Отладочная панель"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            if let track = engine.current { row(t("Отладка::сейчас"), trackLine(track)) }
            if let track = engine.upNext.first { row(t("Отладка::следующий"), trackLine(track)) }
            row(t("Отладка::переход"), t(BlendView.phaseText(blend.phase)) + " · "
                + t("фаза {ms} мс", ["ms": "\(Int(blend.phaseErrMs.rounded()))"]))
            row(t("Отладка::память"), t("анализов {ready} · в очереди {waiting} · считается {running} · ошибок {failed} · посчитано {computed}", [
                "ready": "\(stats.ready)", "waiting": "\(stats.waiting)", "running": "\(stats.running)",
                "failed": "\(stats.failed)", "computed": "\(stats.computed)",
            ]))
            if let next = blend.next {
                row(t("Отладка::план"), t(BlendView.kindText(next.plan.kind).name) + " · "
                    + t("момент {rank} из {total}", ["rank": "\(next.rank)", "total": "\(next.total)"]))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func trackLine(_ track: Track) -> String {
        let line: String
        if let analysis = hub.peek(track.ref) {
            line = BlendView.analysisLine(analysis)
        } else {
            switch hub.state(track.ref) {
            case .pending: line = t("считается…")
            case .failed: line = hub.failure(track.ref) ?? t("анализ не удался")
            default: line = t("нет анализа")
            }
        }
        return "\(track.artist) — \(track.title)\n\(line)"
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
