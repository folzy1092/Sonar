// Быстрое окно (Ctrl+K, app/QuickOpen.svelte): поле и список. Ищет действия, разделы настроек,
// свои плейлисты, Любимые и историю — сразу; треки и артистов подключённых сервисов — через 250 мс
// после ввода, по реестру lib/services.ts. Поиск нечёткий (lib/quick-core.ts): по началам слов и
// в другой раскладке (ghbdtn → привет).
import type { IconName } from '../components/icons'
import { api, errorText, type Artist, type Track } from './api'
import { connected, serviceOf, type ServiceId } from './services'
import { settings } from './settings.svelte'
import { library } from './library.svelte'
import { toast } from './toast.svelte'
import { t } from './i18n.svelte'
import { tracksText } from './format'
import { interleave, normalize, rank, searchLayouts, uniqueByRef } from './quick-core'
import { QUICK_ACTIONS, QUICK_GROUPS, QUICK_SETTINGS, WAVE_MOOD_TITLE, type QuickActionId, type QuickGroupId, type QuickHint } from './quick-catalog'
import { player } from '../player/player.svelte'
import { wave, WAVE_MODES, type WaveMode } from '../player/my-wave.svelte'
import { sleep } from '../player/sleep.svelte'
import { playStation } from '../player/autoplay.svelte'
import { router, openRef, type Page } from '../app/router.svelte'
import { settingsPanel, type SettingsTab } from '../pages/settings-section.svelte'
import { lyrics } from '../lyrics/lyrics.svelte'

export type { QuickHint } from './quick-catalog'

export interface QuickItem {
  key: string
  group: QuickGroupId
  title: string
  sub: string | null
  icon: IconName
  cover: string | null
  service: ServiceId | null
  hint: QuickHint
  /** `shift` — Shift+Enter: трек — в очередь, плейлист — играть. */
  run: (shift: boolean) => void | Promise<void>
}

export interface QuickSection {
  id: QuickGroupId
  title: string
  items: QuickItem[]
}

/** Задержка поиска по сервисам после ввода. */
const REMOTE_DELAY_MS = 250
/** Короче — по сервисам не ищем (слишком много шума). */
const REMOTE_MIN_CHARS = 2
const REMOTE_TRACKS_PER_SERVICE = 5
const REMOTE_ARTISTS_PER_SERVICE = 4
const MAX_TRACKS = 8
const MAX_ARTISTS = 5
/** Сколько строк в своей группе: при пустом запросе и при поиске. */
const LIMIT_IDLE = 6
const LIMIT_FOUND = 5
const HISTORY_SIZE = 30

const SLEEP_MINUTES: Partial<Record<QuickActionId, number>> = { sleep_15: 15, sleep_30: 30, sleep_60: 60 }
const THEMES: Partial<Record<QuickActionId, 'dark' | 'light' | 'system'>> = {
  theme_dark: 'dark',
  theme_light: 'light',
  theme_system: 'system',
}
const PAGES: Partial<Record<QuickActionId, Page>> = {
  go_home: 'home',
  go_library: 'library',
  go_search: 'search',
  go_player: 'player',
}

/** Перед переходом — закрыть то, что лежит поверх страниц: полноэкранный плеер (он выше панели
 *  настроек) и, если идём на страницу, саму панель. Иначе переход случится под ними и его не видно. */
function leaveOverlays(keepSettings = false) {
  lyrics.close()
  if (!keepSettings) settingsPanel.close()
}

function go(page: Page, param: string | null = null) {
  leaveOverlays()
  router.go(page, param)
}

function openSettings(tab?: SettingsTab, sub?: string) {
  leaveOverlays(true)
  settingsPanel.show(tab, sub)
}

function runAction(id: QuickActionId, title: string) {
  const minutes = SLEEP_MINUTES[id]
  const theme = THEMES[id]
  const page = PAGES[id]
  if (minutes) {
    sleep.start(minutes)
    toast.show(t(title))
  } else if (theme) {
    settings.set('appearance.mode', theme)
  } else if (page) {
    go(page)
  } else if (id === 'toggle') {
    if (player.current) player.toggle()
    else wave.toggle()
  } else if (id === 'next') return player.next()
  else if (id === 'prev') return player.prev()
  else if (id === 'like') {
    if (!player.current) toast.show(t('Ничего не играет'))
    else return library.toggleLike(player.current)
  } else if (id === 'shuffle') player.toggleShuffle()
  else if (id === 'wave') wave.toggle()
  else if (id === 'sleep_track') {
    sleep.startEndOfTrack()
    toast.show(t(title))
  } else if (id === 'sleep_off') {
    sleep.cancel()
    toast.show(t('Таймер сна выключен'))
  } else if (id === 'settings') openSettings()
}

function actionItems(): { item: QuickItem; texts: string[] }[] {
  const actions = QUICK_ACTIONS.map((a) => ({
    item: {
      key: `action:${a.id}`,
      group: 'actions' as const,
      title: t(a.title),
      sub: null,
      icon: a.icon,
      cover: null,
      service: null,
      hint: 'run' as const,
      run: () => runAction(a.id, a.title),
    },
    texts: [t(a.title), a.title, ...a.keywords],
  }))
  const moods = WAVE_MODES.map((m) => {
    const title = t(WAVE_MOOD_TITLE, { mode: t(m.title) })
    return {
      item: {
        key: `mood:${m.id}`,
        group: 'actions' as const,
        title,
        sub: t(m.sub),
        icon: m.icon as IconName,
        cover: null,
        service: null,
        hint: 'run' as const,
        run: () => wave.setMode(m.id as WaveMode, true),
      },
      texts: [title, `${m.title.split('::').pop()} микс`, `${t(m.title)} ${t('Sonar Mix')}`, t(m.sub), m.sub, 'mood wave настроение'],
    }
  })
  return [...actions, ...moods]
}

function settingItems(): { item: QuickItem; texts: string[] }[] {
  return QUICK_SETTINGS.map((s) => {
    const path = s.path.map((p) => t(p))
    return {
      item: {
        key: `setting:${s.key}`,
        group: 'settings' as const,
        title: t(s.title),
        sub: path.length ? path.join(' · ') : null,
        icon: s.icon,
        cover: null,
        service: null,
        hint: 'open' as const,
        run: () => openSettings(s.tab, s.sub),
      },
      texts: [[t(s.title), ...path].join(' '), [s.title, ...s.path].join(' ')],
    }
  })
}

async function playOwn(id: string, title: string) {
  if (id === 'favorites') {
    const tracks = await api.favorites()
    if (tracks.length) await player.playList(tracks, 0, 'favorites', t('Любимые'))
    else toast.show(t('В Любимых пока пусто'))
    return
  }
  const pl = await api.playlist(id)
  if (pl.tracks?.length) await player.playList(pl.tracks, 0, `playlist:${id}`, title)
  else toast.show(t('В плейлисте нет треков'))
}

function libraryItems(): { item: QuickItem; texts: string[] }[] {
  const own = (id: string, title: string, sub: string | null, cover: string | null, icon: IconName, extra: string[]) => ({
    item: {
      key: `pl:${id}`,
      group: 'library' as const,
      title,
      sub,
      icon,
      cover,
      service: null,
      hint: 'open-play' as const,
      run: (shift: boolean) => (shift ? playOwn(id, title) : go('playlist', id)),
    },
    texts: [title, ...extra],
  })
  return [
    own('favorites', t('Любимые'), t('Медиатека'), null, 'heart', ['Любимые', 'favorites', 'likes', 'лайки']),
    ...library.playlists
      .filter((p) => !p.hidden)
      .map((p) => own(p.id, p.name, tracksText(p.track_count), p.covers[0] ?? null, 'playlist', [])),
  ]
}

/** Трек из поиска — как на странице поиска (с «Авто похожими» следом похожие), из истории — как
 *  в списке истории (контекст `recent`, очередь «История»). */
function playTrack(group: 'history' | 'tracks', list: Track[], i: number) {
  const context = group === 'history' ? 'recent' : 'search'
  if (settings.get('general.similar_autoplay')) return playStation(list[i], context)
  return player.playList(list, i, context, group === 'history' ? t('История') : null)
}

function trackItem(group: 'history' | 'tracks', list: Track[], i: number): QuickItem {
  const tr = list[i]
  return {
    key: `${group}:${tr.ref}`,
    group,
    title: tr.title,
    sub: tr.artist,
    icon: 'music',
    cover: tr.cover_url,
    service: serviceOf(tr.ref),
    hint: 'play',
    run: async (shift) => {
      if (!shift) return playTrack(group, list, i)
      await player.addToQueue([tr], false)
      toast.show(t('В очереди: {title}', { title: tr.title }))
    },
  }
}

function artistItem(a: Artist): QuickItem {
  return {
    key: `artist:${a.ref}`,
    group: 'artists',
    title: a.name,
    sub: t('Артист'),
    icon: 'user',
    cover: a.avatar_url,
    service: serviceOf(a.ref),
    hint: 'open',
    run: () => {
      leaveOverlays()
      openRef(a.ref)
    },
  }
}

class Quick {
  open = $state(false)
  query = $state('')
  /** Растёт с каждым открытием — ключ каскада списка. */
  opened = $state(0)
  history = $state<Track[]>([])
  tracks = $state<Track[]>([])
  artists = $state<Artist[]>([])
  searching = $state(false)
  remoteError = $state<string | null>(null)

  private seq = 0
  private timer: ReturnType<typeof setTimeout> | null = null

  /** Группы с результатами — по порядку QUICK_GROUPS, пустые не показываются. */
  sections = $derived.by(() => this.build(this.query))

  show() {
    if (this.open) return
    this.query = ''
    this.resetRemote()
    this.opened++
    this.open = true
    void library.load()
    void this.loadHistory()
  }

  hide() {
    if (!this.open) return
    this.open = false
    this.resetRemote()
  }

  toggle() {
    if (this.open) this.hide()
    else this.show()
  }

  setQuery(q: string) {
    this.query = q
    this.scheduleRemote(q)
  }

  /** Выполнить строку и закрыть окно. Ошибка — тостом. */
  run(item: QuickItem, shift: boolean) {
    this.hide()
    Promise.resolve()
      .then(() => item.run(shift))
      .catch((e) => toast.show(errorText(e)))
  }

  private async loadHistory() {
    try {
      this.history = await api.recentTracks(HISTORY_SIZE)
    } catch {
      this.history = [] // вне приложения — пусто
    }
  }

  private resetRemote() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
    this.seq++
    this.tracks = []
    this.artists = []
    this.searching = false
    this.remoteError = null
  }

  private scheduleRemote(q: string) {
    this.resetRemote()
    const query = normalize(q)
    if (query.length < REMOTE_MIN_CHARS) return
    const my = this.seq
    this.searching = true
    this.timer = setTimeout(() => void this.searchRemote(query, my), REMOTE_DELAY_MS)
  }

  private async searchRemote(q: string, my: number) {
    try {
      const services = connected(await api.servicesList()).filter((s) => s.caps.search)
      if (my !== this.seq) return
      // ничего — возможно, набрано не в той раскладке: пробуем каждую (en → ru, en → uk, кириллица → en)
      const ids = services.map((s) => s.id)
      const found = await searchLayouts(
        q,
        (variant) => this.fetchFrom(ids, variant),
        (r) => !r.failed && !r.tracks.length && !r.artists.length,
        () => my === this.seq,
      )
      if (my !== this.seq) return
      this.tracks = found.tracks
      this.artists = found.artists
      this.remoteError = found.failed ? t('Сервисы не ответили — попробуй ещё раз') : null
    } catch (e) {
      if (my === this.seq) this.remoteError = errorText(e)
    } finally {
      if (my === this.seq) this.searching = false
    }
  }

  /** Треки и артисты со всех сервисов сразу. `failed` — не ответил ни один. */
  private async fetchFrom(ids: ServiceId[], q: string) {
    if (!ids.length) return { tracks: [], artists: [], failed: false }
    const [tracks, more] = await Promise.all([
      Promise.allSettled(ids.map((id) => api.search(q, id, REMOTE_TRACKS_PER_SERVICE))),
      Promise.allSettled(ids.map((id) => api.searchMore(q, id, REMOTE_ARTISTS_PER_SERVICE))),
    ])
    const ok = <T>(r: PromiseSettledResult<T>[]) => r.flatMap((x) => (x.status === 'fulfilled' ? [x.value] : []))
    return {
      tracks: uniqueByRef(interleave(ok(tracks))).slice(0, MAX_TRACKS),
      artists: uniqueByRef(interleave(ok(more).map((m) => m.artists))).slice(0, MAX_ARTISTS),
      failed: [...tracks, ...more].every((r) => r.status === 'rejected'),
    }
  }

  private build(query: string): QuickSection[] {
    const q = normalize(query)
    const pick = (rows: { item: QuickItem; texts: string[] }[], limit: number) =>
      rank(rows, q, (r) => r.texts, limit).map((r) => r.item)
    const limit = q ? LIMIT_FOUND : LIMIT_IDLE
    const history = this.history
    const historyRows = history.map((tr, i) => ({ item: trackItem('history', history, i), texts: [`${tr.title} ${tr.artist}`] }))
    const tracks = this.tracks
    const items: Record<QuickGroupId, QuickItem[]> = {
      // без запроса — самые частые действия, без настроений и таймеров
      actions: pick(q ? actionItems() : actionItems().slice(0, LIMIT_IDLE), limit),
      settings: q ? pick(settingItems(), limit) : [],
      library: pick(libraryItems(), limit),
      history: pick(uniqueByRef(historyRows.map((r) => ({ ...r, ref: r.item.key }))), limit),
      tracks: tracks.map((_, i) => trackItem('tracks', tracks, i)),
      artists: this.artists.map(artistItem),
    }
    return QUICK_GROUPS.map((g) => ({ id: g.id, title: t(g.title), items: items[g.id] })).filter((s) => s.items.length)
  }
}

export const quick = new Quick()
