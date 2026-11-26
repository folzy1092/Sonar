import SwiftUI
import UIKit

/// Система → «Общее» (SETTINGS.md «Основные — general.*», как Windows `General.svelte`): язык
/// (`general.language`, сразу), платформа главной (`general.platform`), медиатека (куда добавлять треки —
/// `general.add_position`; облако — с сервером), «Виджет и Siri» (быстрый плейлист — `widget.quick_playlist`; скрыт, пока `Features.widgetsVisible = false`),
/// синхронизация (с сервером), внизу — «О приложении».
/// «Авто похожие» — в Очереди.
struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var languageSheet = false
    @State private var quickSheet = false
    @State private var account = AccountStore.shared
    @State private var sync = SyncService.shared
    @State private var showSignIn = false

    private var lang: Lang { currentLang() }

    private var syncState: SyncCardState {
        SyncCardState.of(signedIn: account.signedIn, syncing: sync.syncing, lastSyncAt: sync.lastSyncAt, lastError: sync.lastError)
    }

    /// Синхронизация через сервер Sonar: лайки, плейлисты и настройки едут сами, как только вошёл (обмен раз в пару минут);
    /// слияние идёт в обе стороны, ничего не заменяется. Без входа — приглашение войти.
    private var syncSection: some View {
        let state = syncState
        return SystemSection(title: t("Синхронизация"), footer: state == .signedOut
            ? t("Лайки, плейлисты и настройки станут общими на iPhone и компьютере после входа в аккаунт.")
            : t("Лайки, плейлисты и настройки едут на сервер и на твои другие устройства сами, раз в пару минут.")) {
            SystemRow(icon: state == .signedOut ? .cloud : .cloudSync, title: syncTitle(state), subtitle: syncSubtitle(state),
                      value: syncSummary(state))
            RowDivider()
            if state == .signedOut {
                SystemButtonRow(icon: .user, title: t("Войти или создать аккаунт"), chevron: true) { showSignIn = true }
            } else {
                SystemButtonRow(icon: .refresh, title: t("Синхронизировать сейчас"), enabled: state.canSyncNow) {
                    Task { await sync.syncNow() }
                }
            }
        }
        .sheet(isPresented: $showSignIn) { AuthGateView() }
        .onChange(of: account.signedIn) { _, signed in
            if signed { showSignIn = false }
        }
    }

    private func syncTitle(_ state: SyncCardState) -> String {
        if let user = account.user { return "@\(user.username)" }
        return t("Нет входа в аккаунт Sonar")
    }

    private func syncSubtitle(_ state: SyncCardState) -> String {
        switch state {
        case .signedOut: t("Лайки, плейлисты и настройки — на всех твоих устройствах")
        case .syncing: t("Синхронизирую…")
        case let .failed(message): t(message)
        case .never: t("Ещё не синхронизировалось")
        case let .done(date): t("Последний обмен: {time}", ["time": date.formatted(.dateTime.hour().minute())])
        }
    }

    private func syncSummary(_ state: SyncCardState) -> String? {
        guard case .done = state, let report = sync.lastReport, report.pushed + report.pulled > 0 else { return nil }
        return "↑\(report.pushed) ↓\(report.pulled)"
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { settings.string(key) }, set: { settings.set(key, .string($0)) })
    }

    var body: some View {
        SystemScreen(title: t("Общее")) {
            NetworkSection()
                .cascade(0)

            SystemSection(title: t("Язык")) {
                Button { languageSheet = true } label: {
                    SystemRow(icon: .translate, title: t("Язык интерфейса"), value: "\(lang.flag) \(lang.nativeName)", chevron: true)
                }
                .buttonStyle(PressableStyle(scale: 0.99))
            }
            .cascade(0)

            SystemSection(title: t("Главная"), footer: t("Откуда главная берёт волну и рекомендации")) {
                SystemChoiceRow(icon: .compass, title: t("Платформа"),
                                options: [SystemSegments<String>.Option(id: "soundcloud", title: "SoundCloud"), SystemSegments<String>.Option(id: "yandex", title: t("Яндекс"))],
                                selection: binding("general.platform"))
            }
            .cascade(1)

            SystemSection(title: t("Медиатека")) {
                SystemChoiceRow(icon: .queue, title: t("Добавление"), subtitle: t("Куда добавлять новые треки в плейлистах"),
                                options: [SystemSegments<String>.Option(id: "start", title: t("В начало")), SystemSegments<String>.Option(id: "end", title: t("В конец"))],
                                selection: binding("general.add_position"))
            }
            .cascade(2)

            SystemSection(title: t("Отклик")) {
                SystemToggle(icon: .wave, title: t("Тактильный отклик"), subtitle: t("Лёгкий тык на кнопки, переключатели и смену трека свайпом"),
                             isOn: Binding(get: { settings.bool(Haptics.key) }, set: { settings.set(Haptics.key, $0); if $0 { Haptics.tap() } }))
            }
            .cascade(2)

            // работает без сервера: ядро само проверяет любимых исполнителей (ReleaseNotifier)
            SystemSection(title: t("Уведомления")) {
                SystemToggle(icon: .bell, title: t("Новинки исполнителей"),
                             subtitle: t("Вышел трек, сингл или альбом у исполнителя, на которого ты подписан или чьи треки лайкаешь, — покажем при запуске и раз в 3 часа"),
                             isOn: Binding(get: { settings.bool(ReleaseNotifier.key) },
                                           set: { on in Task { await ReleaseNotifier.shared.setEnabled(on) } }))
            }
            .cascade(2)

            if Features.widgetsVisible {
                SystemSection(title: t("Виджет и Siri"), footer: t("Его играют кнопка «Быстрый плейлист» в виджете и команда «Быстрый плейлист» в Siri и «Командах»")) {
                    Button { quickSheet = true } label: {
                        SystemRow(icon: .bolt, title: t("Быстрый плейлист"), value: QuickPlaylistSheet.title(of: settings), chevron: true)
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                }
                .cascade(2)
            }

            syncSection
                .cascade(3)

            AboutSection()
                .cascade(4)
        }
        .sheet(isPresented: $languageSheet) {
            LanguageSheet()
                .presentationDetents([.height(LanguageSheet.height)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $quickSheet) {
            QuickPlaylistSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
    }
}

/// Лист выбора языка: флаг, название на самом языке, текущий — галочкой; пункты появляются каскадом
/// («Меньше движения» — только прозрачность, это делает `cascade`), язык меняется сразу.
private struct LanguageSheet: View {
    private static let rowHeight: CGFloat = 56
    /// Заголовок, пункты, подпись и отступы — лист ровно по содержимому.
    static let height: CGFloat = 26 + 24 + 14 + rowHeight * CGFloat(Lang.allCases.count) + 14 + 18 + 40

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("Язык интерфейса"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.top, 26)
            VStack(spacing: 0) {
                ForEach(Array(Lang.allCases.enumerated()), id: \.element) { index, lang in
                    if index > 0 { RowDivider() }
                    let on = currentLang() == lang
                    Button {
                        withAnimation(Motion.spring) { settings.set(Lang.settingKey, .string(lang.rawValue)) }
                        Haptics.select()
                    } label: {
                        HStack(spacing: 12) {
                            Text(lang.flag)
                                .font(.system(size: 22))
                                .accessibilityHidden(true)
                            Text(lang.nativeName)
                                .font(.system(size: 17, weight: on ? .semibold : .regular))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            SonarIcon(.check, size: 20)
                                .foregroundStyle(Theme.accent)
                                .opacity(on ? 1 : 0)
                                .scaleEffect(on ? 1 : 0.6)
                        }
                        .padding(.horizontal, 18)
                        .frame(height: Self.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    .animation(Motion.spring, value: on)
                    .cascade(index)
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            Text(t("Не выбран — как в системе"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
    }
}

/// «Сеть» (docs/OFFLINE.md §4): офлайн-режим и подсказка включить его, когда сеть пропала.
private struct NetworkSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(OfflineMode.self) private var offline

    var body: some View {
        SystemSection(title: t("Сеть"), footer: footer) {
            SystemToggle(icon: .cloudOff, title: t("Офлайн-режим"),
                         subtitle: t("Sonar не выходит в интернет и показывает только скачанные треки и кэш волны. Для роуминга и слабой сети"),
                         isOn: Binding(get: { offline.isOn }, set: { offline.set($0) }))
            RowDivider()
            SystemToggle(icon: .bell, title: t("Предлагать офлайн-режим"),
                         subtitle: t("Пропала сеть — одна плашка с кнопкой. Сам режим не включается"),
                         isOn: Binding(get: { settings.bool(OfflineSuggest.key) }, set: { settings.set(OfflineSuggest.key, $0) }))
        }
    }

    /// Включён — сколько доступно и сколько запросов не пустили.
    private var footer: String? {
        guard offline.isOn else { return nil }
        let count = offline.availableTracks.count
        return "\(t("Доступно офлайн")): \(count) \(tn(count, "трек", "трека", "треков")) · "
            + t("Запросов заблокировано с включения: {n}", ["n": "\(OfflineFlag.blocked)"])
    }
}
