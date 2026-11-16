<script lang="ts">
  // Ползунок времени: пока тянешь — двигается только он, перемотка — при отпускании.
  import { formatTime, player } from './player.svelte'
  import { settings } from '../lib/settings.svelte'
  import { t } from '../lib/i18n.svelte'

  interface Props {
    times?: boolean
  }
  let { times = true }: Props = $props()

  let dragging = $state(false)
  let dragMs = $state(0)
  const duration = $derived(player.durationMs || player.current?.duration_ms || 0)
  const shown = $derived(dragging ? dragMs : player.positionMs)
  let input: HTMLInputElement | undefined = $state()
  let box: HTMLDivElement | undefined = $state()
  // Обычный ползунок рисуется по стилю (appearance.progress_look, Интерфейс → Стиль): line — линия 4 px
  // с кружком, wave — 46 столбиков формы звука (пройденное — акцентом), groove — утопленная дорожка 8 px
  // с заливкой акцентом и свечением. Другой вид в «Плеер → Вид» (тонкий, плавный, волнистый…) — главнее.
  const look = $derived(settings.get('appearance.progress_look'))
  const picked = $derived(settings.get('player.slider'))
  const style = $derived(picked !== 'normal' ? picked : look === 'wave' ? 'wave_bars' : look === 'groove' ? 'groove' : 'normal')
  const accentBars = $derived(picked === 'normal' && look === 'wave')
  // столбики «волнового» ползунка — постоянные для трека (из ref), чтобы не прыгали
  const bars = $derived.by(() => {
    let seed = 0
    for (const c of player.current?.ref ?? 'sonar') seed = (seed * 31 + c.charCodeAt(0)) >>> 0
    return Array.from({ length: accentBars ? 46 : 72 }, (_, i) => {
      seed = (seed * 1103515245 + 12345) >>> 0
      const r = (seed >>> 8) / 0xffffff
      return 25 + Math.round(70 * (0.35 + 0.65 * Math.abs(Math.sin(i * 0.37 + r * 3)) * (0.6 + 0.4 * r)))
    })
  })

  const paint = (ms: number) => {
    const v = `${duration ? Math.min(100, (ms / duration) * 100) : 0}%`
    input?.style.setProperty('--fill', v)
    box?.style.setProperty('--fill', v)
  }

  // заливка едет каждый кадр по часам плеера; пока тянешь — стоит под пальцем
  $effect(() => {
    if (!input) return
    void duration
    return player.onFrame((ms) => !dragging && paint(ms))
  })
</script>

<div class="seek s-{style}" class:accent-bars={accentBars} class:playing={player.playing}>
  {#if times}<span class="t">{formatTime(shown)}</span>{/if}
  <div class="track" bind:this={box}>
    {#if style === 'wavy'}
      <!-- пройденное — волна, которая бежит, пока играет; остальное — ровная линия -->
      <span class="wave-past"></span><span class="wave-rest"></span>
    {:else if style === 'groove'}
      <span class="groove"><span class="gfill"></span></span>
    {:else if style === 'wave_bars'}
      <span class="bars">{#each bars as h, i (i)}<i style:height="{h}%"></i>{/each}</span>
      <span class="bars past">{#each bars as h, i (i)}<i style:height="{h}%"></i>{/each}</span>
    {/if}
  <input
    type="range"
    min="0"
    max={duration || 1}
    step="250"
    value={shown}
    disabled={!player.current}
    aria-label={t('Позиция')}
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
  </div>
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
  .track {
    position: relative;
    flex: 1;
    display: flex;
    align-items: center;
    min-width: 0;
  }
  input {
    flex: 1;
    appearance: none;
    height: 4px;
    margin: 0;
    border-radius: 4px;
    background: linear-gradient(to right, var(--text) var(--fill), var(--surface-3) var(--fill));
    /* «Тактиль»: дорожка утоплена (palette.ts SURFACE_DECOR) */
    box-shadow: var(--well);
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
  /* Тонкий: волосок, ручка только при наведении */
  .s-thin input {
    height: 2px;
  }
  .s-thin:hover input {
    height: 3px;
  }
  /* Плавный: толстая мягкая полоса без ручки, светится заливка */
  .s-smooth input {
    height: 7px;
    border-radius: 7px;
    background: linear-gradient(to right, var(--text) calc(var(--fill) - 1px), color-mix(in srgb, var(--text) 14%, transparent) var(--fill));
    box-shadow: 0 0 12px color-mix(in srgb, var(--text) 18%, transparent);
  }
  .s-smooth input::-webkit-slider-thumb {
    width: 7px;
    height: 7px;
    opacity: 0 !important;
  }
  /* Волнистый и волновой: рисунок под прозрачным ползунком (ползунок ловит мышь) */
  .s-wavy input,
  .s-wave_bars input {
    position: relative;
    z-index: 1;
    height: 18px;
    background: transparent;
  }
  .wave-past,
  .wave-rest {
    position: absolute;
    top: 50%;
    height: 12px;
    translate: 0 -50%;
    pointer-events: none;
  }
  .wave-past {
    left: 0;
    width: var(--fill);
    background: var(--text);
    -webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='24' height='12'%3E%3Cpath d='M0 6 Q 6 0 12 6 T 24 6' fill='none' stroke='black' stroke-width='2.4' stroke-linecap='round'/%3E%3C/svg%3E") 0 50% / 24px 12px repeat-x;
    mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='24' height='12'%3E%3Cpath d='M0 6 Q 6 0 12 6 T 24 6' fill='none' stroke='black' stroke-width='2.4' stroke-linecap='round'/%3E%3C/svg%3E") 0 50% / 24px 12px repeat-x;
  }
  .playing .wave-past {
    animation: wave-run 1.1s linear infinite;
  }
  @keyframes wave-run {
    to {
      -webkit-mask-position: 24px 50%;
      mask-position: 24px 50%;
    }
  }
  .wave-rest {
    left: var(--fill);
    right: 0;
    height: 3px;
    border-radius: 3px;
    background: var(--surface-3);
  }
  .bars {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    gap: 2px;
    pointer-events: none;
  }
  .bars i {
    flex: 1;
    min-width: 1px;
    border-radius: 2px;
    background: var(--surface-3);
  }
  /* пройденные столбики — верхний светлый слой, обрезанный по прогрессу */
  .bars.past {
    clip-path: inset(0 calc(100% - var(--fill)) 0 0);
  }
  .bars.past i {
    background: var(--text);
  }
  .s-wave_bars .track {
    height: 22px;
  }
  /* «Сигнал»: пройденные столбики — акцентом */
  .accent-bars .bars.past i {
    background: var(--accent);
  }
  .accent-bars .bars {
    justify-content: space-between;
    gap: 0;
  }
  .accent-bars .bars i {
    flex: 0 0 3px;
  }
  /* «Тактиль»: утопленная дорожка 8 px, заливка акцентом со свечением */
  .s-groove input {
    position: relative;
    z-index: 1;
    height: 14px;
    background: transparent;
    box-shadow: none;
  }
  .groove {
    position: absolute;
    left: 0;
    right: 0;
    top: 50%;
    height: 8px;
    translate: 0 -50%;
    border-radius: 8px;
    background: color-mix(in oklch, var(--surface-1) 70%, #000);
    box-shadow: inset 0 2px 4px oklch(0 0 0 / 0.55);
    pointer-events: none;
  }
  .gfill {
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    width: var(--fill);
    border-radius: inherit;
    background: var(--accent);
    box-shadow: 0 0 10px color-mix(in oklch, var(--accent) 70%, transparent);
  }
  @media (prefers-reduced-motion: reduce) {
    .playing .wave-past {
      animation: none;
    }
  }
</style>
