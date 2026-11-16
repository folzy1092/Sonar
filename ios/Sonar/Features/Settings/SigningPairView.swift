import SwiftUI
import UniformTypeIdentifiers

/// Состояние пары для подписи на экране (сам `SigningStore` — не наблюдаемый: файлы и Keychain).
@MainActor
@Observable
final class SigningModel {
    enum CheckState: Equatable {
        case idle
        case checking
        case ok
        case failed(String)
    }

    private(set) var hasCertificate = false
    private(set) var hasProfile = false
    private(set) var hasPassword = false
    private(set) var profile: ProvisioningProfile?
    private(set) var check: CheckState = .idle
    var importError: String?

    @ObservationIgnored private let store: SigningStore
    @ObservationIgnored private var checkRun = 0

    init(store: SigningStore = .shared) {
        self.store = store
        reload()
    }

    var isConfigured: Bool { hasCertificate && hasProfile }

    /// «Готов» / «Не выбран» — в строке «Сертификат для подписи».
    var summary: String {
        if !isConfigured { return "Не выбран" }
        switch check {
        case .failed: return "Не подходит"
        default: return profile?.isExpired() == true ? "Профиль истёк" : "Готов"
        }
    }

    func reload() {
        hasCertificate = store.hasCertificate
        hasProfile = store.hasProfile
        hasPassword = store.password != nil
        profile = store.profile
    }

    func importCertificate(_ result: Result<URL, Error>) {
        importFile(result) { try self.store.importCertificate(from: $0) }
    }

    func importProfile(_ result: Result<URL, Error>) {
        importFile(result) { try self.store.importProfile(from: $0) }
    }

    func savePassword(_ password: String) {
        store.setPassword(password)
        reload()
        recheck()
    }

    func remove() {
        store.removeAll()
        check = .idle
        reload()
    }

    /// Открыть `.p12` паролем и сверить с профилем — медленно, не на главном потоке.
    func recheck() {
        guard isConfigured else {
            check = .idle
            return
        }
        checkRun += 1
        let run = checkRun
        check = .checking
        let store = self.store
        Task {
            let problem = await Task.detached(priority: .userInitiated) { store.check() }.value
            guard run == self.checkRun else { return }
            withAnimation(Motion.spring) {
                self.check = problem.map { .failed($0) } ?? .ok
            }
        }
    }

    private func importFile(_ result: Result<URL, Error>, _ save: (URL) throws -> Void) {
        do {
            try save(try result.get())
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
        reload()
        recheck()
    }
}

/// «Сертификат для подписи»: пара `.p12` + пароль + `.mobileprovision`, которой Sonar сам подписывает
/// обновления (SETTINGS.md «Автообновление»). Только на этом iPhone — не синхронизируется.
struct SigningPairView: View {
    @Environment(SigningModel.self) private var model
    @State private var password = ""
    /// Один `fileImporter` на экран: два на одном уровне в SwiftUI мешают друг другу.
    @State private var picking: Pick?
    @State private var showImporter = false
    @State private var confirmRemove = false
    @FocusState private var passwordFocused: Bool

    private enum Pick {
        case certificate, profile
    }

    private static let profileType = UTType(filenameExtension: "mobileprovision") ?? .data

    var body: some View {
        SettingsScreen(title: "Сертификат") {
            Text("Sonar подписывает обновления твоей парой — той же, которой ты ставил его через ESign или Feather. Файлы и пароль остаются только на этом iPhone.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)
                .cascade(0)

            SettingsSection(title: "Сертификат .p12") {
                Button { pick(.certificate) } label: {
                    SettingsRowLabel(icon: "key", title: model.hasCertificate ? "Сертификат выбран" : "Выбрать .p12",
                                     value: model.hasCertificate ? "Заменить" : nil)
                }
                .buttonStyle(PressableStyle(scale: 0.99))
                RowDivider()
                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26)
                    SecureField(model.hasPassword ? "Пароль сохранён" : "Пароль от .p12", text: $password)
                        .textContentType(.password)
                        .focused($passwordFocused)
                        .submitLabel(.done)
                        .onSubmit(savePassword)
                    if !password.isEmpty {
                        Button("Сохранить", action: savePassword)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .animation(Motion.spring, value: password.isEmpty)
            }
            .cascade(1)

            SettingsSection(title: "Профиль .mobileprovision") {
                Button { pick(.profile) } label: {
                    SettingsRowLabel(icon: "doc.badge.gearshape", title: model.hasProfile ? (model.profile?.name.nonEmpty ?? "Профиль выбран") : "Выбрать .mobileprovision",
                                     value: model.hasProfile ? "Заменить" : nil)
                }
                .buttonStyle(PressableStyle(scale: 0.99))
                if let profile = model.profile {
                    RowDivider()
                    ProfileFacts(profile: profile)
                        .transition(.opacity)
                }
            }
            .cascade(2)

            if let error = model.importError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if model.isConfigured {
                CheckRow(state: model.check, recheck: model.recheck)
                    .cascade(3)
                SecondaryButton(title: "Удалить пару", icon: "trash", role: .destructive) { confirmRemove = true }
                    .cascade(4)
                    .confirmationDialog("Удалить сертификат, пароль и профиль с этого iPhone?", isPresented: $confirmRemove, titleVisibility: .visible) {
                        Button("Удалить", role: .destructive) { withAnimation(Motion.spring) { model.remove() } }
                        Button("Отмена", role: .cancel) {}
                    }
            }
        }
        .animation(Motion.spring, value: model.isConfigured)
        .animation(Motion.spring, value: model.importError)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: picking == .certificate ? [.pkcs12, .data] : [Self.profileType, .data]) { result in
            let target = picking
            picking = nil
            withAnimation(Motion.spring) {
                if target == .certificate { model.importCertificate(result) } else { model.importProfile(result) }
            }
        }
        .onAppear {
            model.reload()
            if model.check == .idle { model.recheck() }
        }
    }

    private func pick(_ target: Pick) {
        picking = target
        showImporter = true
    }

    private func savePassword() {
        guard !password.isEmpty else { return }
        model.savePassword(password)
        password = ""
        passwordFocused = false
    }
}

/// Что внутри профиля: команда, App ID, срок (истёк — красным), устройства, подходит ли к установленному id.
private struct ProfileFacts: View {
    let profile: ProvisioningProfile
    private let installedId = Bundle.main.bundleIdentifier ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            fact("Команда", profile.teamName.isEmpty ? profile.teamId : "\(profile.teamName) (\(profile.teamId))")
            fact("App ID", profile.applicationIdentifier)
            if let date = profile.expirationDate {
                fact("Действует до", date.formatted(date: .long, time: .omitted), color: profile.isExpired() ? Theme.danger : nil)
            }
            fact("Устройства", profile.provisionsAllDevices ? "все" : "\(profile.deviceCount)")
            if !installedId.isEmpty, !profile.allows(bundleId: installedId) {
                Label("Профиль не подходит к установленному Sonar (\(installedId)) — iOS не примет обновление.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(16)
    }

    private func fact(_ title: String, _ value: String, color: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color ?? Theme.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

/// Результат проверки пары: «Пара подходит» или причина.
private struct CheckRow: View {
    let state: SigningModel.CheckState
    let recheck: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch state {
                case .checking: ProgressView().tint(Theme.textSecondary)
                case .ok: Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
                case .failed: Image(systemName: "xmark.seal.fill").foregroundStyle(Theme.danger)
                case .idle: Image(systemName: "seal").foregroundStyle(Theme.textSecondary)
                }
            }
            .font(.system(size: 20))
            .frame(width: 26)
            .transition(.scale.combined(with: .opacity))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.opacity)
                if case let .failed(reason) = state {
                    Text(reason)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if state != .checking {
                Button("Проверить", action: recheck)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.line))
        .animation(Motion.spring, value: state)
    }

    private var title: String {
        switch state {
        case .idle: "Пара не проверена"
        case .checking: "Проверяю пару…"
        case .ok: "Пара подходит"
        case .failed: "Пара не подходит"
        }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
