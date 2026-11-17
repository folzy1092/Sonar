import SwiftUI

/// Устройства, где ты вошёл (Аккаунт → Безопасность → Устройства): значок платформы, имя («iPhone 15 Pro»,
/// «Windows 10 (Folzy)»), версия Sonar и когда был в сети. Тап — переименовать или выйти на устройстве.
/// Выходить на **других** можно, только если своя сессия старше 24 часов (правило сервера) — до этого
/// кнопка погашена с подписью.
struct DevicesView: View {
    @State private var account = AccountStore.shared
    @State private var loading = true
    @State private var error: String?
    @State private var selected: AccountDevice?
    @State private var renaming: AccountDevice?
    @State private var newName = ""
    @State private var revoking: AccountDevice?

    var body: some View {
        SystemScreen(title: t("Устройства")) {
            if loading && account.devices.isEmpty {
                ProgressView().tint(Theme.textSecondary).frame(maxWidth: .infinity, minHeight: 120)
            } else if let error, account.devices.isEmpty {
                VStack(spacing: 12) {
                    AccountError(text: error)
                    SecondaryButton(title: t("Попробовать снова")) { Task { await load() } }
                }
            } else {
                if let current = account.currentDevice {
                    SystemSection(title: t("Это устройство")) {
                        row(current)
                    }
                    .cascade(0)
                }
                let others = account.devices.filter { !$0.current }
                if !others.isEmpty {
                    SystemSection(title: t("Другие устройства"), footer: revokeFooter) {
                        ForEach(Array(others.enumerated()), id: \.element.id) { index, device in
                            if index > 0 { RowDivider() }
                            row(device)
                        }
                    }
                    .cascade(1)
                }
                if let error { AccountError(text: error) }
            }
        }
        .animation(Motion.spring, value: account.devices)
        .animation(Motion.spring, value: error)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(selected?.name ?? "", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
                            titleVisibility: .visible, presenting: selected) { device in
            Button(t("Переименовать")) {
                newName = device.name
                renaming = device
            }
            Button(device.current ? t("Выйти из аккаунта") : t("Выйти на устройстве"), role: .destructive) {
                revoking = device
            }
            .disabled(!device.current && !account.canRevokeOthers())
            Button(t("Отмена"), role: .cancel) {}
        } message: { device in
            if !device.current && !account.canRevokeOthers() { Text(t(Self.tooNew)) }
        }
        .alert(t("Название устройства"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { device in
            TextField(t("Название"), text: $newName)
            Button(t("Сохранить")) { rename(device) }
            Button(t("Отмена"), role: .cancel) {}
        }
        .alert(revoking.map { t("Выйти на «{name}»?", ["name": $0.name]) } ?? "",
               isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), presenting: revoking) { device in
            Button(device.current ? t("Выйти из аккаунта") : t("Выйти на устройстве"), role: .destructive) { revoke(device) }
            Button(t("Отмена"), role: .cancel) {}
        } message: { device in
            Text(device.current ? t("Придётся войти заново.") : t("На этом устройстве придётся войти заново."))
        }
    }

    static let tooNew = "Вход был недавно — завершать другие сессии можно через 24 часа"

    private var revokeFooter: String? {
        account.canRevokeOthers() ? nil : t(Self.tooNew)
    }

    private func row(_ device: AccountDevice) -> some View {
        Button { selected = device } label: {
            HStack(spacing: 14) {
                SonarIcon(device.platform.icon, filled: device.current, size: 24)
                    .foregroundStyle(device.current ? Theme.accent : Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.raised.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(subtitle(device))
                        .font(.system(size: 13))
                        .foregroundStyle(device.current ? Theme.success : Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                SonarIcon(.moreH, size: 18).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .accessibilityLabel(device.name)
    }

    private func subtitle(_ device: AccountDevice) -> String {
        var parts: [String] = []
        parts.append(device.current ? t("Сейчас здесь") : AccountFormat.ago(device.lastSeenAt))
        if let version = device.appVersion { parts.append("Sonar \(version)") }
        if let os = device.os, !os.isEmpty { parts.append(os) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        do {
            try await account.loadDevices()
            error = nil
        } catch {
            self.error = t(error.localizedDescription)
        }
        loading = false
    }

    private func rename(_ device: AccountDevice) {
        let name = newName
        Task {
            do { try await account.renameDevice(device.id, name: name) } catch { self.error = t(error.localizedDescription) }
        }
    }

    private func revoke(_ device: AccountDevice) {
        Task {
            do {
                try await account.revokeDevice(device.id)
                Haptics.tap()
            } catch let apiError as APIError where apiError.code == APIError.sessionTooNewCode {
                error = t(Self.tooNew)
            } catch {
                self.error = t(error.localizedDescription)
            }
        }
    }
}
