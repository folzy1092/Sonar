<script lang="ts">
  // Кнопка-часы слева от громкости (как в Dotify): клик по кругу 1× → Slowed 0.8× → Speed 1.25× → 1×.
  // Тон меняется вместе со скоростью. Включённый режим — слово вместо значка.
  import Icon from '../components/Icon.svelte'
  import { player, speedModes } from './player.svelte'

  const mode = $derived(speedModes[player.speedMode])

  function cycle() {
    player.setSpeedMode(player.speedMode === 'normal' ? 'slowed' : player.speedMode === 'slowed' ? 'speed' : 'normal')
  }
</script>

<button class="speed" class:on={player.speedMode !== 'normal'} title="Скорость: {mode.label} ({mode.rate}×)" aria-label="Скорость: {mode.label}" onclick={cycle}>
  {#key player.speedMode}
    <span class="face">
      {#if mode.badge}{mode.badge}{:else}<Icon name="clock" size={17} />{/if}
    </span>
  {/key}
</button>

<style>
  .speed {
    display: grid;
    place-items: center;
    min-width: 32px;
    height: 32px;
    padding: 0 6px;
    border-radius: 999px;
    color: var(--text-2);
    transition: color var(--fast) var(--ease);
  }
  .speed:hover {
    color: var(--text);
  }
  .face {
    display: inline-flex;
    animation: fade 140ms var(--ease);
  }
  .on .face {
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--surface-3);
    color: var(--text);
    font-size: 12px;
    font-weight: 600;
  }
  @keyframes fade {
    from {
      opacity: 0;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .face {
      animation: none;
    }
  }
</style>
