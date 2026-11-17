<script lang="ts">
  // Кнопка-луна «Таймер сна» рядом со скоростью: 15–90 минут или «До конца трека», в конце музыка
  // плавно стихает и встаёт на паузу. Таймер стоит — на кнопке остаток. Открывается и закрывается
  // только кликом.
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { pop } from '../lib/motion'
  import { t } from '../lib/i18n.svelte'
  import { sleep } from './sleep.svelte'
  import { leftLabel, SLEEP_PRESETS } from './sleep-core'

  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()
  let down = $state(false)

  function toggle() {
    if (!open && root) {
      const r = root.getBoundingClientRect()
      down = window.innerHeight - r.bottom > r.top
    }
    open = !open
  }

  const badge = $derived(sleep.endsAt !== null ? leftLabel(sleep.left) : sleep.endOfTrack ? '♪' : '')
  const choice = $derived(sleep.endOfTrack ? 'track' : sleep.endsAt !== null ? 'time' : 'off')

  function pick(fn: () => void) {
    fn()
    open = false
  }

  onMount(() => {
    const outside = (e: MouseEvent) => {
      if (open && root && !root.contains(e.target as Node)) open = false
    }
    window.addEventListener('mousedown', outside, true)
    return () => window.removeEventListener('mousedown', outside, true)
  })
</script>

<div class="wrap" bind:this={root}>
  <button
    class="moon"
    class:active={sleep.active}
    class:open
    title={sleep.active ? t('Таймер сна: {left}', { left: sleep.endOfTrack ? t('до конца трека') : t('{n} мин', { n: leftLabel(sleep.left) }) }) : t('Таймер сна')}
    aria-label={t('Таймер сна')}
    aria-expanded={open}
    onclick={toggle}
  >
    {#key badge === ''}
      <span class="face" class:badge={badge !== ''}>
        {#if badge}{badge}{:else}<Icon name="moon" size={17} />{/if}
      </span>
    {/key}
  </button>

  {#if open}
    <div class="pop" class:down role="dialog" aria-label={t('Таймер сна')} in:pop={{ y: down ? -8 : 8 }} out:pop={{ y: down ? -8 : 8 }}>
      <b class="title">{t('Таймер сна')}</b>
      <small class="sub">{t('Музыка плавно стихнет и встанет на паузу')}</small>
      <div class="presets">
        {#each SLEEP_PRESETS as m (m)}
          <button onclick={() => pick(() => sleep.start(m))}>{t('{n} мин', { n: m })}</button>
        {/each}
        <button class="wide" class:on={choice === 'track'} onclick={() => pick(() => sleep.startEndOfTrack())}>{t('До конца трека')}</button>
      </div>
      {#if sleep.active}
        <div class="state">
          <span class="left">
            {#if sleep.endOfTrack}{t('Пауза в конце трека')}{:else}{t('Пауза через {left}', { left: leftLabel(sleep.left) + (sleep.left >= 60_000 ? ' ' + t('мин') : '') })}{/if}
          </span>
          <button class="off" onclick={() => pick(() => sleep.cancel())}>{t('Выключить')}</button>
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .wrap {
    position: relative;
  }
  .moon {
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
  .moon:hover,
  .moon.open {
    color: var(--text);
  }
  .moon.active {
    color: var(--text);
    background: color-mix(in srgb, var(--text) 14%, transparent);
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--text) 10%, transparent);
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
    width: 260px;
    padding: 12px 14px;
    border-radius: 20px;
    background: color-mix(in srgb, var(--surface-1) 92%, var(--tint));
    border: 1px solid var(--border-strong);
    box-shadow: 0 22px 50px -12px rgba(0, 0, 0, 0.7);
    transform-origin: bottom right;
  }
  .pop.down {
    top: calc(100% + 10px);
    bottom: auto;
    transform-origin: top right;
  }
  .title {
    display: block;
    font-size: calc(14px * var(--fs, 1));
    font-weight: 700;
  }
  .sub {
    display: block;
    margin-top: 2px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .presets {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 4px;
    margin-top: 10px;
  }
  .presets button {
    height: 30px;
    border-radius: 9px;
    background: var(--plate);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    color: var(--text-2);
    transition:
      color var(--normal) var(--ease),
      background var(--normal) var(--ease);
  }
  .presets button:hover {
    color: var(--text);
    background: var(--hover);
  }
  .presets .wide {
    grid-column: 2 / span 2;
  }
  .presets .on {
    color: var(--text);
    box-shadow: inset 0 0 0 1px var(--border-strong);
  }
  .state {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    margin-top: 10px;
    padding-top: 10px;
    border-top: 1px solid var(--border);
  }
  .left {
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
  .off {
    padding: 5px 10px;
    border-radius: 9px;
    background: var(--plate);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .off:hover {
    color: var(--text);
    background: var(--hover);
  }
  @media (prefers-reduced-motion: reduce) {
    .face {
      animation: none;
    }
  }
</style>
