<script lang="ts">
  import Icon from './Icon.svelte'
  import type { IconName } from './icons'
  import { pulse as pulseOn } from '../lib/pulse'

  interface Props {
    icon: IconName
    label: string
    size?: number
    filled?: boolean
    active?: boolean
    disabled?: boolean
    /** «Пульс», когда становится true (лайк). */
    pulse?: boolean
    onclick?: () => void
  }

  let { icon, label, size = 20, filled = false, active = false, disabled = false, pulse, onclick }: Props = $props()
</script>

<button class="icon-btn" class:active aria-label={label} title={label} {disabled} {onclick}>
  <span class="ic" use:pulseOn={pulse}><Icon name={icon} {size} {filled} /></span>
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
      transform var(--fast) var(--ease);
  }
  .icon-btn:hover:not(:disabled) {
    color: var(--text);
    background: var(--hover);
  }
  .icon-btn:active:not(:disabled) {
    transform: scale(0.92);
  }
  .icon-btn.active {
    color: var(--accent);
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
