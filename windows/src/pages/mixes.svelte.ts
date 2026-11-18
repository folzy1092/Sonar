// Подборки «Для тебя» (Главная → карточка → MixPage): «Твой вечер/утро/день/ночь» и «Недавнее» — из
// локальной истории (`home`), «Новое для тебя», «Свежие артисты» и «Похоже на трек» — из похожего на
// любимое (сеть), их держим до полуночи в localStorage, чтобы Главная не ходила в сеть при каждом
// открытии. Отбор и кэш — чистый `lib/home-mixes.ts`.
import { api, type Artist, type Track } from '../lib/api'
import { settings } from '../lib/settings.svelte'
import { t } from '../lib/i18n.svelte'
import { isLocalRef } from '../lib/services'
import { relatedLookup } from '../lib/artist-map/api'
import {
  dayKey,
  dedupe,
  isFresh,
  limitPerArtist,
  parseSeed,
  pickFromPools,
  readCache,
  toSeed,
  trackArtists,
  type MixCache,
  type MixId,
  type SeedTrack,
} from '../lib/home-mixes'
import { DAYPART_TEXT, daypart, home } from './home-data.svelte'

const CACHE_KEY = 'sonar.home-mixes'
/** Сколько затравок (любимых треков) спрашиваем о похожем. */
const SEEDS = 6
/** Сколько похожих берём на одну затравку. */
const PER_SEED = 30
/** Сколько истории смотрим, чтобы понять, каких исполнителей пользователь уже знает. */
const KNOWN_HISTORY = 500
/** В «Твоём вечере» и «Похоже на трек» одного исполнителя может быть больше, чем в «Новом». */
const MAX_PER_ARTIST_LOOSE = 3

function storageGet(): string | null {
  try {
    return localStorage.getItem(CACHE_KEY)
  } catch {
    return null
  }
}

function storageSet(c: MixCache) {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify(c))
  } catch {
    // нет хранилища (приватный режим, квота) — подборки просто соберутся заново
  }
}

/** Что пользователь уже знает и что любит: исполнители истории и Любимых, затравки для похожего. */
async function gatherTaste() {
  const [recent, favs, liked, stats] = await Promise.all([
    api.recentTracks(KNOWN_HISTORY).catch(() => [] as Track[]),
    api.favorites().catch(() => [] as Track[]),
    api.likedCatalog<Artist>('artist').catch(() => [] as Artist[]),
    api.stats('month').catch(() => null),
  ])
  const statArtists = [stats?.top_artist?.name, ...(stats?.more_artists ?? []).map((a) => a.name)].filter((n): n is string => !!n)
  const known = [...recent, ...favs].flatMap((x) => trackArtists(x).map((a) => a.name)).concat(liked.map((a) => a.name), statArtists)
  const seedRefs = [...(stats?.top_tracks ?? []).slice(0, 3).map((x) => x.ref), ...favs.slice(0, 3).map((x) => x.ref), ...recent.slice(0, 3).map((x) => x.ref)]
  // файлы с компьютера похожего не знают — не затравки
  const seeds = [...new Set(seedRefs)].filter((ref) => !isLocalRef(ref)).slice(0, SEEDS)
  return { known, taste: statArtists, seeds }
}

class Mixes {
  newTracks = $state<Track[]>([])
  fresh = $state<Track[]>([])
  like = $state<Track[]>([])
  loading = $state(false)
  likeLoading = $state(false)
  /** Для какой затравки собрано `like` (ref). */
  private likeFor = $state<string | null>(null)
  private day = ''

  /** Затравка «Похоже на трек»: выбранная в настройке, иначе — последний прослушанный трек. */
  get seed(): SeedTrack | null {
    const chosen = parseSeed(settings.get('home.similar_seed'))
    if (chosen) return chosen
    const last = home.recent.find((x) => !isLocalRef(x.ref))
    return last ? toSeed(last) : null
  }

  get chosenSeed(): boolean {
    return parseSeed(settings.get('home.similar_seed')) !== null
  }

  /** Подборка целиком (страница и карточка). */
  tracks(id: MixId): Track[] {
    switch (id) {
      case 'daypart':
        return limitPerArtist(dedupe(home.mix), MAX_PER_ARTIST_LOOSE)
      case 'recent':
        return dedupe(home.recent)
      case 'new':
        return this.newTracks
      case 'fresh':
        return this.fresh
      case 'like':
        return this.likeFor === this.seed?.ref ? this.like : []
    }
  }

  /** Название подборки (уже переведённое). */
  title(id: MixId): string {
    switch (id) {
      case 'daypart':
        return t(DAYPART_TEXT[daypart(new Date().getHours())].mix)
      case 'recent':
        return t('Недавнее')
      case 'new':
        return t('Новое для тебя')
      case 'fresh':
        return t('Свежие артисты')
      case 'like': {
        const s = this.seed
        return s ? t('Похоже на «{title}»', { title: s.title }) : t('Похоже на трек')
      }
    }
  }

  /** Строка под названием: откуда треки. */
  about(id: MixId): string {
    switch (id) {
      case 'daypart':
        return t('Что ты слушаешь в эти часы и твои лайки')
      case 'recent':
        return t('Последнее, что ты слушал')
      case 'new':
        return t('Исполнители в твоём вкусе, которых ты ещё не слушал')
      case 'fresh':
        return t('Малоизвестные исполнители рядом с твоим вкусом — по счётчику прослушиваний SoundCloud')
      case 'like': {
        const s = this.seed
        return s ? t('Похожее на «{title}» — {artist}', { title: s.title, artist: s.artist }) : t('Выбери трек — соберу похожее')
      }
    }
  }

  isLoading(id: MixId): boolean {
    if (id === 'daypart' || id === 'recent') return home.loading
    if (id === 'like') return this.likeLoading
    return this.loading
  }

  /** Подборки из сети: сегодняшний кэш — сразу, нет его — собираем; `force` — собрать заново. */
  async load(force = false) {
    const cache = force ? null : readCache(storageGet())
    if (cache) {
      this.day = cache.day
      this.newTracks = cache.new
      this.fresh = cache.fresh
      if (cache.seed) {
        this.like = cache.like
        this.likeFor = cache.seed
      }
    }
    if (!cache || !cache.new.length) await this.loadDiscover()
    await this.loadLike(force)
  }

  private async loadDiscover() {
    if (this.loading) return
    this.loading = true
    try {
      const { known, taste, seeds } = await gatherTaste()
      const [results, related] = await Promise.all([
        Promise.allSettled(seeds.map((ref) => api.similarTracks(ref, PER_SEED))),
        // соседи любимых по карте исполнителей — доп. сигнал: их треки выше
        relatedLookup(taste),
      ])
      const pools = results.flatMap((r) => (r.status === 'fulfilled' ? [r.value] : []))
      const exclude = new Set(seeds)
      this.newTracks = pickFromPools(pools, { known, taste, related, exclude })
      this.fresh = pickFromPools(pools, { known, taste, related, exclude, filter: (x) => isFresh(x) })
      this.day = dayKey()
      this.save()
    } catch {
      // нет сети или сервисов — карточки покажут подсказку
    } finally {
      this.loading = false
    }
  }

  /** «Похоже на трек»: тот же трек сегодня — не перезапрашиваем. */
  async loadLike(force = false) {
    const seed = this.seed
    if (!seed || this.likeLoading) return
    if (!force && this.likeFor === seed.ref && this.like.length) return
    this.likeLoading = true
    try {
      const list = await api.similarTracks(seed.ref, PER_SEED + 10)
      if (this.seed?.ref !== seed.ref) return
      this.like = limitPerArtist(dedupe(list.filter((x) => x.ref !== seed.ref)), MAX_PER_ARTIST_LOOSE)
      this.likeFor = seed.ref
      this.save()
    } catch {
      this.like = []
      this.likeFor = seed.ref
    } finally {
      this.likeLoading = false
    }
  }

  /** Выбор трека для «Похоже на трек» (запоминается в настройке) и пересборка. */
  async choose(track: Pick<Track, 'ref' | 'title' | 'artist' | 'cover_url'>) {
    settings.set('home.similar_seed', toSeed(track))
    this.like = []
    this.likeFor = null
    await this.loadLike()
  }

  private save() {
    storageSet({
      day: this.day || dayKey(),
      seed: this.likeFor,
      new: $state.snapshot(this.newTracks),
      fresh: $state.snapshot(this.fresh),
      like: $state.snapshot(this.like),
    })
  }
}

export const mixes = new Mixes()
