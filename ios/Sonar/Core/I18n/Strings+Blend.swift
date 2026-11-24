// Строки сведения, которых нет в словарях Windows (docs/BLEND.md §13). es / de / pl — в Strings+App<язык>.swift.

extension I18n {
    static let blendEN: [String: String] = [
        "Закончить вечеринку": "End the party",
        "Этот трек идёт потоком HLS — анализа нет, переход будет кроссфейдом":
            "This track plays as an HLS stream — no analysis, the transition will be a crossfade",
        "Сведение слушает доли и тональность треков-файлов; у потоков HLS анализа нет — там переход кроссфейдом.":
            "Blend listens to the beats and key of file tracks; HLS streams get no analysis, so they crossfade.",
    ]

    static let blendUK: [String: String] = [
        "Закончить вечеринку": "Завершити вечірку",
        "Этот трек идёт потоком HLS — анализа нет, переход будет кроссфейдом":
            "Цей трек іде потоком HLS — аналізу немає, перехід буде кросфейдом",
        "Сведение слушает доли и тональность треков-файлов; у потоков HLS анализа нет — там переход кроссфейдом.":
            "Зведення слухає долі й тональність треків-файлів; у потоків HLS аналізу немає — там перехід кросфейдом.",
    ]
}
