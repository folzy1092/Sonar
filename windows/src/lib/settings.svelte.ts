// Настройки (docs/SETTINGS.md) одним хранилищем: читаются один раз при запуске (`all_settings`),
// меняются сразу в интерфейсе и пишутся в локальную базу. Значения по умолчанию — из каталога.
import { api } from './api'
import type { Surface } from '../theme/palette'
import type { AnimLike, AnimNav, AnimTrack, CustomStyle, IconStroke, LoadingLook, ProgressLook, TitleStyle } from '../theme/style'

export type MiniStyle = 'off' | 'full' | 'rounded' | 'hybrid' | 'deck'

/** Пресеты стиля мини-плеера (как у Dotify, заметка владельца в reference/pc/ПРОЧИТАЙ МЕНЯ.txt). */
export const MINI_PRESETS: Record<Exclude<MiniStyle, 'off'>, { bg: 'theme' | 'cover' | 'cover_color'; progress: 'line' | 'background' | 'cover'; cover: 'default' | 'circle'; shape: 'default' | 'capsule' }> = {
  full: { bg: 'theme', progress: 'line', cover: 'default', shape: 'default' },
  rounded: { bg: 'theme', progress: 'cover', cover: 'circle', shape: 'capsule' },
  hybrid: { bg: 'theme', progress: 'background', cover: 'default', shape: 'default' },
  deck: { bg: 'cover', progress: 'background', cover: 'default', shape: 'default' },
}

export const DEFAULTS = {
  'general.platform': 'soundcloud' as 'soundcloud' | 'yandex',
  'general.restore': 'queue' as 'none' | 'track' | 'queue',
  'general.similar_autoplay': true,
  'general.add_position': 'start' as 'start' | 'end',
  /** Тема: тёмная / светлая / как в системе (меняется на лету). */
  'appearance.mode': 'dark' as 'dark' | 'light' | 'system',
  'appearance.cover_theme': true,
  /** Прозрачность окна (Mica / Acrylic под окном, glass.rs). */
  'appearance.glass': false,
  /** Непрозрачность фона окна и карточек при прозрачности, % (100 — как без неё). */
  'appearance.opacity': 80 as number,
  /** Размытие стекла: радиус backdrop-filter у панелей, px. */
  'appearance.glass_blur': 16 as number,
  'appearance.preset': 'neutral' as string,
  'appearance.animations': true,
  'appearance.scale_window': 100,
  'appearance.scale_fullscreen': 100,
  /** Шрифт интерфейса; по умолчанию — как в стиле Sonar (theme/style.ts). */
  'appearance.font': 'Golos Text Variable' as string,
  /** Размер шрифта: 16 — как задумано, остальные — множитель n / 16 ко всему тексту. */
  'appearance.font_size': 16 as number,
  /** Жирность обычного текста; заголовки и выделенное — как в вёрстке. */
  'appearance.font_weight': 'auto' as 'auto' | '400' | '500' | '600' | '700',
  'appearance.corner_radius': 'rounded' as 'none' | 'soft' | 'rounded' | 'pill',
  // ---- Стиль (Интерфейс → Стиль, theme/style.ts): готовый стиль ставит оси ниже ----
  /** `sonar` / `echo` / `signal` / `edge` / `tactile` / `monolith` / `custom:<id>`. */
  'appearance.style': 'sonar' as string,
  /** Формулы фона, поверхностей, границ, теней и бликов (palette.ts SURFACES). */
  'appearance.surface': 'monolith' as Surface,
  /** Шрифт заголовков («Моя волна», названия страниц и разделов). */
  'appearance.font_display': 'Unbounded Variable' as string,
  'appearance.title_style': 'plain' as TitleStyle,
  /** Толщина линий иконок левой панели и мини-плеера. */
  'appearance.icon_stroke': 2 as IconStroke,
  'appearance.anim_track': 'edge' as AnimTrack,
  'appearance.anim_like': 'signal' as AnimLike,
  'appearance.anim_nav': 'dot' as AnimNav,
  /** Как нарисован прогресс (место — `mini.progress`). */
  'appearance.progress_look': 'line' as ProgressLook,
  /** Как показана загрузка трека: обложка из ч/б в цвет или кольцо-сектор. */
  'appearance.loading': 'color' as LoadingLook,
  'appearance.custom_styles': [] as CustomStyle[],
  /** Панель вкладок (Интерфейс → Вкладки): где она, какая, подстраивается ли под страницу. */
  'tabs.position': 'left' as 'left' | 'top' | 'bottom' | 'right',
  'tabs.style': 'default' as 'default' | 'compact' | 'full' | 'round' | 'floating',
  /** Подстраивать вкладки: цвет панели — от страницы (подкраска обложки). */
  'tabs.adapt': false,
  /** Скрытие элементов: мышь не двигается 3 с — панель вкладок и мини-плеер гаснут. */
  'tabs.autohide': false,
  /** Кеширование треков: прослушанное складывается на диск и играет оттуда (track_cache.rs). */
  'storage.cache_tracks': false,
  /** Лимит кэша треков, МБ; сверх — вытесняются давно не игравшие. */
  'storage.cache_limit_mb': 2048 as number,
  'audio.output_device': '' as string,
  /** Нормализация громкости (player/leveler.ts) — выравнивание тихих и громких треков. */
  'audio.normalize': false,
  /** Кроссфейд, секунды (0 — выкл): следующий трек нарастает, пока текущий затухает. */
  'audio.crossfade': 0 as number,
  /** Бесшовное: без кроссфейда следующий трек стыкуется без паузы (короткое перекрытие). */
  'audio.gapless': true,
  /** Тише во время звонков: пока другое приложение пишет с микрофона, музыка на 20 % (calls.rs). */
  'audio.duck_calls': true,
  'player.cover_position': 'left' as 'left' | 'right',
  'queue.show': true,
  /** Предпросмотр следующего трека: карточка «Дальше» за 10 с до конца трека. */
  'queue.preview': true,
  /** Где очередь на странице плеера: снизу / слева / справа колонкой. */
  'queue.position': 'bottom' as 'bottom' | 'left' | 'right',
  /** Вид строк очереди: развёрнутый (с обложками) / обычный (компактно, без обложек). */
  'queue.view': 'extended' as 'normal' | 'extended',
  'queue.add_following': true,
  'mini.style': 'hybrid' as MiniStyle,
  /** Где мини-плеер: снизу (под карточкой) / сверху / снизу внутри карточки / плавающий. */
  'mini.position': 'bottom' as 'top' | 'bottom' | 'bottom_inset' | 'floating',
  /** Плавающий мини-плеер: центр капсулы в долях окна. */
  'mini.float_x': 0.5 as number,
  'mini.float_y': 0.86 as number,
  'mini.background': 'theme' as 'theme' | 'cover' | 'cover_color',
  'mini.progress': 'background' as 'line' | 'background' | 'cover',
  'mini.cover_shape': 'default' as 'default' | 'circle',
  'mini.shape': 'default' as 'default' | 'capsule',
  /** Скругление концов капсул (мини-плеер и левая панель), % от половины высоты: 100 — капсула. */
  'mini.shape_round': 100 as number,
  /** Скругление обложки в мини-плеере, %: 100 — круг. */
  'mini.cover_round': 100 as number,
  'player.title_align': 'center' as 'left' | 'center' | 'right',
  'player.artist_avatars': true,
  'player.visualizer': 'bar' as 'off' | 'bar' | 'cover' | 'slider',
  /** Стиль страницы плеера: обычный / пластинка (винил крутится, игла) / большой (обложка на всю высоту). */
  'player.style': 'standard' as 'standard' | 'vinyl' | 'large',
  /** Стиль визуализатора: волна или столбцы. */
  'player.visualizer_style': 'wave' as 'wave' | 'bars',
  /** Тип ползунка прогресса (Плеер → Вид). */
  'player.slider': 'normal' as 'normal' | 'thin' | 'smooth' | 'wavy' | 'wave_bars',
  /** Маленькая копия обложки в углу большой. */
  'player.pip_cover': false,
  'integrations.discord.enabled': true,
  'integrations.discord.cover': true,
  'integrations.discord.progress': true,
  /** Заголовок «Слушает …»: исполнитель / трек / «исполнитель — трек» / «трек — исполнитель» / Sonar. */
  'integrations.discord.status_format': 'artist' as 'artist' | 'title' | 'artist_title' | 'title_artist' | 'app',
  'integrations.discord.artist_photo': true,
  'integrations.discord.show_paused': false,
  'integrations.discord.button_listen': true,
  'integrations.discord.button_download': true,
  'integrations.lastfm.scrobble': true,
  'integrations.lastfm.now_playing': true,
  'system.autostart': true,
  'system.tray': true,
  'system.power_saving': 'background' as 'off' | 'minimized' | 'background',
  'wave.mode': 'own' as 'own' | 'hard' | 'calm' | 'sad' | 'fun' | 'new',
  'obs.size': 'standard' as 'standard' | 'compact',
  'obs.hide_paused': true,
  /** Токен ссылки плашки OBS; пусто — плашка выключена (первый создаёт Rust при запуске). */
  'obs.token': '' as string,
  'update.auto_check': true,
  'update.auto_download': true,
  'update.channel': 'stable' as 'stable' | 'beta',
}
export type SettingKey = keyof typeof DEFAULTS
type Value<K extends SettingKey> = (typeof DEFAULTS)[K]

class Settings {
  private values = $state<Record<string, unknown>>({})
  loaded = $state(false)
  private loading: Promise<void> | null = null

  load(): Promise<void> {
    this.loading ??= api
      .allSettings()
      .then((all) => {
        this.values = all
      })
      .catch(() => {})
      .finally(() => (this.loaded = true))
    return this.loading
  }

  get<K extends SettingKey>(key: K): Value<K> {
    const v = this.values[key]
    return (v === undefined || v === null ? DEFAULTS[key] : v) as Value<K>
  }

  set<K extends SettingKey>(key: K, value: Value<K>) {
    this.values = { ...this.values, [key]: value }
    void api.setSetting(key, value).catch(() => {})
  }

  /** Стиль мини-плеера: пресет выставляет фон, прогресс, обложку и форму. */
  setMiniStyle(style: MiniStyle) {
    this.set('mini.style', style)
    if (style === 'off') return
    const p = MINI_PRESETS[style]
    this.set('mini.background', p.bg)
    this.set('mini.progress', p.progress)
    this.set('mini.cover_shape', p.cover)
    this.set('mini.shape', p.shape)
  }

  /** После «Сбросить настройки». */
  async reload() {
    this.loading = null
    await this.load()
  }
}

export const settings = new Settings()
