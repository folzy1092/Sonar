<script lang="ts">
  // Плеер → визуализатор и ползунок (SETTINGS_NEXT «Плеер — раскладка»): все варианты сразу, сеткой
  // карточек-превью без прокрутки вбок. Выбранная карточка оживает — столбики и волна двигаются.
  import PreviewTiles from '../../components/settings/PreviewTiles.svelte'
  import { player } from '../../player/player.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'

  type Viz = 'off' | 'bar' | 'cover' | 'slider'
  type VizStyle = 'wave' | 'bars'
  type Slider = 'normal' | 'thin' | 'smooth' | 'wavy' | 'wave_bars'

  /** Какая часть: визуализатор (где и какой) или тип ползунка — они в разных карточках страницы. */
  let { part }: { part: 'viz' | 'slider' } = $props()

  const BAR_COUNT = 18
  // высоты столбиков — постоянные, чтобы пример не прыгал от перерисовки
  const bars = Array.from({ length: BAR_COUNT }, (_, i) => 28 + Math.round(64 * Math.abs(Math.sin(i * 1.7) * Math.cos(i * 0.31))))
  const cover = $derived(player.current?.cover_url ?? null)
  const vizStyle = $derived(settings.get('player.visualizer_style'))
</script>

{#snippet strip(live: boolean, kind: VizStyle)}
  {#if kind === 'wave'}
    <svg class="wave" class:live viewBox="0 0 120 20" preserveAspectRatio="none">
      <path d="M0 10 Q 7.5 2 15 10 T 30 10 T 45 10 T 60 10 T 75 10 T 90 10 T 105 10 T 120 10 T 135 10 T 150 10" />
    </svg>
  {:else}
    <span class="bars" class:live>{#each bars as h, i (i)}<i style:height="{h}%" style:animation-delay="{-i * 90}ms"></i>{/each}</span>
  {/if}
{/snippet}

{#snippet vizTile(id: Viz, on: boolean)}
  <span class="mock">
    <span class="cov" style:background-image={cover ? `url("${cover}")` : null}>
      {#if id === 'cover'}<span class="over">{@render strip(on, vizStyle)}</span>{/if}
    </span>
    <span class="lines">
      <i class="l1"></i>
      {#if id === 'slider'}
        <span class="on-slider">{@render strip(on, 'bars')}</span>
      {:else}
        <i class="line"></i>
      {/if}
      {#if id === 'bar'}<span class="under">{@render strip(on, vizStyle)}</span>{/if}
    </span>
  </span>
{/snippet}

{#snippet styleTile(id: VizStyle, on: boolean)}
  <span class="big">{@render strip(on, id)}</span>
{/snippet}

{#snippet sliderTile(id: Slider, on: boolean)}
  <span class="sl s-{id}" class:live={on}>
    {#if id === 'wavy'}
      <svg viewBox="0 0 120 12" preserveAspectRatio="none">
        <clipPath id="sonar-wavy-past"><rect x="0" y="0" width="56" height="12" /></clipPath>
        <g clip-path="url(#sonar-wavy-past)"><path class="past" d="M-16 6 Q -12 1 -8 6 T 0 6 T 8 6 T 16 6 T 24 6 T 32 6 T 40 6 T 48 6 T 56 6" /></g>
        <line x1="56" y1="6" x2="120" y2="6" />
      </svg>
    {:else if id === 'wave_bars'}
      {#each bars as h, i (i)}<i style:height="{h}%" class:past={i < BAR_COUNT / 2}></i>{/each}
    {:else}
      <i class="fill"></i><i class="knob"></i>
    {/if}
  </span>
{/snippet}

{#if part === 'viz'}
<PreviewTiles
  title={t('Визуализатор')}
  hint={t('Где показывать визуализацию звука')}
  value={settings.get('player.visualizer')}
  options={[
    { id: 'off' as const, label: t('Выключено') },
    { id: 'bar' as const, label: t('Полоса') },
    { id: 'cover' as const, label: t('На обложке') },
    { id: 'slider' as const, label: t('На ползунке') },
  ]}
  tile={vizTile}
  onchange={(v) => settings.set('player.visualizer', v)}
/>
<PreviewTiles
  title={t('Вид визуализатора')}
  hint={t('Выберите стиль визуализации аудио')}
  cols={2}
  value={vizStyle}
  options={[
    { id: 'wave' as const, label: t('Волна') },
    { id: 'bars' as const, label: t('Столбцы') },
  ]}
  tile={styleTile}
  onchange={(v) => settings.set('player.visualizer_style', v)}
/>
{:else}
<PreviewTiles
  title={t('Тип ползунка')}
  hint={t('Выберите стиль ползунка прогресса')}
  cols={5}
  value={settings.get('player.slider')}
  options={[
    { id: 'normal' as const, label: t('Обычный') },
    { id: 'thin' as const, label: t('Тонкий') },
    { id: 'smooth' as const, label: t('Плавный') },
    { id: 'wavy' as const, label: t('Переливы') },
    { id: 'wave_bars' as const, label: t('Волновой') },
  ]}
  tile={sliderTile}
  onchange={(v) => settings.set('player.slider', v)}
/>
{/if}

<style>
  .mock {
    display: flex;
    align-items: center;
    gap: 7px;
    width: 100%;
    padding: 0 8px;
  }
  .cov {
    position: relative;
    flex-shrink: 0;
    width: 36px;
    height: 36px;
    overflow: hidden;
    border-radius: 7px;
    background: linear-gradient(135deg, var(--surface-3), var(--accent-soft)) center / cover;
  }
  .over {
    position: absolute;
    left: 3px;
    right: 3px;
    bottom: 3px;
    height: 14px;
  }
  .lines {
    display: flex;
    flex-direction: column;
    gap: 5px;
    flex: 1;
    min-width: 0;
  }
  .lines > i {
    display: block;
    height: 3px;
    border-radius: 2px;
    background: var(--surface-3);
  }
  .l1 {
    width: 60%;
  }
  .lines > i.line {
    background: linear-gradient(90deg, var(--text-2) 45%, var(--surface-3) 45%);
  }
  .under,
  .on-slider {
    height: 11px;
  }
  .big {
    width: 70%;
    height: 30px;
  }
  .bars {
    display: flex;
    align-items: flex-end;
    gap: 2px;
    width: 100%;
    height: 100%;
  }
  .bars i {
    flex: 1;
    min-width: 1px;
    border-radius: 1px;
    background: var(--text-2);
    transform-origin: bottom;
  }
  .bars.live i {
    animation: bounce 900ms var(--ease) infinite alternate;
  }
  svg.wave {
    width: 100%;
    height: 100%;
    overflow: hidden;
  }
  svg path {
    fill: none;
    stroke: var(--text-2);
    stroke-width: 2;
  }
  svg.wave.live path {
    animation: flow 1.6s linear infinite;
  }
  .sl {
    position: relative;
    display: flex;
    align-items: center;
    width: 80%;
    height: 18px;
  }
  .sl::before {
    content: '';
    position: absolute;
    left: 0;
    right: 0;
    height: 3px;
    border-radius: 3px;
    background: var(--surface-3);
  }
  .s-wavy::before,
  .s-wave_bars::before {
    display: none;
  }
  .fill {
    position: absolute;
    left: 0;
    width: 50%;
    height: 3px;
    border-radius: 3px;
    background: var(--text-2);
  }
  .s-normal .fill {
    height: 4px;
    background: var(--text);
  }
  .knob {
    display: none;
  }
  .s-thin .fill {
    height: 2px;
  }
  .s-thin .knob {
    display: block;
    position: absolute;
    left: calc(50% - 5px);
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--text);
  }
  .s-smooth .knob {
    display: block;
    position: absolute;
    left: 50%;
    width: 3px;
    height: 14px;
    border-radius: 2px;
    background: var(--text);
  }
  .s-wavy svg {
    width: 100%;
    height: 12px;
  }
  .s-wavy line {
    stroke: var(--surface-3);
    stroke-width: 2;
  }
  .s-wavy.live path.past {
    animation: flow-wavy 1.2s linear infinite;
  }
  .s-wave_bars {
    gap: 2px;
    height: 22px;
  }
  .s-wave_bars i {
    flex: 1;
    border-radius: 1px;
    background: var(--surface-3);
    transition: background var(--normal) var(--ease);
  }
  .s-wave_bars i.past {
    background: var(--text-2);
  }
  @keyframes bounce {
    from {
      transform: scaleY(0.35);
    }
    to {
      transform: scaleY(1);
    }
  }
  /* сдвиг на один период волны — шов не видно */
  @keyframes flow {
    to {
      transform: translateX(-30px);
    }
  }
  @keyframes flow-wavy {
    to {
      transform: translateX(16px);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .bars.live i,
    svg.wave.live path,
    .s-wavy.live path.past {
      animation: none;
    }
  }
</style>
