<script lang="ts">
  // Меню текста (mobile/photo_6, PLATFORMS.md): По словам / По строкам · размер S/M/L/XL по кругу ·
  // Стиль текста › · Анимация › · сдвиг тайминга на трек · Перевод (после MVP).
  // Открывается правым кликом по тексту или кнопкой, закрывается только кликом.
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { formatOffset } from './core/offset'
  import {
    lyrics,
    lyricsAnimations,
    lyricsStyles,
    type LyricsAnimation,
    type LyricsStyle,
  } from './lyrics.svelte'

  interface Props {
    x: number
    y: number
    onclose: () => void
  }
  let { x, y, onclose }: Props = $props()

  let view = $state<'main' | 'style' | 'animation'>('main')
  let el: HTMLDivElement | undefined = $state()
  let pos = $state({ left: 0, top: 0 })

  const steps = [-0.1, -0.01, 0.01, 0.1]
  const stepLabel = (s: number) => `${s > 0 ? '+' : '−'}${Math.abs(s)}`

  // не вылезать за окно
  $effect(() => {
    view
    if (!el) return
    const r = el.getBoundingClientRect()
    pos = {
      left: Math.max(8, Math.min(x, innerWidth - r.width - 8)),
      top: Math.max(8, Math.min(y, innerHeight - r.height - 8)),
    }
  })

  onMount(() => {
    // клик мимо меню — закрыть (наведение и Esc ничего не делают — правило владельца)
    const down = (e: MouseEvent) => {
      const target = e.target as HTMLElement
      // кнопка, которая открыла меню, сама его и закроет
      if (target.closest?.('[data-lyrics-menu-toggle]')) return
      if (el && !el.contains(target)) onclose()
    }
    const t = setTimeout(() => window.addEventListener('mousedown', down, true))
    return () => {
      clearTimeout(t)
      window.removeEventListener('mousedown', down, true)
    }
  })
</script>

<div class="menu" bind:this={el} style:left="{pos.left}px" style:top="{pos.top}px" role="menu" tabindex="-1">
  {#if view === 'main'}
    <div class="row">
      <div class="seg" role="radiogroup" aria-label="Подсветка">
        <button
          class:on={lyrics.mode === 'words'}
          disabled={!lyrics.hasWords}
          title={lyrics.hasWords ? 'Подсветка по словам' : 'Для этого трека — только по строкам'}
          onclick={() => lyrics.setMode('words')}>По словам</button
        >
        <button class:on={lyrics.mode === 'lines' || !lyrics.hasWords} onclick={() => lyrics.setMode('lines')}>По строкам</button>
      </div>
      <button class="size" title="Размер текста" onclick={() => lyrics.cycleSize()}>{lyrics.size}</button>
    </div>

    <button class="item" onclick={() => (view = 'style')}>
      <span><b>Стиль текста</b><small>{lyricsStyles[lyrics.style]}</small></span>
      <Icon name="chevronRight" size={16} />
    </button>
    <button class="item" onclick={() => (view = 'animation')}>
      <span><b>Анимация</b><small>{lyricsAnimations[lyrics.animation]}</small></span>
      <Icon name="chevronRight" size={16} />
    </button>

    <div class="offset" aria-label="Сдвиг текста для этого трека">
      <div class="steps">
        {#each steps as s (s)}
          <button onclick={() => lyrics.setOffset(lyrics.offset + s)} title="{stepLabel(s)} с">{stepLabel(s)}</button>
        {/each}
      </div>
      <button class="value" title="Сбросить сдвиг" disabled={!lyrics.offset} onclick={() => lyrics.setOffset(0)}>
        {formatOffset(lyrics.offset)}
      </button>
    </div>

    <div class="foot">
      <button class="wide" onclick={() => lyrics.reload()} title="Искать текст заново, мимо кэша">
        <Icon name="refresh" size={16} /> Найти заново
      </button>
      <button class="wide" disabled title="Перевод — после MVP">
        <Icon name="language" size={16} /> Перевод
      </button>
    </div>
  {:else}
    <button class="back" onclick={() => (view = 'main')}>
      <Icon name="chevronLeft" size={16} />
      {view === 'style' ? 'Стиль текста' : 'Анимация'}
    </button>
    {#if view === 'style'}
      {#each Object.entries(lyricsStyles) as [key, label] (key)}
        <button class="opt" class:on={lyrics.style === key} onclick={() => lyrics.setStyle(key as LyricsStyle)}>
          {label}
          {#if lyrics.style === key}<Icon name="check" size={16} />{/if}
        </button>
      {/each}
    {:else}
      {#each Object.entries(lyricsAnimations) as [key, label] (key)}
        <button class="opt" class:on={lyrics.animation === key} onclick={() => lyrics.setAnimation(key as LyricsAnimation)}>
          {label}
          {#if lyrics.animation === key}<Icon name="check" size={16} />{/if}
        </button>
      {/each}
    {/if}
  {/if}
</div>

<style>
  .menu {
    position: fixed;
    z-index: 60;
    width: 340px;
    padding: 10px;
    border-radius: 18px;
    background: rgba(16, 16, 19, 0.92);
    backdrop-filter: blur(24px) saturate(140%);
    border: 1px solid var(--border-strong);
    box-shadow: 0 18px 48px -12px rgba(0, 0, 0, 0.7);
    animation: menu-in 0.18s var(--ease);
    font-family: var(--font);
  }
  @keyframes menu-in {
    from {
      opacity: 0;
      transform: translateY(4px) scale(0.98);
    }
  }
  .row {
    display: flex;
    gap: 8px;
  }
  .seg {
    flex: 1;
    display: grid;
    grid-template-columns: 1fr 1fr;
    padding: 3px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--border);
  }
  .seg button {
    height: 34px;
    border-radius: 999px;
    font-size: 13px;
    color: var(--text-2);
  }
  .seg button.on {
    background: var(--text);
    color: var(--accent-ink);
    font-weight: 600;
  }
  .seg button:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .size {
    width: 42px;
    border-radius: 50%;
    background: var(--plate);
    border: 1px solid var(--border);
    font-weight: 700;
    font-size: 13px;
  }
  .item,
  .opt,
  .back {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    padding: 10px 10px;
    border-radius: 12px;
    text-align: left;
  }
  .item {
    margin-top: 6px;
  }
  .item:hover,
  .opt:hover,
  .back:hover,
  .size:hover,
  .steps button:hover,
  .wide:hover:not(:disabled) {
    background: var(--hover);
  }
  .item span {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .item b {
    font-weight: 500;
    font-size: 14px;
  }
  .item small {
    font-size: 12px;
    color: var(--text-3);
  }
  .item :global(svg) {
    color: var(--text-3);
  }
  .offset {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 8px;
  }
  .steps {
    flex: 1;
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 2px;
    border-radius: 10px;
    overflow: hidden;
  }
  .steps button {
    height: 34px;
    background: var(--plate);
    font-size: 12px;
    color: var(--text-2);
    font-variant-numeric: tabular-nums;
  }
  .value {
    min-width: 86px;
    text-align: right;
    font-size: 13px;
    font-variant-numeric: tabular-nums;
    color: var(--text);
  }
  .value:disabled {
    color: var(--text-3);
    cursor: default;
  }
  .foot {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 6px;
    margin-top: 10px;
  }
  .wide {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: 38px;
    border-radius: 12px;
    border: 1px solid var(--border-strong);
    font-size: 13px;
  }
  .wide:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .back {
    justify-content: flex-start;
    gap: 6px;
    color: var(--text-2);
    font-size: 13px;
  }
  .opt {
    font-size: 14px;
  }
  .opt.on {
    font-weight: 600;
  }
</style>
