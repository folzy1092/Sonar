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
  /** Кнопка ⋮, которой открыли меню: повторный клик по ней меню закрывает. */
  anchor: HTMLElement | null = null
  /** С какого экрана меню открывается: кнопка «В плейлист» сразу показывает список плейлистов. */
  startView: 'main' | 'playlists' = 'main'

  open(target: MenuTarget, x: number, y: number, anchor: HTMLElement | null = null, view: 'main' | 'playlists' = 'main') {
    this.anchor = anchor
    this.startView = view
    this.target = target
    this.x = x
    this.y = y
  }

  /** Открыть под кнопкой (⋮). */
  openAt(target: MenuTarget, el: HTMLElement, view: 'main' | 'playlists' = 'main') {
    if (this.target && this.anchor === el) return this.close()
    const r = el.getBoundingClientRect()
    this.open(target, view === 'playlists' ? r.left : r.right, r.bottom + 4, el, view)
  }

  close() {
    this.target = null
    this.anchor = null
  }
}

export const trackMenu = new TrackMenu()
