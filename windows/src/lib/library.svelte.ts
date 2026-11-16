// Медиатека в памяти интерфейса: что лайкнуто и список плейлистов Sonar. Источник правды —
// локальная база (команды Rust); здесь — копия для сердечек и меню «Добавить в плейлист».
import { api, errorText, type Album, type Artist, type Playlist, type Track } from './api'
import { toast } from './toast.svelte'
import { t } from './i18n.svelte'
import { tracksText } from './format'

type Likeable = Track | Album | Artist

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
    } catch (e) {
      toast.show(errorText(e))
      await this.load(true)
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
