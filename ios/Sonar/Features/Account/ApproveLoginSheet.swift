import SwiftUI

/// Окно «Авторизация в аккаунт» (BOT.md §3, «Окно подтверждения»): кто-то открыл быструю ссылку —
/// бот или новое устройство просит доступ. По центру, фон затемнён и размыт, мимо не закрывается —
/// только кнопками. «Разрешить» первые 3 секунды неактивна: отсчёт и заливка слева направо до белого.
///
/// Показывать поверх всего, пока `AccountStore.shared.pendingApproval != nil`:
/// `.overlay { if let code = account.pendingApproval { ApproveLoginSheet(code: code) } }` или
/// `.approveLoginOverlay()` ниже.
struct ApproveLoginSheet: View {
    let code: String
    var account: AccountStore = .shared

    static let delay: Double = 3

    @State private var info: AuthLinkInfo?
    @State private var loadError: String?
    @State private var shownAt = Date()
    @State private var fill = false
    @State private var busy = false
    @State private var actionError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.45))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {} // мимо — не закрывается
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                card(now: context.date)
            }
            .padding(.horizontal, 20)
        }
        .task { await load() }
    }

    private func load() async {
        do {
            info = try await account.linkInfo(code)
            shownAt = Date()
            withAnimation(reduceMotion ? nil : .linear(duration: Self.delay)) { fill = true }
        } catch {
            loadError = t(error.localizedDescription)
        }
    }

    private func card(now: Date) -> some View {
        let expired = info.map { Double($0.expiresAt) / 1000 < now.timeIntervalSince1970 } ?? false
        let left = max(0, Self.delay - now.timeIntervalSince(shownAt))
        let ready = info != nil && left <= 0 && !expired && !busy
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                SonarIcon(.userSecurity, filled: true, size: 22)
                Text(t("Авторизация в аккаунт"))
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(Theme.danger)

            if let info {
                Group {
                    Text(t("Разрешить доступ к аккаунту")) + Text(" ")
                        + Text("@\(account.user?.username ?? "")").bold() + Text(" ") + Text(t("для:"))
                    HStack(spacing: 10) {
                        SonarIcon(info.requester.kind == .telegram ? .telegram : (info.requester.platform ?? .other).icon, filled: true, size: 20)
                        Text(info.requester.name)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)

                Text(expired
                     ? t("Ссылка истекла")
                     : t("Запрос в {time} · ещё {left}", ["time": AccountFormat.clock(info.createdAt),
                                                          "left": AccountFormat.remaining(until: info.expiresAt, now: now)]))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(expired ? Theme.danger : Theme.textSecondary)
                    .contentTransition(.numericText())
            } else if let loadError {
                AccountError(text: loadError)
            } else {
                ProgressView().tint(Theme.textSecondary).frame(maxWidth: .infinity, minHeight: 60)
            }

            Text(t("Если тебе прислали эту ссылку и просят нажать — не разрешай. Так получают доступ к чужим аккаунтам."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionError { AccountError(text: actionError) }

            VStack(spacing: 10) {
                allowButton(ready: ready, left: left, expired: expired)
                Button { decide(approve: false) } label: {
                    Text(t("Отклонить"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .overlay(Capsule().strokeBorder(Theme.text.opacity(0.35)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(busy || (expired && info != nil))
                .opacity(expired && info != nil ? 0.4 : 1)
            }
        }
        .padding(22)
        .frame(maxWidth: 440)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.line))
        .animation(Motion.spring, value: info)
        .animation(Motion.quick, value: expired)
    }

    /// Чёрный текст на белом; до конца отсчёта — светлая (60 % белого) с заливкой слева направо.
    private func allowButton(ready: Bool, left: Double, expired: Bool) -> some View {
        Button { decide(approve: true) } label: {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.6))
                GeometryReader { proxy in
                    Capsule().fill(Color.white)
                        .frame(width: reduceMotion ? (fill && left <= 0 ? proxy.size.width : 0) : (fill ? proxy.size.width : 0))
                }
                Text(left > 0 && info != nil && !expired
                     ? t("Разрешить · {n}", ["n": String(Int(left.rounded(.up)))])
                     : t("Разрешить"))
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.black)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 52)
            .clipShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!ready)
        .opacity(expired ? 0.4 : 1)
        .accessibilityHint(ready ? "" : t("Станет активной через 3 секунды"))
    }

    private func decide(approve: Bool) {
        // ошибка загрузки — «Отклонить» просто закрывает окно
        guard info != nil else {
            account.pendingApproval = nil
            return
        }
        busy = true
        actionError = nil
        Task {
            defer { busy = false }
            do {
                if approve { try await account.approve(code) } else { try await account.reject(code) }
                Haptics.tap()
            } catch {
                actionError = t(error.localizedDescription)
                if !approve { account.pendingApproval = nil }
            }
        }
    }
}

extension View {
    /// Окно подтверждения входа поверх экрана, пока есть `pendingApproval` (появляется из 0.96 с
    /// прозрачностью, исчезает быстрее). Без сервера `pendingApproval` всегда nil — окна нет.
    @MainActor
    func approveLoginOverlay(_ account: AccountStore = .shared) -> some View {
        overlay {
            if let code = account.pendingApproval {
                ApproveLoginSheet(code: code, account: account)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)).animation(.easeOut(duration: 0.28)),
                                            removal: .opacity.animation(.easeIn(duration: 0.16))))
                    .id(code)
            }
        }
        .animation(Motion.spring, value: account.pendingApproval)
    }
}
