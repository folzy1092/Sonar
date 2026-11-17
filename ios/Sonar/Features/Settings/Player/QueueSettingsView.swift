import SwiftUI

/// Профиль → Очередь (по ПК `pages/settings/Queue.svelte`, SETTINGS.md «Очередь»): что вернуть при
/// запуске, вид очереди, карточка «Дальше», «Авто похожие», «Добавлять следующие». Положение и показ
/// панели очереди — только ПК (на iPhone очередь — лист из плеера).
struct QueueSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    private func flag(_ key: String) -> Binding<Bool> {
        Binding(get: { settings.bool(key) }, set: { settings.set(key, $0) })
    }

    var body: some View {
        PlayerSettingsPage(title: "Очередь") {
            PlayerCard(title: "Продолжить с прошлого раза", footer: "Что вернуть при открытии Sonar — на паузе, с той же секунды") {
                ChoiceTiles(items: RestoreMode.allCases.map(\.item), selected: RestoreMode.current(settings).rawValue, height: 84) {
                    RestoreMode.from($0).save(settings)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .cascade(0)

            PlayerCard(title: "Вид очереди") {
                ChoiceTiles(items: QueueView.allCases.map { view in
                    ChoiceItem(id: view.rawValue, icon: view.icon, title: view.title,
                               subtitle: view == .normal ? "Компактно, без обложек" : "С обложками")
                }, selected: QueueView.current(settings).rawValue, height: 96) { QueueView.from($0).save(settings) }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .cascade(1)

            PlayerCard {
                PlayerToggleRow(icon: .next, title: "Предпросмотр следующего",
                                subtitle: "За 10 секунд до конца — «Дальше» с названием следующего в мини-плеере и плеере",
                                isOn: flag("queue.preview"))
                PlayerRowDivider()
                PlayerToggleRow(icon: .sparkles, title: "Авто похожие",
                                subtitle: "Как в SoundCloud: после любой очереди — поиска, Любимых, плейлиста — играют похожие треки",
                                isOn: flag("general.similar_autoplay"))
                PlayerRowDivider()
                PlayerToggleRow(icon: .listCheck, title: "Добавлять следующие",
                                subtitle: "Нажатый трек ставит в очередь и треки после него; выключено — играет только он",
                                isOn: flag("queue.add_following"))
            }
            .cascade(2)
        }
    }
}
