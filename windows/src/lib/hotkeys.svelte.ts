// Горячие клавиши по всей системе (Система → Горячие клавиши, hotkeys.rs): включены — сочетания из
// `hotkeys.map` регистрирует Rust; нажатие приходит событием `hotkey`, кроме «Показать / скрыть
// окно» — его Rust делает сам. Выключены — ни одно сочетание не занято.
import { untrack } from 'svelte'
import { api, onHotkey } from './api'
import { isTauri } from './tauri'
import { DEFAULTS, settings } from './settings.svelte'
import { library } from './library.svelte'
import { player } from '../player/player.svelte'
import { withCombo, withoutCombo } from './hotkeys-core'

export { comboFrom, comboLabel } from './hotkeys-core'

/** Действия по порядку строк в настройках (подписи по-русски — ключи перевода, `t()` при показе). */
export const HOTKEY_ACTIONS = [
  { id: 'toggle', title: 'Играть / пауза' },
  { id: 'next', title: 'Следующий трек' },
  { id: 'prev', title: 'Предыдущий трек' },
  { id: 'like', title: 'В Любимые / убрать' },
  { id: 'volume_up', title: 'Громче' },
  { id: 'volume_down', title: 'Тише' },
  { id: 'window', title: 'Показать / скрыть окно' },
] as const
export type HotkeyAction = (typeof HOTKEY_ACTIONS)[number]['id']

class Hotkeys {
  /** Действия, чьё сочетание не встало (занято другой программой). */
  failed = $state<string[]>([])
  /** Идёт запись нового сочетания — свои снимаем, чтобы нажатие не сработало как команда. */
  suspended = $state(false)
  private started = false

  init() {
    if (this.started || !isTauri) return
    this.started = true
    onHotkey((a) => this.run(a))
    $effect.root(() => {
      $effect(() => {
        if (!settings.loaded) return
        const on = settings.get('hotkeys.enabled') && !this.suspended
        const map = settings.get('hotkeys.map')
        untrack(() => void this.apply(on ? map : {}))
      })
    })
  }

  private async apply(map: Record<string, string>) {
    try {
      this.failed = await api.setHotkeys(map)
    } catch {
      this.failed = []
    }
  }

  run(action: string) {
    if (action === 'toggle') player.toggle()
    else if (action === 'next') void player.next()
    else if (action === 'prev') void player.prev()
    else if (action === 'like' && player.current) void library.toggleLike(player.current)
    else if (action === 'volume_up') player.setVolume(player.volume + 0.05)
    else if (action === 'volume_down') player.setVolume(player.volume - 0.05)
  }

  set(action: HotkeyAction, combo: string) {
    // то же сочетание у другого действия (или у быстрого окна) — снимаем там, чтобы не было двух на одно
    settings.set('hotkeys.map', withCombo(settings.get('hotkeys.map'), action, combo))
    if (combo && settings.get('hotkeys.quick') === combo) settings.set('hotkeys.quick', '')
  }

  /** «Вернуть по умолчанию»: сочетания команд — как с завода, кроме совпавшего с быстрым окном. */
  resetMap() {
    settings.set('hotkeys.map', withoutCombo(DEFAULTS['hotkeys.map'], settings.get('hotkeys.quick')))
  }

  /** Сочетание быстрого окна (Ctrl+K). Занято глобальным действием — там снимается. */
  setQuick(combo: string) {
    settings.set('hotkeys.quick', combo)
    if (combo) settings.set('hotkeys.map', withoutCombo(settings.get('hotkeys.map'), combo))
  }
}

export const hotkeys = new Hotkeys()
