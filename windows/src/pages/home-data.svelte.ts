// Данные главной: подборка под время суток и недавнее (локальная история), релизы недели тех, на
// кого стоят лайки, «Похоже на» трёх последних исполнителей, аккаунт для приветствия. Сетевое держим 15 минут,
// чтобы возврат на главную был мгновенным. Тренды, плейлисты пользователей и чарты Sonar — с
// сервера (API.md §5а), до него эти ряды показывают заготовку.
import { api, type Album, type ArtistRef, type ServiceStatus, type Track } from '../lib/api'
import { seedArtists, similarRow } from '../lib/home-mixes'
import { relatedLookup } from '../lib/artist-map/api'
import { t } from '../lib/i18n.svelte'
import { ACCOUNT_SERVICES, isLocalRef, statusOf } from '../lib/services'

const TTL = 15 * 60_000
/** Сколько недавнего держим: подборка «Недавнее» и затравки «Похоже на». */
const RECENT = 50
/** «Похоже на»: сколько исполнителей из недавнего и сколько похожих на трек каждого. */
const SIMILAR_SEEDS = 3
const SIMILAR_PER_SEED = 16
const WEEK = 7 * 24 * 3600_000

/** Часть суток для приветствия и подборки. Подписи DAYPART_TEXT — ключи перевода, `t()` при показе. */
export type Daypart = 'morning' | 'day' | 'evening' | 'night'

export function daypart(hour: number): Daypart {
  if (hour >= 5 && hour < 12) return 'morning'
  if (hour >= 12 && hour < 18) return 'day'
  if (hour >= 18 && hour < 23) return 'evening'
  return 'night'
}

export const DAYPART_TEXT: Record<Daypart, { hello: string; mix: string }> = {
  morning: { hello: 'Доброе утро', mix: 'Твоё утро' },
  day: { hello: 'Добрый день', mix: 'Твой день' },
  evening: { hello: 'Добрый вечер', mix: 'Твой вечер' },
  night: { hello: 'Доброй ночи', mix: 'Твоя ночь' },
}

/** Релизы за последние 7 дней (по дате выхода `released`, `YYYY-MM-DD`), новые первыми. */
export function weekReleases(list: Album[], now = Date.now()): Album[] {
  return list.filter((a) => {
    if (!a.released) return false
    const t = Date.parse(`${a.released}T00:00:00`)
    return Number.isFinite(t) && t <= now && now - t < WEEK
  })
}

const MONTHS = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек']

/** Подпись даты выхода: «сегодня», «вчера», «12 ноя». */
export function releaseLabel(released: string | null | undefined, now = new Date()): string | undefined {
  if (!released) return undefined
  const [y, m, d] = released.split('-').map(Number)
  if (!y || !m || !d) return undefined
  const day = (x: Date) => Date.UTC(x.getFullYear(), x.getMonth(), x.getDate())
  const diff = Math.round((day(now) - Date.UTC(y, m - 1, d)) / 86_400_000)
  if (diff === 0) return t('сегодня')
  if (diff === 1) return t('вчера')
  return `${d} ${t(MONTHS[m - 1])}${y !== now.getFullYear() ? ` ${y}` : ''}`
}

class Home {
  recent = $state<Track[]>([])
  /** Подборка под время суток (`daypart_mix`). */
  mix = $state<Track[]>([])
  releases = $state<Album[]>([])
  similar = $state<Track[]>([])
  /** Исполнители, на которых похож ряд «Похоже на» (аватар и имя кликабельны). */
  similarArtists = $state<ArtistRef[]>([])
  account = $state<ServiceStatus | null>(null)
  loading = $state(false)
  releasesLoading = $state(false)
  similarLoading = $state(false)

  private releasesAt = 0
  private similarKey = ''

  async load() {
    this.loading = !this.recent.length
    try {
      ;[this.recent, this.mix] = await Promise.all([api.recentTracks(RECENT), api.daypartMix(24).catch(() => [])])
    } catch {
      // вне приложения — пусто
    } finally {
      this.loading = false
    }
    void this.loadAccount()
    void this.loadReleases()
    void this.loadSimilar()
  }

  private async loadAccount() {
    try {
      const s = await api.servicesStatus()
      // первый по порядку реестра подключённый сервис с именем аккаунта (SoundCloud, потом Яндекс)
      this.account = ACCOUNT_SERVICES.map((svc) => statusOf(s, svc)).find((a) => a?.connected && a.name) ?? null
    } catch {
      this.account = null
    }
  }

  private async loadReleases() {
    if (this.releasesLoading || (this.releases.length && Date.now() - this.releasesAt < TTL)) return
    this.releasesLoading = true
    try {
      this.releases = await api.homeReleases()
      this.releasesAt = Date.now()
    } catch {
      // нет сети или сервисов — ряд покажет подсказку
    } finally {
      this.releasesLoading = false
    }
  }

  /** «Похоже на»: по последним трекам трёх разных исполнителей; те же затравки — не перезапрашиваем. */
  private async loadSimilar() {
    const seeds = seedArtists(
      this.recent.filter((x) => !isLocalRef(x.ref)),
      SIMILAR_SEEDS,
    )
    const key = seeds.map((s) => s.track.ref).join('|')
    if (!seeds.length || this.similarLoading || (this.similarKey === key && this.similar.length)) return
    this.similarLoading = true
    try {
      const names = seeds.map((s) => s.artist.name)
      const [results, related] = await Promise.all([
        Promise.allSettled(seeds.map((s) => api.similarTracks(s.track.ref, SIMILAR_PER_SEED))),
        relatedLookup(names),
      ])
      const pools = results.flatMap((r) => (r.status === 'fulfilled' ? [r.value] : []))
      this.similar = similarRow(
        pools,
        this.recent.map((x) => x.ref),
        undefined,
        names.flatMap(related),
      )
      this.similarArtists = seeds.map((s) => s.artist)
      this.similarKey = key
    } catch {
      this.similar = []
    } finally {
      this.similarLoading = false
    }
  }
}

export const home = new Home()
