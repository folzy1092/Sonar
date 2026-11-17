import SwiftUI
import UIKit

/// Интеграции → «Last.fm» (как Windows `Integrations.svelte`, группа Last.fm): вход в один клик через
/// окно входа iOS (`LastfmLogin`), карточка с аватаром и крестиком, «История прослушиваний»
/// (`integrations.lastfm.scrobble`) и «Сейчас играет» (`integrations.lastfm.now_playing`), очередь
/// неотправленных. Ключа Last.fm нет в сборке — честно «появится в сборке с ключом».
struct LastfmSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var scrobbler = LastfmScrobbler.shared
    @State private var login = LastfmLogin()
    @State private var busy = false
    @State private var confirmLogout = false

    private static let brand = Color(red: 0.84, green: 0.06, blue: 0.03)

    private func toggle(_ key: String) -> Binding<Bool> {
        Binding(get: { settings.bool(key) }, set: { settings.set(key, $0) })
    }

    var body: some View {
        SystemScreen(title: "Last.fm") {
            hero
                .cascade(0)

            if !scrobbler.available {
                SystemSection(footer: t("Ключ приложения Last.fm добавляется при сборке на CI. Как только он будет в сборке — вход заработает здесь в один клик.")) {
                    SystemRow(icon: .lock, title: t("Last.fm появится в сборке с ключом"),
                              subtitle: t("В этой сборке ключа Last.fm нет"))
                }
                .cascade(1)
            } else if let session = scrobbler.session {
                account(session)
                    .cascade(1)
                SystemSection(title: t("Что отправлять")) {
                    SystemToggle(icon: .history, title: t("История прослушиваний"),
                                 subtitle: t("Скробблить трек, когда прослушана половина или 4 минуты"),
                                 isOn: toggle(LastfmScrobbler.scrobbleKey))
                    RowDivider()
                    SystemToggle(icon: .headphone, title: t("Сейчас играет"), subtitle: t("Показывать текущий трек в профиле"),
                                 isOn: toggle(LastfmScrobbler.nowPlayingKey))
                }
                .cascade(2)
                status
                    .cascade(3)
            } else {
                connect
                    .cascade(1)
            }
        }
        .animation(Motion.spring, value: scrobbler.session)
        .animation(Motion.spring, value: busy)
        .confirmationDialog(t("Отключить Last.fm?"), isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(t("Отключить"), role: .destructive) {
                scrobbler.logout()
                router.say(t("Last.fm отключён"))
            }
            Button(t("Отмена"), role: .cancel) {}
        }
        .onDisappear { if busy { login.cancel() } }
    }

    /// Знак и пара слов о том, что даёт Last.fm.
    private var hero: some View {
        HStack(spacing: 14) {
            SystemBadgeIcon(icon: .lastfm, size: 56, tint: Self.brand)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Last.fm")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(t("История и «сейчас играет» в твоём профиле"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var connect: some View {
        VStack(spacing: 12) {
            Button {
                Task { await signIn() }
            } label: {
                HStack(spacing: 10) {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        SonarIcon(.lastfm, size: 20)
                    }
                    Text(busy ? t("Подтверди вход в браузере…") : t("Войти через Last.fm"))
                        .font(.system(size: 17, weight: .semibold))
                        .contentTransition(.opacity)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Self.brand, in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .disabled(busy)
            if busy {
                Button(t("Отмена")) { login.cancel() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            } else {
                Text(t("Подключи в один клик — история и «сейчас играет» в твоём профиле"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func account(_ session: LastfmSession) -> some View {
        HStack(spacing: 14) {
            CoverImage(url: session.avatarURL, cornerRadius: 30)
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay {
                    if session.avatarURL == nil {
                        Text(verbatim: String(session.name.prefix(1)).uppercased())
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Self.brand, in: Circle())
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                Button {
                    if let url = URL(string: "https://www.last.fm/user/\(session.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? session.name)") {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(t("Открыть профиль"))
                        SonarIcon(.externalLink, size: 13)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(PressableStyle())
            }
            Spacer(minLength: 0)
            CircleButton(icon: .close, size: 40, iconSize: 18, label: t("Отключить Last.fm")) { confirmLogout = true }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Self.brand.opacity(0.35)))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    /// Что с отправкой: ждёт ли что-то, когда ушло последнее, ошибка.
    @ViewBuilder
    private var status: some View {
        let pending = scrobbler.pending.count
        SystemSection(footer: scrobbler.lastError) {
            if pending > 0 {
                SystemButtonRow(icon: .time, title: t("Ждут отправки"), subtitle: t("Уйдут, как только Last.fm ответит"),
                                value: "\(pending)") { scrobbler.flush() }
            } else {
                SystemRow(icon: .check, title: t("Всё отправлено"),
                          subtitle: scrobbler.lastSent.map { t("Последний скроббл — {time}", ["time": $0.formatted(.relative(presentation: .named).locale(currentLang().locale))]) })
            }
        }
    }

    private func signIn() async {
        guard let api = scrobbler.client else { return }
        busy = true
        defer { busy = false }
        do {
            let session = try await login.signIn(api: api)
            scrobbler.setSession(session)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            router.say(t("Last.fm подключён: {name}", ["name": session.name]))
        } catch let error as LastfmError where error.code == -2 {
            router.say(t("Вход отменён"))
        } catch {
            router.say((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
