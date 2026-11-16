// Меню плейлиста сервиса (SoundCloud / Яндекс) — правый клик по плитке в медиатеке. Одно на окно,
// открывается и закрывается только кликом (правило владельца), как меню трека.
import type { ServicePlaylist } from './api'

class PlaylistMenu {
  target = $state<ServicePlaylist | null>(null)
  x = $state(0)
  y = $state(0)

  open(p: ServicePlaylist, x: number, y: number) {
    this.target = p
    this.x = x
    this.y = y
  }

  close() {
    this.target = null
  }
}

export const playlistMenu = new PlaylistMenu()
