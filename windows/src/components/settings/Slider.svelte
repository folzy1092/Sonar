<script lang="ts">
  // Ползунок настройки (pc/Screenshot_1 «Непрозрачность»): название, полоса, значение справа.
  import Soon from './Soon.svelte'
  interface Props {
    /** Есть на референсе, но ещё не работает. */
    soon?: boolean
    title: string
    hint?: string
    value: number
    min: number
    max: number
    step?: number
    unit?: string
    onchange: (v: number) => void
  }
  let { title, hint, value, min, max, step = 1, unit = '', onchange, soon = false }: Props = $props()
  let live = $state<number | null>(null)
  const shown = $derived(live ?? value)
</script>

<div class="row" class:soon>
  <b>{title}{#if soon}<Soon />{/if}</b>
  {#if hint}<small>{hint}</small>{/if}
  <div class="line">
    <input
      type="range"
      {min}
      {max}
      {step}
      value={shown}
      disabled={soon}
      style:--fill="{((shown - min) / (max - min)) * 100}%"
      oninput={(e) => (live = Number(e.currentTarget.value))}
      onchange={(e) => {
        onchange(Number(e.currentTarget.value))
        live = null
      }}
    />
    <span>{shown}{unit}</span>
  </div>
</div>

<style>
  .row.soon .line {
    opacity: 0.45;
  }
  input:disabled {
    cursor: default;
  }
  .row {
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 10px 0;
  }
  b {
    font-size: 14px;
    font-weight: 600;
  }
  small {
    font-size: 12px;
    color: var(--text-3);
  }
  .line {
    display: flex;
    align-items: center;
    gap: 14px;
    margin-top: 8px;
  }
  span {
    min-width: 44px;
    text-align: right;
    font-size: 12px;
    font-variant-numeric: tabular-nums;
    color: var(--text-2);
  }
  input {
    flex: 1;
    height: 5px;
    appearance: none;
    border-radius: 5px;
    background: linear-gradient(to right, var(--text) var(--fill), var(--surface-3) var(--fill));
    cursor: pointer;
  }
  input::-webkit-slider-thumb {
    appearance: none;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: var(--text);
    transition: transform var(--fast) var(--ease);
  }
  input:active::-webkit-slider-thumb {
    transform: scale(1.25);
  }
</style>
