// Меню трека (pc/Screenshot_29): открывается правым кликом по строке или кнопкой ⋮ — одно на окно.
import type { Track } from './api'

export interface MenuTarget {
  track: Track
  /** Когда трек добавлен (Любимые, плейлист) — строка «Добавлен …» в шапке. */
  addedAt?: number
  /** Свой плейлист, из которого открыли меню: появится «Убрать из плейлиста». */
  playlistId?: string
  itemId?: string
}

class TrackMenu {
  target = $state<MenuTarget | null>(null)
  x = $state(0)
  y = $state(0)

  open(target: MenuTarget, x: number, y: number) {
    this.target = target
    this.x = x
    this.y = y
  }

  /** Открыть под кнопкой (⋮). */
  openAt(target: MenuTarget, el: HTMLElement) {
    const r = el.getBoundingClientRect()
    this.open(target, r.right, r.bottom + 4)
  }

  close() {
    this.target = null
  }
}

export const trackMenu = new TrackMenu()
