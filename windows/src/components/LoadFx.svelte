<script lang="ts">
  // Загрузка трека на обложке (appearance.loading, STYLE_PROMPT §4а). Без спиннеров, по настоящему
  // прогрессу плеера (player.loadProgress — этапы загрузки; −1 — сколько осталось, неизвестно):
  //   color — обложка чёрно-белая, цвет возвращается полосой слева направо (тонкая светлая граница);
  //   ring  — по центру круг на затемнении, сектор заливается акцентом нового трека.
  // Короче 150 мс загрузку не показываем (без мигания). Готово — линия гаснет / круг сжимается.
  // «Меньше движения» — только прозрачность: ч/б плавно становится цветным, круг без вращения.
  // Кладётся внутрь контейнера обложки (position: relative; overflow: hidden).
  import { player } from '../player/player.svelte'
  import { settings } from '../lib/settings.svelte'
  import { fade } from 'svelte/transition'

  /** `url` — обложка трека: для варианта `color` поверх кладутся её ч/б и цветная копии. */
  /** `demo` — показать на примере (экран «Стиль»): свой прогресс вместо плеера, без задержки 150 мс. */
  let { on = true, url = null, demo }: { on?: boolean; url?: string | null; demo?: number | null } = $props()

  let shown = $state(false)
  let timer: ReturnType<typeof setTimeout> | null = null
  const p = $derived(demo !== undefined ? demo : player.loadProgress)
  const active = $derived(on && p !== null && p < 1)

  $effect(() => {
    if (active) {
      if (demo !== undefined) shown = true
      else if (!shown && !timer) timer = setTimeout(() => ((shown = true), (timer = null)), 150)
    } else {
      if (timer) clearTimeout(timer)
      timer = null
      shown = false
    }
  })

  const look = $derived(settings.get('appearance.loading'))
  const unknown = $derived(p !== null && p < 0)
  const pct = $derived(p === null ? 100 : p < 0 ? 0 : Math.round(p * 100))
</script>

{#if shown}
  {#if look === 'color'}
    <span class="ld color" out:fade={{ duration: 320 }} class:unknown style:--p="{pct}%" style:--p-num={pct / 100} aria-hidden="true">
      {#if url}
        <img class="bw" src={url} alt="" draggable="false" />
        <img class="tint" src={url} alt="" draggable="false" />
      {/if}
      <span class="edge"></span>
    </span>
  {:else}
    <span class="ld ring" out:fade={{ duration: 320 }} class:unknown style:--p="{pct}%" aria-hidden="true">
      <span class="disc"></span>
    </span>
  {/if}
{/if}

<style>
  @property --p {
    syntax: '<percentage>';
    inherits: true;
    initial-value: 0%;
  }
  .ld {
    position: absolute;
    inset: 0;
    z-index: 2;
    pointer-events: none;
    border-radius: inherit;
    animation: ld-in 0.28s ease-out both;
  }
  @keyframes ld-in {
    from {
      opacity: 0;
    }
  }
  /* снизу ч/б копия обложки (чуть темнее), сверху цветная — открыта слева до границы загруженного;
     граница — светлая линия 1.5 px */
  .bw,
  .tint {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
    border-radius: inherit;
  }
  .bw {
    filter: grayscale(1) brightness(0.82);
  }
  .tint {
    clip-path: inset(0 calc(100% - var(--p)) 0 0);
    transition: clip-path 0.65s cubic-bezier(0.33, 1, 0.68, 1);
  }
  .edge {
    position: absolute;
    top: 0;
    bottom: 0;
    left: var(--p);
    width: 1.5px;
    margin-left: -0.75px;
    background: oklch(1 0 0 / 0.85);
    box-shadow: 0 0 6px oklch(1 0 0 / 0.6);
    transition:
      left 0.65s cubic-bezier(0.33, 1, 0.68, 1),
      opacity 0.3s ease;
  }
  /* сколько осталось, неизвестно — граница мягко дышит на месте (без маятника: при переходе к
     настоящему прогрессу полоса не скачет, а плавно едет дальше) */
  .color.unknown .edge {
    animation: ld-breathe 1.4s ease-in-out infinite alternate;
  }
  @keyframes ld-breathe {
    from {
      opacity: 0.35;
    }
  }

  .ring {
    display: grid;
    place-items: center;
    background: oklch(0 0 0 / 0.45);
  }
  .disc {
    width: clamp(20px, 30%, 40px);
    aspect-ratio: 1;
    border-radius: 50%;
    border: 1.5px solid oklch(1 0 0 / 0.7);
    background: conic-gradient(var(--accent) var(--p), transparent 0);
    transition: --p 0.65s cubic-bezier(0.33, 1, 0.68, 1);
  }
  /* неизвестно — круг мягко дышит, без рывков вращения */
  .ring.unknown .disc {
    animation: ld-breathe 1.4s ease-in-out infinite alternate;
  }
  /* «Меньше движения»: без полосы и вращения — ч/б плавно становится цветным, круг просто заливается */
  @media (prefers-reduced-motion: reduce) {
    .color .tint {
      clip-path: none !important;
      opacity: var(--p-num, 0);
      transition: opacity 0.3s linear;
    }
    .edge {
      display: none;
    }
  }
  :global(:root.no-motion) .color .tint {
    clip-path: none !important;
    opacity: var(--p-num, 0);
  }
  :global(:root.no-motion) .edge {
    display: none;
  }
</style>
