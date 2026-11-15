<script lang="ts">
  // Меню полноэкранного плеера по правому клику (как в Dotify, скрин владельца 2026-11-15):
  // размер текста A A A A · вид: обложка и текст / только обложка / только текст · Синхронизация,
  // Стиль текста, Анимация (клик — следующее значение) · Смещение ползунком · Перевести, Найти заново.
  // Закрывается только кликом мимо.
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { pop } from '../lib/motion'
  import type { IconName } from '../components/icons'
  import { toMs } from './core/offset'
  import {
    lyrics,
    lyricsAnimations,
    lyricsSizes,
    lyricsStyles,
    type LyricsViewMode,
  } from './lyrics.svelte'

  interface Props {
    x: number
    y: number
    onclose: () => void
  }
  let { x, y, onclose }: Props = $props()

  let el: HTMLDivElement | undefined = $state()
  let pos = $state({ left: 0, top: 0 })

  const views: { id: LyricsViewMode; icon: IconName; title: string }[] = [
    { id: 'both', icon: 'eye', title: 'Обложка и текст' },
    { id: 'cover', icon: 'eyeClosed', title: 'Только обложка' },
    { id: 'lyrics', icon: 'textLines', title: 'Только текст' },
  ]
  const sizeFont = { S: 10, M: 12, L: 14, XL: 17 } as const

  /** Ползунок смещения: ±2 с, точнее — колесом по 10 мс; двойной клик по значению — сброс. */
  const RANGE_MS = 2000
  const offsetMs = $derived(toMs(lyrics.offset))
  const offsetLabel = $derived(offsetMs === 0 ? '0' : `${offsetMs > 0 ? '+' : '−'}${Math.abs(offsetMs)} мс`)

  const hasText = $derived(lyrics.status === 'ready')

  // не вылезать за окно
  $effect(() => {
    if (!el) return
    const r = el.getBoundingClientRect()
    pos = {
      left: Math.max(8, Math.min(x, innerWidth - r.width - 8)),
      top: Math.max(8, Math.min(y, innerHeight - r.height - 8)),
    }
  })

  onMount(() => {
    const down = (e: MouseEvent) => {
      if (el && !el.contains(e.target as Node)) onclose()
    }
    const t = setTimeout(() => window.addEventListener('mousedown', down, true))
    return () => {
      clearTimeout(t)
      window.removeEventListener('mousedown', down, true)
    }
  })
</script>

<div
  class="menu"
  bind:this={el}
  style:left="{pos.left}px"
  style:top="{pos.top}px"
  role="menu"
  tabindex="-1"
  in:pop|global={{ y: -6, scale: 0.95, duration: 220 }}
  out:pop|global={{ y: -6, scale: 0.95, duration: 220 }}
  oncontextmenu={(e) => e.preventDefault()}
>
  <div class="row sizes" role="radiogroup" aria-label="Размер текста">
    {#each lyricsSizes as s (s)}
      <button
        class:on={lyrics.size === s}
        style:font-size="{sizeFont[s]}px"
        aria-label="Размер {s}"
        title="Размер {s}"
        onclick={() => lyrics.setSize(s)}>A</button
      >
    {/each}
  </div>

  <div class="row views" role="radiogroup" aria-label="Вид">
    {#each views as v (v.id)}
      <button class:on={lyrics.view === v.id} aria-label={v.title} title={v.title} onclick={() => lyrics.setView(v.id)}>
        <Icon name={v.icon} size={16} />
      </button>
    {/each}
  </div>

  <div class="list">
    <button
      class="item"
      disabled={!lyrics.hasWords}
      title={lyrics.hasWords ? '' : 'Для этого трека — только по строкам'}
      onclick={() => lyrics.setMode(lyrics.mode === 'words' ? 'lines' : 'words')}
    >
      <span>Синхронизация</span>
      <b>{lyrics.mode === 'words' && lyrics.hasWords ? 'По словам' : 'По строкам'}</b>
    </button>
    <button class="item" onclick={() => lyrics.cycleStyle()}>
      <span>Стиль текста</span>
      <b>{lyricsStyles[lyrics.style]}</b>
    </button>
    <button class="item" onclick={() => lyrics.cycleAnimation()}>
      <span>Анимация</span>
      <b>{lyricsAnimations[lyrics.animation]}</b>
    </button>

    <div class="offset">
      <div class="item static">
        <span>Смещение</span>
        <b
          role="button"
          tabindex="0"
          title="Двойной клик — сбросить"
          ondblclick={() => lyrics.setOffset(0)}
          onkeydown={(e) => e.key === 'Enter' && lyrics.setOffset(0)}>{offsetLabel}</b
        >
      </div>
      <input
        type="range"
        min={-RANGE_MS}
        max={RANGE_MS}
        step="10"
        value={offsetMs}
        disabled={!hasText}
        aria-label="Смещение текста, мс"
        style:--fill="{((offsetMs + RANGE_MS) / (2 * RANGE_MS)) * 100}%"
        oninput={(e) => lyrics.setOffset(Number(e.currentTarget.value) / 1000)}
        onwheel={(e) => {
          e.preventDefault()
          lyrics.setOffset((offsetMs + (e.deltaY < 0 ? 10 : -10)) / 1000)
        }}
      />
    </div>
  </div>

  <button class="wide" disabled title="Перевод — после MVP">
    <Icon name="language" size={14} /> Перевести
  </button>
  <button class="wide" onclick={() => lyrics.reload()} title="Искать текст заново, мимо кэша">
    <Icon name="refresh" size={14} /> Найти текст заново
  </button>
</div>

<style>
  .menu {
    position: fixed;
    z-index: 60;
    /* компактно, как у Dotify (~206 px) */
    width: 206px;
    padding: 8px;
    border-radius: 14px;
    background: rgba(44, 44, 48, 0.82);
    backdrop-filter: blur(28px) saturate(140%);
    border: 1px solid rgba(255, 255, 255, 0.08);
    box-shadow: 0 18px 48px -12px rgba(0, 0, 0, 0.6);
    color: #fff;
    font-family: var(--font);
    transform-origin: top left;
  }
  .row {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    align-items: center;
    padding: 2px 0 7px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  }
  .row.views {
    grid-template-columns: repeat(3, 1fr);
    padding-top: 7px;
  }
  .row button {
    display: grid;
    place-items: center;
    height: 28px;
    border-radius: 8px;
    color: rgba(255, 255, 255, 0.4);
    font-weight: 600;
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .row button:hover {
    color: rgba(255, 255, 255, 0.75);
    background: rgba(255, 255, 255, 0.06);
  }
  .row button.on {
    color: #fff;
  }
  .row button:active {
    transform: scale(0.92);
  }
  .list {
    padding: 6px 0 2px;
  }
  .item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    width: 100%;
    padding: 6px 5px;
    border-radius: 8px;
    font-size: 11px;
    text-align: left;
    transition: background var(--fast) var(--ease);
  }
  .item:hover:not(:disabled):not(.static) {
    background: rgba(255, 255, 255, 0.06);
  }
  .item span {
    color: rgba(255, 255, 255, 0.5);
  }
  .item b {
    font-weight: 600;
    color: #fff;
  }
  .item:disabled {
    cursor: default;
  }
  .item:disabled b {
    color: rgba(255, 255, 255, 0.6);
  }
  .offset .item {
    padding-bottom: 4px;
  }
  .offset b {
    cursor: pointer;
    font-variant-numeric: tabular-nums;
  }
  .offset input {
    width: calc(100% - 12px);
    margin: 6px 6px 10px;
    height: 4px;
    appearance: none;
    border-radius: 4px;
    background: linear-gradient(to right, #fff var(--fill), rgba(255, 255, 255, 0.2) var(--fill));
    cursor: pointer;
  }
  .offset input::-webkit-slider-thumb {
    appearance: none;
    width: 11px;
    height: 11px;
    border-radius: 50%;
    background: #fff;
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.4);
  }
  .offset input:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .wide {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    width: 100%;
    height: 32px;
    margin-top: 5px;
    border-radius: 9px;
    background: rgba(255, 255, 255, 0.08);
    font-size: 11px;
    font-weight: 500;
    color: #fff;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .wide:hover:not(:disabled) {
    background: rgba(255, 255, 255, 0.13);
  }
  .wide:active:not(:disabled) {
    transform: scale(0.97);
  }
  .wide:disabled {
    opacity: 0.45;
    cursor: default;
  }
</style>
