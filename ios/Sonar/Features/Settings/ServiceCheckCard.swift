import SwiftUI

/// «Проверка сервисов» внизу экрана «Сервисы» (как Windows `Services.svelte`): каждый подключённый сервис ищет
/// одну строку — видно, жив ли ключ и отвечает ли сервис. Логика — `ServiceChecker`; тексты песен не проверяем.
struct ServiceCheckCard: View {
    @Environment(OfflineMode.self) private var offline
    @State private var results: [ServiceCheck]?
    @State private var running = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        SettingsSection(title: t("Проверка сервисов"),
                        footer: offline.isOn
                            ? t("Недоступно в офлайне")
                            : t("Каждый подключённый сервис ищет одну строку — видно, жив ли ключ и отвечает ли сервис")) {
            if let results {
                if results.isEmpty {
                    Text(t("Ни один сервис не подключён"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .transition(.opacity)
                } else {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, check in
                        if index > 0 { RowDivider() }
                        row(check).cascade(index)
                    }
                }
                RowDivider()
            }
            Button(action: start) {
                HStack(spacing: 8) {
                    if running { ProgressView().tint(Theme.accent) }
                    Text(running ? t("Проверяю…") : t("Проверить"))
                        .contentTransition(.opacity)
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(PressableStyle())
            .disabled(running || offline.isOn)
        }
        .animation(Motion.spring, value: results)
        .animation(Motion.spring, value: running)
        .onDisappear { task?.cancel() }
    }

    private func row(_ check: ServiceCheck) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(check.ok ? Theme.success : Theme.danger)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text(t(ServiceRegistry.info(check.service).name))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 12)
            Text(verdict(check))
                .font(.system(size: 14))
                .foregroundStyle(check.ok ? Theme.textSecondary : Theme.danger)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func verdict(_ check: ServiceCheck) -> String {
        if check.ok { return t("Работает · {sec} с", ["sec": ServiceChecker.seconds(check.ms)]) }
        if check.timedOut {
            return t("Не ответил за {sec} с", ["sec": String(Int(ServiceChecker.timeout.components.seconds))])
        }
        return t(check.error ?? "")
    }

    private func start() {
        guard !running, !offline.isOn else { return }
        running = true
        task = Task {
            let connected = await Self.connected()
            let found = await ServiceChecker.run(connected: connected) { id in
                if id == .sp {
                    _ = try await SpotifyCore.shared.search(ServiceChecker.query, limit: 1)
                } else if let service = Service(id: id) {
                    _ = try await MusicCore.shared.search(ServiceChecker.query, in: service, limit: 1)
                }
            }
            running = false
            // ушли с экрана посреди проверки — ответы «отменено» не показываем
            if !Task.isCancelled { results = found }
        }
    }

    /// Подключённые сервисы: четыре из `MusicCore` и Spotify (`sp_dc`) отдельно.
    private static func connected() async -> Set<ServiceID> {
        let status = await MusicCore.shared.status()
        var ids = Set<ServiceID>()
        if status.soundCloud != nil { ids.insert(.sc) }
        if status.yandex != nil { ids.insert(.ym) }
        if status.youtube != nil { ids.insert(.yt) }
        if status.vk != nil { ids.insert(.vk) }
        if await SpotifyCore.shared.account != nil { ids.insert(.sp) }
        return ids
    }
}
