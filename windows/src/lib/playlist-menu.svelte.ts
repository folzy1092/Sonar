// Меню плейлиста — правый клик по плитке в медиатеке: плейлист сервиса (SoundCloud / Яндекс) или свой
// плейлист Sonar. Одно на окно, открывается и закрывается только кликом (правило владельца), как меню трека.
import type { Playlist, ServicePlaylist } from './api'

class PlaylistMenu {
  target = $state<ServicePlaylist | null>(null)
  /** Любимые (тогда `target` и `own` пусты). */
  fav = $state(false)
  /** Свой плейлист Sonar (тогда `target` пуст). */
  own = $state<Playlist | null>(null)
  x = $state(0)
  y = $state(0)

  open(p: ServicePlaylist, x: number, y: number) {
    this.fav = false
    this.own = null
    this.target = p
    this.x = x
    this.y = y
  }

  openOwn(p: Playlist, x: number, y: number) {
    this.fav = false
    this.target = null
    this.own = p
    this.x = x
    this.y = y
  }

  openFav(x: number, y: number) {
    this.target = null
    this.own = null
    this.fav = true
    this.x = x
    this.y = y
  }

  close() {
    this.fav = false
    this.target = null
    this.own = null
  }
}

export const playlistMenu = new PlaylistMenu()
