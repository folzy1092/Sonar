// Мини-окно и оверлей (mini.rs): главное окно раздаёт состояние плеера событием `mini:state`, плашки
// шлют команды `mini:cmd` (play / prev / next / like). Звук всегда в главном окне. Оверлею вдобавок
// уходит вид (`overlay:look`), а «Появляться само» следит, на экране ли Sonar (lib/overlay.ts).
import { emit, listen } from '@tauri-apps/api/event'
import { invoke } from '@tauri-apps/api/core'
import { getCurrentWindow } from '@tauri-apps/api/window'
import { isTauri } from './tauri'
import { settings } from './settings.svelte'
import { autoStep, overlayLayout, type OverlayLayout, type OverlayLook } from './overlay'
import { player } from '../player/player.svelte'
import { library } from './library.svelte'

export interface MiniState {
  title: string | null
  artist: string | null
  cover_url: string | null
  playing: boolean
  liked: boolean
  has: boolean
}

export type MiniCmd = 'toggle' | 'prev' | 'next' | 'like'

/** Как часто «Появляться само» проверяет, на экране ли окно Sonar, мс. */
const AUTO_CHECK_MS = 1000

class Mini {
  /** Мини-окно открыто — кнопка в плеере подсвечена. */
  open = $state(false)
  /** Оверлей открыт. */
  overlayOpen = $state(false)
  /** Оверлей открыл сам Sonar («Появляться само») — сам и закроет, когда окно вернётся. */
  private overlayAuto = false
  private started = false

  private layout(): OverlayLayout {
    const g = settings.get.bind(settings)
    return overlayLayout(g('overlay.mode'), g('overlay.width'), g('overlay.height'), g('overlay.scale'), g('overlay.position'))
  }

  private look(): OverlayLook {
    const g = settings.get.bind(settings)
    return { mode: g('overlay.mode'), shape: g('overlay.shape'), opacity: g('overlay.opacity'), scale: g('overlay.scale') }
  }

  /** Горячая клавиша и «Показать сейчас»: открыть / закрыть оверлей. В режиме «Отключен» не открывается. */
  async overlay(show = !this.overlayOpen, auto = false) {
    if (!isTauri || (show && settings.get('overlay.mode') === 'off')) return
    try {
      this.overlayOpen = await invoke<boolean>('overlay_window', { show, layout: this.layout() })
      this.overlayAuto = this.overlayOpen && auto
      if (this.overlayOpen) this.push()
    } catch {
      this.overlayOpen = false
      this.overlayAuto = false
    }
  }

  /** Кнопка в плеере: открыть / закрыть. */
  async toggle() {
    if (!isTauri) return
    try {
      this.open = await invoke<boolean>('mini_window', { show: !this.open })
      if (this.open) this.push()
    } catch {
      this.open = false
    }
  }

  private state(): MiniState {
    const t = player.current
    return {
      title: t?.title ?? null,
      artist: t?.artist ?? null,
      cover_url: t?.cover_url ?? null,
      playing: player.playing,
      liked: library.isLiked(t?.ref),
      has: !!t,
    }
  }

  private push() {
    void emit('mini:state', this.state()).catch(() => {})
    if (this.overlayOpen) void emit('overlay:look', this.look()).catch(() => {})
  }

  /** «Появляться само»: окно Sonar свернули или спрятали в трей — открыть, вернули — закрыть. */
  private async autoCheck() {
    const g = settings.get.bind(settings)
    if (!g('overlay.auto') && !this.overlayAuto) return
    const w = getCurrentWindow()
    const mainShown = (await w.isVisible()) && !(await w.isMinimized())
    const step = autoStep({
      auto: g('overlay.auto'),
      mode: g('overlay.mode'),
      mainShown,
      miniOpen: this.open,
      overlayOpen: this.overlayOpen,
      openedByAuto: this.overlayAuto,
    })
    if (step) await this.overlay(step === 'open', true)
  }

  /** Главное окно: раздаёт состояние и слушает команды мини-окна. */
  start() {
    if (this.started || !isTauri) return
    this.started = true
    $effect.root(() => {
      $effect(() => {
        void [player.current?.ref, player.playing, library.liked]
        if (this.open || this.overlayOpen) this.push()
      })
      // поменяли оверлей в настройках, пока он на экране, — переставить и перерисовать сразу
      $effect(() => {
        const layout = this.layout()
        const look = this.look()
        if (!this.overlayOpen) return
        if (look.mode === 'off') return void this.overlay(false)
        void invoke('overlay_window', { show: true, layout }).catch(() => {})
        void emit('overlay:look', look).catch(() => {})
      })
    })
    setInterval(() => void this.autoCheck().catch(() => {}), AUTO_CHECK_MS)
    void listen('overlay:hello', () => {
      this.overlayOpen = true
      this.push()
    })
    void listen('overlay:bye', () => {
      this.overlayOpen = false
      this.overlayAuto = false
      void invoke('overlay_window', { show: false }).catch(() => {})
    })
    void listen('mini:hello', () => {
      this.open = true
      this.push()
    })
    // плашка закрывается — главное окно само добивает её через Rust (на случай, если её страница
    // зависла и закрыться сама не может)
    void listen('mini:bye', () => {
      this.open = false
      void invoke('mini_window', { show: false }).catch(() => {})
    })
    void listen<MiniCmd>('mini:cmd', (e) => {
      const t = player.current
      if (e.payload === 'toggle') player.toggle()
      else if (e.payload === 'next') void player.next()
      else if (e.payload === 'prev') void player.prev()
      else if (e.payload === 'like' && t) void library.toggleLike(t)
    })
  }
}

export const mini = new Mini()
