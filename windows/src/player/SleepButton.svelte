<script lang="ts">
  // Кнопка-луна «Таймер сна» рядом со скоростью. Всплывашка как у Dotify: крупно минуты, «Остановится в
  // HH:MM», ползунок 5–180 (шаг 1), пресеты в ряд (связаны с ползунком), «До конца трека» и «Запустить».
  // Таймер идёт — обратный отсчёт, «Отменить» / «Изменить». В конце музыка плавно стихает и встаёт на
  // паузу (sleep.svelte.ts). Таймер стоит — на кнопке остаток. Открывается и закрывается только кликом.
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { pop, xfade } from '../lib/motion'
  import { t } from '../lib/i18n.svelte'
  import { sleep } from './sleep.svelte'
  import {
    clampMinutes,
    clockLabel,
    countdownLabel,
    leftLabel,
    minutesFromLeft,
    presetOf,
    SLEEP_MAX,
    SLEEP_MIN,
    SLEEP_PRESETS,
    stopAt,
  } from './sleep-core'

  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()
  let down = $state(false)
  /** Идущий таймер открыли на «Изменить» — снова ползунок вместо отсчёта. */
  let editing = $state(false)
  let minutes = $state(sleep.lastMinutes)
  /** «Сейчас» для «Остановится в …» — тикает раз в секунду, пока всплывашка открыта. */
  let now = $state(Date.now())

  const preset = $derived(presetOf(minutes))
  const editor = $derived(!sleep.active || editing)
  const fill = $derived(((minutes - SLEEP_MIN) / (SLEEP_MAX - SLEEP_MIN)) * 100)

  function toggle() {
    if (!open && root) {
      const r = root.getBoundingClientRect()
      down = window.innerHeight - r.bottom > r.top
      editing = false
      minutes = sleep.lastMinutes
      now = Date.now()
    }
    open = !open
  }

  $effect(() => {
    if (!open) return
    const id = setInterval(() => (now = Date.now()), 1000)
    return () => clearInterval(id)
  })

  const badge = $derived(sleep.endsAt !== null ? leftLabel(sleep.left) : sleep.endOfTrack ? '♪' : '')

  function run() {
    sleep.start(minutes)
    editing = false
  }

  function endOfTrack() {
    sleep.startEndOfTrack()
    editing = false
  }

  function edit() {
    minutes = sleep.endsAt !== null ? minutesFromLeft(sleep.left) : sleep.lastMinutes
    now = Date.now()
    editing = true
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
      {#key editor}
        <div class="body" in:xfade={{ duration: 200 }}>
          {#if editor}
            <div class="big">
              <span class="num">{minutes}</span>
              <span class="unit">{t('мин')}</span>
            </div>
            <span class="at">{t('Остановится в {time}', { time: clockLabel(stopAt(now, minutes)) })}</span>
            <input
              class="range"
              type="range"
              min={SLEEP_MIN}
              max={SLEEP_MAX}
              step="1"
              value={minutes}
              aria-label={t('Минуты до паузы')}
              style:--fill="{fill}%"
              oninput={(e) => (minutes = clampMinutes(Number(e.currentTarget.value)))}
            />
            <div class="presets">
              {#each SLEEP_PRESETS as m (m)}
                <button class:on={preset === m} aria-pressed={preset === m} onclick={() => (minutes = m)}>{m}</button>
              {/each}
            </div>
            <div class="actions">
              <button class="ghost" class:on={sleep.endOfTrack} onclick={endOfTrack}>{t('До конца трека')}</button>
              <button class="main" onclick={run}>{t('Запустить')}</button>
            </div>
          {:else}
            <div class="big">
              {#if sleep.endOfTrack}
                <Icon name="moon" size={28} />
              {:else}
                <span class="num">{countdownLabel(sleep.left)}</span>
              {/if}
            </div>
            <span class="at">
              {#if sleep.endOfTrack}{t('Пауза в конце трека')}{:else if sleep.endsAt !== null}{t('Остановится в {time}', { time: clockLabel(sleep.endsAt) })}{/if}
            </span>
            <div class="actions">
              <button class="ghost" onclick={() => sleep.cancel()}>{t('таймер::Отменить')}</button>
              <button class="main" onclick={edit}>{t('таймер::Изменить')}</button>
            </div>
          {/if}
        </div>
      {/key}
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
    width: 280px;
    padding: 14px 16px 16px;
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
  .body {
    display: flex;
    flex-direction: column;
    align-items: center;
    margin-top: 12px;
  }
  .big {
    display: flex;
    align-items: baseline;
    justify-content: center;
    gap: 6px;
    min-height: 44px;
    color: var(--text);
  }
  .num {
    font-size: calc(36px * var(--fs, 1));
    font-weight: 700;
    line-height: 1.1;
    letter-spacing: -0.02em;
    font-variant-numeric: tabular-nums;
  }
  .unit {
    font-size: calc(15px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
  }
  .at {
    min-height: 1.3em;
    font-size: calc(12px * var(--fs, 1));
    font-variant-numeric: tabular-nums;
    color: var(--text-3);
  }
  .range {
    width: 100%;
    height: 5px;
    margin: 14px 0 12px;
    appearance: none;
    border-radius: 5px;
    background: linear-gradient(to right, var(--text) var(--fill), var(--surface-3) var(--fill));
    box-shadow: var(--well);
    cursor: pointer;
  }
  .range::-webkit-slider-thumb {
    appearance: none;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: var(--text);
    transition: transform var(--fast) var(--ease);
  }
  .range:active::-webkit-slider-thumb {
    transform: scale(1.25);
  }
  .presets {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 4px;
    width: 100%;
  }
  .presets button,
  .actions button {
    height: 30px;
    border-radius: 9px;
    background: var(--plate);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    color: var(--text-2);
    transition:
      color var(--normal) var(--ease),
      background var(--normal) var(--ease),
      box-shadow var(--normal) var(--ease);
  }
  .presets button:hover,
  .actions .ghost:hover {
    color: var(--text);
    background: var(--hover);
  }
  .presets .on,
  .presets .on:hover {
    color: var(--bg, #000);
    background: var(--text);
  }
  .actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 6px;
    width: 100%;
    margin-top: 10px;
  }
  .actions button {
    height: 34px;
    border-radius: 11px;
  }
  .actions .ghost.on {
    color: var(--text);
    box-shadow: inset 0 0 0 1px var(--border-strong);
  }
  .actions .main {
    color: var(--bg, #000);
    background: var(--text);
  }
  .actions .main:hover {
    background: color-mix(in srgb, var(--text) 86%, transparent);
  }
  @media (prefers-reduced-motion: reduce) {
    .face {
      animation: none;
    }
  }
</style>
