// «Поделиться» и «Открыть в Sonar» со страницы трека сайта (`Features/Menus/TrackSheet.swift`, `App/DeepLink.swift`).
// Ключ — русская строка. «Ссылка на {service}» приходит из словаря ПК (`windows/src/i18n/*/share.ts`).

extension I18n {
    static let shareEN: [String: String] = [
        "Не получилось открыть трек: подключи сервис, откуда им поделились": "Couldn't open the track: connect the service it was shared from",
        "Поделились": "Shared with you",
    ]
    static let shareUK: [String: String] = [
        "Не получилось открыть трек: подключи сервис, откуда им поделились": "Не вдалося відкрити трек: підключи сервіс, з якого ним поділилися",
        "Поделились": "Поділилися",
    ]
    static let shareES: [String: String] = [
        "Не получилось открыть трек: подключи сервис, откуда им поделились": "No se pudo abrir el tema: conecta el servicio desde el que se compartió",
        "Поделились": "Compartido contigo",
    ]
    static let shareDE: [String: String] = [
        "Не получилось открыть трек: подключи сервис, откуда им поделились": "Track konnte nicht geöffnet werden: verbinde den Dienst, aus dem er geteilt wurde",
        "Поделились": "Mit dir geteilt",
    ]
    static let sharePL: [String: String] = [
        "Не получилось открыть трек: подключи сервис, откуда им поделились": "Nie udało się otworzyć utworu: połącz serwis, z którego go udostępniono",
        "Поделились": "Udostępnione tobie",
    ]
}
