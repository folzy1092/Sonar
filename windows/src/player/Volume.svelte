<script lang="ts">
  // Громкость: клик по значку — без звука; наведение — выезжает ползунок; колесо мыши меняет.
  import Icon from '../components/Icon.svelte'
  import { player } from './player.svelte'

  const level = $derived(player.muted ? 0 : player.volume)

  function onWheel(e: WheelEvent) {
    player.setVolume(player.volume + (e.deltaY < 0 ? 0.05 : -0.05))
  }
</script>

<div class="vol" onwheel={onWheel}>
  <button class="ico" aria-label={player.muted ? 'Включить звук' : 'Без звука'} title="Громкость {Math.round(level * 100)}%" onclick={() => player.toggleMute()}>
    <Icon name={level === 0 ? 'volumeOff' : 'volume'} size={18} />
  </button>
  <input
    type="range"
    min="0"
    max="1"
    step="0.01"
    value={level}
    aria-label="Громкость"
    style:--fill="{level * 100}%"
    oninput={(e) => player.setVolume(Number(e.currentTarget.value))}
  />
</div>

<style>
  .vol {
    display: flex;
    align-items: center;
  }
  .ico {
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    border-radius: var(--radius-s);
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .ico:hover {
    color: var(--text);
    background: var(--hover);
  }
  input {
    width: 0;
    opacity: 0;
    margin: 0;
    transition:
      width var(--normal) var(--ease),
      opacity var(--normal) var(--ease),
      margin var(--normal) var(--ease);
  }
  .vol:hover input,
  input:focus-visible {
    width: 84px;
    opacity: 1;
    margin: 0 8px 0 4px;
  }
  input {
    appearance: none;
    height: 4px;
    border-radius: 4px;
    background: linear-gradient(to right, var(--text) var(--fill), var(--surface-3) var(--fill));
    cursor: pointer;
  }
  input::-webkit-slider-thumb {
    appearance: none;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: var(--text);
  }
</style>
