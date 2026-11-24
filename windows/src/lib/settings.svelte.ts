// Настройки (docs/SETTINGS.md) одним хранилищем: читаются один раз при запуске (`all_settings`),
// меняются сразу в интерфейсе и пишутся в локальную базу. Значения по умолчанию — из каталога.
import { api } from './api'
import { migrateSettings } from './settings-migrate'
import { preferredLanguages, systemLang, type Lang } from './system-lang'
import type { CoverStrength, Surface } from '../theme/palette'
import type { ServiceId, ServiceKey } from './services'
import type { NickEffect, NickFont, ProfileColor, ProfileLayout, ProfileLink, ShowcaseItem } from './profile-look'
import type { AppIconId } from './app-icons'
import type { AnimLike, AnimNav, AnimTrack, CustomStyle, IconStroke, LoadingLook, ProgressLook, TitleStyle } from '../theme/style'

export type MiniStyle = 'off' | 'full' | 'rounded' | 'hybrid' | 'deck'

/** Оверлей (SETTINGS_NEXT «Оверлей», 2026-11-18): Отключен · Полноэкранный · Остров · Карточка. */
export type OverlayMode = 'off' | 'fullscreen' | 'island' | 'card'
/** Клетка сетки 3×3 на экране: строка (t — сверху, m — посередине, b — снизу) и столбец (l, c, r). */
export type OverlayAnchor = `${'t' | 'm' | 'b'}${'l' | 'c' | 'r'}`

/** Чем показан прогресс в мини-плеере — можно несколько сразу (SETTINGS_NEXT «Мини плеер», 2026-11-18). */
export type MiniProgress = 'line' | 'background' | 'cover'

/** Пресеты стиля мини-плеера (как у Dotify, заметка владельца в reference/pc/ПРОЧИТАЙ МЕНЯ.txt). */
export const MINI_PRESETS: Record<Exclude<MiniStyle, 'off'>, { bg: 'theme' | 'cover' | 'cover_color'; progress: readonly MiniProgress[]; cover: 'default' | 'circle'; shape: 'default' | 'capsule' }> = {
  full: { bg: 'theme', progress: ['line'], cover: 'default', shape: 'default' },
  rounded: { bg: 'theme', progress: ['cover'], cover: 'circle', shape: 'capsule' },
  hybrid: { bg: 'theme', progress: ['background'], cover: 'default', shape: 'default' },
  deck: { bg: 'cover', progress: ['background'], cover: 'default', shape: 'default' },
}

/** Обложка и форма мини-плеера двумя кнопками → скругление, % (тонкая подстройка — ползунками в «Ещё»). */
export const MINI_COVER_ROUND = { default: 20, circle: 100 } as const
export const MINI_SHAPE_ROUND = { default: 0, capsule: 100 } as const

export const DEFAULTS = {
  'general.platform': 'soundcloud' as ServiceKey,
  /** Язык интерфейса (lib/i18n.svelte.ts), меняется на лету. */
  // не выбран — язык системы, если он есть в Sonar, иначе русский
  'general.language': systemLang(preferredLanguages()) as Lang,
  'general.restore': 'queue' as 'none' | 'track' | 'queue',
  'general.similar_autoplay': true,
  /** Офлайн-режим (docs/OFFLINE.md): ни байта в сеть. Владелец — Rust (offline.rs), в синк не идёт. */
  'general.offline': false,
  /** Пропала сеть, а режим выключен — одна плашка «Включить офлайн-режим» (сам режим не включается). Только это устройство. */
  'general.offline_suggest': true,
  'general.add_position': 'start' as 'start' | 'end',
  /** Тема: тёмная / светлая / как в системе (меняется на лету). */
  'appearance.mode': 'dark' as 'dark' | 'light' | 'system',
  /** Профиль (Аккаунт → Профиль) до сервера: имя, @username, аватар (WebP data URL 256×256, круг).
   *  С сервером — из GET /me. Пусто — имя и аватар из подключённого сервиса. */
  'profile.name': '' as string,
  'profile.username': '' as string,
  'profile.avatar': '' as string,
  /** Вид профиля (SETTINGS_NEXT «Профиль», lib/profile-look.ts): баннер 900×300 и фон 960×540 — WebP
   *  data URL; цвет ('' — цвет темы); статус и «о себе»; ссылки; раскладка шапки; шрифт и эффект ника;
   *  витрина до 6 мест. Публикуется с сервером (PATCH /me). */
  'profile.banner': '' as string,
  'profile.background': '' as string,
  'profile.color': '' as '' | ProfileColor,
  'profile.status': '' as string,
  'profile.bio': '' as string,
  'profile.links': [] as ProfileLink[],
  'profile.layout': 'avatar' as ProfileLayout,
  'profile.nick_font': 'default' as NickFont,
  'profile.nick_effect': 'none' as NickEffect,
  /** Второй цвет переливающегося ника; '' — розоватый по умолчанию. */
  'profile.nick_color2': '' as '' | ProfileColor,
  'profile.showcase': [] as ShowcaseItem[],
  /** Приватность профиля (Аккаунт → Приватность, lib/public-profile.ts): что видит гость по ссылке. */
  'privacy.friend_requests': 'everyone' as 'everyone' | 'fof' | 'nobody',
  'privacy.now_playing': 'everyone' as 'everyone' | 'friends' | 'nobody',
  'privacy.stats': 'everyone' as 'everyone' | 'friends' | 'nobody',
  'privacy.likes': 'everyone' as 'everyone' | 'friends' | 'nobody',
  'privacy.playlists': 'everyone' as 'everyone' | 'friends' | 'nobody',
  /** Плейлисты, скрытые ото всех (меню плейлиста → «Скрыть от других»). */
  'privacy.hidden_playlists': [] as string[],
  'appearance.cover_theme': true,
  /** Насколько тема идёт за обложкой: поверхности темнее / светлее (palette.ts COVER_STRENGTH). */
  'appearance.cover_strength': 'medium' as CoverStrength,
  /** Прозрачность окна (Mica / Acrylic под окном, glass.rs). */
  'appearance.glass': false,
  /** Непрозрачность фона окна и карточек при прозрачности, % (100 — как без неё). */
  'appearance.opacity': 80 as number,
  /** Размытие стекла — больше не используется (ползунок убран 2026-11-17), ключ оставлен для старых настроек. */
  'appearance.glass_blur': 16 as number,
  'appearance.preset': 'neutral' as string,
  'appearance.animations': true,
  'appearance.scale_window': 100,
  /** Масштаб, когда окно развёрнуто; `0` — «Авто», как в окне. */
  'appearance.scale_fullscreen': 100 as number,
  /** Кнопки окна: `auto` — как в системе (на Windows — Windows), `windows` — значки, `macos` — три кружка. */
  'appearance.window_buttons': 'auto' as 'auto' | 'windows' | 'macos',
  /** Значок сервиса рядом с длительностью трека в списках («Показывать площадки»). */
  'appearance.show_sources': false,
  /** Шрифт интерфейса; по умолчанию — как в стиле Sonar (theme/style.ts). */
  'appearance.font': 'Manrope Variable' as string,
  /** Размер шрифта: 16 — как задумано, остальные — множитель n / 16 ко всему тексту. */
  'appearance.font_size': 16 as number,
  /** Жирность обычного текста; заголовки и выделенное — как в вёрстке. */
  'appearance.font_weight': 'auto' as 'auto' | '400' | '500' | '600' | '700',
  'appearance.corner_radius': 'soft' as 'none' | 'soft' | 'rounded' | 'pill',
  // ---- Стиль (Интерфейс → Стиль, theme/style.ts): готовый стиль ставит оси ниже ----
  /** `sonar` / `echo` / `signal` / `edge` / `tactile` / `monolith` / `custom:<id>`. */
  'appearance.style': 'classic' as string,
  /** Формулы фона, поверхностей, границ, теней и бликов (palette.ts SURFACES). */
  'appearance.surface': 'classic' as Surface,
  /** Шрифт заголовков (Sonar Mix, названия страниц и разделов). */
  'appearance.font_display': 'Manrope Variable' as string,
  'appearance.title_style': 'plain' as TitleStyle,
  /** Толщина линий иконок левой панели и мини-плеера. */
  'appearance.icon_stroke': 1.75 as IconStroke,
  'appearance.anim_track': 'classic' as AnimTrack,
  'appearance.anim_like': 'classic' as AnimLike,
  'appearance.anim_nav': 'plate' as AnimNav,
  /** Как нарисован прогресс (место — `mini.progress`). */
  'appearance.progress_look': 'line' as ProgressLook,
  /** Как показана загрузка трека: обложка из ч/б в цвет или кольцо-сектор. */
  'appearance.loading': 'color' as LoadingLook,
  'appearance.custom_styles': [] as CustomStyle[],
  /** «Классика» стала основным видом (2026-11-22): один раз переключаем на неё и тех, у кого был прежний стиль. */
  'appearance.classic_switched': false as boolean,
  /** Значок приложения: окно, панель задач и трей (Rust `app_icon.rs`); список — `lib/app-icons.ts`. */
  'appearance.app_icon': 'glass' as AppIconId,
  /** Панель вкладок (Интерфейс → Вкладки): где она, какая, подстраивается ли под страницу. */
  'tabs.position': 'left' as 'left' | 'top' | 'bottom' | 'right',
  'tabs.style': 'default' as 'default' | 'compact' | 'full' | 'round' | 'floating',
  /** Плавающая панель вкладок — центр в долях окна (перетаскивается куда угодно). */
  'tabs.float_x': 0.045 as number,
  'tabs.float_y': 0.5 as number,
  /** Подстраивать вкладки: цвет панели — от страницы (подкраска обложки). */
  'tabs.adapt': false,
  /** Скрытие элементов: мышь не двигается 3 с — панель вкладок и мини-плеер гаснут. */
  'tabs.autohide': false,
  /** Кеширование треков: прослушанное складывается на диск и играет оттуда (track_cache.rs). */
  'storage.cache_tracks': false,
  /** Лимит кэша треков, МБ; сверх — вытесняются давно не игравшие. */
  'storage.cache_limit_mb': 2048 as number,
  /** Sonar Mix офлайн: следующие 15 треков Sonar Mix заранее скачиваются в кэш треков. */
  'storage.wave_offline': false,
  /** Скачивать Любимые: новый лайк — в очередь «Скачать», при запуске докачиваются недостающие (downloads.rs). */
  'storage.auto_download_liked': false,
  /** Потолок автоскачивания Любимых, ГБ (весь объём скачанного); дальше Sonar не ставит в очередь. */
  'storage.auto_download_limit_gb': 5 as number,
  /** Папки с музыкой на этом компьютере (local/, «На этом компьютере» в Медиатеке). */
  'storage.music_folders': [] as string[],
  'audio.output_device': '' as string,
  /** YouTube Music: обычное — AAC 128 кбит/с, высокое — Opus 160 кбит/с (services/yt.rs, тот же ключ на iPhone). */
  'audio.yt_quality': 'high' as 'normal' | 'high',
  /** Нормализация громкости (player/leveler.ts) — выравнивание тихих и громких треков. */
  'audio.normalize': false,
  /** Кроссфейд, секунды (0 — выкл): следующий трек нарастает, пока текущий затухает. */
  'audio.crossfade': 0 as number,
  /** Бесшовное: без кроссфейда следующий трек стыкуется без паузы (короткое перекрытие). */
  'audio.gapless': true,
  /** Сведение: DJ-переход по долям вместо кроссфейда (player/blend/, docs/BLEND.md). */
  'audio.blend': false,
  /** Вид перехода сведения: авто или один из пяти (player/blend/planner.ts). */
  'audio.blend_type': 'auto' as 'auto' | 'bass' | 'filter' | 'echo' | 'smooth' | 'drop',
  /** Длина перехода сведения, с: 6 · 10 · 16. */
  'audio.blend_length': 10 as number,
  /** Сколько можно срезать у конца A и начала B, с (0–45). */
  'audio.blend_cut': 16 as number,
  /** Допуск темпа для сведения бит в бит, % (0–12). */
  'audio.blend_tempo': 8 as number,
  /** Подгонять тональность B под A на ±2 полутона. */
  'audio.blend_key': true,
  /** Отладочная панель сведения (видна только подписке Dev). */
  'audio.blend_debug': false,
  /** Тише во время звонков: пока другое приложение пишет с микрофона, музыка на 20 % (calls.rs). */
  'audio.duck_calls': true,
  /** Звук при запуске: аккорд рояля под волны заставки (index.html, public/splash-chord.wav). Выключен,
   *  чтобы не был назойливым (решение владельца 2026-11-22); заставка читает зеркало в localStorage. */
  'audio.splash_sound': false,
  /** Резервный сервис: свой сервис трек не играет — тот же трек из другого (services/fallback.rs). */
  'audio.fallback': true,
  /** Порядок резервных сервисов (id реестра); пусто — порядок реестра (lib/fallback.ts). */
  'audio.fallback_order': [] as ServiceId[],
  /** Единый поиск: чей результат сверху (lib/unified-search.ts); дальше — порядок `audio.fallback_order`. */
  'search.preferred': 'sc' as ServiceId,
  /** Медиатека → Исполнители: список плиток или карта (app/artist-map/ArtistMap.svelte). */
  'library.artists_view': 'list' as 'list' | 'map',
  /** Баннер «Вот твоя музыкальная карта» уже показан и закрыт (или по нему перешли). */
  'library.map_banner_done': false,
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
  /** Где мини-плеер: сверху / снизу (под карточкой) / снизу во всю ширину (и под левой панелью) / плавающий. */
  'mini.position': 'bottom' as 'top' | 'bottom' | 'bottom_full' | 'floating',
  /** Плавающий мини-плеер: центр капсулы в долях окна. */
  'mini.float_x': 0.5 as number,
  'mini.float_y': 0.86 as number,
  'mini.background': 'theme' as 'theme' | 'cover' | 'cover_color',
  'mini.progress': ['background'] as readonly MiniProgress[],
  'mini.cover_shape': 'default' as 'default' | 'circle',
  'mini.shape': 'default' as 'default' | 'capsule',
  /** Скругление концов капсул (мини-плеер и левая панель), % от половины высоты: 100 — капсула. */
  'mini.shape_round': 100 as number,
  /** Скругление обложки в мини-плеере, %: 100 — круг. */
  'mini.cover_round': 100 as number,
  /** Оверлей поверх других программ и игр (mini.rs): режим; `off` — горячая клавиша и «само» молчат. */
  'overlay.mode': 'card' as OverlayMode,
  /** Появляться само, когда окно Sonar свёрнуто или спрятано в трей. */
  'overlay.auto': false,
  'overlay.shape': 'rounded' as 'square' | 'rounded',
  /** Клетка сетки 3×3 на экране: строка t/m/b + столбец l/c/r. */
  'overlay.position': 'tc' as OverlayAnchor,
  /** Монитор оверлея: `primary` (основной, какой бы ни был) или `monitorDevicePath` (monitors.rs);
   *  выбранный отключили — оверлей на основном, настройка не стирается. */
  'overlay.monitor': 'primary' as string,
  /** Непрозрачность, %. */
  'overlay.opacity': 90 as number,
  /** Масштаб, %: умножает ширину и высоту. */
  'overlay.scale': 100 as number,
  'overlay.width': 340 as number,
  'overlay.height': 58 as number,
  'player.title_align': 'center' as 'left' | 'center' | 'right',
  'player.artist_avatars': true,
  'player.visualizer': 'bar' as 'off' | 'bar' | 'cover' | 'slider',
  /** Стиль страницы плеера: обычный / пластинка (винил крутится, игла) / большой (обложка на всю высоту). */
  'player.style': 'standard' as 'standard' | 'vinyl' | 'large',
  /** Стиль визуализатора: волна или столбцы. */
  'player.visualizer_style': 'wave' as 'wave' | 'bars',
  /** Спектр звука на дне полноэкранного плеера (тихо, за текстом). */
  'player.visualizer_full': false,
  /** Строка «Почему этот трек» под артистом у треков Sonar Mix. */
  'player.wave_why': true,
  /** Тип ползунка прогресса (Плеер → Вид). */
  'player.slider': 'normal' as 'normal' | 'thin' | 'smooth' | 'wavy' | 'wave_bars',
  /** Маленькая копия обложки в углу большой. */
  'player.pip_cover': false,
  /** Кнопка таймера сна в плеере. По умолчанию нет: нужна немногим и бросается в глаза (владелец 2026-11-22). */
  'player.sleep_button': false,
  'integrations.discord.enabled': true,
  'integrations.discord.cover': true,
  'integrations.discord.progress': true,
  /** Заголовок «Слушает …»: исполнитель / трек / «исполнитель — трек» / «трек — исполнитель» / Sonar. */
  'integrations.discord.status_format': 'artist' as 'artist' | 'title' | 'artist_title' | 'title_artist' | 'app',
  'integrations.discord.artist_photo': true,
  'integrations.discord.show_paused': false,
  'integrations.discord.button_listen': true,
  'integrations.discord.button_download': true,
  'system.autostart': true,
  /** Где действуют сочетания (`HotkeyScope`): только в окне · ещё и пока открыто мини-окно / оверлей · везде,
   *  даже из трея (hotkeys.rs). Старое `hotkeys.enabled = true` читается как `global` — `settings-migrate.ts`. */
  'hotkeys.scope': 'app' as 'app' | 'top' | 'global',
  /** Пульт с iPhone по Wi-Fi (remote/): сервер в локальной сети и объявление `_sonar._tcp`. Только на этом устройстве. */
  'remote.enabled': false,
  /** Действие (`HOTKEY_ACTIONS`) → сочетание (коды KeyboardEvent.code); пустая строка — без клавиши. Чего нет
   *  в сохранённой карте (новые действия) — берётся отсюда. Всё, что может работать по всей системе, — с
   *  Ctrl+Alt: голый Ctrl+O / Ctrl+T перехватил бы «Открыть» и «Новую вкладку» во всех программах. */
  'hotkeys.map': {
    toggle: 'Ctrl+Alt+Space',
    next: 'Ctrl+Alt+ArrowRight',
    prev: 'Ctrl+Alt+ArrowLeft',
    seek_back: '',
    seek_fwd: '',
    volume_up: 'Ctrl+Alt+ArrowUp',
    volume_down: 'Ctrl+Alt+ArrowDown',
    mute: 'Ctrl+Alt+KeyM',
    shuffle: '',
    repeat: '',
    like: 'Ctrl+Alt+KeyL',
    search: 'Slash',
    lyrics: 'Ctrl+KeyL',
    queue: 'Ctrl+KeyQ',
    settings: 'Ctrl+Comma',
    wave: '',
    overlay: 'Ctrl+Alt+KeyO',
    mini: 'Ctrl+Alt+KeyT',
    window: 'Ctrl+Alt+KeyS',
  } as Record<string, string>,
  /** Быстрое окно (Ctrl+K) — только внутри окна Sonar, от `hotkeys.scope` не зависит; пусто — выключено. */
  'hotkeys.quick': 'Ctrl+KeyK',
  'system.tray': true,
  /** Новинки исполнителей: колокольчик справа сверху и тост «У … вышел …» (lib/new-releases.svelte.ts). */
  'notify.releases': true,
  'system.power_saving': 'background' as 'off' | 'minimized' | 'background',
  /** Настроение Sonar Mix (`WAVE_MODES`); старое `new` («Незнакомое») читается как `own` — `settings-migrate.ts`. */
  'wave.mode': 'own' as 'own' | 'fun' | 'calm' | 'sad' | 'hard' | 'night' | 'sleep' | 'popular' | 'focus',
  /** Итоги, которые уже открывали или закрыли на Главной: id через запятую (`month-2026-11,year-2026`), до 24 последних; пусто — никакие. */
  'stats.recap_seen': '' as string,
  /** Трек-затравка подборки «Похоже на трек» на Главной (`lib/home-mixes.ts` `SeedTrack`); пусто — последний прослушанный. */
  'home.similar_seed': null as { ref: string; title: string; artist: string; cover_url: string | null } | null,
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

/** Заставка (index.html) рисуется раньше, чем настройки дочитываются из базы, — ей нужен свой
 *  быстрый флаг: «Звук при запуске» дублируется в localStorage. */
function mirrorSplashSound(on: boolean) {
  try {
    localStorage.setItem('sonar.splash_sound', on ? '1' : '0')
  } catch {
    // хранилище недоступно — заставка просто молчит
  }
}

class Settings {
  private values = $state<Record<string, unknown>>({})
  loaded = $state(false)
  private loading: Promise<void> | null = null
  /** Поменяли до того, как база дочиталась, — после загрузки эти значения не перетираются. */
  private early: Record<string, unknown> = {}

  load(): Promise<void> {
    this.loading ??= api
      .allSettings()
      .then((all) => {
        this.values = { ...migrateSettings(all), ...this.early }
        this.early = {}
        mirrorSplashSound(this.get('audio.splash_sound'))
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
    if (!this.loaded) this.early[key] = value
    this.values = { ...this.values, [key]: value }
    void api.setSetting(key, value).catch(() => {})
    if (key === 'audio.splash_sound') mirrorSplashSound(value as boolean)
  }

  /** Стиль мини-плеера: пресет выставляет фон, прогресс, обложку и форму. */
  setMiniStyle(style: MiniStyle) {
    this.set('mini.style', style)
    if (style === 'off') return
    const p = MINI_PRESETS[style]
    this.set('mini.background', p.bg)
    this.set('mini.progress', p.progress)
    this.setMiniCover(p.cover)
    this.setMiniShape(p.shape)
  }

  /** Обложка мини-плеера: по умолчанию (чуть скруглённая) или круглая. */
  setMiniCover(cover: 'default' | 'circle') {
    this.set('mini.cover_shape', cover)
    this.set('mini.cover_round', MINI_COVER_ROUND[cover])
  }

  /** Форма мини-плеера (и левой панели): по умолчанию или капсула. */
  setMiniShape(shape: 'default' | 'capsule') {
    this.set('mini.shape', shape)
    this.set('mini.shape_round', MINI_SHAPE_ROUND[shape])
  }

  /** Значение уже записано в базу другим путём (меню трея → Rust) — только обновить зеркало, без записи. */
  mirror<K extends SettingKey>(key: K, value: Value<K>) {
    this.values = { ...this.values, [key]: value }
  }

  /** После «Сбросить настройки». */
  async reload() {
    this.loading = null
    await this.load()
  }
}

export const settings = new Settings()
