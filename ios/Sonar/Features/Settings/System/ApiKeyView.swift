import SwiftUI
import UIKit

/// Интеграции → Ключ API (API.md §7): один ключ на аккаунт, общий с ботом. По нему selfbot и другие сервисы читают
/// «сейчас играет» (`GET /oauth/now?token=…`). Создать, перевыпустить (старый сразу перестаёт работать), удалить;
/// ключ скрыт, пока не нажмёшь «Показать». Без входа — подсказка. Как на ПК (Интеграции → «Ключ API»).
struct ApiKeyView: View {
    @State private var account = AccountStore.shared
    @State private var info: ApiKeyInfo?
    @State private var loading = true
    @State private var revealed = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var confirmNew = false
    @State private var confirmDelete = false

    var body: some View {
        SystemScreen(title: t("Ключ API")) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.12)).frame(width: 96, height: 96)
                    Circle().strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1).frame(width: 74, height: 74)
                    SonarIcon(.key, filled: true, size: 34).foregroundStyle(Theme.accent)
                }
                Text(t("Ключ, по которому твои боты и сервисы берут из Sonar то, что ты сейчас слушаешь."))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .cascade(0)

            if !account.signedIn {
                SystemSection(footer: t("Войди в аккаунт Sonar, чтобы получить ключ API.")) {
                    SystemRow(icon: .user, title: t("Нет входа в аккаунт Sonar"))
                }
                .cascade(1)
            } else if let key = info?.key {
                SystemSection(title: t("Ключ API"), footer: t("Ключ и адрес — как пароль: не показывай их другим.")) {
                    SystemRow(icon: .key, title: revealed ? key : Self.masked(key), subtitle: created(info?.createdAt))
                    RowDivider()
                    SystemButtonRow(icon: .eyeClosed, title: revealed ? t("Скрыть ключ") : t("Показать ключ")) {
                        withAnimation(Motion.spring) { revealed.toggle() }
                    }
                    RowDivider()
                    SystemButtonRow(icon: .copy, title: t("Скопировать ключ")) { copy(key, done: t("Ключ скопирован")) }
                    RowDivider()
                    SystemButtonRow(icon: .link, title: t("Скопировать адрес «Сейчас играет»")) {
                        copy(Self.nowURL(base: account.apiBaseURL, key: key), done: t("Адрес скопирован"))
                    }
                }
                .cascade(1)

                SystemSection {
                    SystemButtonRow(icon: .refresh, title: t("Перевыпустить ключ"), enabled: !busy) { confirmNew = true }
                    RowDivider()
                    SystemButtonRow(icon: .trash, title: t("Удалить ключ"), tint: Theme.danger, enabled: !busy) { confirmDelete = true }
                }
                .cascade(2)
            } else {
                SystemSection(footer: loading ? nil : t("Ключа ещё нет — создай, и боты и сервисы смогут читать «Сейчас играет».")) {
                    if loading {
                        HStack { Spacer(); ProgressView().tint(Theme.textSecondary); Spacer() }.padding(20)
                    } else {
                        SystemButtonRow(icon: .key, title: t("Создать ключ"), enabled: !busy) { create() }
                    }
                }
                .cascade(1)
            }

            if let error { AccountError(text: error) }
            if let notice {
                Text(notice)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.success)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
        .animation(Motion.spring, value: info)
        .animation(Motion.spring, value: error)
        .animation(Motion.spring, value: notice)
        .task { await load() }
        .alert(t("Перевыпустить ключ?"), isPresented: $confirmNew) {
            Button(t("Перевыпустить"), role: .destructive) { create() }
            Button(t("Отмена"), role: .cancel) {}
        } message: {
            Text(t("Старый ключ сразу перестанет работать — обнови его в selfbot и других сервисах."))
        }
        .alert(t("Удалить ключ?"), isPresented: $confirmDelete) {
            Button(t("Удалить"), role: .destructive) { remove() }
            Button(t("Отмена"), role: .cancel) {}
        } message: {
            Text(t("Сервисы с этим ключом больше не получат «Сейчас играет»."))
        }
    }

    // MARK: чистые куски (тесты)

    /// «snr_ab••••••••yz»: начало и конец, середина скрыта.
    static func masked(_ key: String) -> String {
        guard key.count > 10 else { return String(repeating: "•", count: max(key.count, 4)) }
        return String(key.prefix(6)) + String(repeating: "•", count: 8) + String(key.suffix(4))
    }

    /// Адрес «сейчас играет» для сервиса: `<API>/oauth/now?token=<ключ>`.
    static func nowURL(base: URL?, key: String) -> String {
        let root = base?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://try-sonar.ru/api"
        return "\(root)/oauth/now?token=\(key)"
    }

    // MARK: действия

    private func created(_ at: Int64?) -> String? {
        guard let at else { return nil }
        let formatter = DateFormatter()
        formatter.locale = currentLang().locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return t("Создан {date}", ["date": formatter.string(from: Date(timeIntervalSince1970: Double(at) / 1000))])
    }

    private func load() async {
        defer { loading = false }
        guard account.signedIn else { return }
        do {
            info = try await account.apiKey()
        } catch {
            self.error = t(error.localizedDescription)
        }
    }

    private func copy(_ text: String, done: String) {
        UIPasteboard.general.string = text
        Haptics.tap()
        notice = done
    }

    private func create() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                info = try await account.newApiKey()
                revealed = true // новый ключ видно сразу — его обычно тут же копируют
                notice = t("Ключ создан")
                Haptics.tap()
            } catch {
                self.error = t(error.localizedDescription)
            }
        }
    }

    private func remove() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await account.deleteApiKey()
                info = ApiKeyInfo(key: nil, createdAt: nil)
                revealed = false
                notice = t("Ключ удалён")
            } catch {
                self.error = t(error.localizedDescription)
            }
        }
    }
}
