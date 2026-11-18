<script lang="ts">
  // Полка — горизонтальный ряд карточек (главная, поиск, медиатека). Колесо листает вбок (hscroll),
  // край, за которым есть ещё карточки, затухает (edges), а при наведении по бокам появляются
  // стрелки ‹ ›: даже если ширина окна совпала так, что карточка не обрезалась, видно, что дальше
  // что-то есть. Есть ли куда листать — общая логика `lib/hscroll.ts` (`arrowsFor`, допуск 2 px):
  // ряд влез — стрелок нет. Стрелка плавно листает на видимую ширину, целыми карточками (`pageDelta`).
  import type { Snippet } from 'svelte'
  import Icon from './Icon.svelte'
  import { cascade } from '../lib/cascade'
  import { hscroll, pageDelta } from '../lib/hscroll'
  import { reducedMotion } from '../lib/motion'
  import { edges } from '../lib/edges'
  import { t } from '../lib/i18n.svelte'

  interface Props {
    children: Snippet
    /** Ключ каскада появления (новые результаты — карточки въезжают заново). */
    key?: unknown
    label?: string
    /** Колесо листает ряд вбок, и пока курсор над ним, страница стоит (главная). */
    wheel?: boolean
  }
  let { children, key, label, wheel = false }: Props = $props()

  let row: HTMLDivElement | undefined = $state()
  let left = $state(false)
  let right = $state(false)

  function go(dir: -1 | 1) {
    if (!row) return
    const card = row.firstElementChild?.getBoundingClientRect().width ?? 0
    const gap = parseFloat(getComputedStyle(row).columnGap) || 0
    row.scrollBy({ left: dir * pageDelta(row.clientWidth, card, gap), behavior: reducedMotion() ? 'auto' : 'smooth' })
  }
</script>

<div class="shelf">
  <div class="row" bind:this={row} aria-label={label} use:cascade={key} use:hscroll={{ wheel, trap: wheel ? 'scrollable' : false }} use:edges={(l, r) => ((left = l), (right = r))}>
    {@render children()}
  </div>
  <button class="nav prev" class:on={left} aria-label={t('Назад')} tabindex="-1" onclick={() => go(-1)}>
    <Icon name="chevronLeft" size={20} />
  </button>
  <button class="nav next" class:on={right} aria-label={t('Дальше')} tabindex="-1" onclick={() => go(1)}>
    <Icon name="chevronRight" size={20} />
  </button>
</div>

<style>
  .shelf {
    position: relative;
  }
  .row {
    --fade: 64px;
    display: flex;
    gap: 18px;
    overflow-x: auto;
    overflow-y: hidden;
    padding-bottom: 4px;
    scrollbar-width: none;
  }
  .row::-webkit-scrollbar {
    display: none;
  }
  /* стрелки — по центру обложек (обложка 160 px), видны при наведении на полку */
  .nav {
    position: absolute;
    top: 80px;
    z-index: 2;
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: color-mix(in srgb, var(--bg, #000) 72%, transparent);
    color: var(--text);
    backdrop-filter: blur(10px);
    box-shadow: 0 6px 18px rgba(0, 0, 0, 0.4);
    opacity: 0;
    translate: 0 -50%;
    scale: 0.85;
    pointer-events: none;
    transition:
      opacity var(--fast) var(--ease),
      scale var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .prev {
    left: 4px;
  }
  .next {
    right: 4px;
  }
  .shelf:hover .nav.on {
    opacity: 1;
    scale: 1;
    pointer-events: auto;
  }
  .nav:hover {
    background: color-mix(in srgb, var(--text) 18%, var(--bg, #000));
  }
  .nav:active {
    scale: 0.92 !important;
  }
  @media (prefers-reduced-motion: reduce) {
    .nav {
      scale: 1;
    }
  }
</style>
