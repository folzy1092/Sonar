<script lang="ts">
  // Громкость: клик по значку открывает ползунок, следующий клик — закрывает. Наведение ничего
  // не открывает. Колесо мыши над значком или ползунком меняет громкость.
  import Icon from '../components/Icon.svelte'
  import { player } from './player.svelte'
  import { slide } from 'svelte/transition'
  import { reducedMotion } from '../lib/motion'

  let open = $state(false)
</script>

<div class="vol" onwheel={(e) => player.setVolume(player.volume + (e.deltaY < 0 ? 0.05 : -0.05))}>
  <button
    class="ico"
    class:open
    aria-label="Громкость"
    aria-expanded={open}
    title="Громкость {Math.round(player.volume * 100)}%"
    onclick={() => (open = !open)}
  >
    <Icon name={player.volume === 0 ? 'volumeOff' : 'volume'} size={17} />
  </button>
  {#if open}
    <input
      type="range"
      min="0"
      max="1"
      step="0.01"
      value={player.volume}
      aria-label="Громкость"
      style:--fill="{player.volume * 100}%"
      transition:slide={{ axis: 'x', duration: reducedMotion() ? 0 : 220 }}
      oninput={(e) => player.setVolume(Number(e.currentTarget.value))}
    />
  {/if}
</div>

<style>
  .vol {
    display: flex;
    align-items: center;
  }
  .ico {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    border-radius: 999px;
    color: var(--text-2);
    transition: color var(--fast) var(--ease);
  }
  .ico:hover,
  .ico.open {
    color: var(--text);
  }
  input {
    width: 88px;
    height: 3px;
    margin: 0 10px 0 4px;
    appearance: none;
    border-radius: 3px;
    background: linear-gradient(to right, var(--text) var(--fill), var(--surface-3) var(--fill));
    cursor: pointer;
  }
  input::-webkit-slider-thumb {
    appearance: none;
    width: 3px;
    height: 3px;
  }
</style>
