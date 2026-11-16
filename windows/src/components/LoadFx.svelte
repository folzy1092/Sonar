<script lang="ts">
  // Загрузка трека на обложке (appearance.loading, STYLE_PROMPT §4а). Без спиннеров, по настоящему
  // прогрессу плеера (player.loadProgress — этапы загрузки; −1 — сколько осталось, неизвестно):
  //   color — обложка чёрно-белая, цвет возвращается полосой слева направо (тонкая светлая граница);
  //   ring  — по центру круг на затемнении, сектор заливается акцентом нового трека.
  // Короче 150 мс загрузку не показываем (без мигания). Готово — дотягивается до конца и растворяется.
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

  // Плавность (жалоба владельца 2026-11-17: «резкие дёрганые движения»): настоящий прогресс приходит
  // ступеньками, поэтому на экране — своё значение `disp`, оно каждый кадр мягко тянется к цели. Пока
  // этап не сменился, цель сама понемногу ползёт вперёд (к 90 %), так полоса не стоит и не ходит
  // туда-обратно. Готово — дотягивается до 100 % и только потом слой растворяется.
  let disp = $state(0)
  let creep = 0
  let raf = 0
  let last = 0
  const frame = (now: number) => {
    const dt = last ? Math.min(64, now - last) : 16
    last = now
    creep += (0.9 - creep) * (1 - Math.exp(-dt / 2600))
    const real = p === null || p >= 1 || !active ? 1 : Math.max(p < 0 ? 0 : p, 0)
    const goal = real >= 1 ? 1 : Math.max(real, Math.min(creep, 0.9))
    disp += (goal - disp) * (1 - Math.exp(-dt / 140))
    if (!active && disp > 0.995) {
      disp = 1
      shown = false
      raf = 0
      return
    }
    raf = requestAnimationFrame(frame)
  }
  const run = () => {
    if (raf) return
    last = 0
    raf = requestAnimationFrame(frame)
  }

  $effect(() => {
    if (active) {
      if (shown) return run()
      const start = () => {
        timer = null
        disp = 0
        creep = 0
        shown = true
        run()
      }
      if (demo !== undefined) start()
      else if (!timer) timer = setTimeout(start, 150)
    } else {
      if (timer) clearTimeout(timer)
      timer = null
      // показан — не обрываем, кадры доведут до 100 % и растворят
      if (shown) run()
    }
  })
  $effect(() => () => cancelAnimationFrame(raf))

  const look = $derived(settings.get('appearance.loading'))
  const pct = $derived(Math.round(disp * 1000) / 10)
</script>

{#if shown}
  {#if look === 'color'}
    <span class="ld color" style:--p="{pct}%" style:--p-num={disp} aria-hidden="true" out:fade={{ duration: 260 }}>
      {#if url}
        <img class="bw" src={url} alt="" draggable="false" />
        <img class="tint" src={url} alt="" draggable="false" />
      {/if}
      <span class="edge"></span>
    </span>
  {:else}
    <span class="ld ring" style:--p="{pct}%" aria-hidden="true" out:fade={{ duration: 260 }}>
      <span class="disc"></span>
    </span>
  {/if}
{/if}

<style>
  .ld {
    position: absolute;
    inset: 0;
    z-index: 2;
    pointer-events: none;
    border-radius: inherit;
    animation: ld-in 0.15s ease-out both;
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
  }
  /* «Меньше движения»: без полосы и вращения — ч/б плавно становится цветным, круг просто заливается */
  @media (prefers-reduced-motion: reduce) {
    .color .tint {
      clip-path: none !important;
      opacity: var(--p-num, 0);
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
