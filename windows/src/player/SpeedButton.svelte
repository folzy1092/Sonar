<script lang="ts">
  // Кнопка-часы у громкости и меню скорости (решение владельца 2026-11-16): сверху готовые значения
  // ×0.8 … ×1.35, ниже ползунки скорости и тона с «−» и «+» по краям (шаг 0.01× и 0.1 полутона),
  // «Связать тон со скоростью», «Сохранять между треками», реверб 0–100 %. Открывается и
  // закрывается только кликом. Включено что-то — на кнопке значение вместо значка.
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import Switch from '../components/settings/Switch.svelte'
  import { pop } from '../lib/motion'
  import { cascade } from '../lib/cascade'
  import { PITCH_MAX, PITCH_MIN, SPEED_MAX, SPEED_MIN, SPEED_PRESETS, tempo } from './tempo.svelte'

  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()
  /** Вверх не помещается (страница плеера — кнопка высоко) — открываемся вниз. */
  let down = $state(false)

  function toggle() {
    if (!open && root) down = root.getBoundingClientRect().top < 470
    open = !open
  }

  const active = $derived(tempo.badge !== '')
  const fmtRate = (v: number) => `${v.toFixed(2).replace(/0$/, '')}×`
  const fmtPitch = (v: number) => `${v > 0 ? '+' : ''}${v.toFixed(1)}`

  onMount(() => {
    const outside = (e: MouseEvent) => {
      if (open && root && !root.contains(e.target as Node)) open = false
    }
    window.addEventListener('mousedown', outside, true)
    return () => window.removeEventListener('mousedown', outside, true)
  })
</script>

{#snippet slider(label: string, value: number, min: number, max: number, step: number, text: string, set: (v: number) => void, disabled = false)}
  <div class="sl" class:dim={disabled}>
    <div class="sl-head">
      <span>{label}</span>
      <b>{text}</b>
    </div>
    <div class="sl-line">
      <button class="pm press" aria-label="{label}: меньше" {disabled} onclick={() => set(value - step)}><Icon name="minus" size={14} /></button>
      <input
        type="range"
        {min}
        {max}
        step={step}
        {value}
        {disabled}
        aria-label={label}
        style:--fill="{((value - min) / (max - min)) * 100}%"
        oninput={(e) => set(Number(e.currentTarget.value))}
        ondblclick={() => set(min < 0 ? 0 : 1)}
      />
      <button class="pm press" aria-label="{label}: больше" {disabled} onclick={() => set(value + step)}><Icon name="plus" size={14} /></button>
    </div>
  </div>
{/snippet}

<div class="wrap" bind:this={root}>
  <button
    class="speed"
    class:on={active || open}
    title="Скорость и тон"
    aria-label="Скорость и тон"
    aria-expanded={open}
    onclick={toggle}
  >
    {#key tempo.badge}
      <span class="face" class:badge={active}>
        {#if active}{tempo.badge}{:else}<Icon name="clock" size={17} />{/if}
      </span>
    {/key}
  </button>

  {#if open}
    <div class="pop" class:down role="dialog" aria-label="Скорость и тон" in:pop={{ y: down ? -8 : 8 }} out:pop={{ y: down ? -8 : 8 }}>
      <div class="head">
        <b>Скорость</b>
        <button class="reset" disabled={!active} onclick={() => tempo.reset()}>Сбросить</button>
      </div>
      <div class="presets" use:cascade>
        {#each SPEED_PRESETS as p (p)}
          <button class="chip press" class:on={tempo.rate === p} onclick={() => tempo.setRate(p)}>×{p}</button>
        {/each}
      </div>

      {@render slider('Скорость', tempo.rate, SPEED_MIN, SPEED_MAX, 0.01, fmtRate(tempo.rate), (v) => tempo.setRate(v))}
      {@render slider(
        'Тон',
        tempo.semitones,
        PITCH_MIN,
        PITCH_MAX,
        0.1,
        `${fmtPitch(tempo.semitones)} пт`,
        (v) => tempo.setPitch(v),
        tempo.linked,
      )}

      <div class="switches">
        <Switch title="Связать тон со скоростью" hint="Как slowed и sped up: медленнее — ниже" on={tempo.linked} onchange={(v) => tempo.setLinked(v)} />
        <Switch title="Сохранять между треками" hint="Иначе новый трек играет в 1×" on={tempo.keep} onchange={(v) => tempo.setKeep(v)} />
      </div>

      {@render slider('Реверб', Math.round(tempo.reverb * 100), 0, 100, 1, `${Math.round(tempo.reverb * 100)}%`, (v) => tempo.setReverb(v / 100))}
    </div>
  {/if}
</div>

<style>
  .wrap {
    position: relative;
  }
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
  .speed:hover,
  .speed.on {
    color: var(--text);
  }
  .face {
    display: inline-flex;
    animation: fade 160ms var(--ease);
  }
  .face.badge {
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--surface-3);
    color: var(--text);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
  @keyframes fade {
    from {
      opacity: 0;
      scale: 0.8;
    }
  }
  .pop {
    position: absolute;
    right: -8px;
    bottom: calc(100% + 10px);
    z-index: 20;
    width: 320px;
    padding: 14px 14px 6px;
    border-radius: 18px;
    background: var(--surface-1);
    border: 1px solid var(--border-strong);
    box-shadow: 0 18px 44px -12px rgba(0, 0, 0, 0.7);
    transform-origin: bottom right;
  }
  .pop.down {
    top: calc(100% + 10px);
    bottom: auto;
    transform-origin: top right;
  }
  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 10px;
  }
  .head b {
    font-size: calc(14px * var(--fs, 1));
  }
  .reset {
    padding: 3px 8px;
    border-radius: 8px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease),
      opacity var(--fast) var(--ease);
  }
  .reset:hover:not(:disabled) {
    color: var(--text);
    background: var(--hover);
  }
  .reset:disabled {
    opacity: 0.35;
    cursor: default;
  }
  .presets {
    display: grid;
    grid-template-columns: repeat(6, 1fr);
    gap: 4px;
  }
  .chip {
    height: 30px;
    border-radius: 10px;
    background: var(--plate);
    border: 1px solid var(--border);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      border-color var(--fast) var(--ease);
  }
  .chip:hover {
    color: var(--text);
    background: var(--hover);
  }
  .chip.on {
    background: var(--text);
    border-color: var(--text);
    color: var(--on-text);
  }
  .sl {
    padding: 10px 0 4px;
    transition: opacity var(--normal) var(--ease);
  }
  .sl.dim {
    opacity: 0.45;
  }
  .sl-head {
    display: flex;
    justify-content: space-between;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
  }
  .sl-head b {
    color: var(--text);
    font-variant-numeric: tabular-nums;
  }
  .sl-line {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 6px;
  }
  .pm {
    display: grid;
    place-items: center;
    flex: none;
    width: 26px;
    height: 26px;
    border-radius: 8px;
    background: var(--plate);
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .pm:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  .pm:disabled {
    cursor: default;
  }
  input {
    flex: 1;
    height: 5px;
    appearance: none;
    border-radius: 5px;
    background: linear-gradient(to right, var(--text) var(--fill), var(--surface-3) var(--fill));
    cursor: pointer;
  }
  input:disabled {
    cursor: default;
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
  .switches {
    margin-top: 4px;
    border-top: 1px solid var(--border);
    border-bottom: 1px solid var(--border);
  }
  @media (prefers-reduced-motion: reduce) {
    .face {
      animation: none;
    }
  }
</style>
