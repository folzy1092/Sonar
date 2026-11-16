<script lang="ts">
  // Ползунок времени: пока тянешь — двигается только он, перемотка — при отпускании.
  import { formatTime, player } from './player.svelte'

  interface Props {
    times?: boolean
  }
  let { times = true }: Props = $props()

  let dragging = $state(false)
  let dragMs = $state(0)
  const duration = $derived(player.durationMs || player.current?.duration_ms || 0)
  const shown = $derived(dragging ? dragMs : player.positionMs)
  let input: HTMLInputElement | undefined = $state()

  const paint = (ms: number) =>
    input?.style.setProperty('--fill', `${duration ? Math.min(100, (ms / duration) * 100) : 0}%`)

  // заливка едет каждый кадр по часам плеера; пока тянешь — стоит под пальцем
  $effect(() => {
    if (!input) return
    void duration
    return player.onFrame((ms) => !dragging && paint(ms))
  })
</script>

<div class="seek">
  {#if times}<span class="t">{formatTime(shown)}</span>{/if}
  <input
    type="range"
    min="0"
    max={duration || 1}
    step="250"
    value={shown}
    disabled={!player.current}
    aria-label="Позиция"
    bind:this={input}
    oninput={(e) => {
      dragging = true
      dragMs = Number(e.currentTarget.value)
      paint(dragMs)
    }}
    onchange={(e) => {
      dragging = false
      player.seek(Number(e.currentTarget.value))
    }}
  />
  {#if times}<span class="t">{formatTime(duration)}</span>{/if}
</div>

<style>
  .seek {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
  }
  .t {
    min-width: 38px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .t:last-child {
    text-align: right;
  }
  input {
    flex: 1;
    appearance: none;
    height: 4px;
    margin: 0;
    border-radius: 4px;
    background: linear-gradient(to right, var(--text) var(--fill), var(--surface-3) var(--fill));
    cursor: pointer;
  }
  input:disabled {
    cursor: default;
  }
  input::-webkit-slider-thumb {
    appearance: none;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: var(--text);
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .seek:hover input:not(:disabled)::-webkit-slider-thumb {
    opacity: 1;
  }
</style>
