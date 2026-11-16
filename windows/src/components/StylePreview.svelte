<script lang="ts">
  // Живая миниатюра стиля (Интерфейс → Стиль): полоска левой панели и мини-плеер в токенах стиля —
  // его поверхности, шрифты, толщина линий, отметка раздела и прогресс. Цвет — текущей темы.
  // `play` — проиграть его смену трека (при наведении на карточку).
  import { themeFrom, type RGB } from '../theme/palette'
  import { fontStack } from '../theme/look'
  import { DISPLAY_TUNING, type StyleAxes } from '../theme/style'
  import Icon from './Icon.svelte'
  import NavIcon from './NavIcon.svelte'

  let { axes, accent, play = 0 }: { axes: StyleAxes; accent: RGB | null; play?: number } = $props()

  const vars = $derived.by(() => {
    const t = themeFrom(accent, axes.surface)
    const tune = DISPLAY_TUNING[axes.font_display] ?? {}
    const v: Record<string, string> = {
      ...t.vars,
      '--icon-stroke': String(axes.icon_stroke),
      '--sp-font': fontStack(axes.font) ?? 'var(--font)',
      '--sp-display': fontStack(axes.font_display) ?? fontStack(axes.font) ?? 'var(--font-display)',
      '--sp-wdth': `${tune.wdth ?? 100}%`,
      '--sp-weight': String(tune.weight ?? 800),
    }
    return Object.entries(v)
      .map(([k, x]) => `${k}:${x}`)
      .join(';')
  })

  // перезапуск анимации смены трека: ключ меняется — блок пересоздаётся
  const bars = Array.from({ length: 23 }, (_, i) => 30 + Math.round(60 * Math.abs(Math.sin(i * 0.9 + 0.4))))
</script>

<div class="sp s-{axes.surface} t-{axes.anim_track} n-{axes.anim_nav} p-{axes.progress_look}" style={vars} aria-hidden="true">
  <div class="rail">
    <span class="nav on"><NavIcon name="home" active size={16} /></span>
    <span class="nav"><NavIcon name="search" size={16} /></span>
  </div>
  {#key play}
    <div class="mini" class:run={play > 0}>
      <span class="cover"><span class="rings"><i></i><i></i></span></span>
      <span class="meta">
        <b class:editorial={axes.title_style === 'editorial'}>Моя волна</b>
        <small>Sonar</small>
      </span>
      <span class="ctrls">
        <span class="pp"><Icon name="next" size={12} filled /></span>
        <Icon name="heart" size={12} filled />
      </span>
      <span class="prog">
        {#if axes.progress_look === 'wave'}
          {#each bars as h, i (i)}<i class:past={i < 9} style:height="{h}%"></i>{/each}
        {:else}
          <i class="fill"></i>
        {/if}
      </span>
      {#if axes.anim_track === 'edge'}<span class="arc"></span>{/if}
    </div>
  {/key}
</div>

<style>
  .sp {
    display: flex;
    gap: 6px;
    padding: 8px;
    border-radius: 14px;
    background: var(--bg);
    color: var(--text);
    font-family: var(--sp-font);
    transition: background 0.4s var(--ease);
  }
  .rail {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 5px 4px;
    border-radius: 999px;
    background: var(--surface-1);
    border: 1px solid var(--card-line, var(--border));
    box-shadow: var(--sheen, none);
  }
  .nav {
    position: relative;
    display: grid;
    place-items: center;
    width: 24px;
    height: 24px;
    border-radius: 8px;
    color: var(--text-2);
    --knob-fill: var(--surface-1);
  }
  .nav.on {
    color: var(--text);
  }
  .n-dot .nav.on::before {
    content: '';
    position: absolute;
    left: -4px;
    width: 4px;
    height: 4px;
    border-radius: 50%;
    background: var(--accent);
  }
  .n-capsule .nav.on {
    background: var(--accent);
    color: var(--accent-ink);
  }
  .n-plate .nav.on {
    background: var(--surface-2);
    box-shadow:
      inset 0 0 0 1px var(--border),
      inset 0 1px 0 oklch(1 0 0 / 0.07);
  }
  .n-inset .nav.on {
    background: color-mix(in oklch, var(--surface-1) 70%, #000);
    box-shadow: inset 0 2px 3px oklch(0 0 0 / 0.5);
  }
  .mini {
    position: relative;
    flex: 1;
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    grid-template-rows: auto auto;
    align-items: center;
    column-gap: 6px;
    row-gap: 6px;
    min-width: 0;
    padding: 7px 8px;
    border-radius: 14px;
    background: var(--mini-bg, var(--surface-1));
    border: 1px solid var(--card-line, var(--border));
    box-shadow: var(--sheen, none);
  }
  .s-signal .mini {
    background: var(--surface-2);
    border-color: transparent;
  }
  .s-edge .mini,
  .s-edge .rail {
    box-shadow: inset 0 1px 0 oklch(1 0 0 / 0.07);
  }
  .cover {
    position: relative;
    width: 26px;
    height: 26px;
    border-radius: 8px;
    background: linear-gradient(135deg, var(--accent), color-mix(in oklch, var(--accent) 30%, #000));
  }
  .s-monolith .cover {
    box-shadow: 0 0 14px var(--glow);
  }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  b {
    overflow: hidden;
    font-family: var(--sp-display);
    font-size: 12px;
    font-weight: var(--sp-weight);
    font-stretch: min(var(--sp-wdth), 125%);
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  b.editorial {
    text-transform: uppercase;
    letter-spacing: 0.02em;
  }
  small {
    font-size: 10px;
    color: var(--text-3);
  }
  .ctrls {
    display: flex;
    align-items: center;
    gap: 4px;
    color: var(--text-2);
  }
  .s-tactile .ctrls > :global(svg),
  .s-tactile .pp {
    border-radius: 6px;
    box-shadow: 0 1.5px 0 oklch(0 0 0 / 0.55);
  }
  .pp {
    display: grid;
    place-items: center;
    color: var(--text);
  }
  .prog {
    grid-column: 1 / -1;
    position: relative;
    display: flex;
    align-items: center;
    height: 4px;
    border-radius: 4px;
    background: var(--track, var(--surface-3));
  }
  .prog .fill {
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    width: 38%;
    border-radius: inherit;
    background: var(--text);
  }
  .p-groove .prog {
    height: 6px;
    background: color-mix(in oklch, var(--surface-1) 70%, #000);
    box-shadow: inset 0 1px 3px oklch(0 0 0 / 0.55);
  }
  .p-groove .prog .fill {
    background: var(--accent);
    box-shadow: 0 0 6px var(--accent);
  }
  .p-wave .prog {
    height: 12px;
    gap: 2px;
    justify-content: space-between;
    background: none;
  }
  .p-wave .prog i {
    width: 2px;
    border-radius: 2px;
    background: var(--surface-3);
  }
  .p-wave .prog i.past {
    background: var(--accent);
  }

  /* смена трека стиля — при наведении на карточку */
  .rings {
    position: absolute;
    inset: 0;
    border-radius: inherit;
  }
  .rings i {
    position: absolute;
    inset: 0;
    border-radius: inherit;
    border: 1.5px solid var(--accent);
    opacity: 0;
  }
  .t-echo .run .cover {
    animation: fx-cover-echo 0.42s cubic-bezier(0.22, 1, 0.36, 1);
  }
  .t-echo .run .rings i {
    animation: fx-ring 0.52s cubic-bezier(0.22, 1, 0.36, 1) both;
  }
  .t-echo .run .rings i + i {
    animation-delay: 0.09s;
  }
  .t-signal .run .cover,
  .t-signal .run b {
    animation: fx-signal-in 0.42s cubic-bezier(0.22, 1, 0.36, 1);
  }
  .t-signal .run .prog i {
    animation: sp-grow 0.42s cubic-bezier(0.22, 1, 0.36, 1) both;
  }
  @keyframes sp-grow {
    from {
      transform: scaleY(0.08);
    }
  }
  .t-edge .run .cover {
    animation: fx-reveal 0.3s cubic-bezier(0.22, 1, 0.36, 1);
  }
  .arc {
    position: absolute;
    inset: -1px;
    padding: 1.5px;
    border-radius: inherit;
    opacity: 0;
    background: conic-gradient(from var(--fx-angle), transparent 0 70%, var(--accent) 86%, oklch(1 0 0 / 0.9) 91%, transparent 96%);
    -webkit-mask:
      linear-gradient(#000 0 0) content-box,
      linear-gradient(#000 0 0);
    -webkit-mask-composite: xor;
    mask:
      linear-gradient(#000 0 0) content-box,
      linear-gradient(#000 0 0);
    mask-composite: exclude;
    pointer-events: none;
  }
  .run .arc {
    animation: fx-arc 0.6s cubic-bezier(0.45, 0, 0.2, 1) both;
  }
  .t-tactile .run .cover {
    animation: fx-slot 0.46s cubic-bezier(0.22, 1, 0.36, 1);
  }
  .t-monolith .run .cover {
    animation: sp-pour 0.56s cubic-bezier(0.22, 1, 0.36, 1);
  }
  .t-monolith .run b {
    animation: fx-rise8 0.36s cubic-bezier(0.22, 1, 0.36, 1);
  }
  @keyframes sp-pour {
    0% {
      box-shadow: 0 0 2px -4px var(--glow);
    }
    55% {
      box-shadow: 0 0 22px 4px var(--glow);
    }
  }
</style>
