import SwiftUI
import UIKit

/// Система → «Общее» (SETTINGS.md «Основные — general.*», как Windows `General.svelte`): язык
/// (`general.language`, сразу), платформа главной (`general.platform`), медиатека (куда добавлять треки —
/// `general.add_position`; облако — с сервером), синхронизация (с сервером), внизу — «О приложении».
/// «Авто похожие» — в Очереди.
struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var languageSheet = false

    private var lang: Lang { currentLang() }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { settings.string(key) }, set: { settings.set(key, .string($0)) })
    }

    var body: some View {
        SystemScreen(title: t("Общее")) {
            SystemSection(title: t("Язык")) {
                Button { languageSheet = true } label: {
                    SystemRow(icon: .translate, title: t("Язык интерфейса"), value: lang.nativeName, chevron: true)
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
                SystemToggle(icon: .wave, title: t("Тактильный отклик"), subtitle: t("Лёгкий тык при нажатиях в настройках, вкладках и «Моей волне»"),
                             isOn: Binding(get: { settings.bool(Haptics.key) }, set: { settings.set(Haptics.key, $0); if $0 { Haptics.tap() } }))
            }
            .cascade(2)

            SystemSection(title: t("Синхронизация"), footer: t("Лайки, плейлисты и настройки будут общими на iPhone и компьютере, когда появится сервер Sonar. Пока всё хранится на этом телефоне.")) {
                SystemRow(icon: .cloudSync, title: t("Сохранить в облако"), subtitle: t("Лайки и плейлисты с этого устройства"), value: t("С сервером"))
                    .opacity(0.55)
                RowDivider()
                SystemRow(icon: .cloud, title: t("Загрузить из облака"), subtitle: t("Заменит лайки и плейлисты здесь"), value: t("С сервером"))
                    .opacity(0.55)
            }
            .cascade(3)

            AboutSection()
                .cascade(4)
        }
        .sheet(isPresented: $languageSheet) {
            LanguageSheet()
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(Theme.background)
        }
    }
}

/// Лист выбора языка: три пункта, отмеченный — галочкой; язык меняется сразу.
private struct LanguageSheet: View {
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
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack {
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
                        .frame(height: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    .animation(Motion.spring, value: on)
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
