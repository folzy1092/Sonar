// Горячие клавиши (Приложение → Клавиши, hotkeys.rs). Где действуют — `hotkeys.scope`:
// «В приложении» — только нажатия внутри окна (handleKey); «Поверх окон» — ещё и по всей системе, пока
// открыто мини-окно; «Везде» — всегда, даже из трея. По всей системе сочетания ставит Rust, нажатие
// приходит событием `hotkey`, кроме «Показать / скрыть окно» — его Rust делает сам. Поиск, текст,
// очередь и настройки — только внутри окна (можно голую клавишу, `/`).
import { untrack } from 'svelte'
import { api, onHotkey } from './api'
import { isTauri } from './tauri'
import { DEFAULTS, settings } from './settings.svelte'
import { library } from './library.svelte'
import { mini } from './mini.svelte'
import { player } from '../player/player.svelte'
import { wave } from '../player/my-wave.svelte'
import { lyrics } from '../lyrics/lyrics.svelte'
import { router } from '../app/router.svelte'
import { sidePane } from '../app/side-pane.svelte'
import { settingsPanel } from '../pages/settings-section.svelte'
import { actionFor, comboFrom, globalMap, hasCommandMod, withCombo, withoutCombo, type HotkeyAction } from './hotkeys-core'

export { comboFrom, comboLabel, HOTKEY_ACTIONS, isLocalAction, isOutsideAction, type HotkeyAction, type HotkeyScope } from './hotkeys-core'

const SEEK_STEP_MS = 5000
const VOLUME_STEP = 0.05

/** Сочетания с поправкой на действия, которых не было в сохранённой карте (новые — по умолчанию). */
export function effectiveMap(): Record<string, string> {
  return { ...DEFAULTS['hotkeys.map'], ...settings.get('hotkeys.map') }
}

/** Фокус в поле ввода — голые клавиши и Shift+… там печатают, а не командуют. */
function typing(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false
  return target.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)
}

class Hotkeys {
  /** Действия, чьё сочетание не встало (занято другой программой). */
  failed = $state<string[]>([])
  /** Идёт запись нового сочетания — свои снимаем, чтобы нажатие не сработало как команда. */
  suspended = $state(false)
  /** Что сейчас стоит по всей системе — внутри окна их не дублируем (Rust пришлёт сам). */
  private global = $state<Record<string, string>>({})
  /** Громкость до «Без звука» — второе нажатие её возвращает. */
  private unmuted: number | null = null
  private started = false

  init() {
    if (this.started || !isTauri) return
    this.started = true
    onHotkey((a) => this.run(a))
    $effect.root(() => {
      $effect(() => {
        if (!settings.loaded) return
        const map = this.suspended ? {} : globalMap(effectiveMap(), settings.get('hotkeys.scope'), mini.open || mini.overlayOpen)
        untrack(() => void this.apply(map))
      })
    })
  }

  private async apply(map: Record<string, string>) {
    this.global = map
    try {
      this.failed = await api.setHotkeys(map)
    } catch {
      this.failed = []
    }
  }

  /** Нажатие внутри окна (App.svelte). `true` — нажатие стало командой. */
  handleKey(e: KeyboardEvent): boolean {
    if (this.suspended || e.defaultPrevented || e.isComposing) return false
    const combo = comboFrom(e, true)
    if (!combo) return false
    if (typing(e.target) && !hasCommandMod(combo)) return false
    const action = actionFor(effectiveMap(), combo)
    if (!action || this.global[action] === combo) return false
    e.preventDefault()
    // зажатая клавиша повторяется: громкость и перемотку — пусть, остальное — один раз
    if (e.repeat && !['volume_up', 'volume_down', 'seek_back', 'seek_fwd'].includes(action)) return true
    this.run(action)
    return true
  }

  run(action: string) {
    switch (action) {
      case 'toggle':
        return player.toggle()
      case 'next':
        return void player.next()
      case 'prev':
        return void player.prev()
      case 'seek_back':
        return player.seek(Math.max(0, player.positionMs - SEEK_STEP_MS))
      case 'seek_fwd':
        return player.seek(player.positionMs + SEEK_STEP_MS)
      case 'volume_up':
        return player.setVolume(player.volume + VOLUME_STEP)
      case 'volume_down':
        return player.setVolume(player.volume - VOLUME_STEP)
      case 'mute':
        return this.toggleMute()
      case 'shuffle':
        return player.toggleShuffle()
      case 'repeat':
        return player.cycleRepeat()
      case 'like':
        return void (player.current && library.toggleLike(player.current))
      case 'search':
        return this.focusSearch()
      case 'lyrics':
      case 'queue':
        return sidePane.toggle(action, lyrics.status === 'ready')
      case 'settings':
        return settingsPanel.toggle()
      case 'wave':
        return void wave.toggle()
      case 'mini':
        return void mini.toggle()
      case 'overlay':
        return void mini.overlay()
    }
  }

  private toggleMute() {
    if (player.volume > 0) {
      this.unmuted = player.volume
      player.setVolume(0)
    } else player.setVolume(this.unmuted ?? 0.5)
  }

  private focusSearch() {
    if (router.page !== 'search') router.go('search')
    // строка поиска появляется вместе со страницей — ждём кадр
    requestAnimationFrame(() => document.querySelector<HTMLInputElement>('.bar .field input')?.focus())
  }

  set(action: HotkeyAction, combo: string) {
    // то же сочетание у другого действия (или у быстрого окна) — снимаем там, чтобы не было двух на одно
    settings.set('hotkeys.map', withCombo(effectiveMap(), action, combo))
    if (combo && settings.get('hotkeys.quick') === combo) settings.set('hotkeys.quick', '')
  }

  /** ↻ у строки: сочетание действия — как с завода (если его не занял кто-то ещё). */
  reset(action: HotkeyAction) {
    const combo = DEFAULTS['hotkeys.map'][action]
    const taken = combo && (settings.get('hotkeys.quick') === combo || Object.entries(effectiveMap()).some(([id, c]) => id !== action && c === combo))
    this.set(action, taken ? '' : combo)
  }

  /** «Вернуть по умолчанию»: сочетания команд — как с завода, кроме совпавшего с быстрым окном. */
  resetMap() {
    settings.set('hotkeys.map', withoutCombo(DEFAULTS['hotkeys.map'], settings.get('hotkeys.quick')))
  }

  /** Сочетание быстрого окна (Ctrl+K). Занято другим действием — там снимается. */
  setQuick(combo: string) {
    settings.set('hotkeys.quick', combo)
    if (combo) settings.set('hotkeys.map', withoutCombo(effectiveMap(), combo))
  }
}

export const hotkeys = new Hotkeys()
