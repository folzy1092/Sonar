// Мини-окно (mini.rs): главное окно раздаёт состояние плеера событием `mini:state`, мини-окно шлёт
// команды `mini:cmd` (play / prev / next / like). Звук всегда в главном окне.
import { emit, listen } from '@tauri-apps/api/event'
import { invoke } from '@tauri-apps/api/core'
import { isTauri } from './tauri'
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

class Mini {
  /** Мини-окно открыто — кнопка в плеере подсвечена. */
  open = $state(false)
  private started = false

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
  }

  /** Главное окно: раздаёт состояние и слушает команды мини-окна. */
  start() {
    if (this.started || !isTauri) return
    this.started = true
    $effect.root(() => {
      $effect(() => {
        void [player.current?.ref, player.playing, library.liked]
        if (this.open) this.push()
      })
    })
    void listen('mini:hello', () => {
      this.open = true
      this.push()
    })
    void listen('mini:bye', () => (this.open = false))
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
