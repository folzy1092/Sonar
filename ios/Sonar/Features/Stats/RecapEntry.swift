import SwiftUI

/// Периоды с прослушиваниями — пересчёт вне главного потока на каждую запись журнала.
@MainActor
private func loadPeriods() async -> RecapPeriods {
    let rows = PlayLog.shared.rows
    return await Task.detached(priority: .utility) {
        RecapEngine.periods(rows: rows, now: Date())
    }.value
}

/// Приглашение на Главной (как ПК `RecapInvite.svelte`): первая неделя месяца — итоги прошлого месяца,
/// декабрь и первая неделя января — итоги года. «Открыть» и крестик запоминают показанные итоги
/// (`stats.recap_seen`), второй раз то же приглашение не приходит.
struct RecapInvite: View {
    @Environment(SettingsStore.self) private var settings
    @State private var log = PlayLog.shared
    @State private var periods = RecapPeriods()
    @State private var opened: RecapRef?

    private var invite: RecapRef? {
        let seen = settings.string("stats.recap_seen")
        return RecapEngine.invite(now: Date(), periods: periods, seen: seen.isEmpty ? nil : seen)
    }

    var body: some View {
        // Обёртка остаётся, когда приглашение скрыто, — иначе пропал бы и открытый экран итогов.
        VStack(spacing: 0) {
            if let ref = invite {
                card(ref)
                    .padding(.top, 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(Motion.spring, value: invite)
        .task(id: log.revision) { periods = await loadPeriods() }
        .fullScreenCover(item: $opened) { RecapView(ref: $0) }
    }

    private func card(_ ref: RecapRef) -> some View {
        HStack(spacing: 14) {
            SonarIcon(.sparkles, filled: true, size: 22)
                .foregroundStyle(Theme.accentInk)
                .frame(width: 46, height: 46)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("\(RecapText.kindTitle(ref)) · \(RecapText.periodTitle(ref))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(RecapText.introLine(ref))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(t("Открыть")) { opened = ref }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Theme.accent, in: Capsule())
                .buttonStyle(PressableStyle())
            Button {
                settings.set("stats.recap_seen", .string(ref.id))
            } label: {
                SonarIcon(.close, size: 16)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(t("Скрыть"))
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Статистика → «Итоги» (как ПК `StatsRecaps.svelte`): годы и месяцы с прослушиваниями, свежие первыми.
struct RecapSection: View {
    @State private var log = PlayLog.shared
    @State private var periods = RecapPeriods()
    @State private var opened: RecapRef?

    /// Месяцев — не больше года назад: старее открываются через итоги года.
    private static let maxMonths = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !periods.isEmpty {
                Text(t("Итоги"))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.text)
                FlowChips(items: chips) { opened = $0 }
            }
        }
        .animation(Motion.spring, value: periods)
        .task(id: log.revision) { periods = await loadPeriods() }
        .fullScreenCover(item: $opened) { RecapView(ref: $0) }
    }

    private var chips: [RecapRef] {
        periods.years.map(\.ref) + periods.months.prefix(Self.maxMonths).map(\.ref)
    }
}

/// Кнопки периодов в несколько строк.
private struct FlowChips: View {
    let items: [RecapRef]
    let open: (RecapRef) -> Void

    var body: some View {
        RecapFlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element) { index, ref in
                Button { open(ref) } label: { label(ref) }
                    .buttonStyle(PressableStyle(scale: 0.96))
                    .cascade(index)
            }
        }
    }

    private func label(_ ref: RecapRef) -> some View {
        let year = ref.kind == .year
        return HStack(spacing: 6) {
            if year {
                SonarIcon(.sparkles, filled: true, size: 15)
                    .foregroundStyle(Theme.accent)
                Text("\(t("Итоги года")) · \(RecapText.periodTitle(ref))")
            } else {
                Text(RecapText.periodTitle(ref))
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(year ? Theme.accentSoft : Theme.card, in: Capsule())
    }
}

/// Раскладка «строками с переносом».
private struct RecapFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var items: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.items.isEmpty {
                let nextY = current.y + current.height + spacing
                rows.append(current)
                current = Row(y: nextY)
            }
            let x = current.items.isEmpty ? 0 : current.width + spacing
            current.items.append(index)
            current.width = x + size.width
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
