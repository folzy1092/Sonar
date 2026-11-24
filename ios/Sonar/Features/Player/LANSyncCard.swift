import SwiftUI

/// «Где играть» → синк с ПК по Wi‑Fi, пока нет сервера Sonar: с каким ПК, когда последний раз, ошибка и
/// кнопка «Синхронизировать». Показывается, только когда синк идёт с этим ПК (`SyncTarget.lan`).
struct LANSyncCard: View {
    let pc: RemoteSyncPC
    private var sync: SyncService { SyncService.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Синхронизация с {name}", ["name": pc.name]))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 12) {
                Text(status)
                    .font(.system(size: 14, weight: sync.lastError == nil ? .regular : .medium))
                    .foregroundStyle(sync.lastError == nil ? Theme.text : Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
                Button {
                    Task { await sync.syncNow() }
                } label: {
                    ZStack {
                        Text(t("Синхронизировать")).opacity(sync.syncing ? 0 : 1)
                        if sync.syncing { ProgressView().tint(Theme.accentInk) }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(sync.syncing)
            }
            Text(t("Пока нет сервера Sonar, лайки и настройки синхронизируются с этим ПК по Wi‑Fi"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .animation(Motion.spring, value: sync.syncing)
        .animation(Motion.spring, value: sync.lastError)
    }

    private var status: String {
        if sync.syncing { return t("Синхронизирую…") }
        if let error = sync.lastError { return error }
        guard let at = sync.lastSyncAt else { return t("Ещё не синхронизировались") }
        return t("Синхронизировано {when}", ["when": AccountFormat.ago(Int64(at.timeIntervalSince1970 * 1000))])
    }
}
