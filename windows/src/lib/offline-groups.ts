// Альбомы и исполнители в офлайне (`docs/OFFLINE.md` §6.3, этап 4): не каталог сервисов, а группы из того, что
// играет без сети. Открываются локальным списком треков (PlaylistPage, id `offline:<вид>:<ключ>`), без страницы в сети.
// Ключ — по именам в нижнем регистре: один и тот же альбом из SoundCloud и Яндекса — одна группа.

export type OfflineGroupKind = 'album' | 'artist'

interface GroupTrack {
  ref: string
  artist: string
  artists?: readonly { name: string; avatar_url?: string | null }[]
  album?: { title: string } | null
  cover_url?: string | null
}

export interface OfflineGroup<T> {
  kind: OfflineGroupKind
  key: string
  title: string
  /** Альбом — исполнитель; исполнитель — пусто. */
  subtitle: string
  cover: string | null
  tracks: T[]
}

const ID_PREFIX = 'offline:'

const norm = (s: string) => s.trim().toLowerCase()

/** Главный исполнитель трека: первый из `artists`, иначе строка `artist`. */
function mainArtist(t: GroupTrack): string {
  return (t.artists?.[0]?.name ?? t.artist).trim()
}

/** Исполнители трека по имени (без пустых и повторов). */
function trackArtists(t: GroupTrack): { name: string; avatar: string | null }[] {
  const list = t.artists?.length ? t.artists.map((a) => ({ name: a.name.trim(), avatar: a.avatar_url ?? null })) : [{ name: t.artist.trim(), avatar: null }]
  const named = list.filter((a) => a.name)
  return named.filter((a, i) => named.findIndex((b) => norm(b.name) === norm(a.name)) === i)
}

/** Больше треков — выше; поровну — по названию. */
function byWeight<T>(a: OfflineGroup<T>, b: OfflineGroup<T>): number {
  return b.tracks.length - a.tracks.length || a.title.localeCompare(b.title, 'ru')
}

/** Собрать группы: `keysOf` даёт треку ключи и подписи его групп (порядок треков внутри — как во входе). */
function collect<T extends GroupTrack>(
  kind: OfflineGroupKind,
  tracks: readonly T[],
  keysOf: (t: T) => { key: string; title: string; subtitle: string; cover: string | null }[],
): OfflineGroup<T>[] {
  const groups = new Map<string, OfflineGroup<T>>()
  for (const track of tracks) {
    for (const g of keysOf(track)) {
      const prev = groups.get(g.key)
      groups.set(
        g.key,
        prev
          ? { ...prev, cover: prev.cover ?? g.cover, tracks: [...prev.tracks, track] }
          : { kind, key: g.key, title: g.title, subtitle: g.subtitle, cover: g.cover, tracks: [track] },
      )
    }
  }
  return [...groups.values()].sort(byWeight)
}

/** Альбомы, у которых есть хоть один доступный трек. Трек без альбома ни в какой не попадает. */
export function groupAlbums<T extends GroupTrack>(tracks: readonly T[]): OfflineGroup<T>[] {
  return collect('album', tracks, (t) => {
    const title = t.album?.title.trim()
    if (!title) return []
    const artist = mainArtist(t)
    return [{ key: `${norm(artist)}|${norm(title)}`, title, subtitle: artist, cover: t.cover_url ?? null }]
  })
}

/** Исполнители доступных треков (у фита — у каждого свой). Картинка — аватар, иначе обложка трека. */
export function groupArtists<T extends GroupTrack>(tracks: readonly T[]): OfflineGroup<T>[] {
  return collect('artist', tracks, (t) =>
    trackArtists(t).map((a) => ({ key: norm(a.name), title: a.name, subtitle: '', cover: a.avatar ?? t.cover_url ?? null })),
  )
}

/** Адрес группы для PlaylistPage: `offline:album:<ключ>`. */
export function groupId(kind: OfflineGroupKind, key: string): string {
  return `${ID_PREFIX}${kind}:${key}`
}

/** Обратно из адреса; чужой адрес — null. */
export function parseGroupId(id: string): { kind: OfflineGroupKind; key: string } | null {
  if (!id.startsWith(ID_PREFIX)) return null
  const rest = id.slice(ID_PREFIX.length)
  const colon = rest.indexOf(':')
  const kind = rest.slice(0, colon)
  if (colon < 0 || (kind !== 'album' && kind !== 'artist')) return null
  return { kind, key: rest.slice(colon + 1) }
}

/** Группа по адресу среди доступных треков; её больше нет (трек вытеснен из кэша) — null. */
export function findGroup<T extends GroupTrack>(tracks: readonly T[], id: string): OfflineGroup<T> | null {
  const parsed = parseGroupId(id)
  if (!parsed) return null
  const groups = parsed.kind === 'album' ? groupAlbums(tracks) : groupArtists(tracks)
  return groups.find((g) => g.key === parsed.key) ?? null
}
