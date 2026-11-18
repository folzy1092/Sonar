// Быстрое окно (Ctrl+K) — что в нём ищется, кроме треков: действия и разделы настроек. Только данные
// (подписи по-русски — ключи перевода, `t()` при показе); выполняет их lib/quick.svelte.ts.
// Ключевые слова не показываются — это запасные слова для поиска (в том числе английские).
import type { IconName } from '../components/icons'
import { SUBS, TABS, type SettingsTab } from '../pages/settings-section.svelte'

export type QuickGroupId = 'actions' | 'settings' | 'library' | 'history' | 'tracks' | 'artists'

/** Порядок и названия групп (ключи перевода). Tab переходит между ними. */
export const QUICK_GROUPS: readonly { id: QuickGroupId; title: string }[] = [
  { id: 'actions', title: 'Действия' },
  { id: 'settings', title: 'Настройки' },
  { id: 'library', title: 'Медиатека' },
  { id: 'history', title: 'История' },
  { id: 'tracks', title: 'Треки' },
  { id: 'artists', title: 'Артисты' },
]

/** Что делают Enter и Shift+Enter — подсказка справа у строки: `play` — играть / в очередь,
 *  `open-play` — открыть / играть, `open` — открыть, `run` — выполнить. */
export type QuickHint = 'play' | 'open' | 'open-play' | 'run'

/** Клавиша и подпись (ключ перевода) — подсказки справа у выбранной строки. */
export const QUICK_HINTS: Readonly<Record<QuickHint, readonly (readonly [string, string])[]>> = {
  play: [
    ['Enter', 'играть'],
    ['Shift+Enter', 'в очередь'],
  ],
  'open-play': [
    ['Enter', 'открыть'],
    ['Shift+Enter', 'играть'],
  ],
  open: [['Enter', 'открыть']],
  run: [['Enter', 'выполнить']],
}

export type QuickActionId =
  | 'toggle'
  | 'next'
  | 'prev'
  | 'like'
  | 'shuffle'
  | 'wave'
  | 'sleep_15'
  | 'sleep_30'
  | 'sleep_60'
  | 'sleep_track'
  | 'sleep_off'
  | 'theme_dark'
  | 'theme_light'
  | 'theme_system'
  | 'settings'
  | 'go_home'
  | 'go_library'
  | 'go_search'
  | 'go_player'

export interface QuickAction {
  id: QuickActionId
  title: string
  keywords: readonly string[]
  icon: IconName
}

/** Действия по порядку показа при пустом запросе. Настроения волны добавляются из WAVE_MODES. */
export const QUICK_ACTIONS: readonly QuickAction[] = [
  { id: 'toggle', title: 'Играть / пауза', keywords: ['пауза', 'продолжить', 'play', 'pause'], icon: 'pause' },
  { id: 'next', title: 'Следующий трек', keywords: ['дальше', 'пропустить', 'next', 'skip'], icon: 'next' },
  { id: 'prev', title: 'Предыдущий трек', keywords: ['назад', 'previous', 'back'], icon: 'prev' },
  { id: 'like', title: 'В Любимые / убрать', keywords: ['лайк', 'нравится', 'like', 'favorite'], icon: 'heart' },
  { id: 'shuffle', title: 'Перемешать', keywords: ['shuffle', 'случайно'], icon: 'shuffle' },
  { id: 'wave', title: 'Моя волна', keywords: ['волна', 'wave', 'радио'], icon: 'waveform' },
  { id: 'sleep_15', title: 'Таймер сна: 15 минут', keywords: ['sleep', 'timer', 'спать'], icon: 'clock' },
  { id: 'sleep_30', title: 'Таймер сна: 30 минут', keywords: ['sleep', 'timer', 'спать'], icon: 'clock' },
  { id: 'sleep_60', title: 'Таймер сна: 1 час', keywords: ['sleep', 'timer', 'спать'], icon: 'clock' },
  { id: 'sleep_track', title: 'Таймер сна: до конца трека', keywords: ['sleep', 'timer', 'спать'], icon: 'clock' },
  { id: 'sleep_off', title: 'Выключить таймер сна', keywords: ['sleep', 'timer', 'отменить'], icon: 'clock' },
  { id: 'theme_dark', title: 'Тёмная тема', keywords: ['dark', 'theme', 'ночь'], icon: 'moon' },
  { id: 'theme_light', title: 'Светлая тема', keywords: ['light', 'theme', 'день'], icon: 'sun' },
  { id: 'theme_system', title: 'Тема как в системе', keywords: ['system', 'theme', 'авто'], icon: 'monitor' },
  { id: 'settings', title: 'Открыть настройки…', keywords: ['настройки', 'settings', 'preferences'], icon: 'settings' },
  { id: 'go_home', title: 'Главная', keywords: ['home', 'домой'], icon: 'home' },
  { id: 'go_library', title: 'Медиатека', keywords: ['library', 'плейлисты'], icon: 'library' },
  { id: 'go_search', title: 'Поиск', keywords: ['search', 'найти'], icon: 'search' },
  { id: 'go_player', title: 'Плеер', keywords: ['player', 'сейчас играет', 'now playing'], icon: 'player' },
]

/** Подпись настроения волны: «Моя волна: Грустная». */
export const WAVE_MOOD_TITLE = 'Моя волна: {mode}'

/** Что лежит в разделах настроек (подписи строк — те же ключи перевода, что на страницах):
 *  по ним раздел находится, даже если ищешь не его название, а строку внутри. */
export const SETTINGS_KEYWORDS: Readonly<Record<string, readonly string[]>> = {
  profile: ['Имя пользователя', 'Отображаемое имя', 'Выбрать аватар'],
  stats: ['Любимые артисты', 'Любимые треки', 'История прослушиваний'],
  style: ['Шрифт интерфейса', 'Шрифт заголовков', 'Толщина линий'],
  look: ['Тема', 'Сила темы под обложку', 'Прозрачность', 'Размер шрифта', 'Жирность шрифта', 'Скругление углов', 'Анимации'],
  tabs: ['Позиция вкладок', 'Стиль вкладок', 'Скрытие элементов'],
  audio: ['Устройство вывода', 'Качество аудио', 'YouTube Music', 'Нормализация громкости', 'Бесшовное воспроизведение', 'Кроссфейд', 'Тише во время звонков'],
  view: ['Стиль плеера', 'Визуализатор', 'Аватарки артистов', 'Почему этот трек', 'Позиция обложки'],
  queue: ['Предпросмотр следующего трека', 'Положение очереди', 'Вид очереди', 'Авто похожие'],
  mini: ['Позиция', 'Прогресс', 'Обложка'],
  services: ['SoundCloud', 'Яндекс Музыка', 'YouTube Music', 'VK Музыка', 'Spotify'],
  apps: ['Discord RPC', 'Last.fm', 'OBS Studio'],
  general: ['Язык', 'Платформа', 'Экономия ресурсов', 'Открывать Sonar при входе в систему'],
  hotkeys: ['Сочетания', 'Быстрое окно'],
  update: ['Проверять обновления', 'История версий'],
  storage: ['Кеширование треков', 'Размер кэша треков', 'Волна офлайн', 'Очистка кеша', 'Папки с музыкой'],
}

export interface QuickSetting {
  /** Уникальный ключ строки: `tab/sub` у раздела, `tab/sub/строка` у строки внутри. */
  key: string
  tab: SettingsTab
  sub: string
  /** Что показать: название раздела или строки (ключ перевода). */
  title: string
  /** Где лежит: вкладка и раздел (ключи перевода). */
  path: readonly string[]
  icon: IconName
}

/** Все разделы настроек и строки в них — без «скоро» и «в разработке». */
export const QUICK_SETTINGS: readonly QuickSetting[] = TABS.flatMap((tab) =>
  SUBS[tab.id]
    .filter((s) => !s.soon && !s.lock)
    .flatMap((s) => {
      const sectionPath = s.title === tab.title ? [tab.title] : [tab.title, s.title]
      const section: QuickSetting = { key: `${tab.id}/${s.id}`, tab: tab.id, sub: s.id, title: s.title, path: s.title === tab.title ? [] : [tab.title], icon: s.icon }
      const rows = (SETTINGS_KEYWORDS[s.id] ?? []).map(
        (title): QuickSetting => ({ key: `${tab.id}/${s.id}/${title}`, tab: tab.id, sub: s.id, title, path: sectionPath, icon: s.icon }),
      )
      return [section, ...rows]
    }),
)
