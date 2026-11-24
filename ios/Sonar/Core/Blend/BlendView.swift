import Foundation

// Что показывает кнопка сведения (docs/BLEND.md §10.1): имена видов и длин, карточка «Следующий переход».
// Порт `player/blend/view.ts`. Строки — русские ключи `t()`, переводит экран; здесь только выбор состояния и числа.

struct BlendKindText: Hashable, Sendable {
    let short: String
    let name: String
    let about: String
}

enum BlendView {
    static func kindText(_ type: BlendType) -> BlendKindText {
        switch type {
        case .auto: BlendKindText(short: "Авто", name: "Авто", about: "Сам выбирает вид под пару треков")
        case .bass: BlendKindText(short: "Бас", name: "Бас-свап", about: "Басы меняются местами на сильную долю")
        case .filter: BlendKindText(short: "Фильтр", name: "Фильтр",
                                    about: "Трек уходит в фильтр, следующий раскрывается из глухого")
        case .echo: BlendKindText(short: "Эхо", name: "Эхо", about: "Трек тонет в эхо, следующий входит на «раз»")
        case .smooth: BlendKindText(short: "Сведение::Плавно", name: "Плавный", about: "Длинное наложение без резких мест")
        case .drop: BlendKindText(short: "Дроп", name: "На дроп", about: "Короткий разгон и сразу дроп следующего")
        }
    }

    static func kindText(_ kind: BlendKind) -> BlendKindText {
        kindText(BlendType(rawValue: kind.rawValue) ?? .auto)
    }

    static func lengthText(_ sec: Double) -> String {
        switch Int(sec) {
        case 6: "Коротко"
        case 16: "Длинно"
        default: "Норм"
        }
    }

    /// Подпись на самой кнопке: включено — короткое имя вида, иначе пусто (значок).
    static func buttonLabel(on: Bool, type: BlendType) -> String {
        on ? kindText(type).short : ""
    }

    /// Фаза контроллера для отладочной карточки (`debug-view.ts` `PHASE_TEXT`).
    static func phaseText(_ phase: BlendPhase) -> String {
        switch phase {
        case .idle: "Отладка::нет"
        case .planned: "Отладка::готов"
        case .prerolling: "Отладка::прогрев"
        case .running: "Отладка::идёт"
        case .promoting: "Отладка::доводка"
        case .fallback: "Отладка::кроссфейд"
        }
    }

    /// «128.0 BPM · 0.91 · 8A · 0.34 · −9.8 LUFS» — одни числа, переводить нечего.
    static func analysisLine(_ a: BlendAnalysis) -> String {
        let key = a.key == nil ? "—" : "\(BlendCamelot.name(a.key)) · \(fixed(a.keyConf, 2))"
        return "\(fixed(a.bpm, 1)) BPM · \(fixed(a.bpmConf, 2)) · \(key) · \(minus(a.loudness, 1)) LUFS"
    }

    /// Число с настоящим минусом: «−9.8» (минус у нуля не пишем).
    static func minus(_ v: Double, _ digits: Int = 0) -> String {
        let s = fixed(abs(v), digits)
        return v < 0 && Double(s) != 0 ? "−\(s)" : s
    }

    private static func fixed(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), v)
    }

    struct CardInput {
        var on: Bool
        var repeatOne: Bool
        /// Играющий и следующий треки.
        var a: String?
        var b: String?
        var stateA: BlendAnalysisState
        var stateB: BlendAnalysisState
        /// Для пары не нашлось плана или B не загрузился.
        var failed: Bool
        var next: BlendNext?
        var anA: BlendAnalysis?
        var anB: BlendAnalysis?
        /// Своя скорость A: длина перехода в секундах — уже с ней.
        var rateA: Double
    }

    struct PlanCard: Hashable {
        var kind: BlendKind
        var sync: Bool
        /// Длина перехода, с (одна цифра после запятой).
        var sec: Double
        var rank: Int
        var total: Int
        /// Где A уходит и откуда входит B, мс файла.
        var outMs: Double
        var inMs: Double
        var tempoA: Int
        var tempoB: Int
        var keyA: String
        var keyB: String
    }

    enum Card: Hashable {
        case off, idle, repeatOne, last, counting, noAnalysis, noPlan, waiting
        case plan(PlanCard)

        /// Строка состояния без плана (nil — у `off` и `plan` её нет).
        var stateText: String? {
            switch self {
            case .idle: "Ничего не играет"
            case .repeatOne: "Повтор трека — сведение не работает"
            case .last: "Последний трек — перехода не будет"
            case .counting: "Считаю следующий трек…"
            case .noAnalysis: "Нет анализа — будет кроссфейд"
            case .noPlan: "Нет подходящего момента — будет кроссфейд"
            case .waiting: "Подбираю момент…"
            case .off, .plan: nil
            }
        }
    }

    /// Почему у трека нет анализа — ключ `t()` для шторки. `BlendAnalyzeQueue.failure` хранит
    /// `String(describing:)` ошибки: у `BlendAnalysisError` это имя случая, у остального — что угодно (сеть, сервис).
    static func failureText(_ raw: String) -> String {
        switch raw {
        case "hls": "Поток этого сервиса не разобрать"
        case "offline": "Офлайн — у трека нет своего файла"
        case "tooBig", "tooLong": "Трек слишком длинный для анализа"
        case "decode": "Не удалось прочитать звук трека"
        case "noTrack": "Трек пропал из очереди"
        default: "Не удалось скачать трек для анализа"
        }
    }

    static func card(_ c: CardInput) -> Card {
        guard c.on else { return .off }
        guard let a = c.a else { return .idle }
        if c.repeatOne { return .repeatOne }
        guard let b = c.b else { return .last }
        if c.failed { return .noPlan }
        if c.stateA == .failed || c.stateB == .failed { return .noAnalysis }
        if let n = c.next, n.from == a, n.to == b, let anA = c.anA, let anB = c.anB {
            return .plan(planCard(n, anA, anB, rateA: c.rateA))
        }
        if c.stateA != .ready || c.stateB != .ready { return .counting }
        return .waiting
    }

    private static func planCard(_ n: BlendNext, _ anA: BlendAnalysis, _ anB: BlendAnalysis, rateA: Double) -> PlanCard {
        let p = n.plan
        return PlanCard(
            kind: p.kind,
            sync: p.sync,
            sec: BlendMath.jsRound(Double(p.bars) * BlendPlanner.barMs(anA) / max(rateA, 0.01) / 100) / 10,
            rank: n.rank,
            total: n.total,
            outMs: p.outMs,
            inMs: p.inMs,
            tempoA: BlendMath.jsRoundInt(p.tempoA),
            tempoB: BlendMath.jsRoundInt(p.tempoB),
            keyA: BlendCamelot.name(anA.key),
            keyB: BlendCamelot.name(anB.key)
        )
    }
}
