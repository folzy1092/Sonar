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
            // сведение (docs/BLEND.md §7.3, зеркало ПК): выключено; длина 6 · 10 · 16 с, срез до 45 с, темп ±12 %
            "audio.blend": .bool(false),
            "audio.blend_type": .string(BlendType.auto.rawValue),
            "audio.blend_length": .int(10),
            "audio.blend_cut": .int(16),
            "audio.blend_tempo": .int(8),
            "audio.blend_key": .bool(true),
            "audio.blend_debug": .bool(false),
            "audio.on_interruption": .string(InterruptionMode.fallback.rawValue),
            // эквалайзер: 12 чисел через запятую, пусто — ровно
            "audio.eq": .string(""),
            "audio.eq_enabled": .bool(true),
            // YouTube Music: normal (AAC 128) · high (AAC до 256), ключ как на ПК
            "audio.yt_quality": .string(YouTubeQuality.fallback.rawValue),
            // резервный сервис: включён; порядок — id через запятую, пусто — порядок реестра (FallbackPlan.order)
            FallbackPlan.enabledKey: .bool(true),
            FallbackPlan.orderKey: .string(""),
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
            // Sonar Mix: подкачка следующих на Wi‑Fi для игры без сети (`WaveCache`) и «Почему этот трек»
            "storage.wave_offline": .bool(true),
            "player.wave_why": .bool(true),
            // таймер сна в плеере (лист скорости и меню трека), как ПК — по умолчанию выключен
            "player.sleep_button": .bool(false),
            // общие тон и реверб листа скорости (у трека со своим звуком — его, `TrackSound`); скорость на новом
            // треке — 1×, как раньше. Только этот телефон: у ПК свой `player.tempo`
            "player.pitch_linked": .bool(false),
            "player.pitch": .double(0),
            "player.reverb": .double(0),
            // пространство 0…16 листа скорости (`Playback/Space.swift`), то же имя, что на ПК
            "audio.space": .double(0),
        ]
        for (key, value) in Gestures.defaults { out[key] = .string(value) }
        return out
    }()
}
