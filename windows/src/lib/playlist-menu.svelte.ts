// Меню плейлиста — правый клик по плитке в медиатеке: плейлист сервиса (SoundCloud / Яндекс) или свой
// плейлист Sonar. Одно на окно, открывается и закрывается только кликом (правило владельца), как меню трека.
import type { Playlist, ServicePlaylist } from './api'

class PlaylistMenu {
  target = $state<ServicePlaylist | null>(null)
  /** Свой плейлист Sonar (тогда `target` пуст). */
  own = $state<Playlist | null>(null)
  x = $state(0)
  y = $state(0)

  open(p: ServicePlaylist, x: number, y: number) {
    this.own = null
    this.target = p
    this.x = x
    this.y = y
  }

  openOwn(p: Playlist, x: number, y: number) {
    this.target = null
    this.own = p
    this.x = x
    this.y = y
  }

  close() {
    this.target = null
    this.own = null
  }
}

export const playlistMenu = new PlaylistMenu()
