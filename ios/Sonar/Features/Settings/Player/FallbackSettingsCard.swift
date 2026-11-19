import SwiftUI

/// Плеер → Аудио → «Резервный сервис» (NEXT_PROMPT этап 4, как `FallbackOrder.svelte` на ПК): включатель и
/// порядок, в котором Sonar ищет тот же трек в других сервисах. Список — из реестра (`FallbackPlan.order`),
/// на iPhone порядок меняют стрелки; пишется в `audio.fallback_order` id через запятую.
struct FallbackSettingsCard: View {
    @Environment(SettingsStore.self) private var settings

    private var enabled: Bool { settings.bool(FallbackPlan.enabledKey) }
    private var order: [ServiceID] { FallbackPlan.order(settings.string(FallbackPlan.orderKey)) }

    var body: some View {
        PlayerCard(title: t("Резервный сервис"),
                   footer: t("Где искать трек сначала — порядок меняют стрелки. Яндекс Музыка и VK Музыка ищутся, только если подключены.")) {
            PlayerToggleRow(icon: .transfer, title: t("Резервный сервис"),
                            subtitle: t("Трек недоступен, есть только отрывок или нужна подписка — Sonar найдёт его в другом сервисе (исполнитель, название и длительность совпадают) и скажет, откуда играет."),
                            isOn: Binding(get: { enabled }, set: { settings.set(FallbackPlan.enabledKey, $0) }))
            ForEach(Array(order.enumerated()), id: \.element) { index, id in
                PlayerRowDivider()
                row(index, id)
            }
            .opacity(enabled ? 1 : 0.45)
            .disabled(!enabled)
            .animation(Motion.spring, value: order)
            .animation(Motion.spring, value: enabled)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(t("Порядок резервных сервисов"))
        }
    }

    private func row(_ index: Int, _ id: ServiceID) -> some View {
        HStack(spacing: 14) {
            Text("\(index + 1)")
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 30)
            SonarIcon(LibraryServices.icon(id), size: 22)
                .foregroundStyle(Theme.text)
                .accessibilityHidden(true)
            Text(t(ServiceRegistry.info(id).name))
                .font(.system(size: 17))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            arrow(.arrowUp, label: t("Выше"), index: index, offset: -1)
            arrow(.arrowDown, label: t("Ниже"), index: index, offset: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func arrow(_ icon: IconName, label: String, index: Int, offset: Int) -> some View {
        let possible = order.indices.contains(index + offset)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            let next = FallbackPlan.moved(order, from: index, by: offset)
            withAnimation(Motion.spring) { settings.set(FallbackPlan.orderKey, .string(FallbackPlan.encode(next))) }
        } label: {
            SonarIcon(icon, size: 18)
                .foregroundStyle(possible ? Theme.textSecondary : Theme.textTertiary.opacity(0.4))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!possible)
        .accessibilityLabel(label)
    }
}
