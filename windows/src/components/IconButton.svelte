<script lang="ts">
  import Icon from './Icon.svelte'
  import type { IconName } from './icons'
  import { pulse as pulseOn } from '../lib/pulse'
  import { togglePop } from '../lib/toggle-pop'

  interface Props {
    icon: IconName
    label: string
    size?: number
    filled?: boolean
    active?: boolean
    disabled?: boolean
    /** «Пульс», когда становится true (лайк). */
    pulse?: boolean
    /** Переключатель (повтор, перемешивание): вкл — акцент, кружок-подложка и точка под значком. */
    toggle?: boolean
    onclick?: () => void
  }

  let { icon, label, size = 20, filled = false, active = false, disabled = false, pulse, toggle = false, onclick }: Props = $props()
</script>

<button
  class="icon-btn"
  class:active
  class:toggle
  class:bare={icon === 'heart' || toggle}
  aria-label={label}
  aria-pressed={toggle ? active : undefined}
  title={label}
  {disabled}
  {onclick}
>
  <span class="ic" use:pulseOn={pulse} use:togglePop={toggle ? `${icon}:${active}` : ''}><Icon name={icon} {size} {filled} /></span>
</button>

<style>
  .icon-btn {
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    border-radius: var(--radius-s);
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease),
      box-shadow var(--fast) var(--ease),
      translate var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .icon-btn:hover:not(:disabled) {
    color: var(--text);
  }
  .icon-btn:hover:not(:disabled):not(.bare) {
    background: var(--hover);
  }
  /* «Тактиль»: кнопки выпуклые, при нажатии уходят на 2 px вниз (palette.ts SURFACE_DECOR) */
  .icon-btn:not(.bare) {
    box-shadow: var(--key);
  }
  .icon-btn:active:not(:disabled):not(.bare) {
    box-shadow: var(--key-down);
    translate: 0 var(--key-shift);
  }
  /* лайк (.bare) — без подложки: наведение показывает само сердечко (app.css, «Лайк: наведение») */
  .icon-btn:active:not(:disabled):not(.bare) {
    transform: scale(0.92);
  }
  .icon-btn.active {
    color: var(--accent);
  }
  /* Переключатель (docs/POLISH_PROMPT.md п. 5; без кружка — просьба владельца 2026-11-21): выкл — серый
     значок; вкл — значок акцентом и точка 4 px под ним. Подложки нет ни при наведении, ни при нажатии
     (.toggle входит в .bare), значок — .toggle-pop (app.css). */
  .icon-btn.toggle {
    position: relative;
  }
  .icon-btn.toggle.active:hover:not(:disabled) {
    color: var(--accent);
  }
  .icon-btn.toggle::after {
    content: '';
    position: absolute;
    left: 50%;
    bottom: 2px;
    width: 4px;
    height: 4px;
    margin-left: -2px;
    border-radius: 50%;
    background: var(--accent);
    opacity: 0;
    transform: scale(0.4);
    transition:
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .icon-btn.toggle.active::after {
    opacity: 1;
    transform: none;
  }
  .ic {
    display: grid;
    place-items: center;
  }
  .icon-btn:disabled {
    opacity: 0.35;
    cursor: default;
  }
</style>
