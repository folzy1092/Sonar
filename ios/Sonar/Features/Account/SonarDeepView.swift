import SwiftUI

/// Аккаунт → Подписка Sonar Deep (как ПК `pages/settings/Subscription.svelte`): тариф, срок, что даёт,
/// итог и «Перейти к оплате» — оплата на сайте `sonar.folzy.ru/pay`. Цены и правила — `Core/Account/SonarDeep.swift`.
struct SonarDeepView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var planID = SonarDeep.plans[0].id
    @State private var periodID = SonarDeep.periods[0].id

    private var plan: SonarDeep.Plan { SonarDeep.plans.first { $0.id == planID } ?? SonarDeep.plans[0] }
    private var period: SonarDeep.Period { SonarDeep.periods.first { $0.id == periodID } ?? SonarDeep.periods[0] }

    var body: some View {
        SystemScreen(title: t("Подписка")) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel(t("Тариф"))
                SystemSegments(options: SonarDeep.plans.map { .init(id: $0.id, title: $0.name) }, selection: $planID)
            }
            .cascade(0)
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel(t("Срок"))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(SonarDeep.periods) { option in
                        periodCard(option)
                    }
                }
            }
            .cascade(1)
            summary
                .cascade(2)
        }
        .animation(Motion.spring, value: planID)
        .animation(Motion.spring, value: periodID)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.leading, 4)
    }

    private func periodCard(_ option: SonarDeep.Period) -> some View {
        let on = option.id == periodID
        let saved = SonarDeep.savedPercent(plan, option)
        return Button {
            guard !on else { return }
            withAnimation(Motion.spring) { periodID = option.id }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(periodLabel(option.months))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(on ? Theme.accentInk : Theme.text)
                HStack(spacing: 6) {
                    Text(SonarDeep.rub(SonarDeep.price(plan, option)))
                        .font(.system(size: 14).monospacedDigit())
                        .contentTransition(.numericText())
                    if saved > 0 {
                        Text(verbatim: "−\(saved)\u{00A0}%")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }
                .foregroundStyle(on ? Theme.accentInk.opacity(0.8) : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(on ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Color.clear : Theme.line))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("Подписка на {period}", ["period": periodLabel(period.months)]))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.opacity)
                HStack(spacing: 10) {
                    SystemBadgeIcon(icon: .sparkles, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(SonarDeep.name) \(plan.name)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .contentTransition(.opacity)
                        Text(seatsLabel(plan.seats))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .contentTransition(.opacity)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(SonarDeep.perks.enumerated()), id: \.offset) { index, perk in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        SonarIcon(.check, size: 15)
                            .foregroundStyle(Theme.accent)
                        Text(t(perk))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .cascade(3 + index)
                }
            }
            Text(t("Музыка, лайки, плейлисты, синхронизация и скачивание треков — бесплатно."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                Text(t("Итого"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(SonarDeep.rub(SonarDeep.price(plan, period)))
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
            }
            PrimaryButton(title: t("Перейти к оплате")) { pay() }
            Text(t("Оплата откроется на сайте Sonar. Подписка придёт на аккаунт, с которого ты её оформил."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.line))
    }

    private func periodLabel(_ months: Int) -> String {
        months == 12 ? t("1 год") : tn(months, "{n} месяц", "{n} месяца", "{n} месяцев").replacingOccurrences(of: "{n}", with: String(months))
    }

    private func seatsLabel(_ seats: Int) -> String {
        guard seats > 1 else { return t("Только ты") }
        let more = seats - 1
        return tn(more, "Ты и ещё {n} человек", "Ты и ещё {n} человека", "Ты и ещё {n} человек")
            .replacingOccurrences(of: "{n}", with: String(more))
    }

    private func pay() {
        let username = settings.string(LocalProfile.profileUsername)
        guard let url = SonarDeep.payURL(plan: plan.id, period: period.id, username: username) else { return }
        openURL(url)
    }
}
