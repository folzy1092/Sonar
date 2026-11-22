// «Новинки» (колокольчик справа сверху, app/ReleasesBell.svelte): у любимых исполнителей вышел трек,
// сингл или альбом — Sonar сам это замечает. Без сервера: при запуске (через полминуты, чтобы не мешать
// загрузке) и дальше раз в 3 часа ядро собирает ленту (`release_feed`), здесь из неё берутся релизы
// за последнюю неделю, которых пользователь ещё не видел. Про самый свежий — тост «У … вышел …».
// Что уже видели — localStorage (`sonar.releases.seen`), выключатель — Уведомления → «Новинки исполнителей».
// С сервером — настоящие пуши в ночь релиза (docs/ROADMAP.md).
import { api, type ReleaseItem } from './api'
import { settings } from './settings.svelte'
import { toast } from './toast.svelte'
import { t } from './i18n.svelte'
import { openRef } from '../app/router.svelte'
import { player } from '../player/player.svelte'

const WEEK = 7 * 24 * 60 * 60 * 1000
const SEEN_KEY = 'sonar.releases.seen'
const SEEN_MAX = 600
const FIRST_DELAY = 30_000
const EVERY = 3 * 60 * 60 * 1000

/** Вышло за последнюю неделю (по дате выхода, в будущем — не считается). */
export function isFresh(released: string, now = Date.now()): boolean {
  const at = Date.parse(`${released}T00:00:00`)
  return Number.isFinite(at) && at <= now && now - at < WEEK
}

/** Свежие релизы, которых ещё не видели, — новые первыми (лента уже отсортирована). */
export function unseenFresh(items: readonly ReleaseItem[], seen: ReadonlySet<string>, now = Date.now()): ReleaseItem[] {
  return items.filter((i) => isFresh(i.released, now) && !seen.has(i.ref))
}

function readSeen(): Set<string> {
  try {
    const raw = JSON.parse(localStorage.getItem(SEEN_KEY) ?? '[]')
    return new Set(Array.isArray(raw) ? raw.filter((x): x is string => typeof x === 'string') : [])
  } catch {
    return new Set()
  }
}

class NewReleases {
  /** Свежие за неделю — список во всплывашке колокольчика. */
  fresh = $state<ReleaseItem[]>([])
  /** Ещё не открытые — число на колокольчике. */
  unread = $state(0)
  private seen = readSeen()
  private timer: ReturnType<typeof setInterval> | null = null

  start() {
    if (this.timer) return
    setTimeout(() => void this.check(), FIRST_DELAY)
    this.timer = setInterval(() => void this.check(), EVERY)
  }

  async check() {
    if (!settings.get('notify.releases')) return
    const items = await api.releaseFeed().catch(() => null)
    if (!items) return
    this.fresh = items.filter((i) => isFresh(i.released))
    const unseen = unseenFresh(items, this.seen)
    this.unread = unseen.length
    const top = unseen[0]
    if (top) {
      toast.show(t('У {artist} вышел «{title}»', { artist: top.artist, title: top.title }), 6000, {
        label: t('Открыть'),
        run: () => this.open(top),
      })
    }
  }

  /** Колокольчик открыли — всё, что в нём, считается увиденным. */
  markSeen() {
    for (const i of this.fresh) this.seen.add(i.ref)
    const all = [...this.seen].slice(-SEEN_MAX)
    this.seen = new Set(all)
    try {
      localStorage.setItem(SEEN_KEY, JSON.stringify(all))
    } catch {
      // хранилище недоступно — в следующий раз покажем снова, не беда
    }
    this.unread = 0
  }

  /** Альбом — его страница; трек SoundCloud — сразу играет. */
  open(item: ReleaseItem) {
    this.markSeen()
    if (item.kind === 'track' && item.track) void player.playList([item.track], 0, 'releases', t('Новинки'))
    else openRef(item.ref)
  }
}

export const newReleases = new NewReleases()
