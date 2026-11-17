import Foundation

/// Кнопка «Слушать» на экране подборки (плейлист, Любимые, альбом, исполнитель) — как на ПК
/// (`windows/src/lib/listen.ts`): играет эта же подборка — «Пауза»; после паузы — «Слушать»
/// продолжает с того же места, а не начинает список заново. Подборка узнаётся по `contextTitle`
/// плеера; «Моя волна» — не подборка экрана.
enum ListenAction: Equatable, Sendable {
    /// Поставить на паузу (эта подборка играет).
    case pause
    /// Продолжить с места (эта подборка на паузе).
    case resume
    /// Начать подборку с начала (играет другое или ничего).
    case start

    static func resolve(page: String, context: String, isWave: Bool, hasCurrent: Bool, isPlaying: Bool) -> ListenAction {
        guard !page.isEmpty, page == context, !isWave, hasCurrent else { return .start }
        return isPlaying ? .pause : .resume
    }

    /// Кнопка показывает «Пауза».
    var showsPause: Bool { self == .pause }
}
