<script lang="ts">
  // Кнопка-часы в плеере и меню «Скорость и тональность» (референс владельца 2026-11-16): готовые
  // x0.8 … x1.35 с бегающей капсулой, «барабаны» скорости и питча (Ruler) с −/значение/+, «Связать
  // скорость с питчем» (тогда питч двигает скорость: −2 st ≈ x0.89, лента доезжает плавно),
  // «Сохранять для след. треков», «Реверберация» и её сила 0–100 %, «Пространство» 1D…16D (`space.ts`). Что-то настроено — кнопка
  // подсвечена, на ней значение. Открывается и закрывается только кликом.
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import Switch from '../components/settings/Switch.svelte'
  import { pop, slide } from '../lib/motion'
  import { indicator } from '../lib/indicator'
  import Ruler from '../components/Ruler.svelte'
  import { t } from '../lib/i18n.svelte'
  import { PITCH_MAX, PITCH_MIN, SPEED_MAX, SPEED_MIN, SPEED_PRESETS, tempo } from './tempo.svelte'
  import { SPACE_PRESETS } from './space'

  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()
  /** Вверх не помещается (страница плеера — кнопка высоко) — открываемся вниз. */
  let down = $state(false)
  /** Сколько места до края окна со стороны, куда открываемся, — всплывашка не вылезает за окно. */
  let room = $state(600)

  /** Открываемся туда, где места больше (страница плеера — кнопка высоко, нижний плеер — низко). */
  function place() {
    if (!root) return
    const r = root.getBoundingClientRect()
    const above = r.top - 16
    const below = window.innerHeight - r.bottom - 16
    down = below > above
    room = Math.max(220, down ? below : above)
  }

  function toggle() {
    if (!open) place()
    open = !open
  }

  /** Открыть снаружи — клик по плашке «Свой звук» рядом с названием. */
  export function show() {
    if (open) return
    place()
    open = true
  }

  const fmtRate = (v: number) => `x${v.toFixed(2)}`
  const fmtPitch = (v: number) => `${v > 0 ? '+' : ''}${v.toFixed(1)}`

  onMount(() => {
    const outside = (e: MouseEvent) => {
      if (open && root && !root.contains(e.target as Node)) open = false
    }
    window.addEventListener('mousedown', outside, true)
    return () => window.removeEventListener('mousedown', outside, true)
  })
</script>

{#snippet drum(label: string, value: number, min: number, max: number, step: number, text: string, set: (v: number) => void, reset: number, major: number)}
  <div class="sl">
    <span class="sl-label">{label}</span>
    <Ruler {value} {min} {max} {step} {reset} {major} px={6} onchange={set} />
    <div class="sl-line">
      <button class="pm press" aria-label={t('{label}: меньше', { label })} onclick={() => set(value - step)}><Icon name="minus" size={15} /></button>
      {#key text}<span class="val">{text}</span>{/key}
      <button class="pm press" aria-label={t('{label}: больше', { label })} onclick={() => set(value + step)}><Icon name="plus" size={15} /></button>
    </div>
  </div>
{/snippet}

<div class="wrap" bind:this={root}>
  <button
    class="speed"
    class:active={tempo.active}
    class:mine={tempo.perTrack}
    class:open
    title={tempo.perTrack
      ? t('Свой звук трека: {rate}', { rate: fmtRate(tempo.rate) })
      : tempo.active
        ? t('Скорость и тональность: {rate}', { rate: fmtRate(tempo.rate) })
        : t('Скорость и тональность')}
    aria-label={t('Скорость и тональность')}
    aria-expanded={open}
    onclick={toggle}
  >
    {#key tempo.badge}
      <span class="face" class:badge={tempo.badge !== ''}>
        {#if tempo.badge}{tempo.badge}{:else}<Icon name="clock" size={17} />{/if}
      </span>
    {/key}
  </button>

  {#if open}
    <div class="pop" class:down style:max-height="{room}px" role="dialog" aria-label={t('Скорость и тональность')} in:pop={{ y: down ? -8 : 8 }} out:pop={{ y: down ? -8 : 8 }}>
      <div class="presets" use:indicator={{ key: tempo.rate, kind: 'pill' }}>
        {#each SPEED_PRESETS as p (p)}
          <button class:on={tempo.rate === p} onclick={() => tempo.setRate(p)}>x{p === 1 ? '1.0' : p}</button>
        {/each}
      </div>

      {@render drum(t('Скорость'), tempo.rate, SPEED_MIN, SPEED_MAX, 0.01, `x${tempo.rate.toFixed(2)}`, (v) => tempo.setRate(v), 1, 10)}
      {@render drum(t('Питч'), tempo.semitones, PITCH_MIN, PITCH_MAX, 0.1, `${fmtPitch(tempo.semitones)} st`, (v) => tempo.setPitch(v), 0, 10)}

      <div class="switches">
        <Switch
          title={t('Для этого трека')}
          hint={t('Скорость, тон, реверб, пространство и эквалайзер — только у этого трека и на всех твоих устройствах')}
          on={tempo.perTrack}
          disabled={!tempo.hasTrack}
          onchange={(v) => tempo.setPerTrack(v)}
        />
        <Switch title={t('Связать скорость с питчем')} hint={t('Режим винила / кассеты: скорость меняет высоту звука')} on={tempo.linked} onchange={(v) => tempo.setLinked(v)} />
        <Switch title={t('Сохранять для след. треков')} hint={t('Иначе новый трек играет в x1.0')} on={tempo.keep} onchange={(v) => tempo.setKeep(v)} />
        <Switch title={t('Реверберация ✦')} hint={t('Атмосферное пространство и объёмная глубина')} on={tempo.reverbOn} onchange={(v) => tempo.setReverbOn(v)} />
      </div>

      {#if tempo.reverbOn}
        <div class="rev" transition:slide={{ duration: 260 }}>
          {@render drum(t('Реверберация'), Math.round(tempo.reverb * 100), 0, 100, 1, `${Math.round(tempo.reverb * 100)}%`, (v) => tempo.setReverb(v / 100), 35, 10)}
        </div>
      {/if}

      <div class="switches">
        <Switch
          title={t('Пространство ✦')}
          hint={t('Звук плавно кружит вокруг головы. Чем больше D — тем шире, глубже и живее движение. Лучше в наушниках')}
          on={tempo.space > 0}
          onchange={(v) => tempo.setSpaceOn(v)}
        />
      </div>

      {#if tempo.space > 0}
        <div class="rev" transition:slide={{ duration: 260 }}>
          <div class="presets space" use:indicator={{ key: tempo.space, kind: 'pill' }} role="radiogroup" aria-label={t('Пространство')}>
            {#each SPACE_PRESETS as d (d)}
              <button class:on={tempo.space === d} role="radio" aria-checked={tempo.space === d} onclick={() => tempo.setSpace(d)}>{d}D</button>
            {/each}
          </div>
        </div>
      {/if}
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
    border-radius: 10px;
    color: var(--text-2);
    transition:
      color var(--normal) var(--ease),
      background var(--normal) var(--ease),
      box-shadow var(--normal) var(--ease);
  }
  .speed:hover,
  .speed.open {
    color: var(--text);
  }
  /* что-то настроено — кнопка мягко подсвечена, как эквалайзер */
  .speed.active {
    color: var(--text);
    background: color-mix(in srgb, var(--text) 14%, transparent);
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--text) 10%, transparent);
  }
  /* у трека свой звук — точка в углу, появляется пружиной */
  .speed {
    position: relative;
  }
  .speed.mine::after {
    content: '';
    position: absolute;
    top: 3px;
    right: 3px;
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--accent);
    animation: dot-in 260ms var(--ease);
  }
  @keyframes dot-in {
    from {
      transform: scale(0);
      opacity: 0;
    }
  }
  .face {
    display: inline-flex;
    animation: fade 180ms var(--ease);
  }
  .face.badge {
    font-size: calc(12px * var(--fs, 1));
    font-weight: 700;
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
    padding: 12px 14px 8px;
    border-radius: 20px;
    background: color-mix(in srgb, var(--surface-1) 92%, var(--tint));
    border: 1px solid var(--border-strong);
    box-shadow: 0 22px 50px -12px rgba(0, 0, 0, 0.7);
    transform-origin: bottom right;
    overflow-y: auto;
    scrollbar-width: thin;
  }
  .pop.down {
    top: calc(100% + 10px);
    bottom: auto;
    transform-origin: top right;
  }
  .presets {
    display: grid;
    grid-template-columns: repeat(6, 1fr);
    gap: 4px;
  }
  .presets :global(.tab-ind.pill) {
    border-radius: 9px;
    background: var(--text);
  }
  .presets button {
    height: 30px;
    border-radius: 9px;
    background: var(--plate);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    color: var(--text-2);
    transition: color var(--normal) var(--ease);
  }
  .presets button:hover {
    color: var(--text);
  }
  .presets button.on {
    background: transparent;
    color: var(--on-text);
  }
  .sl {
    padding-top: 12px;
  }
  .sl-label {
    display: block;
    margin-bottom: 4px;
    font-size: calc(14px * var(--fs, 1));
    font-weight: 700;
  }
  .sl-line {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    margin-top: 6px;
  }
  .val {
    min-width: 76px;
    padding: 5px 12px;
    border-radius: 9px;
    background: var(--plate);
    text-align: center;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    animation: fade 160ms var(--ease);
  }
  .pm {
    display: grid;
    place-items: center;
    width: 34px;
    height: 30px;
    border-radius: 9px;
    background: var(--plate);
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .pm:hover {
    background: var(--hover);
    color: var(--text);
  }
  .switches {
    margin-top: 10px;
  }
  .presets.space {
    margin: 4px 0 8px;
  }
  @media (prefers-reduced-motion: reduce) {
    .face,
    .val {
      animation: none;
    }
  }
</style>
