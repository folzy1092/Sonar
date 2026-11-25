import SwiftUI

/// «Чаще · Реже · Никогда» для артиста (`ArtistPrefs`, зеркало ПК `components/ArtistTasteSeg.svelte`): лист трека
/// и Профиль → Вкус. Нажатое ещё раз — снять. Выбранное подсвечено, «Никогда» — красным.
struct ArtistTasteChips: View {
    let name: String
    var onPick: (@MainActor (ArtistLevel?) -> Void)?
    @Environment(PlaybackEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings

    private var level: ArtistLevel? { ArtistPrefs.level(settings.artistPrefs, name: name) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ArtistLevel.allCases, id: \.self) { item in
                let on = level == item
                Button {
                    engine.setArtistTaste(name, item)
                    Haptics.select()
                    onPick?(ArtistPrefs.level(settings.artistPrefs, name: name))
                } label: {
                    Text(t(item.title))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(on ? (item == .never ? Theme.danger : Theme.text) : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Theme.raisedHigh : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.raised.opacity(0.6), in: Capsule())
        .animation(Motion.spring, value: level)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("Артист в Sonar Mix"))
    }
}

/// Профиль → Вкус (ПК — Плеер → Вкус): артисты «Чаще · Реже · Никогда» и сколько треков с 👎. Названий 👎-треков
/// телефон не хранит (только ref), поэтому здесь — только число; вернуть трек — в его меню («Снова интересно»).
struct TasteSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackEngine.self) private var engine
    @State private var query = ""

    var body: some View {
        let all = ArtistPrefs.list(settings.artistPrefs)
        let shown = ArtistPrefs.list(settings.artistPrefs, query: query)
        PlayerSettingsPage(title: t("Вкус")) {
            PlayerCard(title: t("Артисты"),
                       footer: t("«Никогда» — артиста нет в Sonar Mix и похожих, «Чаще» и «Реже» двигают его в Sonar Mix")) {
                if all.count > 6 {
                    TextField(t("Найти артиста"), text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    PlayerRowDivider()
                }
                if all.isEmpty {
                    note(t("Пока никого. Открой меню трека или страницу исполнителя и выбери «Чаще», «Реже» или «Никогда»."))
                } else if shown.isEmpty {
                    note(t("Никого не нашлось"))
                } else {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { PlayerRowDivider() }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.pref.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Button {
                                    engine.setArtistTaste(item.pref.name, nil)
                                } label: {
                                    SonarIcon(.close, size: 18)
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(width: 32, height: 32)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PressableStyle(scale: 0.85))
                                .accessibilityLabel(t("Убрать"))
                            }
                            ArtistTasteChips(name: item.pref.name)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .transition(.opacity)
                    }
                }
            }
            .animation(Motion.spring, value: shown.map(\.id))
            .cascade(0)

            PlayerCard(title: t("Не нравится"), footer: t("Треки с 👎 не попадают в Sonar Mix и похожие")) {
                if library.disliked.isEmpty {
                    note(t("Таких треков нет"))
                } else {
                    Text("\(library.disliked.count) \(tn(library.disliked.count, "трек", "трека", "треков"))")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                }
            }
            .cascade(1)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
    }
}
