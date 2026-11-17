import Foundation

extension SettingsDefaults {
    /// Плеер: Аудио, Вид плеера, Очередь, Жесты — ключи и умолчания как в docs/SETTINGS.md.
    /// Значения перечислений — rawValue в `Playback/PlayerPrefs.swift` и `Playback/Gestures.swift`.
    static let player: [String: SettingValue] = {
        var out: [String: SettingValue] = [
            // Аудио
            "audio.gapless": .bool(true),
            // на iPhone нормализация включена сразу (R128 Яндекса — громкостью плеера, остальное — выравнивателем)
            "audio.normalize": .bool(true),
            // кроссфейд, секунды: 0 — выключен (как на ПК)
            "audio.crossfade": .int(0),
            "audio.on_interruption": .string(InterruptionMode.fallback.rawValue),
            // эквалайзер: 12 чисел через запятую, пусто — ровно
            "audio.eq": .string(""),
            "audio.eq_enabled": .bool(true),
            // Вид плеера
            "player.style": .string(PlayerStyle.fallback.rawValue),
            "player.background": .string(PlayerBackground.fallback.rawValue),
            "player.title_align": .string(TitleAlign.fallback.rawValue),
            "player.slider": .string(SliderStyle.fallback.rawValue),
            "player.play_button": .string(PlayButtonStyle.fallback.rawValue),
            "player.artist_avatars": .bool(true),
            // Очередь
            "queue.preview": .bool(true),
            "queue.view": .string(QueueView.fallback.rawValue),
            "queue.add_following": .bool(true),
            "general.restore": .string(RestoreMode.fallback.rawValue),
            // Моя волна: подкачка следующих на Wi‑Fi для игры без сети (`WaveCache`) и «Почему этот трек»
            "wave.offline": .bool(true),
            "wave.reasons": .bool(true),
        ]
        for (key, value) in Gestures.defaults { out[key] = .string(value) }
        return out
    }()
}
