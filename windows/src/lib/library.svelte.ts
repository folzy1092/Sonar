// Медиатека в памяти интерфейса: что лайкнуто и список плейлистов Sonar. Источник правды —
// локальная база (команды Rust); здесь — копия для сердечек и меню «Добавить в плейлист».
import { api, errorText, type Album, type Artist, type DupeListId, type Playlist, type RemovedDupes, type Track } from './api'
import { toast } from './toast.svelte'
import { downloads } from './downloads.svelte'
import { t } from './i18n.svelte'
import { tracksText } from './format'

type Likeable = Track | Album | Artist

/** Сколько висит тост «Убрано … · Отменить» после чистки дублей. */
const UNDO_MS = 8000

class Library {
  liked = $state(new Set<string>())
  playlists = $state<Playlist[]>([])
  /** Меняется после каждой правки — страницы медиатеки перезагружают данные. */
  version = $state(0)
  private loaded = false

  async load(force = false) {
    if (this.loaded && !force) return
    this.loaded = true
    try {
      const [liked, playlists] = await Promise.all([api.likedRefs(), api.playlists()])
      this.liked = new Set(liked)
      this.playlists = playlists
    } catch {
      this.loaded = false // вне приложения — пусто
    }
  }

  isLiked(ref: string | null | undefined) {
    return !!ref && this.liked.has(ref)
  }

  async toggleLike(item: Likeable) {
    const on = !this.liked.has(item.ref)
    const next = new Set(this.liked)
    if (on) next.add(item.ref)
    else next.delete(item.ref)
    this.liked = next
    try {
      await api.setLike(item.ref, on, on ? item : undefined)
      this.version++
      if (on) void downloads.fillLiked(item.ref)
    } catch (e) {
      toast.show(errorText(e))
      await this.load(true)
    }
  }

  /** Лайкнуть все треки разом (меню плейлиста Sonar); вернёт, сколько добавилось в Любимые. */
  async likeAll(tracks: Track[]) {
    const fresh = tracks.filter((x, i) => !this.liked.has(x.ref) && tracks.findIndex((y) => y.ref === x.ref) === i)
    if (!fresh.length) return 0
    const next = new Set(this.liked)
    for (const x of fresh) next.add(x.ref)
    this.liked = next
    try {
      // с конца: в Любимых новые сверху, так верх плейлиста и окажется сверху, а его низ — снизу
      for (const x of [...fresh].reverse()) await api.setLike(x.ref, true, x)
    } catch (e) {
      toast.show(errorText(e))
      await this.load(true)
    }
    this.version++
    void downloads.fillLiked()
    return fresh.length
  }

  /** Снять все лайки треков (после двойного подтверждения в меню Любимых). */
  async clearFavorites() {
    try {
      const n = await api.clearFavorites()
      await this.load(true)
      this.version++
      toast.show(n ? t('Любимые очищены — убрано {tracks}', { tracks: tracksText(n) }) : t('В Любимых и так пусто'))
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  async refreshPlaylists() {
    try {
      this.playlists = await api.playlists()
      this.version++
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  async createPlaylist(name: string, tracks: Track[] = []) {
    try {
      const p = await api.createPlaylist(name, tracks)
      await this.refreshPlaylists()
      toast.show(t('Плейлист «{name}» создан', { name: p.name }))
      return p
    } catch (e) {
      toast.show(errorText(e))
      return null
    }
  }

  async addToPlaylist(p: Playlist, tracks: Track[]) {
    try {
      const pos = (await api.getSetting<'start' | 'end'>('general.add_position').catch(() => null)) ?? 'start'
      await api.addToPlaylist(p.id, tracks, pos)
      await this.refreshPlaylists()
      toast.show(
        tracks.length === 1
          ? t('Добавлено в «{name}»', { name: p.name })
          : t('{tracks} добавлено в «{name}»', { tracks: tracksText(tracks.length), name: p.name }),
      )
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  /** «Убрать отмеченные» на экране дублей — одна правка, в тосте «Отменить». */
  async removeDuplicates(list: DupeListId, itemIds: string[]) {
    try {
      const removed = await api.removeDuplicates(list, itemIds)
      await this.afterBulkEdit()
      const n = removed.items.length
      if (!n) return toast.show(t('Нечего убирать — список уже поменялся'))
      toast.show(t('Убрано {tracks}', { tracks: tracksText(n) }), UNDO_MS, {
        label: t('Отменить'),
        run: () => this.restoreDuplicates(removed),
      })
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  async restoreDuplicates(removed: RemovedDupes) {
    try {
      const n = await api.restoreDuplicates(removed)
      await this.afterBulkEdit()
      toast.show(n ? t('Вернул {tracks}', { tracks: tracksText(n) }) : t('Нечего возвращать'))
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  /** После правки сразу многих строк: сердечки, счётчики плейлистов и открытые страницы. */
  private async afterBulkEdit() {
    await this.load(true)
    this.version++
  }

  async removeFromPlaylist(id: string, itemIds: string[]) {
    try {
      await api.removeFromPlaylist(id, itemIds)
      await this.refreshPlaylists()
    } catch (e) {
      toast.show(errorText(e))
    }
  }
}

export const library = new Library()
