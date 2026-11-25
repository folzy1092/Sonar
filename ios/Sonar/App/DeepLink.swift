import Foundation

/// Ссылки `sonar://` (BOT.md, SPEC §4.5а):
/// - `sonar://play/liked|wave|quick` — кнопки виджета: включить Любимые, Sonar Mix, быстрый плейлист;
/// - `sonar://auth/<code>` — вход с другого устройства (окно подтверждения, с сервером);
/// - `sonar://remote/pair?pc=…&code=…` — QR пульта с экрана ПК (Система → Пульт), `RemotePairLink`;
/// - `sonar://album/<ref>` — уведомление «Новинки»: страница альбома;
/// - `sonar://track/<ref>` — уведомление «Новинки» (трек из ленты, `ReleaseNotifier`) или «Открыть в Sonar» на
///   странице трека сайта (`try-sonar.ru/t/#…`): трек находится по ref и играет;
/// - `sonar://user/<username>` — пока только узнаём вид ссылки;
/// - `sonar://room/<id>` — приглашение в комнату из сообщений (docs/ROOMS.md); до сервера только узнаём.
enum DeepLink: Equatable {
    case track(String)
    case album(String)
    case auth(String)
    case user(String)
    case room(String)
    case play(PlayTarget)
    case remotePair(RemotePairLink)

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "sonar", let host = url.host()?.lowercased() else { return nil }
        let value = url.pathComponents.dropFirst().joined(separator: "/")
        guard !value.isEmpty else { return nil }
        switch host {
        case "track": self = .track(value)
        case "album": self = .album(value)
        case "auth": self = .auth(value)
        case "user": self = .user(value)
        case "room": self = .room(value)
        case "remote":
            guard let link = RemotePairLink(url) else { return nil }
            self = .remotePair(link)
        case "play":
            guard let target = PlayTarget(rawValue: value.lowercased()) else { return nil }
            self = .play(target)
        default: return nil
        }
    }

    @MainActor
    static func handle(_ url: URL, router: Router, chrome: ChromeState) {
        guard let link = DeepLink(url) else { return }
        switch link {
        case let .album(ref):
            router.push(.album(ref: ref, title: ""), on: chrome.tab, chrome: chrome)
        case let .track(ref):
            if let track = ReleaseNotifier.shared.track(ref) {
                PlaybackEngine.shared.play([track], at: 0, context: t("Новинки"))
                return
            }
            Task { @MainActor in
                guard let track = await MusicCore.shared.track(ref: ref) else {
                    router.say(t("Не получилось открыть трек: подключи сервис, откуда им поделились"))
                    return
                }
                PlaybackEngine.shared.play([track], at: 0, context: t("Поделились"))
                router.showMenu(track)
            }
        case let .auth(code):
            // вход с другого устройства / из бота — окно подтверждения (работает, только когда включён сервер)
            AccountStore.shared.handleAuthLink(code)
        case let .play(target):
            Task { await QuickPlay.start(target) }
        case let .remotePair(link):
            RemoteControl.shared.pair(link)
        default:
            break
        }
    }
}
