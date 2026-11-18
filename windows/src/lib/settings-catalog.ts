// Каталог настроек для поиска в панели настроек (NEXT_PROMPT «Этап 0» п. 4, docs/SETTINGS.md):
// что где лежит — раздел, подраздел, название как на экране, подсказка, ключ настройки. Ключи — из
// SETTINGS.md (общие с iPhone), порядок строк — как пункты идут на экране. Строки — по-русски (это ключи
// перевода), поиск идёт и по переводу, и по русскому оригиналу. Плюс строка «что это меняет» у
// каждого подраздела (SUB_LEADS) — её показывает панель над страницей.
import type { SettingsTab } from '../pages/settings-section.svelte'

export interface CatalogEntry {
  tab: SettingsTab
  sub: string
  /** Название пункта ровно как на экране — по нему панель находит строку и подсвечивает её. */
  title: string
  hint?: string
  /** Ключ из SETTINGS.md (DEFAULTS или настройка на стороне Rust). Нет — пункт-раздел или кнопка. */
  key?: string
  /** Слова, по которым тоже ищется (синонимы, английские названия). */
  words?: string
}

/** Настройки, которые хранит Rust (`api.getSetting`), а не `lib/settings.svelte.ts`. */
export const RUST_KEYS: readonly string[] = ['audio.quality', 'audio.sc_via_yandex']

type Row = [title: string, hint?: string, key?: string, words?: string]

const rows = (tab: SettingsTab, sub: string, list: Row[]): CatalogEntry[] =>
  list.map(([title, hint, key, words]) => ({ tab, sub, title, hint, key, words }))

export const CATALOG: readonly CatalogEntry[] = [
  ...rows('account', 'profile', [['Профиль', 'Имя, @username и аватар', undefined, 'аватар имя username ник']]),
  ...rows('account', 'stats', [['Статистика', 'Сколько и что ты слушаешь', undefined, 'итоги прослушивания минуты']]),
  ...rows('interface', 'style', [
    ['Готовые стили', undefined, 'appearance.style', 'стиль оформление style'],
    ['Поверхности', 'Фон, карточки, рамки, тени и блики', 'appearance.surface'],
    ['Шрифт интерфейса', 'Обычный текст, кнопки, списки'],
    ['Шрифт заголовков', '«Моя волна», названия страниц и разделов', 'appearance.font_display'],
    ['Оформление заголовков', '«Журнал» — капсом, крупно, с номерами разделов', 'appearance.title_style'],
    ['Толщина линий', 'Иконки левой панели и кнопок плеера', 'appearance.icon_stroke', 'иконки значки'],
    ['Скругления', 'Углы карточек, кнопок и обложек'],
    ['Смена трека', 'Как обложка и заголовок встречают новый трек', undefined, 'анимация'],
    ['Лайк', 'Что происходит с сердцем, когда ставишь лайк', undefined, 'анимация сердце'],
    ['Выбранный раздел', 'Как отмечен раздел в левой панели'],
    ['Прогресс', 'Как нарисован ползунок времени'],
    ['Загрузка трека', 'Пока трек грузится — по настоящему прогрессу'],
  ]),
  ...rows('interface', 'look', [
    ['Тема', 'Тёмная, светлая или как в системе', 'appearance.mode', 'темная светлая ночь dark light'],
    ['Готовые темы', undefined, 'appearance.preset', 'цвет под трек обложка акцент'],
    ['Сила темы под обложку', 'Насколько фон и карточки темнеют под тёмную обложку и светлеют под светлую', 'appearance.cover_strength', 'слабо средне сильно оттенок'],
    ['Прозрачность', 'Под окном — системное стекло (Windows 11 — Mica, Windows 10 — Blur)', 'appearance.glass', 'стекло mica blur'],
    ['Непрозрачность', 'Насколько плотные фон окна и карточки', 'appearance.opacity'],
    ['Шрифт', 'Семейство шрифта', 'appearance.font', 'font'],
    ['Размер шрифта', 'Базовый размер шрифта интерфейса', 'appearance.font_size', 'текст крупнее мельче'],
    ['Жирность шрифта', 'Плотность начертания обычного текста', 'appearance.font_weight'],
    ['Скругление углов', 'Радиус скругления элементов интерфейса и карточек', 'appearance.corner_radius'],
    ['Масштаб в окне', 'Размер интерфейса в обычном окне', 'appearance.scale_window', 'zoom увеличить'],
    ['Масштаб на весь экран', 'Размер интерфейса, когда окно развёрнуто', 'appearance.scale_fullscreen', 'zoom'],
    ['Анимации', 'Плавные переходы, появление списков, всплывашки', 'appearance.animations', 'движение motion'],
  ]),
  ...rows('interface', 'tabs', [
    ['Позиция вкладок', 'Где стоит панель разделов', 'tabs.position', 'панель сверху снизу слева справа'],
    ['Стиль вкладок', 'Как выглядит панель разделов', 'tabs.style', 'компактный плавающий круглый'],
    ['Подстраивать вкладки', 'Панель берёт цвет подкраски страницы', 'tabs.adapt'],
    ['Скрытие элементов', 'Мышь замерла на 3 секунды — панель и мини плеер гаснут', 'tabs.autohide', 'автоскрытие'],
  ]),
  ...rows('player', 'audio', [
    ['Устройство вывода', 'Выберите аудиоустройство для воспроизведения музыки на этом компьютере', 'audio.output_device', 'наушники колонки динамики'],
    ['Качество аудио', 'Выберите предпочтительное качество воспроизведения', 'audio.quality', 'flac битрейт кбит'],
    ['Нормализация громкости', 'Тихие и громкие треки звучат ровно — без докручивания громкости', 'audio.normalize', 'громкость уровень loudness'],
    ['Бесшовное воспроизведение', 'Следующий трек начинается без паузы — заранее подгружается', 'audio.gapless', 'gapless'],
    ['Кроссфейд', 'Плавное затухание в конце трека и нарастание в начале следующего', 'audio.crossfade', 'crossfade переход'],
    ['Тише во время звонков', 'Музыка стихает, пока другое приложение занимает микрофон', 'audio.duck_calls', 'звонок discord микрофон'],
    ['SoundCloud в качестве Яндекса', 'Играть трек SoundCloud с Яндекса, если он там есть', 'audio.sc_via_yandex'],
  ]),
  ...rows('player', 'view', [
    ['Стиль плеера', 'Выберите визуальный стиль плеера', 'player.style', 'пластинка винил'],
    ['Выравнивание заголовка', 'Выберите выравнивание названия трека', 'player.title_align'],
    ['Аватарки артистов', 'Отображать аватарки исполнителей перед их именами в плеере и мини плеере', 'player.artist_avatars'],
    ['Визуализатор', 'Где показывать визуализацию звука', 'player.visualizer', 'спектр эквалайзер'],
    ['Вид визуализатора', 'Выберите стиль визуализации аудио', 'player.visualizer_style', 'визуализатор волна столбцы'],
    ['Спектр в полноэкранном плеере', 'Тихая волна звука на дне экрана, за текстом', 'player.visualizer_full'],
    ['Почему этот трек', 'Под артистом у треков «Моей волны» — откуда трек', 'player.wave_why', 'моя волна'],
    ['Тип ползунка', 'Выберите стиль ползунка прогресса', 'player.slider', 'перемотка'],
    ['Позиция обложки', 'Выберите где отображается обложка', 'player.cover_position'],
    ['Обложка в обложке', 'Отображать меньшую обложку внутри основной', 'player.pip_cover'],
  ]),
  ...rows('player', 'queue', [
    ['Продолжить с прошлого раза', 'Что вернуть при открытии приложения', 'general.restore', 'восстановить запуск'],
    ['Показывать очередь', 'Отображать панель очереди', 'queue.show'],
    ['Предпросмотр следующего трека', 'За 10 секунд до конца — карточка «Дальше» с названием следующего', 'queue.preview'],
    ['Положение очереди', 'Где открывается панель очереди', 'queue.position'],
    ['Вид очереди', 'Выберите режим отображения треков в списке очереди', 'queue.view'],
    ['Авто похожие', 'После любой очереди играют похожие треки', 'general.similar_autoplay', 'автоплей'],
    ['Добавлять следующие', 'Нажатый трек ставит в очередь и треки после него', 'queue.add_following'],
  ]),
  ...rows('player', 'mini', [
    ['Стиль', 'Готовый набор: фон, прогресс, обложка и форма', 'mini.style', 'мини плеер гибрид дек'],
    ['Позиция', 'Где мини плеер в окне', 'mini.position', 'мини плеер плавающий'],
    ['Фон', 'Чем залит мини плеер', 'mini.background', 'мини плеер'],
    ['Прогресс', 'Как видно, сколько прошло', 'mini.progress', 'мини плеер'],
    ['Форма', 'Скругление концов мини плеера и левой панели: 100% — капсула', 'mini.shape_round', 'мини плеер капсула'],
    ['Обложка', 'Скругление обложки в мини плеере: 100% — круг', 'mini.cover_round', 'мини плеер круг'],
  ]),
  ...rows('services', 'services', [['Сервисы', 'SoundCloud и Яндекс: вход и ключи', undefined, 'soundcloud яндекс токен вход аккаунт']]),
  ...rows('integrations', 'apps', [
    ['Активность в Discord', 'Показывать в профиле, что ты слушаешь', 'integrations.discord.enabled', 'discord rpc статус'],
    ['Формат статуса', 'Что видно в заголовке «Слушает …»', 'integrations.discord.status_format', 'discord'],
    ['Шкала времени трека', 'Прошедшее и оставшееся время', 'integrations.discord.progress', 'discord'],
    ['Обложка трека', 'Обложка альбома в карточке активности', 'integrations.discord.cover', 'discord'],
    ['Мини-фото артиста', 'Маленький значок в углу обложки', 'integrations.discord.artist_photo', 'discord'],
    ['Показывать при паузе', 'Статус остаётся со значком паузы', 'integrations.discord.show_paused', 'discord'],
    ['Кнопка «Слушать в Sonar»', 'Ссылка на этот трек в Sonar', 'integrations.discord.button_listen', 'discord'],
    ['Кнопка «Скачать Sonar»', 'Ссылка на последнюю версию приложения', 'integrations.discord.button_download', 'discord'],
    ['История прослушиваний', 'Скробблить прослушанные треки', 'integrations.lastfm.scrobble', 'last.fm lastfm скробблинг'],
    ['Сейчас играет', 'Показывать текущий трек в профиле', 'integrations.lastfm.now_playing', 'last.fm lastfm'],
    ['Размер плашки', 'Габариты на экране стрима', undefined, 'obs стрим оверлей'],
    ['Скрывать при паузе', 'Плавно убирать плашку со стрима, когда трек остановлен', undefined, 'obs стрим'],
  ]),
  ...rows('system', 'general', [
    ['Язык', 'Язык интерфейса', 'general.language', 'language english українська'],
    ['Платформа', 'Откуда главная берёт волну и рекомендации', 'general.platform', 'моя волна soundcloud яндекс'],
    ['Добавление', 'Куда добавлять новые треки в плейлистах', 'general.add_position', 'плейлист начало конец'],
    ['Автозапуск', 'Открывать Sonar при входе в систему', 'system.autostart', 'запуск windows'],
    ['Сворачивать в трей', 'Крестик прячет окно, музыка играет дальше', 'system.tray', 'tray закрыть крестик'],
    ['Экономия ресурсов', 'Когда упрощать эффекты, чтобы не нагружать компьютер', 'system.power_saving', 'батарея производительность'],
  ]),
  ...rows('system', 'hotkeys', [
    ['Горячие клавиши по всей системе', 'Управлять музыкой, даже когда Sonar свёрнут или спрятан в трей', 'hotkeys.enabled', 'клавиатура сочетания hotkeys'],
    ['Сочетания', undefined, 'hotkeys.map', 'клавиши'],
  ]),
  ...rows('system', 'update', [
    ['Проверять обновления', 'При запуске и раз в 6 часов', 'update.auto_check', 'версия update'],
    ['Скачивать в фоне', 'Обновление скачается само, установится только по кнопке «Установить»', 'update.auto_download'],
    ['История версий', undefined, undefined, 'changelog что нового'],
  ]),
  ...rows('system', 'storage', [
    ['Кеширование треков', 'Прослушанные треки сохраняются на диск и в следующий раз играют без сети', 'storage.cache_tracks', 'кэш офлайн диск'],
    ['Размер кэша треков', 'Сверх лимита удаляются давно не игравшие', 'storage.cache_limit_mb', 'кеш лимит'],
    ['Волна офлайн', 'Следующие 15 треков «Моей волны» заранее скачиваются в кэш', 'storage.wave_offline', 'без сети'],
    ['Очистка кеша', undefined, undefined, 'кэш удалить место'],
    ['Папки с музыкой', 'Музыка с этого компьютера: mp3, flac, m4a, ogg, opus и wav. Треки появятся в Медиатеке — «На этом компьютере», их можно лайкать и добавлять в плейлисты.', undefined, 'локальные файлы mp3 flac диск компьютер local files'],
  ]),
]

/** «Что это меняет» — одна строка над каждым подразделом. */
export const SUB_LEADS: Readonly<Record<string, string>> = {
  profile: 'Имя, @username и аватар — как тебя видят друзья',
  login: 'Вход в аккаунт Sonar — появится вместе с сервером',
  privacy: 'Кто видит твою музыку — в разработке',
  stats: 'Сколько и что ты слушаешь на этом компьютере',
  style: 'Характер интерфейса: поверхности, шрифты и анимации — целиком или по частям',
  look: 'Цвета, прозрачность, шрифт и масштаб окна',
  tabs: 'Где стоит панель разделов и как она выглядит',
  audio: 'Куда и в каком качестве идёт звук',
  view: 'Как выглядит страница плеера',
  queue: 'Что играет дальше и где это видно',
  mini: 'Плеер внизу окна: вид, место и форма',
  services: 'Подключи SoundCloud и Яндекс — отсюда берётся музыка',
  apps: 'Discord, Last.fm и OBS: где ещё видно, что ты слушаешь',
  general: 'Язык, источник волны и что делает Sonar при запуске',
  hotkeys: 'Управление музыкой с клавиатуры, даже когда окно спрятано',
  update: 'Как Sonar находит и ставит новые версии',
  storage: 'Кеш треков и место на диске',
}

/** Нижний регистр, ё → е, лишние пробелы прочь (длина символов не меняется, кроме обрезки). */
export const normalize = (s: string) => s.toLowerCase().replaceAll('ё', 'е').replace(/\s+/g, ' ').trim()

const tokens = (query: string) => normalize(query).split(' ').filter(Boolean)

export interface SearchHit {
  entry: CatalogEntry
  score: number
}

const MAX_HITS = 12
/** Вес совпадения: название с начала слова важнее середины, подсказки и синонимов. */
const WEIGHT = { titleStart: 6, title: 4, original: 3, hint: 1, words: 1 } as const

function tokenScore(tok: string, title: string, original: string, rest: string, words: string): number {
  const at = title.indexOf(tok)
  if (at === 0 || (at > 0 && title[at - 1] === ' ')) return WEIGHT.titleStart
  if (at > 0) return WEIGHT.title
  if (original.includes(tok)) return WEIGHT.original
  if (rest.includes(tok)) return WEIGHT.hint
  return words.includes(tok) ? WEIGHT.words : 0
}

/** Поиск по каталогу: все слова запроса должны найтись; `translate` — t() текущего языка. */
export function searchSettings(query: string, translate: (ru: string) => string, limit = MAX_HITS): SearchHit[] {
  const toks = tokens(query)
  if (!toks.length) return []
  const hits: SearchHit[] = []
  CATALOG.forEach((entry, order) => {
    const title = normalize(translate(entry.title))
    const original = normalize(entry.title)
    const rest = entry.hint ? normalize(`${translate(entry.hint)} ${entry.hint}`) : ''
    const words = normalize(entry.words ?? '')
    const scores = toks.map((tok) => tokenScore(tok, title, original, rest, words))
    if (scores.some((s) => s === 0)) return
    // при равном счёте — порядок каталога (он же порядок пунктов на экране)
    hits.push({ entry, score: scores.reduce((a, b) => a + b, 0) - order / 10_000 })
  })
  return hits.sort((a, b) => b.score - a.score).slice(0, limit)
}

export interface Piece {
  text: string
  mark: boolean
}

/** Куски текста с отметкой совпадений со словами запроса — для `<mark>` в результатах. */
export function markRanges(text: string, query: string): Piece[] {
  const low = text.toLowerCase().replaceAll('ё', 'е')
  const marked = new Array<boolean>(text.length).fill(false)
  for (const tok of tokens(query)) {
    for (let at = low.indexOf(tok); at >= 0; at = low.indexOf(tok, at + tok.length)) marked.fill(true, at, at + tok.length)
  }
  const pieces: Piece[] = []
  for (let i = 0; i < text.length; i++) {
    const last = pieces[pieces.length - 1]
    if (last && last.mark === marked[i]) pieces[pieces.length - 1] = { text: last.text + text[i], mark: last.mark }
    else pieces.push({ text: text[i], mark: marked[i] })
  }
  return pieces.length ? pieces : [{ text, mark: false }]
}

/** Текст элемента на странице — заголовок этого пункта? (переход из поиска к самой настройке) */
export function titleMatches(text: string, title: string): boolean {
  const want = normalize(title)
  return want.length > 0 && normalize(text).startsWith(want)
}
