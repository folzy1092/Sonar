import SwiftUI

/// «Где играть» (значок устройства в плеере): этот iPhone или Sonar на ПК в той же сети Wi-Fi — пульт
/// (`RemoteControl`). ПК находятся сами (Bonjour); первый раз — код с экрана ПК («Система → Пульт →
/// Привязать iPhone») или QR системной камерой. Звук остаётся на ПК, телефон только управляет.
struct DevicePickerSheet: View {
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    private var remote: RemoteControl { RemoteControl.shared }

    /// Найденные ПК; выбранный по QR, которого нет в поиске, — первым.
    private var computers: [RemotePC] {
        let extra = remote.target.map { pc in remote.pcs.contains { $0.id == pc.id } ? [] : [pc] } ?? []
        return extra + remote.pcs
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Где играть"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 26)
                    .padding(.bottom, 6)
                row(icon: .cellphone, title: t("Этот iPhone"), subtitle: remote.target == nil ? t("Играет здесь") : nil,
                    selected: remote.target == nil, busy: false) {
                    remote.useThisPhone()
                }
                HStack(spacing: 8) {
                    Text(t("Компьютеры в сети"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    if !remote.browseFailed {
                        ProgressView().controlSize(.mini).tint(Theme.textSecondary)
                    }
                }
                .padding(.top, 14)
                if computers.isEmpty {
                    hint
                        .transition(.opacity)
                }
                ForEach(computers) { pc in
                    let selected = remote.target?.id == pc.id
                    row(icon: .computer, title: pc.name, subtitle: selected ? status : nil, selected: selected && remote.isConnected,
                        busy: selected && remote.phase == .connecting) {
                        remote.choose(pc)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if remote.phase == .needsCode, remote.target != nil {
                    codeEntry
                        .transition(.opacity.combined(with: .offset(y: 10)))
                }
                if let pc = syncPC {
                    LANSyncCard(pc: pc)
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .offset(y: 10)))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(Motion.spring, value: computers)
        .animation(Motion.spring, value: remote.phase)
        .animation(Motion.spring, value: remote.target)
        .onAppear {
            remote.startBrowsing()
            remote.reconnectIfNeeded()
        }
        .onDisappear { remote.stopBrowsing() }
        .onChange(of: remote.phase) { _, phase in
            codeFocused = phase == .needsCode
            if phase == .connected { code = "" }
        }
    }

    /// ПК, с которым идёт синк по Wi‑Fi (пока нет сервера), — для карточки синка.
    private var syncPC: RemoteSyncPC? {
        guard let pc = RemoteSyncPC.load(), SyncService.shared.currentTarget() == .lan(pcID: pc.id) else { return nil }
        return pc
    }

    /// Что с выбранным ПК.
    private var status: String {
        switch remote.phase {
        case .idle: ""
        case .connecting: t("Подключаюсь…")
        case .needsCode: t("Нужен код с экрана ПК")
        case .connected: t("Играет здесь")
        case let .failed(text): text
        }
    }

    private var hint: some View {
        Text(remote.browseFailed
            ? t("Нет доступа к локальной сети — разреши его для Sonar: Настройки iPhone → Конфиденциальность → Локальная сеть.")
            : t("Ищу Sonar на компьютерах в этой сети Wi-Fi. На ПК включи Настройки → Система → Пульт."))
            .font(.system(size: 14))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Код с экрана ПК"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(t("На ПК: Настройки → Система → Пульт → «Привязать iPhone». Или наведи камеру iPhone на QR-код."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .kerning(6)
                    .foregroundStyle(Theme.text)
                    .focused($codeFocused)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: code) { _, typed in
                        let clean = RemoteProtocol.cleanCode(typed)
                        if clean != typed { code = clean }
                        if RemoteProtocol.isCode(clean) { remote.submit(code: clean) }
                    }
                Button {
                    remote.submit(code: code)
                } label: {
                    Text(t("Привязать"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 18)
                        .frame(height: 56)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .disabled(!RemoteProtocol.isCode(code))
                .opacity(RemoteProtocol.isCode(code) ? 1 : 0.5)
            }
            if let error = remote.codeError {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .padding(.top, 6)
        .animation(Motion.spring, value: remote.codeError)
    }

    private func row(icon: IconName, title: String, subtitle: String?, selected: Bool, busy: Bool,
                     action: @escaping @MainActor () -> Void) -> some View {
        Button {
            withAnimation(Motion.spring) { action() }
        } label: {
            HStack(spacing: 14) {
                SonarIcon(icon, size: 22)
                    .foregroundStyle(selected ? Theme.accentInk : Theme.text)
                    .frame(width: 44, height: 44)
                    .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                            .lineLimit(2)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
                if busy {
                    ProgressView().tint(Theme.text)
                } else if selected {
                    SonarIcon(.check, size: 20)
                        .foregroundStyle(Theme.accent)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .padding(12)
            .background(selected ? Theme.accentSoft : Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}
