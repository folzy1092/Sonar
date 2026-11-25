import SwiftUI
import UIKit

/// Ворота входа (когда сервер включён и входа нет): Войти / Создать аккаунт / Войти через Telegram —
/// как бот (BOT.md §2.1–2.3, §3) и ПК. В приложении вход всегда начинается с логина и пароля; Telegram —
/// быстрая ссылка `?start=link_<code>`: подтверждаешь в боте или на устройстве, где уже вошёл.
///
/// С 2026-11-25 — лист из Профиля («Войти или создать аккаунт»), вход на iPhone по желанию.
struct AuthGateView: View {
    enum Step: Hashable {
        case welcome, login, register, link
    }

    @State private var step: Step = .welcome
    @State private var account = AccountStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.18), .clear], center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    header
                    Group {
                        switch step {
                        case .welcome: welcome
                        case .login: LoginForm(account: account, back: { go(.welcome) }, register: { go(.register) })
                        case .register: RegisterForm(account: account, back: { go(.welcome) })
                        case .link: LinkLoginView(account: account, back: { go(.welcome) })
                        }
                    }
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)),
                                                                     removal: .opacity.combined(with: .move(edge: .leading))))
                    .id(step)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 40)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }

    private func go(_ next: Step) {
        Haptics.tap()
        withAnimation(Motion.spring) { step = next }
    }

    private var header: some View {
        VStack(spacing: 14) {
            SonarIcon(.logo, filled: true, size: 64)
                .foregroundStyle(Theme.accent)
                .frame(width: 96, height: 96)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(Theme.accent.opacity(0.25)))
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.text)
                .contentTransition(.opacity)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .animation(Motion.spring, value: step)
    }

    private var title: String {
        switch step {
        case .welcome: "Sonar"
        case .login: t("Вход")
        case .register: t("Регистрация")
        case .link: t("Вход через Telegram")
        }
    }

    private var subtitle: String {
        switch step {
        case .welcome: t("Войди, чтобы лайки, плейлисты и настройки были общими на телефоне и компьютере")
        case .login: t("Логин и пароль от аккаунта Sonar")
        case .register: t("Логин — навсегда, имя и @username поменяешь потом")
        case .link: t("Подтверди вход в боте @SonarMusicApp или на устройстве, где ты уже вошёл")
        }
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: t("Войти")) { go(.login) }
                .cascade(0)
            SecondaryButton(title: t("Создать аккаунт")) { go(.register) }
                .cascade(1)
            Button { go(.link) } label: {
                HStack(spacing: 10) {
                    SonarIcon(.telegram, filled: true, size: 20)
                    Text(t("Войти через Telegram"))
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line))
            }
            .buttonStyle(PressableStyle())
            .cascade(2)
            Text(t("Почты нет: вход — логин и пароль или Telegram."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .cascade(3)
        }
    }
}

/// Вход логином и паролем.
private struct LoginForm: View {
    let account: AccountStore
    let back: @MainActor () -> Void
    let register: @MainActor () -> Void

    @State private var login = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Int?

    private var ready: Bool { !login.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AccountField(title: t("Логин"), text: $login, contentType: .username) { focus = 1 }
                .focused($focus, equals: 0)
            AccountField(title: t("Пароль"), text: $password, secure: true, contentType: .password) { submit() }
                .focused($focus, equals: 1)
            if let error { AccountError(text: error) }
            PrimaryButton(title: busy ? t("Вхожу…") : t("Войти"), enabled: ready) { submit() }
                .padding(.top, 4)
            HStack {
                Button(t("навигация::Назад"), action: back)
                Spacer()
                Button(t("Создать аккаунт"), action: register)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 4)
        }
        .animation(Motion.spring, value: error)
        .onAppear { focus = 0 }
    }

    private func submit() {
        guard ready else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await account.login(login, password: password)
                Haptics.tap()
            } catch {
                self.error = t(error.localizedDescription)
                password = ""
                focus = 1
            }
        }
    }
}

/// Регистрация: логин (3–24, `a-z 0-9 _ .`) → пароль (от 8) → ещё раз — как в боте.
private struct RegisterForm: View {
    let account: AccountStore
    let back: @MainActor () -> Void

    @State private var login = ""
    @State private var password = ""
    @State private var repeatPassword = ""
    @State private var busy = false
    @State private var error: String?
    /// Ошибки поля — после ухода с поля (не на каждой букве).
    @State private var touched: Set<Int> = []
    @FocusState private var focus: Int?

    private var loginProblem: String? { AccountValidation.loginProblem(login).map { t($0) } }
    private var passwordProblem: String? { AccountValidation.passwordProblem(password).map { t($0) } }
    private var repeatProblem: String? { repeatPassword == password ? nil : t("Пароли не совпадают") }
    private var ready: Bool { loginProblem == nil && passwordProblem == nil && repeatProblem == nil && !busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AccountField(title: t("Логин"), text: $login, contentType: .username,
                         problem: touched.contains(0) && !login.isEmpty ? loginProblem : nil) { focus = 1 }
                .focused($focus, equals: 0)
            AccountField(title: t("Пароль"), text: $password, secure: true, contentType: .newPassword,
                         problem: touched.contains(1) && !password.isEmpty ? passwordProblem : nil) { focus = 2 }
                .focused($focus, equals: 1)
            AccountField(title: t("Пароль ещё раз"), text: $repeatPassword, secure: true, contentType: .newPassword,
                         problem: touched.contains(2) && !repeatPassword.isEmpty ? repeatProblem : nil) { submit() }
                .focused($focus, equals: 2)
            if let error { AccountError(text: error) }
            PrimaryButton(title: busy ? t("Создаю…") : t("Создать аккаунт"), enabled: ready) { submit() }
                .padding(.top, 4)
            Button(t("навигация::Назад"), action: back)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)
        }
        .animation(Motion.spring, value: error)
        .onChange(of: focus) { old, _ in
            if let old { touched.insert(old) }
        }
        .onChange(of: login) { error = nil }
        .onAppear { focus = 0 }
    }

    private func submit() {
        touched = [0, 1, 2]
        guard ready else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await account.register(login, password: password)
                Haptics.tap()
            } catch {
                self.error = t(error.localizedDescription)
            }
        }
    }
}

/// Вход быстрой ссылкой: «Открыть в Telegram» (бот `?start=link_<code>`), QR и ссылка для другого
/// устройства, отсчёт 5 минут; подтвердили — вошли сами.
struct LinkLoginView: View {
    let account: AccountStore
    let back: @MainActor () -> Void

    @State private var link: AuthLink?
    @State private var outcome: AuthLinkPoll.Status?
    @State private var error: String?
    @State private var copied = false
    @State private var attempt = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            if let link {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(link, now: context.date)
                }
                .transition(.opacity)
            } else if let error {
                AccountError(text: error)
                SecondaryButton(title: t("Попробовать снова")) { attempt += 1 }
            } else {
                ProgressView().tint(Theme.textSecondary).frame(height: 120)
            }
            Button(t("навигация::Назад"), action: back)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .animation(Motion.spring, value: link)
        .animation(Motion.spring, value: outcome)
        .task(id: attempt) { await run() }
    }

    private func run() async {
        link = nil
        outcome = nil
        error = nil
        do {
            let fresh = try await account.createLoginLink()
            link = fresh
            outcome = try await account.waitForLink(fresh)
            if outcome == .approved { Haptics.tap() }
        } catch is CancellationError {
        } catch {
            self.error = t(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func content(_ link: AuthLink, now: Date) -> some View {
        let expired = outcome == .expired || Double(link.expiresAt) / 1000 < now.timeIntervalSince1970
        VStack(spacing: 16) {
            if outcome == .rejected || expired {
                VStack(spacing: 8) {
                    Text(outcome == .rejected ? t("Вход отклонён") : t("Ссылка истекла"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    SecondaryButton(title: t("Новая ссылка")) { attempt += 1 }
                }
            } else {
                Button {
                    if let url = link.telegramURL { openURL(url) }
                } label: {
                    HStack(spacing: 10) {
                        SonarIcon(.telegram, filled: true, size: 20)
                        Text(t("Открыть в Telegram"))
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableStyle())

                VStack(spacing: 10) {
                    if let url = link.appURL?.absoluteString {
                        QRCodeView(text: link.url.isEmpty ? url : link.url)
                            .frame(width: 180, height: 180)
                    }
                    Text(t("Или отсканируй на устройстве, где ты уже вошёл в Sonar"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button {
                        UIPasteboard.general.string = link.url.isEmpty ? link.appURL?.absoluteString : link.url
                        withAnimation(Motion.quick) { copied = true }
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 8) {
                            SonarIcon(copied ? .check : .copy, size: 16)
                            Text(copied ? t("Скопировано") : t("Скопировать ссылку"))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Theme.card, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.line))

                HStack(spacing: 8) {
                    ProgressView().tint(Theme.textSecondary)
                    Text(t("Жду подтверждения · ещё {time}", ["time": AccountFormat.remaining(until: link.expiresAt, now: now)]))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.numericText())
                }
            }
        }
    }
}
